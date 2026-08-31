import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'http_config.dart';

/// 纯 REST 传输层：建连、发请求、读 body、解码。
///
/// 与 [jsonRpcCall]（见 json_rpc.dart）同层——两者都只管「怎么把字节送出去、
/// 把响应拿回来」，不认识链、钱包、余额等任何业务概念。
/// 区别仅在于协议：那边套 JSON-RPC 2.0 信封，这边是裸 REST。

/// 统一的发送/读取：建连、写 body、读响应，全程套 [kRemoteTimeout]。
///
/// 三段 timeout 缺一不可——connect 卡住、服务端接了不回、body 慢慢滴，
/// 只包最后一段的话前两种情况仍会无限挂起。总资产改成并发拉取之后，
/// 一条挂死的链会拖住整个 Future.wait，所以这里必须硬性封顶。
Future<({int statusCode, String body})> _send(Uri uri, {Map<String, Object?>? jsonBody}) async {
  try {
    final request = jsonBody == null
        ? await sharedHttpClient.getUrl(uri).timeout(kRemoteTimeout)
        : await sharedHttpClient.postUrl(uri).timeout(kRemoteTimeout);
    if (jsonBody != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(jsonBody)));
    }
    final response = await request.close().timeout(kRemoteTimeout);
    final body = await response.transform(utf8.decoder).join().timeout(kRemoteTimeout);
    return (statusCode: response.statusCode, body: body);
  } on TimeoutException {
    throw Exception('HTTP timeout $uri after ${kRemoteTimeout.inSeconds}s');
  }
}

/// 非 2xx 一律抛 [HttpStatusException]；哪些状态码算业务空值由调用方自己判断。
({int statusCode, String body}) _ensureOk(Uri uri, ({int statusCode, String body}) r) {
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw HttpStatusException(r.statusCode, uri, r.body);
  }
  return r;
}

/// POST JSON 请求体，返回解码后的 JSON 对象。
Future<Map<String, dynamic>> postJson(String url, Map<String, Object?> body) async {
  final uri = Uri.parse(url);
  // 原实现不校验状态码：Tron 被限流返回 429 + HTML 时会一路掉进 jsonDecode 抛
  // FormatException，再被上游的 catch(_) 吃掉变成「余额 0」。先校验，故障才是故障。
  final r = _ensureOk(uri, await _send(uri, jsonBody: body));
  return jsonDecode(r.body) as Map<String, dynamic>;
}

/// GET 返回原始文本；非 2xx 抛 [HttpStatusException]。供响应体为标量的接口使用。
Future<String> getText(Uri uri) async => _ensureOk(uri, await _send(uri)).body;

/// GET 返回解码后的 JSON 对象；非 2xx 抛 [HttpStatusException]。
Future<Map<String, dynamic>> getJson(Uri uri) async {
  final r = _ensureOk(uri, await _send(uri));
  return jsonDecode(r.body) as Map<String, dynamic>;
}

/// GET 返回解码后的 JSON 数组；非 2xx 抛 [HttpStatusException]。
Future<List<dynamic>> getJsonArray(Uri uri) async {
  final r = _ensureOk(uri, await _send(uri));
  return jsonDecode(r.body) as List<dynamic>;
}
