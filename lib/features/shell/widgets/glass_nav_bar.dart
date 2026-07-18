import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/screen_adapter.dart';
import '../../../i18n/translations.g.dart';
import '../state.dart';

/// 悬浮在页面内容之上的毛玻璃底部导航栏。
///
/// 通过 [BackdropFilter] 对其后方内容做高斯模糊，再叠加半透明 surface 色，
/// 形成 frosted glass 效果，能隐约透出当前页面。父级以 Positioned 让它悬浮。
class GlassNavBar extends ConsumerWidget {
  const GlassNavBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = context.t;
    final current = ref.watch(tabIndexProvider);
    final isDark = theme.brightness == Brightness.dark;

    final radius = BorderRadius.circular(24.s);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.35), // 半透明白色叠加：在模糊之上铺一层"玻璃膜"，让整体偏白而非透出灰色。
            borderRadius: radius,
            // 顶部亮、底部暗的描边，强化玻璃边缘的厚度感。
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.20 : 0.45),
              width: 0.8,
            ),
            boxShadow: [
              // 外阴影：让导航栏从背景中浮起。
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              // 内高光：玻璃表面的薄反光。
              BoxShadow(
                color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.20),
                blurRadius: 1,
                spreadRadius: -1,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          // 上下内边距约为左右间隔(16)的一半，整体更紧凑。
          padding: EdgeInsets.symmetric(vertical: 4.s),
          child: Row(
            children: [
              for (var i = 0; i < kTabs.length; i++)
                Expanded(
                  child: _NavItem(
                    item: kTabs[i],
                    label: kTabs[i].label(t),
                    selected: i == current,
                    onTap: () => ref.read(tabIndexProvider.notifier).select(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final TabItem item;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.s),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 4.s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? item.activeIcon : item.icon,
              color: color,
              size: 24.s,
            ),
            SizedBox(height: 4.s),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
