import 'package:flutter/widgets.dart';

/// 按屏幕宽度自适应缩放字体与长度单位的极简工具（零依赖）。
///
/// 用法：
/// 1. 在 MaterialApp.builder 里调用 [ScreenAdapter.init]，让缩放比随 MediaQuery 实时刷新。
/// 2. 任意长度/字号写成 `16.s`，即按当前屏宽缩放后的值。
///
/// 字体无障碍：`.s` 只做「按宽度缩放」；用作 fontSize 时，Flutter 的 Text 仍会自动叠加
/// MediaQuery.textScaler（系统字体大小）。只要不锁死 textScaler，字体即同时随屏宽和系统设置缩放。
class ScreenAdapter {
  ScreenAdapter._();

  /// 设计基准宽度（iPhone 设计稿常用 375）。设计稿在该宽度下的数值即「原始值」。
  static const double designWidth = 375;

  /// 缩放比的安全区间：手机区间近似等比，平板/桌面收敛，避免大屏撑爆或窄屏过压。
  static const double _minScale = 0.85;
  static const double _maxScale = 1.3;

  static double _scale = 1.0;
  static double _screenWidth = designWidth;

  /// 在 MaterialApp.builder 里调用，用最新 MediaQuery 刷新缩放比。
  static void init(BuildContext context) {
    _screenWidth = MediaQuery.sizeOf(context).width;
    _scale = (_screenWidth / designWidth).clamp(_minScale, _maxScale);
  }

  /// 当前屏宽（逻辑像素）。
  static double get screenWidth => _screenWidth;

  /// 把设计稿数值按当前屏宽缩放。
  static double scale(num value) => value * _scale;
}

extension ResponsiveNum on num {
  /// 按屏幕宽度缩放后的长度 / 字号（已 clamp）。例：`16.s`、`EdgeInsets.all(12.s)`。
  double get s => ScreenAdapter.scale(this);

  /// 屏宽百分比。例：`50.sw` = 半屏宽。用于偶发的「按屏宽比例」布局。
  double get sw => ScreenAdapter.screenWidth * (this / 100);
}
