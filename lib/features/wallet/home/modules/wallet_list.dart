import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/screen_adapter.dart';
import '../../../../providers/modules/balance_provider.dart';
import '../../../../providers/modules/chain_icon_provider.dart';
import '../../../../providers/modules/wallet_provider.dart';
import '../../../../providers/token_catalog_provider.dart';
import '../../../../widgets/asset_tile.dart';
import 'token_section.dart';
import 'total_assets_card.dart';

/// 已有钱包时的首页视图：顶部总资产卡片 + 代币列表。
///
/// 下拉刷新的 RefreshIndicator 放在这里（而非 HomeScreen 外层）：
/// home_view 那层有 Transform 会随钱包面板拖拽缩放/位移，
/// 指示器必须与真正滚动的 CustomScrollView 同层，否则跟着一起缩放会错位。
class WalletList extends ConsumerWidget {
  const WalletList({super.key});

  /// 下拉刷新：重取行情与当前钱包各链余额，指示器随返回的 Future 收起。
  Future<void> _onRefresh(WidgetRef ref) => refreshHomeData(ref, walletId: ref.read(activeWalletProvider)?.id);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final markets = ref.watch(marketsProvider).value ?? const {};
    final chainIcons = ref.watch(chainIconsProvider).value ?? const {};
    final assets = ref.watch(visibleAssetsProvider(null));

    return RefreshIndicator(
      onRefresh: () => _onRefresh(ref),
      displacement: 40.s,
      child: CustomScrollView(
        // 内容不足一屏时默认不可滚动，下拉就产生不了 overscroll、触发不了刷新。
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16.s, 16.s, 16.s, 0),
            sliver: const SliverToBoxAdapter(child: TotalAssetsCard()),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 16.s),
            sliver: const SliverToBoxAdapter(child: TokenSectionHeader()),
          ),
          SliverList.builder(
            itemCount: assets.length,
            itemBuilder: (context, i) =>
                AssetTile(asset: assets[i], showChainName: true, markets: markets, chainIcons: chainIcons),
          ),
          // 底部留白，避免最后一项被悬浮的毛玻璃导航栏遮挡。
          SliverToBoxAdapter(child: SizedBox(height: 96.s)),
        ],
      ),
    );
  }
}
