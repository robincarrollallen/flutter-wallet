import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../blockchain/token.dart';

/// 远程代币目录的落盘缓存：只管读写与序列化，TTL 判定与失败回退归 repository。
class TokenCatalogCache {
  const TokenCatalogCache(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'token_catalog_cache';

  /// 读取落盘缓存。返回 (数据, 写入时刻)；无缓存或脏数据时返回 (null, null)。
  (List<Token>?, DateTime?) read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return (null, null);
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.fromMillisecondsSinceEpoch(json['at'] as int);
      final tokens = Token.listFromJson(json['data']);
      return (tokens, at);
    } catch (_) {
      return (null, null);
    }
  }

  /// 把目录连同写入时刻落盘。
  Future<void> write(List<Token> tokens) {
    final json = {'at': DateTime.now().millisecondsSinceEpoch, 'data': tokens.map((t) => t.toJson()).toList()};
    return _prefs.setString(_key, jsonEncode(json));
  }
}
