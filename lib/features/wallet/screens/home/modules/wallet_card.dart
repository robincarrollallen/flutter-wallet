import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/responsive/screen_adapter.dart';
import '../../../../../i18n/translations.g.dart';
import '../../../../../core/widgets/amount_text.dart';
import '../../../../../providers/modules/balance_provider.dart';
import '../../../domain/chain.dart';
import '../../../domain/wallet.dart';
import '../../../domain/wallet_avatar.dart';
import '../../../services/secure_wallet_storage.dart';

/// 单个钱包卡片：把该钱包的全部信息分成带标题的模块展示。
/// ⚠️ 「敏感数据」模块（助记词 / 私钥）仅为临时验证用，正式版应移除。
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
                  child: Text(
                    wallet.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.s),

            _SectionTitle('基本信息'),
            _InfoRow(label: 'ID', value: wallet.id),
            _InfoRow(label: '来源', value: walletSourceLabel(wallet.source)),

            SizedBox(height: 16.s),
            _SectionTitle('多链资产（测试网）'),
            for (final chain in wallet.chainsWithAddress)
              _ChainTile(chain: chain, address: wallet.addressFor(chain)),

            SizedBox(height: 16.s),
            _SensitiveSection(walletId: wallet.id),
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
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// 一行「标签 + 值」，值过长可换行，可选复制按钮。
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.copyable = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool copyable;
  final Color? valueColor;

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
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(color: valueColor),
            ),
          ),
          if (copyable)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制')),
                );
              },
              child: Padding(
                padding: EdgeInsets.only(left: 4.s),
                child: Icon(Icons.copy_rounded, size: 16.s),
              ),
            ),
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
        loading: () => SizedBox(
          width: 14.s,
          height: 14.s,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (_, _) => Text(t.balance.unavailable),
        data: (b) => Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AmountText.raw('${b.amount} ${b.symbol}',
                style: theme.textTheme.bodyMedium),
            AmountText(
              b.fiatValue,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
                Text(chain.name,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(height: 2.s),
                Text(
                  address ?? '（未派生地址）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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

/// 敏感数据模块：从安全存储读出助记词 / 私钥。⚠️ 临时展示用。
class _SensitiveSection extends ConsumerWidget {
  const _SensitiveSection({required this.walletId});

  final String walletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.s),
      decoration: BoxDecoration(
        color: error.withValues(alpha: 0.06),
        border: Border.all(color: error.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8.s),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18.s, color: error),
              SizedBox(width: 6.s),
              Text(
                '敏感数据（临时展示，请勿泄露）',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: error, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: 8.s),
          // ⚠️ 临时展示：每次构建时一次性读取，不进 Provider 缓存。
          FutureBuilder<WalletSecrets>(
            future: ref.read(secureWalletStorageProvider).readSecrets(walletId),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return SizedBox(
                  width: 16.s,
                  height: 16.s,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return const Text('读取失败');
              }
              final s = snapshot.data!;
              return Column(
                children: [
                  _InfoRow(
                    label: '助记词',
                    value: s.mnemonic ?? '（无）',
                    copyable: s.mnemonic != null,
                    valueColor: error,
                  ),
                  _InfoRow(
                    label: '私钥',
                    value: s.privateKey ?? '（无）',
                    copyable: s.privateKey != null,
                    valueColor: error,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
