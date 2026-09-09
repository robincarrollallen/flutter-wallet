import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../persistent_notifier.dart';
import '../../enums/app_theme_name.dart';
import '../../enums/prefs_key.dart';

/// 外观状态：同时持有「主题名称」与「主题模式」两个属性
@immutable // 注解: 字段全是 final，建好就不能改(可以更改对象中的字段值)
class Appearance {
  const Appearance({required this.themeName, required this.themeMode});

  final AppThemeName themeName; // 选中的配色（亮色 / 暗色），驱动 MaterialApp 的 theme / darkTheme 取向
  final ThemeMode themeMode; // 显示模式（跟随系统 / 白天 / 黑夜），驱动 MaterialApp 的 themeMode

  Appearance copyWith({AppThemeName? themeName, ThemeMode? themeMode}) => Appearance(themeName: themeName ?? this.themeName, themeMode: themeMode ?? this.themeMode);
}

/// 外观（主题 + 模式）状态，用 PersistentNotifier 持久化两个字段。
class AppearanceNotifier extends Notifier<Appearance> with PersistentNotifier<Appearance> {
  @override
  PrefsKey get persistKey => PrefsKey.appearance; // 定义持久化标识<persistKey>(重写)

  /// 定义持久化内容(重写)
  @override
  Map<String, dynamic> toJson(Appearance state) => {
    'themeName': state.themeName.name,
    'themeMode': state.themeMode.name,
  };

  /// 还原状态
  @override
  Appearance fromJson(Map<String, dynamic> json, Appearance fallback) => fallback.copyWith(
    themeName: AppThemeName.values.asNameMap()[json['themeName']],
    themeMode: ThemeMode.values.asNameMap()[json['themeMode']],
  );

  /// 初始化设置
  @override
  Appearance build() => restore(const Appearance(themeName: AppThemeName.light, themeMode: ThemeMode.system));

  /// 选择「模式」：白天 / 黑夜同时把主题名同步过去；跟随系统时保留原主题名(自动落盘<持久化>：restore 中 的 listenSelf 监听)
  void setMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        state = state.copyWith(themeMode: mode, themeName: AppThemeName.light);
      case ThemeMode.dark:
        state = state.copyWith(themeMode: mode, themeName: AppThemeName.dark);
      case ThemeMode.system:
        state = state.copyWith(themeMode: mode);
    }
  }

  /// 选择「主题」：主题名与其对应模式一起更新（亮色→白天，暗色→黑夜）。
  void setThemeName(AppThemeName name) => state = state.copyWith(themeName: name, themeMode: name.mode);
}

/// 供外部调用(ref.read, ref.watch...)
final appearanceProvider = NotifierProvider<AppearanceNotifier, Appearance>(AppearanceNotifier.new);
