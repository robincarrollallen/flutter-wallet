import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/screen_adapter.dart';
import '../../../providers/modules/balance_provider.dart';
import '../../../providers/modules/chain_icon_provider.dart';
import '../../../blockchain/chain_registry.dart';
import '../../../providers/token_catalog_provider.dart';
import '../../../widgets/token_icon.dart';
import '../../../core/navigation/panel_routes.dart';
import '../../../widgets/asset_tile.dart';
import 'logic.dart';
import 'pages/address/view.dart';

/// 接收弹窗：从底部弹起，选择要接收的资产。
/// 内部嵌套 Navigator（类似钱包管理面板）：
/// 根页为「搜索 + Tabs + 资产列表」，点击资产在弹窗内滑入「收款地址」子页。
class ReceiveSheet extends StatefulWidget {
  const ReceiveSheet({super.key});

  /// 以底部弹窗形式展示。
  static Future<void> show(BuildContext context) {
    final navigator = Navigator.of(context);
    return navigator.push(
      _BarrierClosesSheetRoute<void>(
        capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20.s))),
        builder: (_) => const ReceiveSheet(),
      ),
    );
  }

  @override
  State<ReceiveSheet> createState() => _ReceiveSheetState();
}

/// 遮罩点击直接关闭整个弹窗的底部弹窗路由。
///
/// 默认 [ModalBottomSheetRoute] 的遮罩点击走 `maybePop`，会被弹窗内
/// [NavigatorPopHandler] 的 PopScope 拦截成"嵌套 Navigator 后退一级"；
/// 这里重写遮罩，改为直接 `pop()` 关闭弹窗。返回键/返回手势不受影响，
/// 仍在弹窗内逐级后退。
class _BarrierClosesSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _BarrierClosesSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.useSafeArea,
    super.backgroundColor,
    super.shape,
  });

  @override
  Widget buildModalBarrier() {
    return AnimatedModalBarrier(
      color: animation!.drive(
        ColorTween(begin: barrierColor.withValues(alpha: 0), end: barrierColor).chain(CurveTween(curve: barrierCurve)),
      ),
      semanticsLabel: barrierLabel,
      barrierSemanticsDismissible: semanticsDismissible,
      onDismiss: () => navigator?.pop(),
    );
  }
}

class _ReceiveSheetState extends State<ReceiveSheet> {
  /// 弹窗内嵌套 Navigator 的 key：子页在弹窗内 push/pop。
  final _nestedNavKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Column(
        children: [
          // —— 顶部把手（持久，不随子页变化） —— //
          Padding(
            padding: EdgeInsets.symmetric(vertical: 10.s),
            child: Container(
              width: 36.s,
              height: 4.s,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2.s),
              ),
            ),
          ),
          // —— 弹窗内容区：嵌套 Navigator，子页在弹窗内滑动切换 —— //
          Expanded(
            child: NavigatorPopHandler(
              onPopWithResult: (_) => _nestedNavKey.currentState?.maybePop(),
              child: Navigator(
                key: _nestedNavKey,
                onGenerateRoute: (_) => panelRootRoute<void>(const _ReceiveHomePage()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 嵌套 Navigator 的根页：顶部搜索栏 + 「全部 + 支持链」Tabs + 对应 token 列表。
class _ReceiveHomePage extends ConsumerStatefulWidget {
  const _ReceiveHomePage();

  @override
  ConsumerState<_ReceiveHomePage> createState() => _ReceiveHomePageState();
}

class _ReceiveHomePageState extends ConsumerState<_ReceiveHomePage> with SingleTickerProviderStateMixin {
  // 全部 + 每条链，故长度 +1。
  late final TabController _tabController = TabController(length: ReceiveLogic.chains.length + 1, vsync: this);
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markets = ref.watch(marketsProvider).markets;
    // Tab 图标用「链图标」；列表行仍用各自的币/代币图标。
    final chainIcons = ref.watch(chainIconsProvider).icons;

    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          // —— 1. 顶部搜索栏 —— //
          Padding(
            padding: EdgeInsets.fromLTRB(16.s, 0, 16.s, 8.s),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索币种 / 链',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.s), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.symmetric(vertical: 12.s),
              ),
            ),
          ),
          // —— 2. 全部 + 支持链 Tabs（图标 + 名称） —— //
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            indicatorColor: theme.colorScheme.primary,
            tabs: [
              Tab(
                height: 56.s,
                icon: Icon(Icons.apps_rounded, size: 24.s),
                text: '全部',
              ),
              for (final c in ReceiveLogic.chains)
                Tab(
                  height: 56.s,
                  icon: TokenIcon(
                    symbol: c.symbol,
                    // 三级降级：链图标 -> 币图标（如 Bitcoin 无平台 id）-> 首字母圆底。
                    logoUrl: chainIcons[c.coinGeckoPlatformId] ?? markets[c.coinGeckoId]?.logoUrl,
                    size: 24.s,
                  ),
                  text: c.name,
                ),
            ],
          ),
          const Divider(height: 1),
          // —— 3. 对应 Tabs 的 token 列表 —— //
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _AssetList(chain: null, query: _query, markets: markets, chainIcons: chainIcons),
                for (final c in ReceiveLogic.chains)
                  _AssetList(chain: c, query: _query, markets: markets, chainIcons: chainIcons),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个 Tab 下的资产列表（原生币 + 代币），按搜索词过滤。
class _AssetList extends ConsumerWidget {
  const _AssetList({required this.chain, required this.query, required this.markets, required this.chainIcons});

  final Chain? chain;
  final String query;
  final Markets markets;
  final ChainIcons chainIcons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ReceiveLogic.filter(ref.watch(visibleAssetsProvider(chain?.id)), query);
    if (assets.isEmpty) {
      return Center(
        child: Text(
          '未找到相关资产',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 8.s),
      itemCount: assets.length,
      itemBuilder: (context, i) => AssetTile(
        asset: assets[i],
        showChainName: chain == null,
        markets: markets,
        chainIcons: chainIcons,
        onTap: (tokenLogoUrl, chainLogoUrl) => Navigator.of(context).push(
          panelSlideRoute<void>(
            ReceiveAddressPage(asset: assets[i], tokenLogoUrl: tokenLogoUrl, chainLogoUrl: chainLogoUrl),
          ),
        ),
      ),
    );
  }
}
