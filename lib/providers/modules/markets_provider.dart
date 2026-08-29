import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasource/remote/coingecko_api.dart' show Markets;
import '../../enums/prefs_key.dart';
import '../coingecko_api_provider.dart';
import '../persistent_notifier.dart';
import '../token_catalog_provider.dart';
import 'currency_provider.dart';

export '../../data/datasource/remote/coingecko_api.dart' show Markets;

/// 一个币种的行情快照：数据 + 写入时刻 + 抓这份数据时请求过的 coinGeckoId。
///
/// 三者都必须进 state：[PersistentNotifier] 只落盘 state，
/// 判过期要用的东西不在里面就落不了盘，重启后也就判不出来。
typedef MarketsSnapshot = ({Markets markets, DateTime? at, Set<String> ids});

/// 行情 state：当前计价币种 + 各币种各自的快照。
///
/// 按币种分槽而不是只留一份，是为了保住旧 MarketsCache 的行为——
/// 切到 CNY 再切回 USD，USD 的旧价格还在，不必空窗等一次往返。
class MarketsState {
  const MarketsState({required this.currency, required this.byCurrency});

  /// 当前计价法币，跟随 [currencyProvider]，不落盘（币种本身由它自己持久化）。
  final String currency;

  /// 币种 -> 该币种的行情快照。
  final Map<String, MarketsSnapshot> byCurrency;

  MarketsSnapshot? get current => byCurrency[currency];

  /// 当前币种的行情：coinGeckoId -> (单价, 图标 URL)。没有任何数据时是空表。
  Markets get markets => current?.markets ?? const {};

  MarketsState withSnapshot(String currency, MarketsSnapshot snapshot) =>
      MarketsState(currency: this.currency, byCurrency: {...byCurrency, currency: snapshot});
}

/// 一份价格都没有、且这次请求也失败了。
///
/// 与「部分链失败」区分开：此时每条链都算不出价值，报成 0 元是误导，
/// 宁可让上层走 error 态。见 [MarketsNotifier.ready]。
class MarketsUnavailable implements Exception {
  const MarketsUnavailable();

  @override
  String toString() => 'MarketsUnavailable: 行情取数失败且本地无任何缓存价格';
}

/// 全部受支持币种的行情：coinGeckoId -> (单价, 图标 URL)。
/// 一次请求覆盖所有链与代币，避免每张卡片重复请求。
///
/// 取数策略是「先旧后新」，与 [chainIconsProvider] 同一套路：
///
/// 1. [restore] 同步读盘 —— 没有 await，[build] 执行完这行旧价格已经在手上；
/// 2. 失效（见 [_isStale]）才发请求，且**不 await**，[build] 立刻带着旧数据返回；
/// 3. 请求回来后 `state = ...`，watcher 自动重建，listenSelf 自动落盘。
///
/// 刻意用同步 [Notifier] 而非 FutureProvider：后者把网络挡在「state 建立」的路上，
/// 缓存一过期首页的价格与代币图标就会空一下窗（`.value` 为 null，图标退回首字母）。
/// 同步 Notifier 里网络在旁边跑，UI 首帧永远有上一次的价格。
///
/// 冷启动、一份缓存都没有时没有旧数据可给，那条路走 [ready]。
class MarketsNotifier extends Notifier<MarketsState> with PersistentNotifier<MarketsState> {
  /// 行情缓存有效期。CoinGecko 免费档约 5~15 次/分钟，超限返回 429，
  /// 因此宁可让价格滞后 5 分钟，也不要把配额耗在来回切页上。
  static const _ttl = Duration(minutes: 5);

  /// 当前目录里要问价的全部 id，随 [tokenCatalogProvider] 变。
  late Set<String> _ids;

  /// 正在飞的那次请求；没有请求在飞时为 null。只给 [ready] 用。
  Future<void>? _pending;

  @override
  PrefsKey get persistKey => PrefsKey.markets;

  /// 只落 [byCurrency]：币种本身跟随 [currencyProvider]，重复存一份只会读到过期值。
  @override
  Map<String, dynamic> toJson(MarketsState state) => {
    'byCurrency': {
      for (final e in state.byCurrency.entries)
        e.key: {
          'at': e.value.at?.millisecondsSinceEpoch,
          'data': {
            for (final m in e.value.markets.entries) m.key: {'price': m.value.price, 'logoUrl': m.value.logoUrl},
          },
          'ids': e.value.ids.toList(),
        },
    },
  };

  @override
  MarketsState fromJson(Map<String, dynamic> json, MarketsState fallback) {
    final raw = json['byCurrency'];
    if (raw is! Map) return fallback;
    return MarketsState(
      currency: fallback.currency, // 币种只认 currencyProvider，不认磁盘
      byCurrency: {
        for (final e in raw.entries)
          if (e.key is String && e.value is Map) e.key as String: _snapshotFromJson(e.value as Map),
      },
    );
  }

  static MarketsSnapshot _snapshotFromJson(Map json) {
    final at = json['at'];
    final data = json['data'];
    final ids = json['ids'];
    return (
      markets: {
        if (data is Map)
          for (final e in data.entries)
            if (e.key is String && e.value is Map && (e.value as Map)['price'] is num)
              e.key as String: (
                price: ((e.value as Map)['price'] as num).toDouble(),
                logoUrl: (e.value as Map)['logoUrl'] as String?,
              ),
      },
      at: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
      ids: ids is List ? ids.whereType<String>().toSet() : const {},
    );
  }

  @override
  MarketsState build() {
    ref.keepAlive();

    final currency = ref.watch(currencyProvider); // 切币种即重建，从磁盘取该币种的旧价格再重取
    // select 字符串：远程目录 loading→data 若 id 集合不变，不会重拉行情。
    _ids = ref.watch(tokenCatalogProvider.select((c) => c.coinGeckoIdsKey)).split(',').toSet();

    final restored = restore(MarketsState(currency: currency, byCurrency: const {})); // 同步读盘

    _pending = _isStale(restored.byCurrency[currency]) ? _fetch(currency) : null; // 刻意不 await

    return restored; // 立刻带着旧价格返回，UI 首帧即有数
  }

  /// 失效有两个维度，任一成立就重取：
  ///
  /// 1. 时间过期（含从没抓过这个币种）；
  /// 2. 落盘那批 id 盖不住当前目录——远程目录新增了代币。
  ///    只判时间的话，新代币最长要等 5 分钟才问得到价，这期间列表里是 0。
  ///
  /// 第 2 条比对「请求过的 id」而不是「行情里已有的 key」：CoinGecko 不认识的 id
  /// 永远不会出现在响应里，按 key 判会退化成每次都重取。
  bool _isStale(MarketsSnapshot? s) =>
      s == null || s.at == null || DateTime.now().difference(s.at!) >= _ttl || _ids.any((id) => !s.ids.contains(id));

  /// 后台取数。返回是否拿到了新数据。
  Future<bool> _fetch(String currency) async {
    final fresh = await ref.read(coinGeckoApiProvider).fetchMarkets(_ids, vsCurrency: currency);

    // 空 map 即失败（数据源约定）：保持旧价格、旧 at 与旧 ids 不动，绝不把失败写成空缓存——
    // 旧价格远好过 $0.00。
    if (fresh.isEmpty) return false;
    // fire-and-forget 期间 provider 可能已销毁，此时赋值会抛。
    if (!ref.mounted) return false;

    state = state.withSnapshot(currency, (markets: fresh, at: DateTime.now(), ids: _ids)); // listenSelf 自动落盘
    return true;
  }

  /// 下拉刷新：无视 TTL 强制重取。返回是否取到了新数据——失败时旧价格原封不动。
  ///
  /// 不需要调用方再 invalidate：拿到新数据就直接赋值 state，watcher 自动重建。
  Future<bool> refresh() => _fetch(state.currency);

  /// 给「必须有价格才算得下去」的调用方用：一份缓存都没有时等这次请求落地。
  ///
  /// 已有旧价格就立刻返回，不会因为后台在刷新而多等一个往返。
  /// 请求失败且没有任何旧价格 → 抛 [MarketsUnavailable]，让上层走 error 态而不是报成 0。
  Future<Markets> get ready async {
    if (state.markets.isNotEmpty) return state.markets;
    await _pending;
    if (state.markets.isEmpty) throw const MarketsUnavailable();
    return state.markets;
  }
}

final marketsProvider = NotifierProvider<MarketsNotifier, MarketsState>(MarketsNotifier.new);
