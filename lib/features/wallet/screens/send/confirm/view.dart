import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/blockchain/units.dart';
import '../../../../../core/responsive/screen_adapter.dart';
import '../../../../../core/widgets/app_toast.dart';
import '../../../../../core/widgets/asset_icon.dart';
import '../../../../../providers/modules/balance_provider.dart';
import '../../../../../providers/modules/currency_provider.dart';
import '../../../../../providers/modules/recent_address_provider.dart';
import '../../../../../providers/modules/wallet_provider.dart';
import '../../../data/dto/send_tx_request.dart';
import '../coins/state.dart';
import '../result/view.dart';

/// 确认发送子页：汇总资产 / 发送方 / 收款方 / 金额，确认后提交交易。
class SendConfirmPage extends ConsumerStatefulWidget {
  const SendConfirmPage({
    super.key,
    required this.asset,
    required this.toAddress,
    required this.amount,
    this.tokenLogoUrl,
    this.chainLogoUrl,
  });

  final SendAsset asset;
  final String toAddress;
  final String amount;
  final String? tokenLogoUrl;
  final String? chainLogoUrl;

  @override
  ConsumerState<SendConfirmPage> createState() => _SendConfirmPageState();
}

class _SendConfirmPageState extends ConsumerState<SendConfirmPage> {
  bool _submitting = false;

  Future<void> _submit() async {
    final wallet = ref.read(activeWalletProvider);
    final from = wallet?.addressFor(widget.asset.chain);
    if (wallet == null || from == null) return;

    setState(() => _submitting = true);
    try {
      final result = await ref
          .read(walletServiceProvider)
          .sendTransaction(
            SendTxRequest(
              from: from,
              to: widget.toAddress,
              amount: widget.amount,
              chainId: widget.asset.chain.id,
            ),
            wallet,
          );
      if (!mounted) return; // 确保当前 Widget 仍然存在于页面树（未被销毁）
      // 记入「最近使用」，供下次发送时快速选择。
      ref
          .read(recentAddressesProvider.notifier)
          .record(widget.asset.chain.id, widget.toAddress);
      // 交易提交后余额可能变化，按惯例整体刷新。
      ref.invalidate(balanceProvider);
      // 结果页替换掉整个发送流程栈（仅保留首页），防止返回到确认页重复提交。
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => SendResultPage(
            asset: widget.asset,
            toAddress: widget.toAddress,
            // gas 不足自动扣费时实际金额会小于输入金额，结果页按链上实际值展示。
            amount: result.sentAmount,
            txHash: result.hash,
          ),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      // 统一转为 Exception 后，优先透传异常文案；其余给通用文案。
      final reason = switch (e) {
        UnsupportedError(:final message) => message ?? '该链转账暂未支持',
        FormatException(:final message) => message,
        Exception _ => '发送失败：${_stripExceptionPrefix(e.toString())}',
        _ => '发送失败，请稍后重试',
      };
      AppToast.show(context, reason);
    }
  }

  /// 费用行文案：按费率上限（maxFeePerGas × 21000）估算并附法币折算；
  /// 查询失败回退 `--`——估费只是展示，不阻塞发送，最终由节点把关。
  String _feeText(SendAsset asset, String from) {
    final feeAsync = ref.watch(evmFeeProvider(asset.chain.id));
    return feeAsync.when(
      loading: () => '查询中…',
      error: (_, _) => '--',
      data: (fee) {
        final amount = formatUnits(fee, asset.chain.decimals);
        final price = from.isEmpty
            ? 0.0
            : ref.watch(balanceProvider((asset.chain.id, from))).value?.price ??
                  0.0;
        if (price <= 0) return '≈ $amount ${asset.chain.symbol}';
        final fiat = (double.tryParse(amount) ?? 0) * price;
        final symbol = ref.watch(currencySymbolProvider);
        return '≈ $amount ${asset.chain.symbol}（$symbol${fiat.toStringAsFixed(2)}）';
      },
    );
  }

  String _stripExceptionPrefix(String message) {
    const prefix = 'Exception: ';
    return message.startsWith(prefix)
        ? message.substring(prefix.length)
        : message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = widget.asset;
    final wallet = ref.watch(activeWalletProvider);
    final from = wallet?.addressFor(asset.chain) ?? '';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // —— 顶部头部：返回箭头 + 标题 —— //
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '返回',
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text(
                    '确认发送',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 48.s),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24.s, 8.s, 24.s, 24.s),
                child: Column(
                  children: [
                    // —— 资产标识 + 发送金额 —— //
                    AssetIcon(
                      symbol: asset.symbol,
                      tokenLogoUrl: widget.tokenLogoUrl,
                      chainSymbol: asset.chain.symbol,
                      chainLogoUrl: widget.chainLogoUrl,
                      size: 48.s,
                    ),
                    SizedBox(height: 12.s),
                    Text(
                      '${widget.amount} ${asset.symbol}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4.s),
                    Text(
                      asset.chain.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(height: 24.s),
                    // —— 明细卡片 —— //
                    Container(
                      padding: EdgeInsets.all(16.s),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12.s),
                      ),
                      child: Column(
                        children: [
                          _DetailRow(label: '发送方', value: from),
                          SizedBox(height: 12.s),
                          _DetailRow(label: '收款方', value: widget.toAddress),
                          SizedBox(height: 12.s),
                          _DetailRow(label: '网络', value: asset.chain.name),
                          SizedBox(height: 12.s),
                          _DetailRow(
                            label: '网络费用（预估）',
                            value: _feeText(asset, from),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 24.s),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? SizedBox(
                                width: 18.s,
                                height: 18.s,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('确认发送'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 明细行：左侧灰色标签，右侧等宽字体值（地址类内容可完整换行展示）。
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(width: 16.s),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}
