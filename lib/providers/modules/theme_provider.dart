import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../persistent_notifier.dart';

/// 主题模式（跟随系统 / 浅色 / 深色），用 PersistentNotifier 持久化。
/// 写时由 toJson 决定存什么，读时 fromJson 全量恢复；set() 只需改 state。
class ThemeModeNotifier extends Notifier<ThemeMode>
    with PersistentNotifier<ThemeMode> {
  @override
  String get persistKey => 'theme_mode';

  @override
  Map<String, dynamic> toJson(ThemeMode state) => {'mode': state.name};

  @override
  ThemeMode fromJson(Map<String, dynamic> json, ThemeMode fallback) =>
      ThemeMode.values.asNameMap()[json['mode']] ?? fallback;

  @override
  ThemeMode build() => restore(ThemeMode.system);

  void set(ThemeMode mode) => state = mode; // 自动落盘
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
