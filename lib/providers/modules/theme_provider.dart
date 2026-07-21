import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../persistent_notifier.dart';

/// 主题名称：当前支持亮色 / 暗色两套配色，各自有独立的种子色。
enum AppThemeName {
  light,
  dark;

  /// 该主题对应的展示模式（亮色→白天，暗色→黑夜）。
  ThemeMode get mode =>
      this == AppThemeName.light ? ThemeMode.light : ThemeMode.dark;

  /// 该主题的种子色：决定 [lightTheme] / [darkTheme] 的整套配色。
  /// 切换主题名即切换种子色，main.dart 的 theme / darkTheme 随之重建。
  Color get seedColor =>
      this == AppThemeName.light ? Colors.deepPurple : Colors.teal;

  /// 该主题名下的浅色 ThemeData（供 MaterialApp.theme）。
  ThemeData get lightTheme => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
    extensions: const [AppColors.light],
  );

  /// 该主题名下的深色 ThemeData（供 MaterialApp.darkTheme）。
  ThemeData get darkTheme => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    ),
    extensions: const [AppColors.dark],
  );
}

/// 外观状态：同时持有「主题名称」与「主题模式」两个属性。
///
/// - [themeName]：选中的配色（亮色 / 暗色），驱动 MaterialApp 的 theme / darkTheme 取向。
/// - [themeMode]：显示模式（跟随系统 / 白天 / 黑夜），驱动 MaterialApp 的 themeMode。
///
/// 「模式」组与「主题」组两处 UI 都读写同一份状态，避免两个来源给出冲突的 themeMode。
@immutable
class Appearance {
  const Appearance({required this.themeName, required this.themeMode});

  final AppThemeName themeName;
  final ThemeMode themeMode;

  Appearance copyWith({AppThemeName? themeName, ThemeMode? themeMode}) =>
      Appearance(
        themeName: themeName ?? this.themeName,
        themeMode: themeMode ?? this.themeMode,
      );
}

/// 外观（主题 + 模式）状态，用 PersistentNotifier 持久化两个字段。
class AppearanceNotifier extends Notifier<Appearance>
    with PersistentNotifier<Appearance> {
  @override
  String get persistKey => 'appearance';

  @override
  Map<String, dynamic> toJson(Appearance state) => {
    'themeName': state.themeName.name,
    'themeMode': state.themeMode.name,
  };

  @override
  Appearance fromJson(Map<String, dynamic> json, Appearance fallback) =>
      fallback.copyWith(
        themeName: AppThemeName.values.asNameMap()[json['themeName']],
        themeMode: ThemeMode.values.asNameMap()[json['themeMode']],
      );

  @override
  Appearance build() => restore(
    const Appearance(
      themeName: AppThemeName.light,
      themeMode: ThemeMode.system,
    ),
  );

  /// 选择「模式」：白天 / 黑夜同时把主题名同步过去；跟随系统时保留原主题名。
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
  void setThemeName(AppThemeName name) =>
      state = state.copyWith(themeName: name, themeMode: name.mode);
}

final appearanceProvider = NotifierProvider<AppearanceNotifier, Appearance>(
  AppearanceNotifier.new,
);
