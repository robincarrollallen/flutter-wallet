import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../blockchain/chain_registry.dart';
import '../../../../../core/format/token_amount_formatter.dart';
import '../../../../../core/responsive/screen_adapter.dart';
import '../../../../../domain/transaction_record.dart';
import '../../../../../i18n/translations.g.dart';
import '../../../../../widgets/app_toast.dart';
import '../../view.dart';

/// 交易详情：一条历史记录的全部字段，哈希与地址可点击复制。
class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({super.key, required this.record});

  final TransactionRecord record;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final (statusLabel, statusColor) = statusAppearance(context, record.status);
    final submitted = record.submittedAt.toLocal();

    return Scaffold(
      appBar: AppBar(title: Text(t.transactionHistory.detailTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16.s, 16.s, 16.s, 24.s),
        children: [
          // —— 金额与状态：进详情页第一眼要看的两件事 —— //
          Center(
            child: Column(
              children: [
                Text(
                  '${record.direction == TransactionDirection.outgoing ? '-' : '+'}'
                  '${formatTokenAmount(record.amount)} ${record.symbol}',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8.s),
                Text(statusLabel, style: theme.textTheme.titleSmall?.copyWith(color: statusColor)),
              ],
            ),
          ),
          SizedBox(height: 24.s),
          _DetailRow(label: t.transactionHistory.fieldChain, value: _chainNameOf(record.chainId)),
          _DetailRow(label: t.transactionHistory.fieldFrom, value: record.fromAddress, copyable: true),
          _DetailRow(label: t.transactionHistory.fieldTo, value: record.toAddress, copyable: true),
          _DetailRow(label: t.transactionHistory.fieldHash, value: record.transactionHash, copyable: true),
          _DetailRow(
            label: t.transactionHistory.fieldTime,
            value:
                '${submitted.year}-${_twoDigits(submitted.month)}-${_twoDigits(submitted.day)} '
                '${_twoDigits(submitted.hour)}:${_twoDigits(submitted.minute)}',
          ),
        ],
      ),
    );
  }
}

/// 一行「标签 + 值」。[copyable] 的行整行可点，点了复制原始值（不是缩略后的）。
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.copyable = false});

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: copyable ? () => _copy(context) : null,
      borderRadius: BorderRadius.circular(12.s),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.s, horizontal: 4.s),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88.s,
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
            if (copyable) ...[
              SizedBox(width: 8.s),
              Icon(Icons.copy_rounded, size: 16.s, color: theme.colorScheme.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final copied = context.t.transactionHistory.copied;
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    AppToast.show(context, copied);
  }
}

String _chainNameOf(String chainId) {
  final chain = SupportedChains.all.where((candidate) => candidate.id == chainId).firstOrNull;
  return chain?.name ?? chainId;
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
