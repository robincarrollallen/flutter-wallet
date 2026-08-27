import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/blockchain/token.dart';
import 'package:wallet/data/datasource/local/token_catalog_cache.dart';
import 'package:wallet/data/datasource/remote/token_catalog_api.dart';
import 'package:wallet/data/repository/token_repository.dart';

final _usdc = Token(
  chainId: SupportedChains.ethereumSepolia.id,
  symbol: 'USDC',
  name: 'USD Coin',
  standard: TokenStandard.erc20,
  identifier: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
  coinGeckoId: 'usd-coin',
  decimals: 6,
);

final _dai = Token(
  chainId: SupportedChains.ethereumSepolia.id,
  symbol: 'DAI',
  name: 'Dai',
  standard: TokenStandard.erc20,
  identifier: '0x0000000000000000000000000000000000000001',
  coinGeckoId: 'dai',
  decimals: 18,
);

class _FakeApi implements TokenCatalogApi {
  _FakeApi({this.result = const []});

  List<Token> result;
  int calls = 0;

  @override
  String get catalogUrl => 'https://example.test/tokens.json';

  @override
  Future<List<Token>> fetchCatalog() async {
    calls++;
    return result;
  }
}

Future<TokenRepository> _repo(_FakeApi api, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  return TokenRepository(api: api, cache: TokenCatalogCache(p), bundled: [_usdc]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TokenCatalogApi', () {
    test('未配置 URL 立刻返回空列表、不发请求', () async {
      expect(await const TokenCatalogApi(catalogUrl: '').fetchCatalog(), isEmpty);
    });
  });

  group('TokenRepository.getCatalog', () {
    test('远端成功则落盘并返回远端', () async {
      final api = _FakeApi(result: [_dai]);
      final repo = await _repo(api);
      expect((await repo.getCatalog()).single.symbol, 'DAI');
      expect(api.calls, 1);

      expect((await repo.getCatalog()).single.symbol, 'DAI');
      expect(api.calls, 1); // TTL 内不重拉
    });

    test('远端失败且无缓存时回退 bundled，不把 bundled 写入缓存', () async {
      final api = _FakeApi();
      final repo = await _repo(api);
      expect((await repo.getCatalog()).single.symbol, 'USDC');
      expect(api.calls, 1);

      api.result = [_dai];
      expect((await repo.getCatalog()).single.symbol, 'DAI');
      expect(api.calls, 2);
    });

    test('远端失败时回退未过期之外的旧缓存', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await TokenCatalogCache(prefs).write([_usdc]);
      // 把写入时刻改到 TTL 之外，迫使走网络。
      final raw = jsonDecode(prefs.getString('token_catalog_cache')!) as Map<String, dynamic>;
      raw['at'] = DateTime.now().subtract(TokenRepository.ttl + const Duration(minutes: 1)).millisecondsSinceEpoch;
      await prefs.setString('token_catalog_cache', jsonEncode(raw));

      final api = _FakeApi();
      final repo = TokenRepository(api: api, cache: TokenCatalogCache(prefs), bundled: [_dai]);
      expect((await repo.getCatalog()).single.symbol, 'USDC');
      expect(api.calls, 1);
    });
  });

  group('TokenRepository.refreshCatalog', () {
    test('成功才覆盖缓存；失败返回 false', () async {
      final api = _FakeApi(result: [_dai]);
      final repo = await _repo(api);
      expect(await repo.refreshCatalog(), isTrue);
      expect((await repo.getCatalog()).single.symbol, 'DAI');

      api.result = const [];
      expect(await repo.refreshCatalog(), isFalse);
      expect((await repo.getCatalog()).single.symbol, 'DAI');
    });
  });
}
