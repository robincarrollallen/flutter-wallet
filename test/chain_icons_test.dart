import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/data/datasource/remote/coingecko_api.dart';
import 'package:wallet/enums/prefs_key.dart';
import 'package:wallet/providers/market_repository_provider.dart';
import 'package:wallet/providers/modules/chain_icon_provider.dart';
import 'package:wallet/providers/prefs_provider.dart';

/// 假数据源：记录被调用次数，好断言「命中缓存时一次请求都不发」。
class _FakeApi implements CoinGeckoApi {
  _FakeApi(this.result);

  /// 返回给 fetchChainIcons 的结果；空 map 即代表失败（数据源约定）。
  final ChainIcons result;
  int calls = 0;

  @override
  Future<ChainIcons> fetchChainIcons(Iterable<String> platformIds) async {
    calls++;
    return result;
  }

  @override
  Future<Markets> fetchMarkets(Iterable<String> ids, {String vsCurrency = 'usd'}) async => const {};
}

const _old = {'ethereum': 'https://old/eth.png'};
const _fresh = {'ethereum': 'https://new/eth.png'};

/// 当前版本会请求的全部平台 id，即缓存「不缺链」时该存下来的那批。
/// 现算而非硬编码：新增链只改 [SupportedChains]，这里跟着走。
final _allIds = SupportedChains.all.map((c) => c.coinGeckoPlatformId).whereType<String>().toList();

/// 造一个预置了落盘缓存的容器。[age] 为 null 表示完全没有缓存。
///
/// [ids] 是「上次抓这份缓存时请求过的平台 id」，默认与当前版本一致（不缺链）；
/// [legacy] 为 true 则连 ids 键都不写，模拟加这个字段之前的老格式缓存。
Future<(ProviderContainer, _FakeApi, SharedPreferences)> _container({
  Duration? age,
  ChainIcons remote = _fresh,
  List<String>? ids,
  bool legacy = false,
}) async {
  SharedPreferences.setMockInitialValues({
    if (age != null)
      PrefsKey.chainIcons.value: jsonEncode({
        'at': DateTime.now().subtract(age).millisecondsSinceEpoch,
        'data': _old,
        if (!legacy) 'ids': ids ?? _allIds,
      }),
  });
  final prefs = await SharedPreferences.getInstance();
  final api = _FakeApi(remote);
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs), coinGeckoApiProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  return (container, api, prefs);
}

/// 读回落盘的那份 JSON。
Map<String, dynamic> _persisted(SharedPreferences prefs) =>
    jsonDecode(prefs.getString(PrefsKey.chainIcons.value)!) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('chainIconsProvider', () {
    test('缓存未过期且链没变：首次读同步拿到旧图标，一次请求都不发', () async {
      final (c, api, _) = await _container(age: const Duration(days: 1));

      expect(c.read(chainIconsProvider).icons, _old);
      expect(api.calls, 0, reason: 'TTL 内且 id 集合已覆盖，不该发请求');

      // 再等一拍，确认没有迟到的后台请求。
      await Future<void>.delayed(Duration.zero);
      expect(api.calls, 0);
    });

    // 只判时间的话，新链图标要等旧缓存满 7 天才补得上。
    test('版本更新新增了链：TTL 内也重取，首帧仍是旧图标', () async {
      final (c, api, prefs) = await _container(
        age: const Duration(days: 1),
        ids: _allIds.sublist(1), // 少一条链，模拟上个版本抓的那批 id
      );

      expect(c.read(chainIconsProvider).icons, _old, reason: '缺链也不能空窗，先把旧图标交出去');
      expect(api.calls, 1, reason: 'id 集合盖不住当前配置，必须重取');

      await Future<void>.delayed(Duration.zero);

      expect(c.read(chainIconsProvider).icons, _fresh);
      expect(_persisted(prefs)['ids'], unorderedEquals(_allIds), reason: '落盘的 ids 应补齐到全量，下次启动才不会再判失效');
    });

    test('老格式缓存（没有 ids 键）：升级后首次冷启动补拉一次', () async {
      final (c, api, prefs) = await _container(age: const Duration(days: 1), legacy: true);

      expect(c.read(chainIconsProvider).icons, _old);
      expect(api.calls, 1);

      await Future<void>.delayed(Duration.zero);

      expect(_persisted(prefs)['ids'], unorderedEquals(_allIds), reason: '补上 ids 后即自愈，不该每次启动都拉');
    });

    // 本次改动的核心：过期时**不等网络**，先把旧图标交出去。
    test('缓存已过期：首帧仍是旧图标，请求回来后才换成新的并落盘', () async {
      final (c, api, prefs) = await _container(age: const Duration(days: 8));

      expect(c.read(chainIconsProvider).icons, _old, reason: '过期也必须先返回旧值，不能空窗');
      expect(api.calls, 1);

      await Future<void>.delayed(Duration.zero);

      expect(c.read(chainIconsProvider).icons, _fresh);
      expect(_persisted(prefs)['data'], _fresh, reason: 'listenSelf 应已自动落盘');
      expect(
        DateTime.now().millisecondsSinceEpoch - (_persisted(prefs)['at'] as int),
        lessThan(5000),
        reason: '写入时刻应一并更新，否则下次启动又判过期',
      );
    });

    test('请求失败（空 map）：state 与落盘都保持旧值', () async {
      final (c, api, prefs) = await _container(age: const Duration(days: 8), remote: const {});

      c.read(chainIconsProvider); // provider 是惰性的，先读一次才会触发后台重取
      await Future<void>.delayed(Duration.zero);

      expect(api.calls, 1);
      expect(c.read(chainIconsProvider).icons, _old, reason: '旧图标远好过首字母占位');
      expect(_persisted(prefs)['data'], _old, reason: '绝不能把失败写成空缓存');
    });

    test('从没缓存过：首帧为空，请求回来后补上', () async {
      final (c, api, prefs) = await _container();

      expect(c.read(chainIconsProvider).icons, isEmpty);
      expect(api.calls, 1);

      await Future<void>.delayed(Duration.zero);

      expect(c.read(chainIconsProvider).icons, _fresh);
      expect(_persisted(prefs)['data'], _fresh);
    });

    test('脏数据：当作没缓存过，重新取', () async {
      SharedPreferences.setMockInitialValues({PrefsKey.chainIcons.value: 'not json'});
      final prefs = await SharedPreferences.getInstance();
      final api = _FakeApi(_fresh);
      final c = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs), coinGeckoApiProvider.overrideWithValue(api)],
      );
      addTearDown(c.dispose);

      expect(c.read(chainIconsProvider).icons, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(chainIconsProvider).icons, _fresh);
    });
  });
}
