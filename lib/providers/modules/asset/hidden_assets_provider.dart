import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../enums/prefs_key.dart';
import '../persistent_notifier.dart';

/// 用户手动隐藏的资产身份键集合（见 `ListedAsset.key`），持久化到 SharedPreferences。
///
/// 刻意存「隐藏集合」而非「可见集合」：远程目录随时会下发新代币，
/// 存可见集合的话新币会默认消失，存隐藏集合则天然默认可见。
class HiddenAssetsNotifier extends Notifier<Set<String>> with PersistentNotifier<Set<String>> {
  @override
  Set<String> build() => restore(const {});

  @override
  PrefsKey get persistKey => PrefsKey.hiddenAssets;

  @override
  Map<String, dynamic> toJson(Set<String> state) => {'keys': state.toList()};

  @override
  Set<String> fromJson(Map<String, dynamic> json, Set<String> fallback) {
    final keys = json['keys'];
    if (keys is! List) return fallback;
    return {
      for (final k in keys)
        if (k is String && k.isNotEmpty) k,
    };
  }

  bool isHidden(String key) => state.contains(key);

  void hide(String key) => state = {...state, key};

  void show(String key) => state = {
    for (final k in state)
      if (k != key) k,
  };

  void toggle(String key) => isHidden(key) ? show(key) : hide(key);
}

final hiddenAssetsProvider = NotifierProvider<HiddenAssetsNotifier, Set<String>>(HiddenAssetsNotifier.new);
