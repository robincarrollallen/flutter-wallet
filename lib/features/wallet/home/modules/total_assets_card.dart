import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/responsive/screen_adapter.dart';
import '../../../../widgets/amount_text.dart';
import '../../../../i18n/translations.g.dart';
import '../../../../providers/modules/balance_provider.dart';
import '../../../../providers/modules/balance_visibility_provider.dart';
import '../../../../providers/modules/wallet_provider.dart';
import '../../../../blockchain/chain_registry.dart';
import '../../../../domain/wallet.dart';
import '../../../../domain/wallet_avatar.dart';
import '../../../../domain/wallet_total.dart';
import '../../../../router/route_args.dart';
import '../../../../router/routes.dart';
import '../../receive/view.dart';

/// 顶部「总资产」卡片：展示当前选中钱包按币种折算后的跨链法币总价值。
/// 顶部一行展示当前钱包名称（点击进入钱包管理）与地址入口（进入地址管理）。
class TotalAssetsCard extends ConsumerWidget {
  const TotalAssetsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = context.t;
    final wallet = ref.watch(activeWalletProvider);
    // 总资产只算当前选中钱包的跨链合计；无钱包时显示 0。
    final total = wallet == null
        ? const AsyncValue.data(WalletTotal.empty)
        : ref.watch(walletTotalProvider(wallet.id));
    final hidden = ref.watch(balanceHiddenProvider);

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.s, vertical: 12.s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // —— 顶部：钱包名称 pill（左）+ 地址管理入口（右） —— //
            if (wallet != null)
              Row(
                children: [
                  _WalletNamePill(name: wallet.name, wallet: wallet),
                  IconButton(
                    icon: Icon(Icons.copy_rounded, size: 20.s, color: theme.colorScheme.onPrimaryContainer),
                    tooltip: '地址管理',
                    onPressed: () =>
                        context.push(AppRoute.addressManagement, extra: AddressManagementArgs(wallet: wallet)),
                  ),
                ],
              ),
            if (wallet != null) SizedBox(height: 12.s),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  t.home.totalAssets,
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                ),
                // 睁眼/闭眼：切换全局金额与代币数量的隐藏显示。
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 32.s, minHeight: 32.s),
                  icon: Icon(
                    hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 18.s,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  tooltip: hidden ? '显示金额' : '隐藏金额',
                  onPressed: () => ref.read(balanceHiddenProvider.notifier).toggle(),
                ),
              ],
            ),
            SizedBox(height: 8.s),
            _Total(total: total),
            // —— 功能按钮栏：发送 / 接收 / 历史 / 更多（仅有钱包时展示，逻辑待补） —— //
            if (wallet != null) ...[
              SizedBox(height: 16.s),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ActionButton(
                    icon: Icons.arrow_upward_rounded,
                    label: '发送',
                    onTap: () => context.push(AppRoute.send),
                  ),
                  _ActionButton(
                    icon: Icons.arrow_downward_rounded,
                    label: '接收',
                    onTap: () => ReceiveSheet.show(context),
                  ),
                  const _ActionButton(icon: Icons.history_rounded, label: '历史'),
                  const _ActionButton(icon: Icons.grid_view_rounded, label: '更多'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 卡片正中的总资产金额。
///
/// 刻意**不显示加载态**：转圈与「正在扫描」文案会让金额位每次刷新都跳一下，
/// 且下拉刷新时卡片已经有上一次的数字，再盖一层进度条纯属倒退。
/// 首次加载（还没有任何数字）显示 0，等结果落地直接替换。
///
/// 唯一的例外是 error 且一个数字都没有：那时显示不出金额，只能报「暂不可用」，
/// 报成 0 会被当成真实资产。刷新失败但手上有旧数字时继续显示旧数字。
class _Total extends StatelessWidget {
  const _Total({required this.total});

  final AsyncValue<WalletTotal> total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.t;
    final v = total.value; // riverpod 3：value 可空且不会因 error 抛出

    if (v == null && total.hasError) {
      return Text(
        t.balance.unavailable,
        style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
      );
    }

    final value = v ?? WalletTotal.empty;
    return Column(
      children: [
        AmountText(
          value.value,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
        // 部分链取数失败：数字仍然出，但必须标明它是不完整的——
        // 否则用户会把缩水后的金额当成真实资产。tooltip 里报出具体链名。
        if (value.isPartial)
          Tooltip(
            message: value.failedChainIds.map((id) => SupportedChains.byId(id).name).join('、'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 14.s, color: theme.colorScheme.onPrimaryContainer),
                SizedBox(width: 4.s),
                Text(
                  t.home.partialAssets,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 总资产卡片下方的单个功能按钮：圆形图标 + 文案，纵向排列。
/// 目前仅提供 UI，点击逻辑后续补充。
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;

  /// 点击回调；为空时按钮无动作（逻辑待补的按钮）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor = theme.colorScheme.onPrimaryContainer;
    return InkWell(
      borderRadius: BorderRadius.circular(24.s),
      onTap: onTap, // 历史/更多逻辑待补；发送/接收已接入
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.s, vertical: 4.s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44.s,
              height: 44.s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surface.withValues(alpha: 0.85),
              ),
              child: Icon(icon, size: 22.s, color: theme.colorScheme.primary),
            ),
            SizedBox(height: 6.s),
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: onColor)),
          ],
        ),
      ),
    );
  }
}

/// 钱包名称椭圆胶囊：文本为「名称 >」，点击进入钱包管理页。
class _WalletNamePill extends StatelessWidget {
  const _WalletNamePill({required this.name, required this.wallet});

  final String name;
  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(20.s),
      child: InkWell(
        borderRadius: BorderRadius.circular(20.s),
        onTap: () => context.push(AppRoute.walletPanel),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10.s, vertical: 6.s),
          child: Row(
            spacing: 6.s,
            mainAxisSize: MainAxisSize.min,
            children: [
              WalletAvatar(iconName: wallet.icon, size: 22.s),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 18.s, color: theme.colorScheme.onSurface),
            ],
          ),
        ),
      ),
    );
  }
}
