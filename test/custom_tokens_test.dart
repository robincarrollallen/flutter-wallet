import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/blockchain/bundled_token_catalog.dart';
import 'package:wallet/blockchain/token.dart';
import 'package:wallet/enums/prefs_key.dart';
import 'package:wallet/providers/prefs_provider.dart';
import 'package:wallet/providers/token_catalog_provider.dart';

final _foo = Token(
  chainId: SupportedChains.bscTestnet.id,
  symbol: 'FOO',
  name: 'Foo Token',
  standard: TokenStandard.erc20,
  identifier: '0x1111111111111111111111111111111111111111',
  coinGeckoId: '',
  decimals: 18,
);

final _fooUpdated = Token(
  chainId: SupportedChains.bscTestnet.id,
  symbol: 'FOO',
  name: 'Foo v2',
  standard: TokenStandard.erc20,
  identifier: '0x1111111111111111111111111111111111111111',
  coinGeckoId: '',
  decimals: 8,
);

Future<ProviderContainer> _container({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(p)]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomTokensNotifier', () {
    test('add 追加；同身份键原地替换', () async {
      final c = await _container();
      c.read(customTokensProvider.notifier).add(_foo);
      expect(c.read(customTokensProvider).single.name, 'Foo Token');
      c.read(customTokensProvider.notifier).add(_fooUpdated);
      expect(c.read(customTokensProvider), hasLength(1));
      expect(c.read(customTokensProvider).single.name, 'Foo v2');
      expect(c.read(customTokensProvider).single.decimals, 8);
    });

    test('remove 按身份键删除（ERC-20 忽略大小写）', () async {
      final c = await _container();
      c.read(customTokensProvider.notifier).add(_foo);
      c
          .read(customTokensProvider.notifier)
          .remove(
            Token(
              chainId: _foo.chainId,
              symbol: 'X',
              name: 'X',
              standard: TokenStandard.erc20,
              identifier: _foo.identifier.toUpperCase(),
              coinGeckoId: '',
              decimals: 18,
            ),
          );
      expect(c.read(customTokensProvider), isEmpty);
    });

    test('落盘后能还原', () async {
      final c = await _container();
      c.read(customTokensProvider.notifier).add(_foo);
      final raw = c.read(sharedPrefsProvider).getString(PrefsKey.customTokens.value);
      expect(raw, isNotNull);

      final c2 = await _container(prefs: {PrefsKey.customTokens.value: raw!});
      expect(c2.read(customTokensProvider).single.symbol, 'FOO');
    });
  });

  group('tokenCatalogProvider', () {
    test('远程占位 ∪ 自定义：BSC 上出现 FOO，ETH 仍有打包 USDC', () async {
      final c = await _container();
      c.read(customTokensProvider.notifier).add(_foo);
      await c.read(remoteTokensProvider.future);

      final catalog = c.read(tokenCatalogProvider);
      expect(catalog.tokensOf(SupportedChains.bscTestnet.id).single.symbol, 'FOO');
      expect(catalog.tokensOf(SupportedChains.ethereumSepolia.id).any((t) => t.symbol == 'USDC'), isTrue);
      expect(catalog.tokens.length, BundledTokenCatalog.all.length + 1);
    });
  });
}
