import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/responsive/screen_adapter.dart';
import '../../../../widgets/app_toast.dart';
import '../../../../blockchain/listed_asset.dart';
import '../../../../enums/evm_send_status.dart';

/// 发送结果页：展示上链状态与交易哈希，支持复制；「完成」回到首页。
class SendResultPage extends StatelessWidget {
  const SendResultPage({
    super.key,
    required this.asset,
    required this.toAddress,
    required this.amount,
    required this.txHash,
    this.status = EvmSendStatus.pending,
  });

  final ListedAsset asset;
  final String toAddress;
  final String amount;
  final String txHash;
  final EvmSendStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, title, subtitle) = switch (status) {
      EvmSendStatus.confirmed => (
        Icons.check_circle_rounded,
        theme.colorScheme.primary,
        '已确认',
        '交易已上链确认',
      ),
      EvmSendStatus.failed => (
        Icons.error_rounded,
        theme.colorScheme.error,
        '上链失败',
        '交易已广播但执行失败，gas 可能已消耗',
      ),
      EvmSendStatus.pending => (
        Icons.hourglass_top_rounded,
        theme.colorScheme.tertiary,
        '确认中',
        '已广播，等待网络确认（可稍后在区块浏览器查看）',
      ),
    };

    // 结果页是流程终点：禁用返回手势（确认页已被移出栈，无处可退）。
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24.s, 16.s, 24.s, 24.s),
            child: Column(
              children: [
                const Spacer(),
                Icon(icon, size: 64.s, color: color),
                SizedBox(height: 16.s),
                Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                SizedBox(height: 8.s),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                SizedBox(height: 4.s),
                Text(
                  '$amount ${asset.symbol} · ${asset.chain.name}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                SizedBox(height: 24.s),
                // —— 交易哈希：点击整块复制 —— //
                InkWell(
                  borderRadius: BorderRadius.circular(12.s),
                  onTap: () => _copy(context),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12.s),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12.s),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '交易哈希',
                          style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        SizedBox(height: 6.s),
                        Row(
                          children: [
                            Expanded(
                              child: Text(txHash, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                            ),
                            SizedBox(width: 8.s),
                            Icon(Icons.copy_rounded, size: 18.s, color: theme.colorScheme.primary),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    // 确认页已把发送流程移出栈，这里 pop 即回到首页。
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('完成'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: txHash));
    AppToast.show(context, '已复制');
  }
}
