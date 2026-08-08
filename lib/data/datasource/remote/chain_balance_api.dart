import '../../../blockchain/chain_registry.dart';
import '../../../core/utils/evm_hex.dart';
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
      RpcMethod.suiGetBalance => () async {
        try {
          final result = await jsonRpcCall(chain.endpoint, method.wireName, [address, '0x2::sui::SUI']);
          final total = (result as Map)['totalBalance'] as String?;
          return total == null ? BigInt.zero : BigInt.parse(total);
        } catch (_) {
          return BigInt.zero;
        }
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
  /// 未激活账户返回 {}（无 balance 字段）；查询失败均按 0 处理。
  Future<BigInt> _tronBalance(Chain chain, String address) async {
    try {
      final json = await postJson('${chain.endpoint}/wallet/getaccount', {
        'address': address,
        'visible': true, // 传入的是 base58（T...）地址
      });
      return BigInt.from((json['balance'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return BigInt.zero;
    }
  }

  /// Aptos：REST GET .../balance/0x1::aptos_coin::AptosCoin，响应体为标量数字
  /// （单位 octa，1e8）。账户不存在时返回 404，按 0 处理。
  Future<BigInt> _aptosBalance(Chain chain, String address) async {
    try {
      final uri = Uri.parse('${chain.endpoint}/v1/accounts/$address/balance/0x1::aptos_coin::AptosCoin');
      final body = await getText(uri); // 404 时抛异常，下方 catch 归零
      return BigInt.parse(body.trim().replaceAll('"', ''));
    } catch (_) {
      return BigInt.zero;
    }
  }
}
