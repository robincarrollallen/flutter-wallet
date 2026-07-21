import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../core/responsive/screen_adapter.dart';
import '../../../../../../providers/modules/wallet_provider.dart';
import '../../../../widgets/create_wallet_sheet.dart';
import '../../widgets/panel/view.dart';
import '../../../../../../core/navigation/panel_routes.dart';
import '../wallet_detail/view.dart';
import 'widgets/wallet_tile/view.dart';

/// 面板初始页：钱包列表（嵌套 Navigator 的 root）。
class WalletListPage extends ConsumerWidget {
  const WalletListPage({super.key});

  /// 弹出「创建/导入钱包」选择弹窗，复用空钱包引导页同一套 [CreateWalletSheet]。
  ///
  /// 用 rootNavigator 承载弹窗与后续创建流程：创建页需 push 到根路由，
  /// 成功后 popUntil(isFirst) 才能连同钱包管理面板一起关闭、回到首页展示新钱包。
  void _showCreateWalletSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.s)),
      ),
      builder: (context) => const CreateWalletSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletListProvider);
    final currentId = ref.watch(currentWalletIdProvider);

    return PanelPage(
      title: '钱包管理',
      child: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.all(12.s),
              itemCount: wallets.length,
              separatorBuilder: (_, _) => SizedBox(height: 8.s),
              itemBuilder: (context, index) {
                final wallet = wallets[index];
                final selected = wallet.id == currentId;

                return WalletTile(
                  wallet: wallet,
                  selected: selected,
                  onTap: () {
                    ref
                        .read(currentWalletIdProvider.notifier)
                        .select(wallet.id);
                    Navigator.of(context, rootNavigator: true).pop();
                  },
                  // 卡片内「选项」按钮进入钱包详情。
                  onOptions: () => Navigator.of(context).push(
                    panelSlideRoute(WalletDetailPage(wallet: wallet)),
                  ),
                );
              },
            ),
          ),
          // 底部「创建新钱包」按钮，复用创建钱包弹窗逻辑。
          Padding(
            padding: EdgeInsets.fromLTRB(16.s, 4.s, 16.s, 16.s),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _showCreateWalletSheet(context),
                icon: const Icon(Icons.add),
                label: const Text('创建新钱包'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
