import 'package:flutter/material.dart';

/// 应用自定义主题色 token（ColorScheme 之外的语义色）。
/// 通过 [ThemeExtension] 接入主题系统：明暗各一份、切换有 lerp 过渡，
/// 统一用 `context.appColors.success` 读取。新增 token 时在此扩展即可。
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
  });

  /// 通用成功（绿）。
  final Color success;

  /// 成功色上的前景（文字/图标）。
  final Color onSuccess;

  /// 通用警告（橙）。Material 的 error 偏红，这里区分中等级别提示。
  final Color warning;

  /// 亮色主题取值。
  static const AppColors light = AppColors(
    success: Color(0xFF2E7D32),
    onSuccess: Colors.white,
    warning: Color(0xFFE65100),
  );

  /// 暗色主题取值（提亮，避免深背景上发暗刺眼）。
  static const AppColors dark = AppColors(
    success: Color(0xFF81C784),
    onSuccess: Color(0xFF003910),
    warning: Color(0xFFFFB74D),
  );

  @override
  AppColors copyWith({Color? success, Color? onSuccess, Color? warning}) {
    return AppColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

/// 便捷访问：`context.appColors.success`。
extension AppColorsX on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
