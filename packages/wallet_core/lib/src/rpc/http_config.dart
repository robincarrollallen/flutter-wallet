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
  String toString() => 'HTTP $statusCode $uri: ${previewBody(body)}';
}
