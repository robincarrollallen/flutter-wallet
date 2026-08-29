import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../blockchain/chain_registry.dart';
import '../../data/datasource/remote/coingecko_api.dart' show ChainIcons;
import '../../enums/prefs_key.dart';
import '../market_repository_provider.dart';
import '../persistent_notifier.dart';

export '../../data/datasource/remote/coingecko_api.dart' show ChainIcons;

/// 链图标 + 这批数据的写入时刻 + 抓这批数据时请求过的平台 id。
///
/// [at] 与 [ids] 都必须进 state：[PersistentNotifier] 只落盘 state，
/// 判过期要用的东西不在里面就落不了盘，重启后也就判不出来。
typedef ChainIconsState = ({ChainIcons icons, DateTime? at, Set<String> ids});

/// 各链自己的图标：平台 id -> 图标 URL。
///
/// 取数策略是「先旧后新」，靠 [PersistentNotifier] 一把做完：
///
/// 1. [restore] 同步读盘 —— 没有 await，[build] 执行完这行就已经拿到旧图标；
/// 2. 失效（见 [ChainIconsNotifier._isStale]）才发请求，且**不 await**，
///    [build] 立刻带着旧数据返回，UI 首帧就有图标；
/// 3. 请求回来后 `state = ...`，watcher 自动重建，[restore] 挂的 listenSelf 自动落盘。
///
/// 与行情不同，这里刻意用同步 [Notifier] 而非 FutureProvider：后者把网络挡在
/// 「state 建立」的路上，缓存一过期首页就会空一下窗；同步 Notifier 里网络在旁边跑。
///
/// 也刻意不参与下拉刷新：图标不是行情，没有刷新的必要。
class ChainIconsNotifier extends Notifier<ChainIconsState> with PersistentNotifier<ChainIconsState> {
  /// 链 logo 基本不变，没有任何实时性要求，给足 7 天把这次请求摊薄到可忽略
  /// ——它与行情共用 CoinGecko 的限流配额。
  static const _ttl = Duration(days: 7);

  /// 只取配置里实际用到的平台，其余 400 多个不进缓存。
  static final _ids = SupportedChains.all.map((c) => c.coinGeckoPlatformId).whereType<String>().toSet();

  @override
  PrefsKey get persistKey => PrefsKey.chainIcons;

  /// `at` / `data` 两个键沿用旧的 ChainIconsCache，老用户升级后直接读得出旧缓存；
  /// `ids` 是后加的，老数据里没有，读出来是空集合——正好被 [_isStale] 判为过期，
  /// 升级后首次冷启动补拉一次即自愈。
  @override
  Map<String, dynamic> toJson(ChainIconsState state) => {
    'at': state.at?.millisecondsSinceEpoch,
    'data': state.icons,
    'ids': state.ids.toList(),
  };

  @override
  ChainIconsState fromJson(Map<String, dynamic> json, ChainIconsState fallback) {
    final at = json['at'];
    final data = json['data'];
    final ids = json['ids'];
    if (data is! Map) return fallback;
    return (
      icons: {
        for (final e in data.entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
      },
      at: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
      ids: ids is List ? ids.whereType<String>().toSet() : const {},
    );
  }

  @override
  ChainIconsState build() {
    ref.keepAlive();
    
    final restored = restore((icons: const {}, at: null, ids: const {})); // 同步读盘：这一行返回时旧图标已经在手上了。

    if (_isStale(restored)) unawaited(_refresh()); // 失效（或从没存过）才发请求，且刻意不 await——build 不会停在这里等网络。

    return restored; // 立刻带着旧数据返回，UI 首帧即有图标。
  }

  /// 失效有两个维度，任一成立就重取：
  ///
  /// 1. 时间过期；
  /// 2. 落盘那批 id 盖不住当前的 [_ids]——版本更新新增了链。
  ///    只判时间的话，新链的图标要等上一次落盘满 7 天才补得上，这期间共用 ETH 计价的
  ///    L2 会一路回退到以太坊的 logo，几条链在地址列表里长得一模一样。
  ///
  /// 第 2 条刻意比对「请求过的 id」而不是「图标里已有的 key」：`asset_platforms` 里
  /// 有些平台压根没带 image 字段，那种 id 永远补不齐，按 key 判会退化成每次冷启动
  /// 都重拉一次 184 KB 的整包。
  bool _isStale(ChainIconsState s) => _isExpired(s.at) || _ids.any((id) => !s.ids.contains(id));

  bool _isExpired(DateTime? at) => at == null || DateTime.now().difference(at) >= _ttl;

  /// 后台重取。几秒后网络回来才走到赋值那行，此时 [build] 早已返回。
  Future<void> _refresh() async {
    final fresh = await ref.read(coinGeckoApiProvider).fetchChainIcons(_ids);

    // 空 map 即失败（数据源约定）：保持旧图标、旧 at 与旧 ids 不动，下次启动再试，
    // 绝不把「失败」写成空缓存——旧图标远好过首字母占位。
    // 新增链恰好碰上失败也一样：ids 没更新，下次冷启动照样判失效。
    if (fresh.isEmpty) return;
    // fire-and-forget 期间 provider 可能已销毁，此时赋值会抛。
    if (!ref.mounted) return;

    state = (icons: fresh, at: DateTime.now(), ids: _ids); // listenSelf 监听到，自动落盘
  }
}

final chainIconsProvider = NotifierProvider<ChainIconsNotifier, ChainIconsState>(ChainIconsNotifier.new);
