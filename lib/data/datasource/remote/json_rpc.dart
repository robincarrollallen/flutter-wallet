import 'dart:async';
import 'dart:convert';
import 'dart:io';

const Duration _jsonRpcTimeout = Duration(seconds: 15); // 默认 15 秒超时
const int _maxErrorBodyPreviewChars = 300; // 最大错误体预览字符数

int _nextJsonRpcRequestId = 0; // 自增请求初始 ID
final HttpClient _jsonRpcHttpClient = HttpClient()..connectionTimeout = _jsonRpcTimeout; // 创建 HTTP 客户端

/// 通用 JSON-RPC 调用：统一使用自增请求 id，并在错误时抛出 Exception。
Future<Object?> jsonRpcCall(String url, String method, List<Object?> params) async {
  final requestId = ++_nextJsonRpcRequestId; // 自增请求 ID
  final uri = Uri.parse(url); // 解析 URL
  final payload = utf8.encode( // 编码 JSON 请求体
    jsonEncode({'jsonrpc': '2.0', 'id': requestId, 'method': method, 'params': params}),
  );
  try {
    final request = await _jsonRpcHttpClient.postUrl(uri).timeout(_jsonRpcTimeout); // 创建 HTTP 请求
    request.headers.contentType = ContentType.json; // 设置请求头
    request.add(payload); // 添加请求体

    final response = await request.close().timeout(_jsonRpcTimeout); // 发送请求
    final body = await response.transform(utf8.decoder).join().timeout(_jsonRpcTimeout); // 获取响应体

    if (response.statusCode < 200 || response.statusCode >= 300) { // 如果响应状态码不在 200-299 范围内则抛出异常
      throw Exception(
        'RPC HTTP error [$method] $url: status=${response.statusCode}, '
        'body=${_previewBody(body)}',
      );
    }

    final decoded = jsonDecode(body); // 解析响应体
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
  } on TimeoutException {
    throw Exception('RPC timeout [$method] $url after ${_jsonRpcTimeout.inSeconds}s'); // 超时异常
  } on FormatException catch (e) {
    throw Exception('RPC invalid JSON [$method] $url: ${e.message}'); // 格式异常
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

/// 预览响应体
String _previewBody(String body) {
  if (body.length <= _maxErrorBodyPreviewChars) return body;
  return '${body.substring(0, _maxErrorBodyPreviewChars)}...';
}
