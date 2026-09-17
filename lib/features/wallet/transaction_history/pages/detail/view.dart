import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:wallet_core/chains.dart';
import '../../../../../core/format/token_amount_formatter.dart';
import '../../../../../core/responsive/screen_adapter.dart';
import '../../../../../domain/transaction_record.dart';
import '../../../../../i18n/translations.g.dart';
import '../../../../../providers/modules/asset/token_catalog_provider.dart';
import '../../../../../widgets/app_toast.dart';
import '../../logic.dart';
import '../../view.dart';

/// 交易详情：一条历史记录的全部字段，哈希与地址可点击复制。
class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({super.key, required this.record});

  final TransactionRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final (statusLabel, statusColor) = statusAppearance(context, record.status);
    final chain = _chainOf(record.chainId);
    final symbol = displaySymbolOf(record, ref.watch(tokenCatalogProvider));
    final explorerUrl = chain?.explorerTxUrl(record.transactionHash);

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
                  '${formatTokenAmount(record.amount)} $symbol',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8.s),
                Text(statusLabel, style: theme.textTheme.titleSmall?.copyWith(color: statusColor)),
              ],
            ),
          ),
          SizedBox(height: 24.s),
          _DetailRow(label: t.transactionHistory.fieldChain, value: chain?.name ?? record.chainId),
          // 原生币没有合约地址，显示币种名即可；代币则符号与合约地址都给：
          // 光有地址读不出是什么币（Solana 的记录里尤其如此，符号本来就查不到），
          // 光有符号又没法拿去浏览器核对是不是自己以为的那个代币——而后者正是
          // 详情页的主要用途之一。所以两个都列，复制仍然只复制地址。
          _DetailRow(
            label: t.transactionHistory.fieldToken,
            value: record.isNativeCoin
                ? '$symbol · ${t.transactionHistory.nativeCoin}'
                : '$symbol · ${record.tokenIdentifier!}',
            copyable: !record.isNativeCoin,
            copyValue: record.tokenIdentifier,
          ),
          _DetailRow(label: t.transactionHistory.fieldFrom, value: record.fromAddress, copyable: true),
          _DetailRow(label: t.transactionHistory.fieldTo, value: record.toAddress, copyable: true),
          _DetailRow(label: t.transactionHistory.fieldHash, value: record.transactionHash, copyable: true),
          // 以下三项要查链 / 查浏览器才有值，没回填就整行不渲染，不留空位。
          if (record.feeAmount != null)
            _DetailRow(
              label: t.transactionHistory.fieldFee,
              value: '${formatTokenAmount(record.feeAmount!)} ${chain?.symbol ?? ''}'.trim(),
            ),
          if (record.blockNumber != null)
            _DetailRow(label: t.transactionHistory.fieldBlock, value: '${record.blockNumber}'),
          _DetailRow(label: t.transactionHistory.fieldTime, value: _formatTime(record.submittedAt)),
          if (record.confirmedAt != null)
            _DetailRow(label: t.transactionHistory.fieldConfirmedAt, value: _formatTime(record.confirmedAt!)),
          if (explorerUrl != null) ...[
            SizedBox(height: 24.s),
            FilledButton.tonalIcon(
              onPressed: () => _openExplorer(context, explorerUrl),
              icon: Icon(Icons.open_in_new_rounded, size: 18.s),
              label: Text(t.transactionHistory.viewOnExplorer),
            ),
          ],
        ],
      ),
    );
  }

  /// 跳外部浏览器而不是应用内 WebView：浏览器页会引导用户登录、跳其它 dApp，
  /// 这些都不该发生在钱包 App 的壳子里。
  Future<void> _openExplorer(BuildContext context, String url) async {
    final failed = context.t.transactionHistory.openExplorerFailed;
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (opened || !context.mounted) return;
    AppToast.show(context, failed);
  }
}

/// 一行「标签 + 值」。[copyable] 的行整行可点，点了复制原始值（不是缩略后的）。
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.copyable = false, this.copyValue});

  final String label;
  final String value;
  final bool copyable;

  /// 复制时真正写进剪贴板的内容；不给就复制 [value]。
  ///
  /// 存在的理由只有一个：代币那一行显示的是「符号 · 合约地址」，而用户点复制要的
  /// 是那串地址本身——把符号和分隔点一起复制进去，粘到浏览器里是查不出东西的。
  final String? copyValue;

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
    await Clipboard.setData(ClipboardData(text: copyValue ?? value));
    if (!context.mounted) return;
    AppToast.show(context, copied);
  }
}

Chain? _chainOf(String chainId) => SupportedChains.all.where((candidate) => candidate.id == chainId).firstOrNull;

String _formatTime(DateTime instant) {
  final local = instant.toLocal();
  return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)} '
      '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
