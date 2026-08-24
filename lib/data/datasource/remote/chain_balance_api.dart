import 'dart:io';

import '../../../blockchain/chain_registry.dart';
import '../../../core/utils/evm_hex.dart';
import 'http_config.dart';
import 'json_rpc.dart';
import 'rest_client.dart';

/// 各链原生币余额的远程查询：按 [ChainKind] 分发到对应协议。
///
/// 只返回**原始最小单位**的 [BigInt]（wei / lamport / sun / octa / satoshi），
/// 不做小数换算、不构造领域对象——那是 repository 的职责。
class ChainBalanceApi {
  const ChainBalanceApi();

  /// 查询某条链上某地址的原生币余额（原始最小单位）。
  Future<BigInt> fetchNativeBalance(Chain chain, String address) async {
    return switch (chain.kind) {
      ChainKind.evm || ChainKind.solana || ChainKind.sui => await _rpcNativeBalance(chain, address),
      ChainKind.bitcoin => await _bitcoinBalance(chain, address),
      // Tron / Aptos 原生币余额查询（代币查询另见 tokens，暂未接入）。
      ChainKind.tron => await _tronBalance(chain, address),
      ChainKind.aptos => await _aptosBalance(chain, address),
    };
  }

  /// JSON-RPC 链（EVM/Solana/Sui）的原生币余额查询。
  Future<BigInt> _rpcNativeBalance(Chain chain, String address) async {
    final method = chain.nativeBalanceRpcMethod;
    if (method == null) {
      throw StateError('${chain.name} 未配置 nativeBalanceRpcMethod');
    }
    return switch (method) {
      RpcMethod.ethGetBalance => () async {
        final result = await jsonRpcCall(chain.endpoint, method.wireName, [address, 'latest']);
        return parseEvmHexQuantity(result as String);
      }(),
      RpcMethod.solGetBalance => () async {
        final result = await jsonRpcCall(chain.endpoint, method.wireName, [address]);
        return BigInt.from(((result as Map)['value'] as num?) ?? 0);
      }(),
      // 无币地址 suix_getBalance 会正常返回 totalBalance:"0"，不需要兜底 catch：
      // 下面的 null 判断已覆盖响应缺字段的情况，再包一层只会把 RPC 故障伪装成「余额 0」。
      RpcMethod.suiGetBalance => () async {
        final result = await jsonRpcCall(chain.endpoint, method.wireName, [address, '0x2::sui::SUI']);
        final total = (result as Map)['totalBalance'] as String?;
        return total == null ? BigInt.zero : BigInt.parse(total);
      }(),
    };
  }

  /// Bitcoin：浏览器 API 返回已收到/已花费的聪，差值即余额。
  Future<BigInt> _bitcoinBalance(Chain chain, String address) async {
    final uri = Uri.parse('${chain.endpoint}/address/$address');
    final json = await getJson(uri);
    final stats = json['chain_stats'] as Map<String, dynamic>? ?? const {};
    final funded = (stats['funded_txo_sum'] as num?)?.toInt() ?? 0;
    final spent = (stats['spent_txo_sum'] as num?)?.toInt() ?? 0;
    return BigInt.from(funded - spent);
  }

  /// Tron：REST POST wallet/getaccount，返回 balance（单位 sun，1e6）。
  ///
  /// 未激活账户返回 {}（无 balance 字段）——这是**业务上真实的 0**，由下面的 `?? 0`
  /// 覆盖，不需要 catch。反过来说，能抛出来的都是传输故障，必须原样上抛：
  /// 把它伪装成「余额 0」会让用户的总资产凭空缩水且毫无提示。
  Future<BigInt> _tronBalance(Chain chain, String address) async {
    final json = await postJson('${chain.endpoint}/wallet/getaccount', {
      'address': address,
      'visible': true, // 传入的是 base58（T...）地址
    });
    return BigInt.from((json['balance'] as num?)?.toInt() ?? 0);
  }

  /// Aptos：REST GET .../balance/0x1::aptos_coin::AptosCoin，响应体为标量数字
  /// （单位 octa，1e8）。
  Future<BigInt> _aptosBalance(Chain chain, String address) async {
    final uri = Uri.parse('${chain.endpoint}/v1/accounts/$address/balance/0x1::aptos_coin::AptosCoin');
    try {
      return BigInt.parse((await getText(uri)).trim().replaceAll('"', ''));
    } on HttpStatusException catch (e) {
      // 账户从未上链时 Aptos 返回 404 —— 这是「确实没有这个账户 = 余额 0」，属业务空值。
      // 其余状态码（429 限流 / 5xx）一律上抛，交给上层显示为「取数失败」而非 0。
      if (e.statusCode == HttpStatus.notFound) return BigInt.zero;
      rethrow;
    }
  }
}
