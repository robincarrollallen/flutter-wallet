import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/screen_adapter.dart';
import '../../../../i18n/translations.g.dart';
import '../../../../widgets/amount_text.dart';
import '../../../../providers/modules/balance_provider.dart';
import '../../../../blockchain/chain_registry.dart';
import '../../../../domain/wallet.dart';
import '../../../../domain/wallet_avatar.dart';

/// 单个钱包卡片：把该钱包的全部信息分成带标题的模块展示。
class WalletCard extends ConsumerWidget {
  const WalletCard({super.key, required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // —— 卡片标题：钱包名称 —— //
            Row(
              children: [
                WalletAvatar(iconName: wallet.icon, size: 22.s),
                SizedBox(width: 8.s),
                Expanded(
                  child: Text(wallet.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            SizedBox(height: 16.s),

            _SectionTitle('基本信息'),
            _InfoRow(label: 'ID', value: wallet.id),
            _InfoRow(label: '来源', value: walletSourceLabel(wallet.source)),

            SizedBox(height: 16.s),
            _SectionTitle('多链资产（测试网）'),
            for (final chain in wallet.chainsWithAddress) _ChainTile(chain: chain, address: wallet.addressFor(chain)),
          ],
        ),
      ),
    );
  }
}

/// 模块小标题。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 8.s),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// 一行「标签 + 值」，值过长可换行。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 6.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64.s,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: SelectableText(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// 单链资产行：链名 + 该链余额与折算价值。
class _ChainTile extends ConsumerWidget {
  const _ChainTile({required this.chain, required this.address});

  final Chain chain;
  final String? address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = context.t;

    final Widget trailing;
    if (address == null) {
      trailing = Text(t.balance.unavailable);
    } else {
      final balance = ref.watch(balanceProvider((chain.id, address!)));
      trailing = balance.when(
        loading: () => SizedBox(width: 14.s, height: 14.s, child: const CircularProgressIndicator(strokeWidth: 2)),
        error: (_, _) => Text(t.balance.unavailable),
        data: (b) => Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AmountText.raw('${b.amount} ${b.symbol}', style: theme.textTheme.bodyMedium),
            AmountText(
              b.fiatValue,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chain.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(height: 2.s),
                Text(
                  address ?? '（未派生地址）',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.s),
          trailing,
        ],
      ),
    );
  }
}
