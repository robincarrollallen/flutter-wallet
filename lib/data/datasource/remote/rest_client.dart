import 'dart:convert';
import 'dart:io';

/// 纯 REST 传输层：建连、发请求、读 body、解码、关闭连接。
///
/// 与 [jsonRpcCall]（见 json_rpc.dart）同层——两者都只管「怎么把字节送出去、
/// 把响应拿回来」，不认识链、钱包、余额等任何业务概念。
/// 区别仅在于协议：那边套 JSON-RPC 2.0 信封，这边是裸 REST。

/// POST JSON 请求体，返回解码后的 JSON 对象。
Future<Map<String, dynamic>> postJson(String url, Map<String, Object?> body) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

/// GET 返回原始文本；非 200 抛 [HttpException]。供响应体为标量的接口使用。
Future<String> getText(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}: $body');
    }
    return body;
  } finally {
    client.close();
  }
}

/// GET 返回解码后的 JSON 对象。
Future<Map<String, dynamic>> getJson(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

/// GET 返回解码后的 JSON 数组；非 200 抛 [HttpException]。
Future<List<dynamic>> getJsonArray(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}: $body');
    }
    return jsonDecode(body) as List<dynamic>;
  } finally {
    client.close();
  }
}
