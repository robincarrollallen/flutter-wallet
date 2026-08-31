import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../blockchain/token.dart';
import '../../blockchain/token_catalog.dart';
import '../../enums/prefs_key.dart';
import '../persistent_notifier.dart';

/// 用户手动添加的代币，持久化到 SharedPreferences。
///
/// 与远程目录生命周期不同：远程是只读缓存，这里是用户写入。
/// 合并发生在 [tokenCatalogProvider]，不要在 UI 里自己拼。
class CustomTokensNotifier extends Notifier<List<Token>> with PersistentNotifier<List<Token>> {
  @override
  List<Token> build() => restore(const []);

  @override
  PrefsKey get persistKey => PrefsKey.customTokens;

  @override
  Map<String, dynamic> toJson(List<Token> state) => {'tokens': state.map((t) => t.toJson()).toList()};

  @override
  List<Token> fromJson(Map<String, dynamic> json, List<Token> fallback) {
    if (json['tokens'] is! List) return fallback;
    return Token.listFromJson(json['tokens']);
  }

  /// 同身份键则原地替换（自定义覆盖自己上次填的 decimals / 符号），否则追加。
  void add(Token token) {
    final key = TokenCatalog.identityKey(token);
    if (state.any((t) => TokenCatalog.identityKey(t) == key)) {
      state = [
        for (final t in state)
          if (TokenCatalog.identityKey(t) == key) token else t,
      ];
    } else {
      state = [...state, token];
    }
  }

  void remove(Token token) {
    final key = TokenCatalog.identityKey(token);
    state = [
      for (final t in state)
        if (TokenCatalog.identityKey(t) != key) t,
    ];
  }
}

final customTokensProvider = NotifierProvider<CustomTokensNotifier, List<Token>>(CustomTokensNotifier.new);
