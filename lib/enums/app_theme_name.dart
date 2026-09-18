import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// 主题名称：当前支持亮色 / 暗色两套配色，各自有独立的种子色。
enum AppThemeName {
  light,
  dark;

  ThemeMode get mode => this == AppThemeName.light ? ThemeMode.light : ThemeMode.dark; // 该主题对应的展示模式（亮色→白天，暗色→黑夜）

  Color get seedColor => this == AppThemeName.light ? Colors.deepPurple : Colors.teal; // 主题种子色<喂给 ColorScheme.fromSeed(seedColor: ...)>

  /// 浅色主题 ThemeData（供 MaterialApp.theme）。
  ThemeData get lightTheme => _build(
    ColorScheme.fromSeed(seedColor: seedColor), // 配色表
    AppColors.light, // 扩展色<自定义属性>
  );

  /// 深色主题 ThemeData（供 MaterialApp.darkTheme）。
  ThemeData get darkTheme => _build(
    ColorScheme.fromSeed(
      seedColor: seedColor, // 种子色<自动延伸主题色>
      brightness: Brightness.dark, // 明暗基调<默认浅低深字>
    ),
    AppColors.dark, // 扩展色<自定义属性>
  );

  /// 亮暗两套共用的组装逻辑：差异只在配色表与扩展色，其余组件级样式必须一致。
  ThemeData _build(ColorScheme scheme, AppColors colors) => ThemeData(
    colorScheme: scheme,
    extensions: [colors],
    bottomSheetTheme: BottomSheetThemeData(
      // Material 默认的拖拽手柄是不透明的 onSurfaceVariant，比钱包管理面板里
      // 手写的那条明显更深。统一到后者的观感（36×4，四成透明度），
      // 否则同一个 App 里两种手柄深浅不一。
      dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
      dragHandleSize: const Size(36, 4),
    ),
  );
}
