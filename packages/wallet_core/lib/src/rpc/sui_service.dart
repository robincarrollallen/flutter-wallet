import 'dart:async';
import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:on_chain/sui/sui.dart';

import '../../chains.dart';
import 'http_config.dart';

/// on_chain 的 Sui provider 与本项目 HTTP 栈之间的适配层。
///
/// 与 [SolanaHttpService]（solana_service.dart）逐行同构：Sui 同样是标准 JSON-RPC、
/// 所有方法打同一个端点，不像 Tron 要按 `params.path` 分路由。[SuiServiceProvider]
/// 也只要求实现 [doRequest]，于是传输接回项目自己的 [sharedHttpClient]——既拿到 SDK
/// 那套 typed 请求/响应（`suix_getCoins`、`sui_dryRunTransactionBlock` 这些方法的参数
/// 拼装与结果解析不必手写），又不引入第二套 http 客户端：连接复用与 [kRemoteTimeout]
/// 与全站其余请求一致。
class SuiHttpService with SuiServiceProvider {
  SuiHttpService(this.endpoint);

  /// 该链的 JSON-RPC 端点，如 `https://sui-testnet-rpc.publicnode.com`。
  final String endpoint;

  @override
  Future<SuiServiceResponse> doRequest(SuiRequestDetails params, {Duration? timeout}) async {
    final uri = params.encodeUrl(endpoint);
    final deadline = timeout ?? kRemoteTimeout;

    final (:statusCode, :body) = await _send(uri, params, deadline);

    // 2xx 之外交给 SDK 统一构造错误响应（剥 HTML 错误页、解析 JSON 错误体），
    // 最终由 SuiProvider 抛成带状态码的 RPCError，比在这里自己拼文案准确。
    if (statusCode < 200 || statusCode >= 300) {
      return ServiceProviderUtils.findError(object: body, statusCode: statusCode, allowStatusCode: params.errorStatusCodes);
    }
    // 原样交回 body 字符串，由 params.responseEncoding 决定怎么解码——
    // 在这里提前 jsonDecode 会跟 SDK 的编码约定打架。
    return ServiceSuccessRespose(statusCode: statusCode, response: body);
  }

  /// 建连、写 body、读响应，三段各自套超时。
  ///
  /// 三段缺一不可的理由同 solana_service.dart 里的 `_send`：只包最后一段的话，
  /// connect 卡住或服务端接了不回都会无限挂起。
  Future<({int statusCode, String body})> _send(Uri uri, SuiRequestDetails params, Duration deadline) async {
    try {
      final request = await sharedHttpClient.postUrl(uri).timeout(deadline);

      // SDK 的 defaultPostHeaders 里已经带了 content-type，不必在这里补。
      params.headers.forEach(request.headers.set);

      final payload = params.encodeBody();
      if (payload != null) request.add(payload);

      final response = await request.close().timeout(deadline);
      final body = await response.transform(utf8.decoder).join().timeout(deadline);
      return (statusCode: response.statusCode, body: body);
    } on TimeoutException {
      throw Exception('HTTP timeout ${redactCredentials(uri)} after ${deadline.inSeconds}s');
    }
  }
}

/// 按链配置造一个 Sui provider。
SuiProvider suiProviderFor(Chain chain) => SuiProvider(SuiHttpService(chain.endpoint));
