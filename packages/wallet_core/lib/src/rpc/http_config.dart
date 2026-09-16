import 'dart:io';

/// 远程调用的统一超时。RPC 与 REST 共用同一个值——两者都是「一次链上/浏览器查询」，
/// 没有理由给出不同的耐心；分开写只会随时间漂移。
const Duration kRemoteTimeout = Duration(seconds: 15);

/// 进程级共享的 HttpClient。
///
/// REST 侧原先每次调用都 new 一个再 close，等于每次请求重新握手一遍；
/// 总资产改成并发拉取后一次刷新有十来条链同时发起，这笔开销会被成倍放大。
/// 改为单例后连接可复用。
///
/// **不要 close 它**——close 之后所有后续请求都会抛 Bad state。
final HttpClient sharedHttpClient = HttpClient()..connectionTimeout = kRemoteTimeout;

/// 错误体预览的最大字符数，避免把一整页 HTML 错误页塞进日志。
const int _maxErrorBodyPreviewChars = 300;

/// 查询串里按凭据处理、不允许出现在任何错误信息中的参数名。
///
/// 区块浏览器的 key 是以 `?apikey=` 的形式拼在 URL 里的，而 URL 会随异常信息
/// 流向日志、崩溃上报，甚至 UI 上的错误提示。只要有一次 429 或 5xx，key 就跟着出去了。
const Set<String> _credentialQueryParams = {'apikey', 'api_key', 'key', 'token', 'access_token'};

/// 把 URI 里的凭据参数替换成 `REDACTED`，其余部分原样保留。
///
/// 保留路径和其他参数是有意的：排查问题时需要知道请求打到了哪个端点、带了什么条件，
/// 脱敏脱到只剩 host 就没人会看了，最后大家又会绕过它去打印原始 uri。
Uri redactCredentials(Uri uri) {
  if (uri.queryParameters.isEmpty) return uri;
  if (!uri.queryParameters.keys.any((k) => _credentialQueryParams.contains(k.toLowerCase()))) {
    return uri;
  }
  return uri.replace(
    queryParameters: {
      for (final entry in uri.queryParameters.entries)
        entry.key: _credentialQueryParams.contains(entry.key.toLowerCase()) ? 'REDACTED' : entry.value,
    },
  );
}

/// 截断过长的响应体，仅用于错误信息展示。
String previewBody(String body) =>
    body.length <= _maxErrorBodyPreviewChars ? body : '${body.substring(0, _maxErrorBodyPreviewChars)}...';

/// 非 2xx 响应。
///
/// 相比裸 [HttpException]，这里保留了结构化的 [statusCode]，上层才能区分
/// 「业务性的 404（账户根本不存在 = 余额确实是 0）」与「传输故障（429 限流 / 5xx）」。
/// 没有这个区分，就只能一把 catch 全吞——那正是本次要修掉的问题。
class HttpStatusException implements Exception {
  const HttpStatusException(this.statusCode, this.uri, this.body);

  final int statusCode;
  final Uri uri;
  final String body;

  @override
  String toString() => 'HTTP $statusCode ${redactCredentials(uri)}: ${previewBody(body)}';
}
