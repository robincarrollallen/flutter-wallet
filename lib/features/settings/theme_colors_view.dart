import 'package:flutter/material.dart';

import '../../core/responsive/screen_adapter.dart';
import '../../core/theme/app_colors.dart';

/// 主题颜色一览：分类展示当前主题（含明/暗）所有色值，
/// 每项显示色块 + 对应主题变量名 + #AARRGGBB 十六进制值，便于取色与排查。
class ThemeColorsScreen extends StatelessWidget {
  const ThemeColorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final app = context.appColors;

    // 按语义分组，每组 (变量名, 颜色)。变量名直接对应代码里的取值路径。
    final groups = <String, List<(String, Color)>>{
      'Primary': [
        ('colorScheme.primary', cs.primary),
        ('colorScheme.onPrimary', cs.onPrimary),
        ('colorScheme.primaryContainer', cs.primaryContainer),
        ('colorScheme.onPrimaryContainer', cs.onPrimaryContainer),
        ('colorScheme.primaryFixed', cs.primaryFixed),
        ('colorScheme.primaryFixedDim', cs.primaryFixedDim),
        ('colorScheme.onPrimaryFixed', cs.onPrimaryFixed),
        ('colorScheme.onPrimaryFixedVariant', cs.onPrimaryFixedVariant),
      ],
      'Secondary': [
        ('colorScheme.secondary', cs.secondary),
        ('colorScheme.onSecondary', cs.onSecondary),
        ('colorScheme.secondaryContainer', cs.secondaryContainer),
        ('colorScheme.onSecondaryContainer', cs.onSecondaryContainer),
        ('colorScheme.secondaryFixed', cs.secondaryFixed),
        ('colorScheme.secondaryFixedDim', cs.secondaryFixedDim),
        ('colorScheme.onSecondaryFixed', cs.onSecondaryFixed),
        ('colorScheme.onSecondaryFixedVariant', cs.onSecondaryFixedVariant),
      ],
      'Tertiary': [
        ('colorScheme.tertiary', cs.tertiary),
        ('colorScheme.onTertiary', cs.onTertiary),
        ('colorScheme.tertiaryContainer', cs.tertiaryContainer),
        ('colorScheme.onTertiaryContainer', cs.onTertiaryContainer),
        ('colorScheme.tertiaryFixed', cs.tertiaryFixed),
        ('colorScheme.tertiaryFixedDim', cs.tertiaryFixedDim),
        ('colorScheme.onTertiaryFixed', cs.onTertiaryFixed),
        ('colorScheme.onTertiaryFixedVariant', cs.onTertiaryFixedVariant),
      ],
      'Error': [
        ('colorScheme.error', cs.error),
        ('colorScheme.onError', cs.onError),
        ('colorScheme.errorContainer', cs.errorContainer),
        ('colorScheme.onErrorContainer', cs.onErrorContainer),
      ],
      'Surface': [
        ('colorScheme.surface', cs.surface),
        ('colorScheme.onSurface', cs.onSurface),
        ('colorScheme.onSurfaceVariant', cs.onSurfaceVariant),
        ('colorScheme.surfaceDim', cs.surfaceDim),
        ('colorScheme.surfaceBright', cs.surfaceBright),
        ('colorScheme.surfaceContainerLowest', cs.surfaceContainerLowest),
        ('colorScheme.surfaceContainerLow', cs.surfaceContainerLow),
        ('colorScheme.surfaceContainer', cs.surfaceContainer),
        ('colorScheme.surfaceContainerHigh', cs.surfaceContainerHigh),
        ('colorScheme.surfaceContainerHighest', cs.surfaceContainerHighest),
        ('colorScheme.surfaceTint', cs.surfaceTint),
      ],
      'Outline & Inverse': [
        ('colorScheme.outline', cs.outline),
        ('colorScheme.outlineVariant', cs.outlineVariant),
        ('colorScheme.inverseSurface', cs.inverseSurface),
        ('colorScheme.onInverseSurface', cs.onInverseSurface),
        ('colorScheme.inversePrimary', cs.inversePrimary),
      ],
      'Misc': [
        ('colorScheme.shadow', cs.shadow),
        ('colorScheme.scrim', cs.scrim),
      ],
      'ThemeData': [
        ('primaryColor', theme.primaryColor),
        ('primaryColorLight', theme.primaryColorLight),
        ('primaryColorDark', theme.primaryColorDark),
        ('canvasColor', theme.canvasColor),
        ('scaffoldBackgroundColor', theme.scaffoldBackgroundColor),
        ('cardColor', theme.cardColor),
        ('dividerColor', theme.dividerColor),
        ('focusColor', theme.focusColor),
        ('hoverColor', theme.hoverColor),
        ('highlightColor', theme.highlightColor),
        ('splashColor', theme.splashColor),
        ('disabledColor', theme.disabledColor),
        ('hintColor', theme.hintColor),
        ('shadowColor', theme.shadowColor),
        ('secondaryHeaderColor', theme.secondaryHeaderColor),
        ('unselectedWidgetColor', theme.unselectedWidgetColor),
      ],
      'App (ThemeExtension)': [
        ('appColors.success', app.success),
        ('appColors.onSuccess', app.onSuccess),
        ('appColors.warning', app.warning),
      ],
      // 已弃用但仍可访问，列出以保证完整；新代码请勿使用。
      'Deprecated': [
        // ignore: deprecated_member_use
        ('colorScheme.background', cs.background),
        // ignore: deprecated_member_use
        ('colorScheme.onBackground', cs.onBackground),
        // ignore: deprecated_member_use
        ('colorScheme.surfaceVariant', cs.surfaceVariant),
        // ignore: deprecated_member_use
        ('dialogBackgroundColor', theme.dialogBackgroundColor),
        // ignore: deprecated_member_use
        ('indicatorColor', theme.indicatorColor),
      ],
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('主题颜色（${theme.brightness == Brightness.dark ? '暗色' : '亮色'}）'),
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: 8.s),
        children: [
          for (final entry in groups.entries) ...[
            _SectionHeader(title: entry.key),
            for (final (name, color) in entry.value)
              _ColorRow(name: name, color: color),
          ],
          SizedBox(height: 16.s),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16.s, 16.s, 16.s, 8.s),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// 单行颜色项：色块 + 变量名 + 十六进制值。
class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.s, vertical: 6.s),
      child: Row(
        children: [
          // 色块：带边框以便在与背景同色时仍可分辨。
          Container(
            width: 44.s,
            height: 44.s,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8.s),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
          ),
          SizedBox(width: 12.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2.s),
                Text(
                  _hex(color),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 转成 #AARRGGBB 大写十六进制。
  static String _hex(Color color) {
    final argb = color.toARGB32();
    return '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }
}
