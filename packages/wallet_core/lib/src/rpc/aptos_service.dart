import 'dart:async';
import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:on_chain/aptos/aptos.dart';

import '../../chains.dart';
import 'http_config.dart';

/// on_chain 的 Aptos provider 与本项目 HTTP 栈之间的适配层。
///
/// 与 [TronHttpService] / [SolanaHttpService] 同一个用意：[AptosServiceProvider]
/// 只要求实现 [doRequest]，传输接到项目自己的 [sharedHttpClient] 上——既拿到 SDK 那套
/// typed 请求/响应（`/transactions`、`/estimate_gas_price` 这些接口的路径拼装与
/// 字段解析不必手写），又不引入第二套 http 客户端：连接复用与 [kRemoteTimeout]
/// 与全站其余请求保持一致。
///
/// 结构上更贴近 Tron 那版而非 Solana 那版：Aptos 是 REST，每个方法自带路径与动词
/// （GET `/accounts/{address}`、POST `/transactions`），不是所有方法打同一个端点。
class AptosHttpService with AptosServiceProvider {
  AptosHttpService(this.endpoint);

  /// 该链的 fullnode REST 根地址，**含 API 版本前缀**，如
  /// `https://fullnode.testnet.aptoslabs.com/v1`。
  ///
  /// 版本前缀在这里拼好而不是留给调用方：SDK 给的 path 是 `/transactions` 这种
  /// 不带版本的相对路径（见 `AptosApiMethod`），少了 `/v1` 会一路 404。
  final String endpoint;

  @override
  Future<AptosServiceResponse> doRequest(AptosRequestDetails params, {Duration? timeout}) async {
    // GraphQL 索引器是另一套服务、另一个域名。本项目只接 fullnode，
    // 真走到这里说明调用方选错了请求类型——静默打到 fullnode 只会得到一个
    // 难以归因的 404，不如在这里说清楚。
    if (params.api == AptosRequestType.graphQl) {
      throw UnsupportedError('本项目只接 Aptos fullnode REST，未接入 GraphQL 索引器');
    }

    final uri = params.encodeUrl(endpoint);
    final deadline = timeout ?? kRemoteTimeout;

    final (:statusCode, :body) = await _send(uri, params, deadline);

    // 2xx 之外交给 SDK 统一构造错误响应（剥 HTML 错误页、解析 JSON 错误体），
    // 最终由 AptosProvider 抛成带 vm_error_code 的 RPCError，比在这里自己拼文案准确。
    if (statusCode < 200 || statusCode >= 300) {
      return ServiceProviderUtils.findError(object: body, statusCode: statusCode, allowStatusCode: params.errorStatusCodes);
    }
    // 原样交回 body 字符串，由 params.responseEncoding 决定怎么解码——
    // 在这里提前 jsonDecode 会跟 SDK 的编码约定打架。
    return ServiceSuccessRespose(statusCode: statusCode, response: body);
  }

  /// 建连、写 body、读响应，三段各自套超时。
  ///
  /// 三段缺一不可的理由同 tron_service.dart 里的 `_send`：只包最后一段的话，
  /// connect 卡住或服务端接了不回都会无限挂起。
  Future<({int statusCode, String body})> _send(Uri uri, AptosRequestDetails params, Duration deadline) async {
    try {
      final request = params.requestMethod.isGet ? await sharedHttpClient.getUrl(uri).timeout(deadline) : await sharedHttpClient.postUrl(uri).timeout(deadline);

      // 提交与模拟交易走的是 `application/x.aptos.signed_transaction+bcs`，
      // body 是裸 BCS 字节而不是 JSON——content-type 由 SDK 在 headers 里给全，
      // 这里照搬即可，不要自作主张覆盖成 application/json。
      params.headers.forEach(request.headers.set);

      if (!params.requestMethod.isGet) {
        final payload = params.encodeBody();
        if (payload != null) {
          // **必须显式设长度**：不设的话 Dart 的 HttpClient 会用分块传输
          // （`Transfer-Encoding: chunked`），而 Aptos 的 fullnode 直接回
          // 「Transfer-Encoding is not supported」把请求打回来。提交与模拟都是 POST，
          // 少了这一行两条路都走不通——而失败发生在 HTTP 层，报错里一个字都不会提到交易。
          request.contentLength = payload.length;
          request.add(payload);
        }
      }

      final response = await request.close().timeout(deadline);
      final body = await response.transform(utf8.decoder).join().timeout(deadline);
      return (statusCode: response.statusCode, body: body);
    } on TimeoutException {
      throw Exception('HTTP timeout ${redactCredentials(uri)} after ${deadline.inSeconds}s');
    }
  }
}

/// 按链配置造一个 Aptos provider。
///
/// 余额查询（`chain_balance_api.dart` 的 `_aptosAssetBalance`）同样在
/// [Chain.endpoint] 后面补 `/v1`，两处口径一致。
AptosProvider aptosProviderFor(Chain chain) => AptosProvider(AptosHttpService('${chain.endpoint}/v1'));
