import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core/chains.dart';

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
        expect(chain.evmChainId != null, chain.kind == ChainKind.evm, reason: '${chain.name}：EVM 链必须有 chainId（EIP-155 签名依赖），非 EVM 链必须留空');
      }
    });

    test('evmChainId 钉死为各测试网官方值', () {
      // 这是 EIP-155 防跨链重放的全部依据。只断言「非空」拦不住把 Sepolia 写成 1。
      const expected = {'ethereum-sepolia': 11155111, 'polygon-amoy': 80002, 'bsc-testnet': 97, 'base-sepolia': 84532, 'arbitrum-sepolia': 421614, 'plasma-testnet': 9746};
      for (final chain in SupportedChains.all.where((c) => c.kind == ChainKind.evm)) {
        expect(chain.evmChainId, expected[chain.id], reason: chain.name);
      }
    });

    test('Aptos / Solana / Tron / Sui 的签名域钉死在测试网', () {
      expect(SupportedChains.aptosTestnet.aptosChainId, 2);
      expect(SupportedChains.solanaDevnet.genesisHash, 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG');
      expect(SupportedChains.tronNile.genesisHash, 'cd8690dc');
      // sui_getChainIdentifier 的实测返回值。主网是 35834a8a——写在这里是为了让
      // 「有没有钉错成主网」一眼可查。
      expect(SupportedChains.suiTestnet.genesisHash, '4c78adac');
    });

    test('靠创世信息钉网络身份的链都配了 genesisHash', () {
      // 少配一条的后果不是报错而是**静默失去保护**：ensureGenesisHash 会抛
      // 「未配置」，但那是签名时才炸；而更糟的情况是有人给某条链加了
      // ensureGenesisHash 调用却忘了配值。放在注册表这一层一次查清。
      //
      // 断言写成双向的：多配一条同样是错——那说明有人给一条并不校验创世信息的链
      // 配了个不会被读的值，下一个人会以为它真的在保护什么。
      const pinnedByGenesis = {ChainKind.solana, ChainKind.tron, ChainKind.sui};
      for (final chain in SupportedChains.all) {
        expect(chain.genesisHash != null, pinnedByGenesis.contains(chain.kind), reason: '${chain.id}（${chain.kind}）的 genesisHash 配置与它的校验方式对不上');
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
      final evmSchemes = SupportedChains.all.where((c) => c.kind == ChainKind.evm).map((c) => c.derivation).toSet();
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
        expect(chain.derivation.btcScriptType != null, chain.kind == ChainKind.bitcoin, reason: '${chain.name} 的派生方案 btcScriptType 不应参与');
      }
    });
  });
}
