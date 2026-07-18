import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/responsive/screen_adapter.dart';
import '../../../../../core/widgets/amount_text.dart';
import '../../../../../i18n/translations.g.dart';
import '../../../../../providers/modules/balance_provider.dart';
import '../../../../../providers/modules/balance_visibility_provider.dart';
import '../../../../../providers/modules/wallet_provider.dart';
import '../../../domain/wallet.dart';
import '../../../domain/wallet_avatar.dart';
import '../../address_management/address_management_view.dart';
import '../../wallet_management/view.dart';

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
        ? const AsyncValue.data(0.0)
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
                    icon: Icon(
                      Icons.copy_rounded,
                      size: 20.s,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    tooltip: '地址管理',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            AddressManagementScreen(wallet: wallet),
                      ),
                    ),
                  ),
                ],
              ),
            if (wallet != null) SizedBox(height: 12.s),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  t.home.totalAssets,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                // 睁眼/闭眼：切换全局金额与代币数量的隐藏显示。
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 32.s, minHeight: 32.s),
                  icon: Icon(
                    hidden
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18.s,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  tooltip: hidden ? '显示金额' : '隐藏金额',
                  onPressed: () =>
                      ref.read(balanceHiddenProvider.notifier).toggle(),
                ),
              ],
            ),
            SizedBox(height: 8.s),
            total.when(
              loading: () => Padding(
                padding: EdgeInsets.symmetric(vertical: 4.s),
                child: Row(
                  // Row 默认撑满卡片宽度，不写就贴左——外层 Column 的 crossAxisAlignment
                  // 对已占满宽度的 Row 不起作用，需在此显式居中。
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18.s,
                      height: 18.s,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12.s),
                    Text(
                      t.home.assetsScanning,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              error: (_, _) => Text(
                t.balance.unavailable,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              data: (value) => AmountText(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // —— 功能按钮栏：发送 / 接收 / 历史 / 更多（仅有钱包时展示，逻辑待补） —— //
            if (wallet != null) ...[
              SizedBox(height: 16.s),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: const [
                  _ActionButton(icon: Icons.arrow_upward_rounded, label: '发送'),
                  _ActionButton(
                    icon: Icons.arrow_downward_rounded,
                    label: '接收',
                  ),
                  _ActionButton(icon: Icons.history_rounded, label: '历史'),
                  _ActionButton(icon: Icons.grid_view_rounded, label: '更多'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 总资产卡片下方的单个功能按钮：圆形图标 + 文案，纵向排列。
/// 目前仅提供 UI，点击逻辑后续补充。
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor = theme.colorScheme.onPrimaryContainer;
    return InkWell(
      borderRadius: BorderRadius.circular(24.s),
      onTap: () {}, // TODO: 接入发送/接收/历史/更多逻辑
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
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: onColor),
            ),
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
        onTap: () =>
            Navigator.of(context).push(WalletManagementScreen.route()),
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
              Icon(
                Icons.chevron_right,
                size: 18.s,
                color: theme.colorScheme.onSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
