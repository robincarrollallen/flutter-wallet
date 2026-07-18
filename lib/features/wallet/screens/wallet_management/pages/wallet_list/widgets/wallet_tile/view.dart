import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../../../core/responsive/screen_adapter.dart';
import '../../../../../../../../core/widgets/amount_text.dart';
import '../../../../../../../../providers/modules/balance_provider.dart';
import '../../../../../../domain/wallet.dart';
import '../../../../../../domain/wallet_avatar.dart';

/// 单个钱包行：点击行=切换钱包
class WalletTile extends ConsumerWidget {
  const WalletTile({
    super.key,
    required this.wallet,
    required this.selected,
    required this.onTap,
    required this.onOptions,
  });

  final Wallet wallet;
  final bool selected;
  final VoidCallback onTap;

  /// 点击卡片内的「选项」按钮（纵向三个点）回调。
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final total = ref.watch(walletTotalProvider(wallet.id));
    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      fontSize: 10.s,
    );

    return Card(
      color: selected ? theme.colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6.s), // 设置圆角大大小
      ),
      child: ListTile(
        onTap: onTap,
        visualDensity: const VisualDensity(vertical: -4), // 最大压缩高度 -4
        contentPadding: EdgeInsets.only(left: 8.s),
        leading: WalletAvatar(iconName: wallet.icon, size: 28.s),
        title: Text(
          wallet.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 12.s,
          ),
        ),
        subtitle: total.when( // 副标题：钱包总余额。
          loading: () => Text('…', maxLines: 1, style: subtitleStyle),
          error: (_, _) => Text('--', maxLines: 1, style: subtitleStyle),
          data: (value) => AmountText(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: subtitleStyle,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
            IconButton(
              icon: Icon(Icons.more_vert, size: 20.s),
              tooltip: '选项',
              onPressed: onOptions,
            ),
          ],
        ),
      ),
    );
  }
}
