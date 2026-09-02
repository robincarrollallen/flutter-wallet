import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/blockchain/chain_registry.dart';

/// 链注册表的静态自洽性检查：这些约束散落在 Chain 的多个字段之间，
/// 类型系统表达不了（`nativeBalanceRpcMethod` / `evmChainId` 都是可空字段），
/// 漏填只会在用户刷新余额时才炸。这里把它们钉在编译-测试环节。
void main() {
  group('SupportedChains 字段自洽', () {
    test('nativeBalanceRpcMethod 与 kind 精确配对', () {
      for (final chain in SupportedChains.all) {
        final expected = switch (chain.kind) {
          ChainKind.evm => RpcMethod.ethGetBalance,
          ChainKind.solana => RpcMethod.solGetBalance,
          ChainKind.sui => RpcMethod.suiGetBalance,
          // 走 REST 的链必须留空，否则 _rpcNativeBalance 会被误选。
          ChainKind.bitcoin || ChainKind.tron || ChainKind.aptos => null,
        };
        expect(chain.nativeBalanceRpcMethod, expected, reason: '${chain.name} 的余额 RPC 方法与链类型不匹配');
      }
    });

    test('evmChainId 当且仅当 EVM 链非空', () {
      for (final chain in SupportedChains.all) {
        expect(
          chain.evmChainId != null,
          chain.kind == ChainKind.evm,
          reason: '${chain.name}：EVM 链必须有 chainId（EIP-155 签名依赖），非 EVM 链必须留空',
        );
      }
    });

    test('id 唯一', () {
      final ids = SupportedChains.all.map((c) => c.id).toList();
      // byId 用 firstWhere，id 重复不会报错，只会静默取到第一条。
      expect(ids.toSet().length, ids.length, reason: '存在重复的链 id：$ids');
    });

    test('byId 能取回每条链', () {
      for (final chain in SupportedChains.all) {
        expect(SupportedChains.byId(chain.id).name, chain.name);
      }
    });

    test('展示与估值所需字段非空', () {
      for (final chain in SupportedChains.all) {
        expect(chain.decimals, greaterThan(0), reason: '${chain.name} 的 decimals 无效');
        expect(chain.coinGeckoId, isNotEmpty, reason: '${chain.name} 缺少 coinGeckoId，无法估值');
        expect(chain.symbol, isNotEmpty, reason: '${chain.name} 缺少 symbol');
        expect(chain.endpoint, startsWith('https://'), reason: '${chain.name} 的 endpoint 不是 https');
      }
    });
  });

  group('派生方案', () {
    test('EVM 多链共用同一派生方案，去重后只派生一次', () {
      final evmSchemes = SupportedChains.all
          .where((c) => c.kind == ChainKind.evm)
          .map((c) => c.derivation)
          .toSet();
      expect(evmSchemes.length, 1);
    });

    test('distinctDerivations 覆盖全部链且无重复', () {
      final schemes = SupportedChains.distinctDerivations;
      expect(schemes.toSet().length, schemes.length, reason: '去重后仍有重复方案');
      for (final chain in SupportedChains.all) {
        expect(schemes, contains(chain.derivation), reason: '${chain.name} 的派生方案未被覆盖');
      }
    });

    test('只有 BTC 链带 btcScriptType，其余链的派生方案忽略它', () {
      for (final chain in SupportedChains.all) {
        expect(
          chain.derivation.btcScriptType != null,
          chain.kind == ChainKind.bitcoin,
          reason: '${chain.name} 的派生方案 btcScriptType 不应参与',
        );
      }
    });
  });
}
