import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/blockchain/bundled_token_catalog.dart';
import 'package:wallet/blockchain/token_catalog.dart';
import 'package:wallet/features/wallet/receive/logic.dart';

final _catalog = TokenCatalog.merge(chains: SupportedChains.all, remote: BundledTokenCatalog.all);

void main() {
  group('ReceiveLogic.assetsOf', () {
    test('全部：每条链原生币 + 该链代币，顺序与 catalog 一致', () {
      final all = ReceiveLogic.assetsOf(null, _catalog);
      expect(all.length, SupportedChains.all.length + BundledTokenCatalog.all.length);
      expect(all.where((a) => a.token != null).length, BundledTokenCatalog.all.length);

      expect(all.first.symbol, 'ETH');
      expect(all.first.token, isNull);
      expect(all[1].symbol, 'USDC');
      expect(all[1].chain.id, SupportedChains.ethereumSepolia.id);
    });

    test('指定链时只返回该链原生币 + 代币', () {
      final assets = ReceiveLogic.assetsOf(SupportedChains.ethereumSepolia, _catalog);
      expect(assets, hasLength(2));
      expect(assets.first.symbol, 'ETH');
      expect(assets.last.symbol, 'USDC');
    });

    test('无代币的链只有原生币', () {
      final assets = ReceiveLogic.assetsOf(SupportedChains.bscTestnet, _catalog);
      expect(assets, hasLength(1));
      expect(assets.single.symbol, 'BNB');
    });
  });

  group('ReceiveLogic.filter', () {
    final assets = ReceiveLogic.assetsOf(null, _catalog);

    test('按符号 / 名称 / 链名过滤，忽略大小写', () {
      expect(ReceiveLogic.filter(assets, 'usdc').length, BundledTokenCatalog.all.length);
      expect(ReceiveLogic.filter(assets, 'BITCOIN').single.symbol, 'BTC');
      expect(
        ReceiveLogic.filter(assets, 'sepolia').any((a) => a.chain.id == SupportedChains.ethereumSepolia.id),
        isTrue,
      );
      expect(ReceiveLogic.filter(assets, ''), assets);
    });
  });
}
