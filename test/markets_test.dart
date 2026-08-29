import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/constants/currency_symbols.dart';
import 'package:wallet/data/datasource/remote/coingecko_api.dart';
import 'package:wallet/enums/prefs_key.dart';
import 'package:wallet/providers/coingecko_api_provider.dart';
import 'package:wallet/providers/modules/currency_provider.dart';
import 'package:wallet/providers/modules/markets_provider.dart';
import 'package:wallet/providers/prefs_provider.dart';
import 'package:wallet/providers/token_catalog_provider.dart';

/// 假数据源：记录被调用次数与币种，好断言「命中缓存时一次请求都不发」。
class _FakeApi implements CoinGeckoApi {
  _FakeApi(this.price);

  /// 返回给 fetchMarkets 的单价；null 表示这次请求失败（数据源约定：返回空 map）。
  final double? price;
  int calls = 0;
  final currencies = <String>[];

  @override
  Future<Markets> fetchMarkets(Iterable<String> ids, {String vsCurrency = 'usd'}) async {
    calls++;
    currencies.add(vsCurrency);
    if (price == null) return const {};
    return {for (final id in ids) id: (price: price!, logoUrl: 'https://new/$id.png')};
  }

  @override
  Future<ChainIcons> fetchChainIcons(Iterable<String> platformIds) async => const {};
}

/// 造一个预置了落盘缓存的容器。[age] 为 null 表示完全没有缓存。
///
/// [ids] 是「上次抓这份缓存时请求过的 coinGeckoId」，默认与当前目录一致（不缺币）。
/// 落盘的旧价格固定 1.0，远端新价格固定 [remote]，两者不同才分得清用的是哪一份。
Future<(ProviderContainer, _FakeApi, SharedPreferences)> _container({
  Duration? age,
  double? remote = 9.0,
  List<String>? ids,
  String currency = defaultCurrencyCode,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _FakeApi(remote);
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs), coinGeckoApiProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);

  // 目录 id 要从容器里现取（远程目录 loading 时用打包目录兜底），
  // 硬编码的话新增代币就会把「id 集合没变」这条判定测歪。
  final catalogIds = container.read(tokenCatalogProvider).coinGeckoIds.toList();
  if (age != null) {
    await prefs.setString(
      PrefsKey.markets.value,
      jsonEncode({
        'byCurrency': {
          currency: {
            'at': DateTime.now().subtract(age).millisecondsSinceEpoch,
            'data': {
              for (final id in catalogIds) id: {'price': 1.0, 'logoUrl': 'https://old/$id.png'},
            },
            'ids': ids ?? catalogIds,
          },
        },
      }),
    );
  }
  return (container, api, prefs);
}

/// 取任意一个币的单价——各币价格在本文件里恒等，取第一个即可代表整份快照。
double _anyPrice(ProviderContainer c) => c.read(marketsProvider).markets.values.first.price;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('marketsProvider', () {
    test('缓存未过期且目录没变：首次读同步拿到旧价格，一次请求都不发', () async {
      final (c, api, _) = await _container(age: const Duration(minutes: 1));

      expect(_anyPrice(c), 1.0);
      expect(api.calls, 0, reason: 'TTL 内且 id 集合已覆盖，不该发请求');

      await Future<void>.delayed(Duration.zero);
      expect(api.calls, 0, reason: '也不该有迟到的后台请求');
    });

    // 本次改动的核心：过期时**不等网络**，先把旧价格交出去。
    test('缓存已过期：首帧仍是旧价格，请求回来后才换成新的并落盘', () async {
      final (c, api, prefs) = await _container(age: const Duration(minutes: 6));

      expect(_anyPrice(c), 1.0, reason: '过期也必须先返回旧价，不能空窗到 \$0.00');
      expect(api.calls, 1);

      await Future<void>.delayed(Duration.zero);

      expect(_anyPrice(c), 9.0);
      final persisted = jsonDecode(prefs.getString(PrefsKey.markets.value)!) as Map<String, dynamic>;
      final slot = (persisted['byCurrency'] as Map)[defaultCurrencyCode] as Map;
      expect(((slot['data'] as Map).values.first as Map)['price'], 9.0, reason: 'listenSelf 应已自动落盘');
    });

    // 只判时间的话，新代币最长要等 5 分钟才问得到价，这期间列表里是 0。
    test('目录新增了代币：TTL 内也重取，首帧仍是旧价格', () async {
      final (c, api, _) = await _container(
        age: const Duration(minutes: 1),
        ids: const ['ethereum'], // 只抓过一个 id，模拟上个版本的目录
      );

      expect(_anyPrice(c), 1.0, reason: '缺币也不能空窗，先把旧价交出去');
      expect(api.calls, 1, reason: 'id 集合盖不住当前目录，必须重取');

      await Future<void>.delayed(Duration.zero);
      expect(_anyPrice(c), 9.0);
    });

    test('请求失败（空 map）：state 与落盘都保持旧价格', () async {
      final (c, api, prefs) = await _container(age: const Duration(minutes: 6), remote: null);

      expect(_anyPrice(c), 1.0);
      await Future<void>.delayed(Duration.zero);

      expect(api.calls, 1);
      expect(_anyPrice(c), 1.0, reason: '旧价格远好过 \$0.00');
      final persisted = jsonDecode(prefs.getString(PrefsKey.markets.value)!) as Map<String, dynamic>;
      final slot = (persisted['byCurrency'] as Map)[defaultCurrencyCode] as Map;
      expect(((slot['data'] as Map).values.first as Map)['price'], 1.0, reason: '绝不能把失败写成空缓存');
    });

    test('从没缓存过：首帧为空，ready 等到这次请求落地', () async {
      final (c, api, _) = await _container();

      expect(c.read(marketsProvider).markets, isEmpty);
      expect(api.calls, 1);

      final markets = await c.read(marketsProvider.notifier).ready;
      expect(markets.values.first.price, 9.0);
    });

    // 一份价格都没有 + 请求也失败：报成 0 元是误导，必须让上层走 error 态。
    test('从没缓存过且请求失败：ready 抛 MarketsUnavailable', () async {
      final (c, _, _) = await _container(remote: null);

      expect(c.read(marketsProvider.notifier).ready, throwsA(isA<MarketsUnavailable>()));
    });

    test('已有旧价格时 ready 立刻返回，不等后台那次刷新', () async {
      final (c, api, _) = await _container(age: const Duration(minutes: 6));

      expect((await c.read(marketsProvider.notifier).ready).values.first.price, 1.0);
      expect(api.calls, 1, reason: '后台刷新照发，只是 ready 不等它');
    });

    test('脏数据：当作没缓存过，重新取', () async {
      SharedPreferences.setMockInitialValues({PrefsKey.markets.value: 'not json'});
      final prefs = await SharedPreferences.getInstance();
      final api = _FakeApi(9.0);
      final c = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs), coinGeckoApiProvider.overrideWithValue(api)],
      );
      addTearDown(c.dispose);

      expect(c.read(marketsProvider).markets, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(_anyPrice(c), 9.0);
    });

    // 按币种分槽的意义：切走再切回来，原币种的旧价格还在，不必空窗等一次往返。
    test('切换币种：新币种先空窗后重取，切回原币种仍命中旧缓存', () async {
      final (c, api, _) = await _container(age: const Duration(minutes: 1));

      expect(_anyPrice(c), 1.0);
      expect(api.calls, 0);

      c.read(currencyProvider.notifier).set('CNY');
      expect(c.read(marketsProvider).markets, isEmpty, reason: 'CNY 从没抓过，只能空窗');
      expect(api.calls, 1);
      expect(api.currencies.single, 'CNY', reason: '大小写由数据源自己转，provider 原样传币种代码');

      await Future<void>.delayed(Duration.zero);
      expect(_anyPrice(c), 9.0);

      c.read(currencyProvider.notifier).set(defaultCurrencyCode);
      expect(_anyPrice(c), 1.0, reason: '原币种的槽位还在，切回来立刻有价');
      expect(api.calls, 1, reason: '该槽位仍在 TTL 内，不该再发请求');
    });
  });
}
