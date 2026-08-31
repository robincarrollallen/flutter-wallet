import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../blockchain/chain_registry.dart';
import '../../data/datasource/remote/coingecko_api.dart' show ChainIcons;
import '../../enums/prefs_key.dart';
import '../coingecko_api_provider.dart';
import '../persistent_notifier.dart';

export '../../data/datasource/remote/coingecko_api.dart' show ChainIcons;

/// 定义状态类型: 数据内容, 缓存时刻(过期更新)，缓存集合(新增更新)
typedef ChainIconsState = ({ChainIcons icons, DateTime? at, Set<String> ids});

/// 各链自己的图标：平台 id -> 图标 URL。
class ChainIconsNotifier extends Notifier<ChainIconsState> with PersistentNotifier<ChainIconsState> {
  static const _ttl = Duration(days: 7); // 缓存过期时长
  static final _supportedPlatformIds =
      SupportedChains.all.map((c) => c.coinGeckoPlatformId).whereType<String>().toSet(); // 需要图标的平台 id 合集(只取用到的平台，其余 400 多个不进缓存)

  @override
  PrefsKey get persistKey => PrefsKey.chainIcons; // 定义持久化标识<persistKey>(重写)

  /// 定义持久化内容(重写): 缓存时刻 `at`，数据内容 `data`，缓存对应ID合集 `ids`
  @override
  Map<String, dynamic> toJson(ChainIconsState state) => {
    'at': state.at?.millisecondsSinceEpoch,
    'data': state.icons,
    'ids': state.ids.toList(),
  };

  /// 初始化设置(重写)
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

  /// 构建逻辑(重写)
  @override
  ChainIconsState build() {
    ref.keepAlive();
    
    final restored = restore((icons: const {}, at: null, ids: const {})); // 同步读盘：这一行返回时旧图标已经在手上了。

    if (_isStale(restored)) unawaited(_refresh()); // 失效（或从没存过）才发请求，且刻意不 await——build 不会停在这里等网络。

    return restored; // 立刻带着旧数据返回，UI 首帧即有图标。
  }

  bool _isStale(ChainIconsState cached) =>
      _isExpired(cached.at) || _supportedPlatformIds.any((id) => !cached.ids.contains(id)); // 是否持久化数据失效(1. 时间过期, 2. 允许链的 CoinGecko ID 集合是否与缓存的 ID 合集一致)

  bool _isExpired(DateTime? at) => at == null || DateTime.now().difference(at) >= _ttl; // 缓存是否过期

  /// 重新获取图标。几秒后网络回来才走到赋值那行，此时 [build] 早已返回。
  Future<void> _refresh() async {
    final fresh = await ref.read(coinGeckoApiProvider).fetchChainIcons(_supportedPlatformIds); // 获取链图标<CoinGecko>

    if (fresh.isEmpty) return; // 空 map 即失败<不更新>：保持旧图标、旧 at 与旧 ids 不动，下次启动再试，
    if (!ref.mounted) return; //  如果Provider销毁, 不更新。

    state = (icons: fresh, at: DateTime.now(), ids: _supportedPlatformIds); // listenSelf 监听到，自动落盘
  }
}

/// 链图标状态管理<落盘持久化>
final chainIconsProvider = NotifierProvider<ChainIconsNotifier, ChainIconsState>(ChainIconsNotifier.new);
