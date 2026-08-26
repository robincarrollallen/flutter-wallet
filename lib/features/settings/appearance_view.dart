import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/responsive/screen_adapter.dart';
import '../../providers/modules/theme_provider.dart';
import '../../enums/app_theme_name.dart';

/// 主题 / 模式选择页：
/// - 「模式」组：跟随系统 / 白天 / 黑夜（驱动 themeMode）。
/// - 「主题」组：亮色 / 暗色（驱动 themeName，并同步对应模式）。
/// 两组共享同一份 [appearanceProvider] 状态，选中即时生效并持久化。
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final appearance = ref.watch(appearanceProvider);
    final notifier = ref.read(appearanceProvider.notifier);

    return Scaffold(
      appBar: AppBar(backgroundColor: theme.colorScheme.inversePrimary, title: const Text('主题 / 模式')),
      body: ListView(
        children: [
          _SectionHeader(title: '模式'),
          _OptionTile(
            icon: Icons.brightness_auto_outlined,
            label: '跟随系统',
            selected: appearance.themeMode == ThemeMode.system,
            onTap: () => notifier.setMode(ThemeMode.system),
          ),
          _OptionTile(
            icon: Icons.light_mode_outlined,
            label: '白天',
            selected: appearance.themeMode == ThemeMode.light,
            onTap: () => notifier.setMode(ThemeMode.light),
          ),
          _OptionTile(
            icon: Icons.dark_mode_outlined,
            label: '黑夜',
            selected: appearance.themeMode == ThemeMode.dark,
            onTap: () => notifier.setMode(ThemeMode.dark),
          ),
          const Divider(height: 1),
          _SectionHeader(title: '主题'),
          _OptionTile(
            icon: Icons.wb_sunny_outlined,
            label: '亮色',
            selected: appearance.themeName == AppThemeName.light,
            onTap: () => notifier.setThemeName(AppThemeName.light),
          ),
          _OptionTile(
            icon: Icons.nightlight_outlined,
            label: '暗色',
            selected: appearance.themeName == AppThemeName.dark,
            onTap: () => notifier.setThemeName(AppThemeName.dark),
          ),
        ],
      ),
    );
  }
}

/// 分组标题。
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
        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// 单选项：图标 + 文案，选中时右侧显示对勾。
class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: selected ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
      onTap: onTap,
    );
  }
}
