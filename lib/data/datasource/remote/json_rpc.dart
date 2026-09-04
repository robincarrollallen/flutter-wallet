import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'http_config.dart';

int _nextJsonRpcRequestId = 0; // 自增请求初始 ID

/// 批量调用中的单条请求。字段名与 JSON-RPC 报文一致，构造点读起来即报文本身。
typedef JsonRpcRequest = ({String method, List<Object?> params});

/// [jsonRpcCall] 的函数签名。调用方把它当参数收下，测试就能塞一份假节点进来，
/// 不必为了验证请求编排而真的联网。
typedef JsonRpcCaller = Future<Object?> Function(String url, String method, List<Object?> params);

/// 通用 JSON-RPC 调用：统一使用自增请求 id，并在错误时抛出 Exception。
Future<Object?> jsonRpcCall(String url, String method, List<Object?> params) async {
  final requestId = ++_nextJsonRpcRequestId; // 自增请求 ID
  final decoded = await _post(url, {'jsonrpc': '2.0', 'id': requestId, 'method': method, 'params': params}, method);

  if (decoded is! Map<String, dynamic>) { // 如果响应体不是 JSON 对象则抛出异常
    throw Exception('RPC invalid response [$method] $url: expected JSON object');
  }

  final responseId = decoded['id']; // 获取响应 ID
  if (!_isMatchingRpcId(responseId, requestId)) { // 如果响应 ID 不匹配则抛出异常
    throw Exception(
      'RPC id mismatch [$method] $url: expected=$requestId, got=$responseId',
    );
  }

  final error = decoded['error']; // 获取错误信息
  if (error != null) { // 如果错误信息不为空则抛出异常
    throw Exception('RPC error [$method] $url: ${_formatRpcError(error)}');
  }
  return decoded['result']; // 返回结果
}

/// 批量 JSON-RPC：一次 HTTP 往返发出多条调用，**返回顺序与 [calls] 一致**。
///
/// 规范允许服务端乱序返回，所以不能按数组下标取结果——这里按分配出去的 id
/// 建索引再回填。同链多代币的 `balanceOf` 靠它合并成一个往返：
/// 六条 EVM 链各查 N 个代币，逐条发就是 6×N 次握手。
///
/// **任一条目出错即整批抛出**，不做「部分成功」：调用方拿到的是
/// 「这条链这一轮取数失败」，与 [jsonRpcCall] 的失败语义一致——
/// 把失败条目静默填成 0 会让持仓凭空缩水。
Future<List<Object?>> jsonRpcBatch(String url, List<JsonRpcRequest> calls) async {
  if (calls.isEmpty) return const []; // 空批次不发请求，省掉一次无意义的往返

  // 一次性分配连续 id，索引位置与 calls 对齐，便于回填时报出是哪一条出错。
  final ids = [for (var i = 0; i < calls.length; i++) ++_nextJsonRpcRequestId];
  final label = 'batch(${calls.map((c) => c.method).toSet().join(',')})'; // 错误文案里指明批次内容
  final decoded = await _post(url, [
    for (var i = 0; i < calls.length; i++)
      {'jsonrpc': '2.0', 'id': ids[i], 'method': calls[i].method, 'params': calls[i].params},
  ], label);

  if (decoded is! List) {
    throw Exception('RPC invalid response [$label] $url: expected JSON array');
  }
  if (decoded.length != calls.length) {
    throw Exception('RPC batch size mismatch [$label] $url: sent=${calls.length}, got=${decoded.length}');
  }

  // 先按 id 建索引，再按请求顺序取——服务端乱序返回也能对上号。
  final byId = <String, Map<String, dynamic>>{};
  for (final item in decoded) {
    if (item is! Map<String, dynamic>) {
      throw Exception('RPC invalid response [$label] $url: batch item is not a JSON object');
    }
    byId['${item['id']}'] = item;
  }

  return [
    for (var i = 0; i < calls.length; i++)
      _unwrapBatchItem(byId['${ids[i]}'], url: url, method: calls[i].method, requestId: ids[i]),
  ];
}

/// 取出单条批量响应的 result；缺条目或带 error 一律抛出。
Object? _unwrapBatchItem(
  Map<String, dynamic>? item, {
  required String url,
  required String method,
  required int requestId,
}) {
  if (item == null) {
    throw Exception('RPC batch missing response [$method] $url: id=$requestId');
  }
  final error = item['error'];
  if (error != null) {
    throw Exception('RPC error [$method] $url: ${_formatRpcError(error)}');
  }
  return item['result'];
}

/// POST 一份 JSON-RPC 报文并解码响应体。单条与批量共用同一段传输逻辑，
/// [label] 只用于错误文案（单条是方法名，批量是批次描述）。
Future<Object?> _post(String url, Object payload, String label) async {
  final uri = Uri.parse(url); // 解析 URL
  final body = utf8.encode(jsonEncode(payload)); // 编码 JSON 请求体
  try {
    final request = await sharedHttpClient.postUrl(uri).timeout(kRemoteTimeout); // 创建 HTTP 请求
    request.headers.contentType = ContentType.json; // 设置请求头
    request.add(body); // 添加请求体

    final response = await request.close().timeout(kRemoteTimeout); // 发送请求
    final text = await response.transform(utf8.decoder).join().timeout(kRemoteTimeout); // 获取响应体

    if (response.statusCode < 200 || response.statusCode >= 300) { // 如果响应状态码不在 200-299 范围内则抛出异常
      throw Exception(
        'RPC HTTP error [$label] $url: status=${response.statusCode}, '
        'body=${previewBody(text)}',
      );
    }
    return jsonDecode(text); // 解析响应体
  } on TimeoutException {
    throw Exception('RPC timeout [$label] $url after ${kRemoteTimeout.inSeconds}s'); // 超时异常
  } on FormatException catch (e) {
    throw Exception('RPC invalid JSON [$label] $url: ${e.message}'); // 格式异常
  }
}

/// 检查响应 ID 是否匹配请求 ID
bool _isMatchingRpcId(Object? responseId, int requestId) {
  if (responseId == requestId) return true;
  return responseId?.toString() == requestId.toString();
}

/// 格式化 RPC 错误信息
String _formatRpcError(Object error) {
  if (error is Map) {
    final code = error['code'];
    final message = error['message'];
    final data = error['data'];
    final parts = <String>[];
    if (code != null) parts.add('code=$code');
    if (message != null) parts.add('message=$message');
    if (data != null) parts.add('data=$data');
    if (parts.isNotEmpty) return parts.join(', ');
  }
  return error.toString();
}

