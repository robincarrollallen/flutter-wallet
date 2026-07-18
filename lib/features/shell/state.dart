import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/translations.g.dart';

/// 一个底部 tab 的元数据：标签取值函数（随语言变化）+ 未选中/选中图标。
@immutable
class TabItem {
  const TabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String Function(Translations t) label;
  final IconData icon;
  final IconData activeIcon;
}

/// 五个一级 tab：首页 / 市场 / 兑换 / 合约 / 发现。
const List<TabItem> kTabs = [
  TabItem(
    label: _homeLabel,
    icon: Icons.home_outlined,
    activeIcon: Icons.home,
  ),
  TabItem(
    label: _marketLabel,
    icon: Icons.show_chart_outlined,
    activeIcon: Icons.show_chart,
  ),
  TabItem(
    label: _exchangeLabel,
    icon: Icons.swap_horiz_outlined,
    activeIcon: Icons.swap_horiz,
  ),
  TabItem(
    label: _contractLabel,
    icon: Icons.description_outlined,
    activeIcon: Icons.description,
  ),
  TabItem(
    label: _discoverLabel,
    icon: Icons.explore_outlined,
    activeIcon: Icons.explore,
  ),
];

String _homeLabel(Translations t) => t.tabs.home;
String _marketLabel(Translations t) => t.tabs.market;
String _exchangeLabel(Translations t) => t.tabs.exchange;
String _contractLabel(Translations t) => t.tabs.contract;
String _discoverLabel(Translations t) => t.tabs.discover;

/// 当前选中 tab 索引。Riverpod 3.x 下 NotifierProvider 默认 autoDispose，
/// Shell 销毁时状态自动清理。
class TabIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final tabIndexProvider = NotifierProvider<TabIndexNotifier, int>(
  TabIndexNotifier.new,
);
