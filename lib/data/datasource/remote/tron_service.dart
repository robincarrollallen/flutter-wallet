import 'dart:async';
import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:on_chain/tron/tron.dart';

import '../../../blockchain/chain_registry.dart';
import 'http_config.dart';

/// on_chain 的 Tron provider 与本项目 HTTP 栈之间的适配层。
///
/// [TronServiceProvider] 只要求实现 [doRequest]——传输方式由使用方决定。
/// 这里接到项目自己的 [sharedHttpClient] 上，于是既拿到 SDK 那套 typed 请求/响应
/// （`wallet/createtransaction` 这类接口的字段名与解析不必手写），又不引入第二套
/// http 客户端：连接复用与 [kRemoteTimeout] 与全站其余请求保持一致。
///
/// 与 [postJson]（rest_client.dart）的分工：那边服务于我们自己手写的 REST 调用
/// （如余额查询），这边只服务于 SDK 构造出来的请求。两者共用同一个 HttpClient。
class TronHttpService with TronServiceProvider {
  TronHttpService(this.endpoint);

  /// 该链的 REST 根地址，如 `https://api.shasta.trongrid.io`（不带尾斜杠）。
  final String endpoint;

  @override
  Future<TronServiceResponse> doRequest(TronRequestDetails params, {Duration? timeout}) async {
    // SDK 给的 path 不带前导斜杠（如 `wallet/createtransaction`），这里补上。
    final uri = Uri.parse('$endpoint/${params.path}');
    final deadline = timeout ?? kRemoteTimeout;

    final (:statusCode, :body) = await _send(uri, params, deadline);

    // 2xx 之外交给 SDK 统一构造错误响应：它会剥离 HTML 错误页、解析 JSON 错误体，
    // 最终由 TronProvider 抛成带状态码的 RPCError，比在这里自己拼文案准确。
    if (statusCode < 200 || statusCode >= 300) {
      return ServiceProviderUtils.findError(
        object: body,
        statusCode: statusCode,
        allowStatusCode: params.errorStatusCodes,
      );
    }
    // 原样把 body 字符串交回去，由 params.responseEncoding 决定怎么解码——
    // 在这里提前 jsonDecode 会跟 SDK 的编码约定打架。
    return ServiceSuccessRespose(statusCode: statusCode, response: body);
  }

  /// 建连、写 body、读响应，三段各自套超时。
  ///
  /// 三段缺一不可的理由同 [rest_client.dart] 里的 `_send`：只包最后一段的话，
  /// connect 卡住或服务端接了不回都会无限挂起。
  Future<({int statusCode, String body})> _send(
    Uri uri,
    TronRequestDetails params,
    Duration deadline,
  ) async {
    try {
      final request = params.requestMethod.isGet
          ? await sharedHttpClient.getUrl(uri).timeout(deadline)
          : await sharedHttpClient.postUrl(uri).timeout(deadline);

      params.headers.forEach(request.headers.set);

      if (!params.requestMethod.isGet) {
        final payload = params.encodeBody();
        if (payload != null) request.add(payload);
      }

      final response = await request.close().timeout(deadline);
      final body = await response.transform(utf8.decoder).join().timeout(deadline);
      return (statusCode: response.statusCode, body: body);
    } on TimeoutException {
      throw Exception('HTTP timeout $uri after ${deadline.inSeconds}s');
    }
  }
}

/// 按链配置造一个 Tron provider。
TronProvider tronProviderFor(Chain chain) => TronProvider(TronHttpService(chain.endpoint));
