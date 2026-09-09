import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../persistent_notifier.dart';
import '../../i18n/translations.g.dart';
import '../../enums/prefs_key.dart';

/// 应用语言，用 PersistentNotifier 持久化。
///
/// slang 自身不持久化用户的语言选择，这里包一层：
/// - 写时由 toJson 决定存什么，读时 fromJson 全量恢复。
/// - build() 把初值（设备语言）交给 restore()，再同步给 slang。
/// - set() 改 state 即自动落盘；额外需要通知 slang，所以仍手动调 LocaleSettings。
class LocaleNotifier extends Notifier<AppLocale> with PersistentNotifier<AppLocale> {
  @override
  PrefsKey get persistKey => PrefsKey.locale; // 定义持久化标识<persistKey>(重写)

  /// 定义持久化内容(重写)
  @override
  Map<String, dynamic> toJson(AppLocale state) => {'locale': state.languageTag}; // 定义持久化内容

  /// 还原状态
  @override
  AppLocale fromJson(Map<String, dynamic> json, AppLocale fallback) {
    final tag = json['locale'];
    return tag is String ? AppLocaleUtils.parse(tag) : fallback;
  }

  @override
  AppLocale build() {
    final locale = restore(AppLocaleUtils.findDeviceLocale()); // 让 context.t / TranslationProvider 使用该 locale。
    LocaleSettings.setLocale(locale);
    return locale;
  }

  void set(AppLocale locale) {
    state = locale; // 落盘<持久化>
    LocaleSettings.setLocale(locale);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, AppLocale>(LocaleNotifier.new);
