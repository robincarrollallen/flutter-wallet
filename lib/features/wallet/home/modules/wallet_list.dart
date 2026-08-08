import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/screen_adapter.dart';
import '../../../../providers/modules/balance_provider.dart';
import '../../../../providers/modules/wallet_provider.dart';
import 'total_assets_card.dart';
import 'wallet_card.dart';

/// 已有钱包时的首页视图：顶部总资产卡片 + 当前选中钱包卡片。
/// 切换选中钱包（activeWalletProvider）时，下方钱包卡整体随之切换。
///
/// 下拉刷新的 RefreshIndicator 放在这里（而非 HomeScreen 外层）：
/// home_view 那层有 Transform 会随钱包面板拖拽缩放/位移，
/// 指示器必须与真正滚动的 ListView 同层，否则跟着一起缩放会错位。
class WalletList extends ConsumerWidget {
  const WalletList({super.key});

  /// 下拉刷新：重取行情与当前钱包各链余额，指示器随返回的 Future 收起。
  Future<void> _onRefresh(WidgetRef ref) => refreshHomeData(ref, walletId: ref.read(activeWalletProvider)?.id);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(activeWalletProvider);
    return RefreshIndicator(
      onRefresh: () => _onRefresh(ref),
      displacement: 40.s,
      child: ListView(
        // 内容不足一屏时默认不可滚动，下拉就产生不了 overscroll、触发不了刷新，
        // 故强制始终可滚动（例如尚未选中钱包、只有一张总资产卡的情况）。
        physics: const AlwaysScrollableScrollPhysics(),
        // 底部留白，避免最后一项被悬浮的毛玻璃导航栏遮挡。
        padding: EdgeInsets.fromLTRB(16.s, 16.s, 16.s, 96.s),
        children: [
          const TotalAssetsCard(),
          if (wallet != null) ...[SizedBox(height: 8.s), WalletCard(wallet: wallet)],
        ],
      ),
    );
  }
}
