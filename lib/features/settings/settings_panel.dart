import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive/screen_adapter.dart';
import '../../i18n/translations.g.dart';
import '../../providers/modules/currency_provider.dart';
import '../../router/routes.dart';

/// 设置面板：从屏幕顶部下滑进入的全屏毛玻璃覆盖层。
///
/// 由 [AppRoute.settings] 以透明覆盖路由推入，渲染在 [RootShell] 的悬浮导航栏之上，
/// 背景用 [BackdropFilter] 毛玻璃透出下方模糊内容。
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.t;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Material(
        // 透明 Material：为 ListTile 等提供 Material 祖先 + ink 效果，
        type: MaterialType.canvas,
        color: theme.colorScheme.surface.withValues(alpha: 0.1), // // 背景色仍用半透明 surface（比导航栏更不透明，保证设置项可读）。
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部栏：标题 + 关闭。
              Padding(
                padding: EdgeInsets.fromLTRB(8.s, 8.s, 8.s, 0),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
                    SizedBox(width: 4.s),
                    Text(t.settings.title, style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: [
                    _SettingsTile(icon: Icons.tune, title: t.settings.general),
                    // 主题 / 模式：打开选择页（模式：跟随系统/白天/黑夜；主题：亮色/暗色）。
                    _SettingsTile(
                      icon: Icons.brightness_6_outlined,
                      title: '主题 / 模式',
                      onTap: () => context.push(AppRoute.settingsAppearance),
                    ),
                    // 币种：全应用金额折算所用的法币，行尾显示当前选择。
                    // 只用 Consumer 包这一行——整个面板是毛玻璃覆盖层，
                    // 若改成 ConsumerWidget，切币种会让整层重建。
                    Consumer(
                      builder: (context, ref, _) => _SettingsTile(
                        icon: Icons.attach_money,
                        title: t.currency.title,
                        trailingText: ref.watch(currencyProvider),
                        onTap: () => context.push(AppRoute.settingsCurrency),
                      ),
                    ),
                    _SettingsTile(icon: Icons.shield_outlined, title: t.settings.security),
                    _SettingsTile(icon: Icons.info_outline, title: t.settings.about),
                    // 调试入口：查看当前主题所有颜色及对应变量。
                    _SettingsTile(
                      icon: Icons.palette_outlined,
                      title: '主题颜色（调试）',
                      onTap: () => context.push(AppRoute.settingsThemeColors),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.icon, required this.title, this.trailingText, this.onTap});

  final IconData icon;
  final String title;

  /// 箭头左侧的当前值文案（如当前币种代码）；null 时只显示箭头。
  final String? trailingText;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = trailingText;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      // mainAxisSize.min 必须保留，否则 Row 会撑满整个 ListTile 宽度。
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null) ...[
            Text(value, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            SizedBox(width: 4.s),
          ],
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap ?? () {},
    );
  }
}
