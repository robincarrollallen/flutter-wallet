import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/responsive/screen_adapter.dart';
import '../../i18n/translations.g.dart';
import 'modules/contract/view.dart';
import 'modules/dapp/view.dart';
import 'modules/history/view.dart';
import 'modules/pill/state.dart';
import 'modules/pill/view.dart';
import 'modules/token/view.dart';

/// 搜索页：
/// - 未输入关键词：整页可滚动，上为搜索历史、下为热门搜索（代币/合约/Dapp 三个
///   Tab 属于热门模块），Tabs 栏滚动到顶部时吸顶。
/// - 输入关键词：整页替换为搜索结果，结果仍按这三个 Tab 分类。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 统一的 Tab 栏样式（空词吸顶态与搜索结果态共用）。
  Widget _buildTabBar(ThemeData theme) {
    final t = context.t;
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicatorPadding: EdgeInsets.symmetric(vertical: 6.s),
      indicator: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16.s),
      ),
      labelColor: theme.colorScheme.onSurface,
      unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.35),
      tabs: [
        Tab(text: t.search.tabs.token),
        Tab(text: t.search.tabs.contract),
        Tab(text: t.search.tabs.dapp),
      ],
    );
  }

  /// Tab内容列表
  Widget _tabViews() => TabBarView(
        controller: _tabController,
        children: const [
          TokenTabView(),
          ContractTabView(),
          DappTabView(),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final isEmptyQuery = ref.watch(searchQueryProvider).trim().isEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        automaticallyImplyLeading: false,
        titleSpacing: 8,
        title: const SearchInputPill(),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 8.s),
            child: Material(
              color: theme.colorScheme.surface.withValues(alpha: 0.85),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                child: Padding(
                  padding: EdgeInsets.all(6.s),
                  child: Icon(
                    Icons.close,
                    size: 20.s,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: isEmptyQuery
          // 空词：历史 + 热门，整页滚动 + Tabs 吸顶。
          ? NestedScrollView(
              headerSliverBuilder: (context, _) => [
                const SliverToBoxAdapter(child: SearchHistoryModule()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16.s, 12.s, 16.s, 4.s),
                    child: Text(
                      t.search.hot,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedTabBarDelegate(
                    height: 48.s,
                    background: theme.colorScheme.surface,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _buildTabBar(theme),
                    ),
                  ),
                ),
              ],
              body: _tabViews(),
            )
          // 非空词：搜索结果。
          : Column(
              children: [
                Align(alignment: Alignment.centerLeft, child: _buildTabBar(theme)),
                Expanded(child: _tabViews()),
              ],
            ),
    );
  }
}

/// 把 TabBar 包成可吸顶的 SliverPersistentHeader；带背景色避免吸顶时透出下层内容。
class _PinnedTabBarDelegate extends SliverPersistentHeaderDelegate {
  _PinnedTabBarDelegate({
    required this.child,
    required this.height,
    required this.background,
  });

  final Widget child;
  final double height;
  final Color background;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: background, height: height, child: child);
  }

  @override
  bool shouldRebuild(_PinnedTabBarDelegate old) =>
      height != old.height || background != old.background || child != old.child;
}
