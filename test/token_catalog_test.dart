import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/blockchain/bundled_token_catalog.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/blockchain/token.dart';
import 'package:wallet/data/datasource/remote/token_catalog_api.dart';
import 'package:wallet/enums/prefs_key.dart';
import 'package:wallet/providers/prefs_provider.dart';
import 'package:wallet/providers/token_catalog_provider.dart';

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

/// 假数据源：记录被调用次数，好断言「命中缓存时一次请求都不发」。
class _FakeApi implements TokenCatalogApi {
  _FakeApi({this.result = const []});

  /// 返回给 fetchCatalog 的目录；空列表表示这次请求失败（数据源约定）。
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

/// 造一个预置了落盘缓存的容器。[age] 为 null 表示完全没有缓存。
///
/// 落盘的旧目录固定为 [_usdc]，远端新目录固定为 [_dai]，两者不同才分得清用的是哪一份。
Future<(ProviderContainer, _FakeApi, SharedPreferences)> _container({Duration? age, List<Token>? remote}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  if (age != null) {
    await prefs.setString(
      PrefsKey.tokenCatalog.value,
      jsonEncode({
        'at': DateTime.now().subtract(age).millisecondsSinceEpoch,
        'data': [_usdc.toJson()],
      }),
    );
  }
  final api = _FakeApi(result: remote ?? [_dai]);
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs), tokenCatalogApiProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  return (container, api, prefs);
}

List<Token> _tokens(ProviderContainer c) => c.read(remoteTokensProvider).tokens;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TokenCatalogApi', () {
    test('未配置 URL 立刻返回空列表、不发请求', () async {
      expect(await const TokenCatalogApi(catalogUrl: '').fetchCatalog(), isEmpty);
    });
  });

  group('remoteTokensProvider', () {
    test('缓存未过期：首次读同步拿到旧目录，一次请求都不发', () async {
      final (c, api, _) = await _container(age: const Duration(hours: 1));

      expect(_tokens(c).single.symbol, 'USDC');
      expect(api.calls, 0, reason: 'TTL 内不该发请求');

      await Future<void>.delayed(Duration.zero);
      expect(api.calls, 0, reason: '也不该有迟到的后台请求');
    });

    // 本次改动的核心：过期时**不等网络**，先把旧目录交出去。
    test('缓存已过期：首帧仍是旧目录，请求回来后才换成新的并落盘', () async {
      final (c, api, prefs) = await _container(age: RemoteTokensNotifier.ttl + const Duration(minutes: 1));

      expect(_tokens(c).single.symbol, 'USDC', reason: '过期也必须先返回旧目录，不能空窗');
      expect(api.calls, 1);

      await Future<void>.delayed(Duration.zero);

      expect(_tokens(c).single.symbol, 'DAI');
      final persisted = jsonDecode(prefs.getString(PrefsKey.tokenCatalog.value)!) as Map<String, dynamic>;
      expect(Token.listFromJson(persisted['data']).single.symbol, 'DAI', reason: 'listenSelf 应已自动落盘');
    });

    test('请求失败（空列表）：state 与落盘都保持旧目录', () async {
      final (c, api, prefs) = await _container(
        age: RemoteTokensNotifier.ttl + const Duration(minutes: 1),
        remote: const [],
      );

      expect(_tokens(c).single.symbol, 'USDC', reason: '过期也必须先返回旧目录');
      expect(api.calls, 1);

      await Future<void>.delayed(Duration.zero);

      expect(_tokens(c).single.symbol, 'USDC', reason: '旧目录远好过空列表');
      final persisted = jsonDecode(prefs.getString(PrefsKey.tokenCatalog.value)!) as Map<String, dynamic>;
      expect(Token.listFromJson(persisted['data']).single.symbol, 'USDC', reason: '绝不能把失败写成空缓存');
    });

    test('从没缓存过：首帧同步就是打包目录（不是 loading），后台补拉', () async {
      final (c, api, _) = await _container();

      expect(_tokens(c).length, BundledTokenCatalog.all.length, reason: '首帧就要有一份完整目录');
      expect(api.calls, 1);

      expect((await c.read(remoteTokensProvider.notifier).ready).single.symbol, 'DAI');
    });

    // 把打包目录写进缓存等于把打包结果当成远端结果，会挡住下次重试。
    test('从没缓存过且请求失败：一直用打包目录，且不把打包目录写入缓存', () async {
      final (c, api, prefs) = await _container(remote: const []);

      expect((await c.read(remoteTokensProvider.notifier).ready).length, BundledTokenCatalog.all.length);
      expect(api.calls, 1);
      // 落的是一份空 JSON（不带 at/data），下次冷启动读到它会退回打包目录并重试；
      // 关键是绝不能把打包目录当成远端结果存进去。
      expect(jsonDecode(prefs.getString(PrefsKey.tokenCatalog.value) ?? '{}'), isEmpty);
    });

    test('脏数据：当作没缓存过，回到打包目录并重取', () async {
      SharedPreferences.setMockInitialValues({PrefsKey.tokenCatalog.value: 'not json'});
      final prefs = await SharedPreferences.getInstance();
      final api = _FakeApi(result: [_dai]);
      final c = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs), tokenCatalogApiProvider.overrideWithValue(api)],
      );
      addTearDown(c.dispose);

      expect(_tokens(c).length, BundledTokenCatalog.all.length);
      await Future<void>.delayed(Duration.zero);
      expect(_tokens(c).single.symbol, 'DAI');
    });

    // 老用户升级后必须直接读得出旧 TokenCatalogCache 的数据：键名与 JSON 结构都不能变。
    test('旧 TokenCatalogCache 的键名与结构仍然读得出', () async {
      SharedPreferences.setMockInitialValues({
        'token_catalog_cache': jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'data': [_usdc.toJson()],
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final api = _FakeApi(result: [_dai]);
      final c = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs), tokenCatalogApiProvider.overrideWithValue(api)],
      );
      addTearDown(c.dispose);

      expect(_tokens(c).single.symbol, 'USDC');
      expect(api.calls, 0);
    });
  });

  group('RemoteTokensNotifier.refresh', () {
    test('无视 TTL 强制重取并落盘', () async {
      final (c, api, prefs) = await _container(age: const Duration(hours: 1));

      expect(api.calls, 0, reason: 'TTL 内，build 不该发请求');
      expect(await c.read(remoteTokensProvider.notifier).refresh(), isTrue);

      expect(api.calls, 1);
      expect(_tokens(c).single.symbol, 'DAI');
      final persisted = jsonDecode(prefs.getString(PrefsKey.tokenCatalog.value)!) as Map<String, dynamic>;
      expect(Token.listFromJson(persisted['data']).single.symbol, 'DAI');
    });

    test('失败返回 false 且旧目录不变', () async {
      final (c, _, _) = await _container(age: const Duration(hours: 1), remote: const []);

      expect(await c.read(remoteTokensProvider.notifier).refresh(), isFalse);
      expect(_tokens(c).single.symbol, 'USDC');
    });
  });
}
