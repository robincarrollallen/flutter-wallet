import 'dart:convert';
import 'dart:io';

int _nextJsonRpcRequestId = 0;

/// 通用 JSON-RPC 调用：统一使用自增请求 id，并在错误时抛出 Exception。
Future<Object?> jsonRpcCall(String url, String method, List<Object?> params) async {
  final requestId = ++_nextJsonRpcRequestId;
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode({'jsonrpc': '2.0', 'id': requestId, 'method': method, 'params': params})));

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['id'] != requestId) {
      throw Exception('RPC id mismatch: expected $requestId, got ${json['id']}');
    }

    final error = json['error'];
    if (error != null) {
      final message = error is Map ? error['message'] : null;
      throw Exception(message?.toString() ?? 'RPC error: $error');
    }
    return json['result'];
  } finally {
    client.close();
  }
}
