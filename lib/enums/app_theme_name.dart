import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// 主题名称：当前支持亮色 / 暗色两套配色，各自有独立的种子色。
enum AppThemeName {
  light,
  dark;

  ThemeMode get mode => this == AppThemeName.light ? ThemeMode.light : ThemeMode.dark; // 该主题对应的展示模式（亮色→白天，暗色→黑夜）

  Color get seedColor => this == AppThemeName.light ? Colors.deepPurple : Colors.teal; // 主题种子色<喂给 ColorScheme.fromSeed(seedColor: ...)>

  /// 浅色主题 ThemeData（供 MaterialApp.theme）。
  ThemeData get lightTheme => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: seedColor), // 配色表
    extensions: const [AppColors.light], // 扩展色<自定义属性>
  );

  /// 深色主题 ThemeData（供 MaterialApp.darkTheme）。
  ThemeData get darkTheme => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor, // 种子色<自动延伸主题色>
      brightness: Brightness.dark, // 明暗基调<默认浅低深字>
    ),
    extensions: const [AppColors.dark], // 扩展色<自定义属性>
  );
}
