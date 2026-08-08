import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../remote/coingecko_api.dart' show ChainIcons;

/// 链图标的落盘缓存：只管读写与序列化，TTL 判定与失败回退归 repository。
class ChainIconsCache {
  const ChainIconsCache(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'chain_icons_cache';

  /// 读取落盘缓存。返回 (数据, 写入时刻)；无缓存或脏数据时返回 (null, null)。
  (ChainIcons?, DateTime?) read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return (null, null);
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.fromMillisecondsSinceEpoch(json['at'] as int);
      final data = (json['data'] as Map<String, dynamic>).map((id, url) => MapEntry(id, url as String));
      return (data, at);
    } catch (_) {
      // 脏数据 / 结构变更：当作没缓存过，走网络重取。
      return (null, null);
    }
  }

  /// 把链图标连同写入时刻落盘。
  Future<void> write(ChainIcons icons) {
    final json = {'at': DateTime.now().millisecondsSinceEpoch, 'data': icons};
    return _prefs.setString(_key, jsonEncode(json));
  }
}
