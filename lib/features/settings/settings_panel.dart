import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/responsive/screen_adapter.dart';
import '../../i18n/translations.g.dart';
import 'debug_storage_view.dart';
import 'theme_colors_view.dart';

/// 设置面板：从屏幕顶部下滑进入的全屏毛玻璃覆盖层。
///
/// 通过根 Navigator 推入（[route]），渲染在 [RootShell] 的悬浮导航栏之上，
/// 背景用 [BackdropFilter] 毛玻璃透出下方模糊内容。
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  /// 从顶部下滑进入的覆盖路由。用 rootNavigator 推入以盖住底部导航栏。
  static Route<void> route() {
    return PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => const SettingsPanel(),
      transitionsBuilder: (_, animation, _, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.t;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Material( // 透明 Material：为 ListTile 等提供 Material 祖先 + ink 效果，
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
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    SizedBox(width: 4.s),
                    Text(t.settings.title, style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: [
                    _SettingsTile(
                      icon: Icons.tune,
                      title: t.settings.general,
                    ),
                    _SettingsTile(
                      icon: Icons.shield_outlined,
                      title: t.settings.security,
                    ),
                    _SettingsTile(
                      icon: Icons.info_outline,
                      title: t.settings.about,
                    ),
                    // 调试入口：查看已持久化的全部钱包原始数据。
                    _SettingsTile(
                      icon: Icons.storage,
                      title: '存储数据（调试）',
                      onTap: () {
                        // 设置是普通页面而非抽屉，跳转子页面时不关闭它，返回后仍停留在设置。
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DebugStorageScreen(),
                          ),
                        );
                      },
                    ),
                    // 调试入口：查看当前主题所有颜色及对应变量。
                    _SettingsTile(
                      icon: Icons.palette_outlined,
                      title: '主题颜色（调试）',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ThemeColorsScreen(),
                          ),
                        );
                      },
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
  const _SettingsTile({required this.icon, required this.title, this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap ?? () {},
    );
  }
}
