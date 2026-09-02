import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../blockchain/units.dart';
import '../../../../core/responsive/screen_adapter.dart';
import '../../../../widgets/app_toast.dart';
import '../../../../widgets/asset_icon.dart';
import '../../../../providers/modules/balance_provider.dart';
import '../../../../services/wallet_service.dart';
import '../../../../providers/modules/currency_provider.dart';
import '../../../../providers/modules/recent_address_provider.dart';
import '../../../../providers/modules/wallet_provider.dart';
import '../../../../dto/request/send_tx_request.dart';
import '../../../../blockchain/listed_asset.dart';
import '../result/view.dart';

/// 确认发送子页：汇总资产 / 发送方 / 收款方 / 金额，确认后提交交易。
class SendConfirmPage extends ConsumerStatefulWidget {
  const SendConfirmPage({
    super.key,
    required this.asset,
    required this.toAddress,
    required this.amount,
    this.isMaxAmount = false,
    this.tokenLogoUrl,
    this.chainLogoUrl,
  });

  final ListedAsset asset;
  final String toAddress;
  final String amount;

  /// 金额是否来自「最大」（= 全额余额）。仅该场景允许从转出额中扣除网络费用，
  /// 本页展示扣除后的发送上限。
  final bool isMaxAmount;
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
              deductFeeFromAmount: widget.isMaxAmount,
            ),
            wallet,
          );
      if (!mounted) return; // 确保当前 Widget 仍然存在于页面树（未被销毁）
      // 记入「最近使用」，供下次发送时快速选择。
      ref.read(recentAddressesProvider.notifier).record(widget.asset.chain.id, widget.toAddress);
      // 交易提交后余额可能变化，按惯例整体刷新。
      ref.invalidate(balanceProvider);
      // 结果页替换掉整个发送流程栈（仅保留首页），防止返回到确认页重复提交。
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => SendResultPage(
            asset: widget.asset,
            toAddress: widget.toAddress,
            // MAX 场景下链上重估费用后金额可能再被扣减，结果页按链上实际值展示。
            amount: result.sentAmount,
            txHash: result.hash,
            status: result.status,
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

  /// 全额转出（MAX）时的发送上限：可用余额 − 费用上限。
  /// 费用或余额尚未就绪、以及扣完不为正时回退用户输入值，由发送时的链上校验兜底。
  /// 非 MAX 场景恒为用户输入的金额。
  String _sendableAmount(ListedAsset asset, String from) {
    if (!widget.isMaxAmount || from.isEmpty) return widget.amount;
    final fee = ref.watch(evmFeeProvider((asset.chain.id, from, widget.toAddress))).value;
    // 第三个键位固定传 null（原生币）：MAX 是「余额 − 手续费」，而手续费以原生币计价。
    // 代币转账接入后这里要改成「代币余额不扣费、另判原生币够不够付 gas」。
    final balance = ref.watch(balanceProvider((asset.chain.id, from, null))).value?.amount;
    if (fee == null || balance == null) return widget.amount;
    try {
      final net = parseUnits(balance, asset.chain.decimals) - fee;
      return net <= BigInt.zero ? widget.amount : formatUnits(net, asset.chain.decimals);
    } on FormatException {
      return widget.amount;
    }
  }

  /// 费用行文案：按费率上限 × gasLimit 估算并附法币折算；
  /// 查询失败回退 `--`——估费只是展示，不阻塞发送，最终由节点把关。
  String _feeText(ListedAsset asset, String from) {
    final feeAsync = ref.watch(evmFeeProvider((asset.chain.id, from, widget.toAddress)));
    return feeAsync.when(
      loading: () => '查询中…',
      error: (_, _) => '--',
      data: (fee) {
        final amount = formatUnits(fee, asset.chain.decimals);
        // 手续费按原生币折算，所以取的是原生币单价（第三个键位为 null），与 asset 是不是代币无关。
        final price = from.isEmpty ? 0.0 : ref.watch(balanceProvider((asset.chain.id, from, null))).value?.price ?? 0.0;
        if (price <= 0) return '≈ $amount ${asset.chain.symbol}';
        final fiat = (double.tryParse(amount) ?? 0) * price;
        final symbol = ref.watch(currencySymbolProvider);
        return '≈ $amount ${asset.chain.symbol}（$symbol${fiat.toStringAsFixed(2)}）';
      },
    );
  }

  String _stripExceptionPrefix(String message) {
    const prefix = 'Exception: ';
    return message.startsWith(prefix) ? message.substring(prefix.length) : message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = widget.asset;
    final wallet = ref.watch(activeWalletProvider);
    final from = wallet?.addressFor(asset.chain) ?? '';
    // MAX 场景展示扣除网络费用后的发送上限，与实际上链金额保持一致。
    final sendable = _sendableAmount(asset, from);

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
                  onPressed: _submitting ? null : () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text('确认发送', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
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
                      '$sendable ${asset.symbol}',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4.s),
                    Text(
                      asset.chain.name,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    // —— 全额转出：说明金额已扣除网络费用 —— //
                    if (widget.isMaxAmount) ...[
                      SizedBox(height: 4.s),
                      Text(
                        '全额转出：可用 ${widget.amount} ${asset.symbol}，已扣除预估网络费用',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
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
                          _DetailRow(label: '网络费用（预估）', value: _feeText(asset, from)),
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
                                child: const CircularProgressIndicator(strokeWidth: 2),
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
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
