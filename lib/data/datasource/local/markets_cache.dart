import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../remote/coingecko_api.dart' show Markets;

/// 行情的落盘缓存：只管读写与序列化，TTL 判定与失败回退归 repository。
///
/// 按币种分键：切换法币后不会读到上一币种的价格，切回来也仍能命中各自的缓存。
class MarketsCache {
  const MarketsCache(this._prefs);

  final SharedPreferences _prefs;

  static String _key(String currency) => 'markets_cache_$currency';

  /// 读取落盘缓存。返回 (数据, 写入时刻)；无缓存或脏数据时返回 (null, null)。
  (Markets?, DateTime?) read(String currency) {
    final raw = _prefs.getString(_key(currency));
    if (raw == null) return (null, null);
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.fromMillisecondsSinceEpoch(json['at'] as int);
      final data = (json['data'] as Map<String, dynamic>).map(
        (id, v) => MapEntry(id, (price: (v['price'] as num).toDouble(), logoUrl: v['logoUrl'] as String?)),
      );
      return (data, at);
    } catch (_) {
      // 脏数据 / 结构变更：当作没缓存过，走网络重取。
      return (null, null);
    }
  }

  /// 把行情连同写入时刻落盘。
  Future<void> write(String currency, Markets markets) {
    final json = {
      'at': DateTime.now().millisecondsSinceEpoch,
      'data': {
        for (final e in markets.entries) e.key: {'price': e.value.price, 'logoUrl': e.value.logoUrl},
      },
    };
    return _prefs.setString(_key(currency), jsonEncode(json));
  }
}
