import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/wallet/domain/chain.dart';
import '../prefs_provider.dart';
import 'balance_provider.dart';

/// 链图标类型别名：CoinGecko 平台 id -> 图标 URL。
typedef ChainIcons = Map<String, String>;

/// 链图标缓存在 SharedPreferences 中的存储键。
const _chainIconsCacheKey = 'chain_icons_cache';

/// 链图标缓存有效期。链 logo 基本不变，没有任何实时性要求，
/// 给足 7 天把这次请求摊薄到可忽略——它与行情共用 CoinGecko 的限流配额。
const _chainIconsTtl = Duration(days: 7);

/// 各链自己的图标：平台 id -> 图标 URL。
///
/// 结构与 [marketsProvider] 一致（keepAlive + 落盘 TTL + 失败回退旧缓存），
/// 只是数据更简单、TTL 长得多。刻意不参与下拉刷新：图标不是行情，没有刷新的必要。
final chainIconsProvider = FutureProvider<ChainIcons>((ref) async {
  ref.keepAlive();
  final prefs = ref.watch(sharedPrefsProvider);

  final (cached, cachedAt) = _readCache(prefs);
  if (cached != null && DateTime.now().difference(cachedAt!) < _chainIconsTtl) {
    return cached;
  }

  // 只取配置里实际用到的平台，其余 400 多个不进缓存。
  final ids = SupportedChains.all
      .map((c) => c.coinGeckoPlatformId)
      .whereType<String>();
  final fresh = await ref.watch(walletServiceProvider).fetchChainIcons(ids);

  // 空即代表失败：退回旧缓存，图标宁可旧也不要变回首字母。
  if (fresh.isEmpty) return cached ?? const {};

  await _writeCache(prefs, fresh);
  return fresh;
});

/// 读取落盘的链图标缓存。返回 (数据, 写入时刻)；无缓存或脏数据时返回 (null, null)。
(ChainIcons?, DateTime?) _readCache(SharedPreferences prefs) {
  final raw = prefs.getString(_chainIconsCacheKey);
  if (raw == null) return (null, null);
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final at = DateTime.fromMillisecondsSinceEpoch(json['at'] as int);
    final data = (json['data'] as Map<String, dynamic>).map(
      (id, url) => MapEntry(id, url as String),
    );
    return (data, at);
  } catch (_) {
    // 脏数据 / 结构变更：当作没缓存过，走网络重取。
    return (null, null);
  }
}

/// 把链图标连同写入时刻落盘。
Future<void> _writeCache(SharedPreferences prefs, ChainIcons icons) {
  final json = {
    'at': DateTime.now().millisecondsSinceEpoch,
    'data': icons,
  };
  return prefs.setString(_chainIconsCacheKey, jsonEncode(json));
}
