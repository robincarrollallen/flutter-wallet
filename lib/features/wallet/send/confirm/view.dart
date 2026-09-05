import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../blockchain/units.dart';
import '../../../../core/format/token_amount_formatter.dart';
import '../../../../core/responsive/screen_adapter.dart';
import '../../../../widgets/app_toast.dart';
import '../../../../widgets/asset_icon.dart';
import '../../../../widgets/network_fee_selector.dart';
import '../../../../enums/fee_speed.dart';
import '../../../../providers/modules/balance_provider.dart';
import '../../../../providers/modules/evm_fee_provider.dart';
import '../../../../services/wallet_service.dart';
import '../../../../providers/modules/currency_provider.dart';
import '../../../../providers/modules/recent_address_provider.dart';
import '../../../../providers/modules/wallet_provider.dart';
import '../../../../dto/request/send_tx_request.dart';
import '../../../../blockchain/listed_asset.dart';
import '../../../../router/route_args.dart';
import '../../../../router/routes.dart';

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

  /// 当前选择的网络费档位，默认「普通」。
  FeeSpeed _feeSpeed = FeeSpeed.defaultSpeed;

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
              tokenIdentifier: widget.asset.token?.identifier,
              deductFeeFromAmount: _deductsFee,
              speed: _feeSpeed,
            ),
            wallet,
          );
      if (!mounted) return; // 确保当前 Widget 仍然存在于页面树（未被销毁）
      // 记入「最近使用」，供下次发送时快速选择。
      ref.read(recentAddressesProvider.notifier).record(widget.asset.chain.id, widget.toAddress);
      // 交易提交后余额可能变化，按惯例整体刷新（代币转账还会动原生币——扣了 gas）。
      ref.invalidate(balanceProvider);
      ref.invalidate(chainTokenBalancesProvider);
      // 用结果页替换掉确认页，防止返回到确认页重复提交；
      // 结果页自身禁用返回手势，「完成」按钮直接 go 回首页，不会退回中间步骤。
      context.pushReplacement(
        AppRoute.sendResult,
        extra: SendResultArgs(
          asset: widget.asset,
          toAddress: widget.toAddress,
          // MAX 场景下链上重估费用后金额可能再被扣减，结果页按链上实际值展示。
          amount: result.sentAmount,
          txHash: result.hash,
          status: result.status,
        ),
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

  /// 本次转账的报价查询键：带资产维度——原生币与代币的 gasLimit 不是一个量级。
  EvmFeeKey _feeKey(ListedAsset asset, String from) =>
      (chainId: asset.chain.id, from: from, to: widget.toAddress, tokenIdentifier: asset.token?.identifier);

  /// 本次是否会从转出额里扣手续费：只有**原生币**的 MAX 才会。
  ///
  /// 代币的手续费付的是原生币，从代币里扣不出来——代币 MAX 就是代币余额本身，
  /// 够不够付 gas 由 [_feeShortfall] 单独判。
  bool get _deductsFee => widget.isMaxAmount && widget.asset.token == null;

  /// 全额转出（MAX）时的发送上限：可用余额 − 费用上限。
  /// 费用或余额尚未就绪、以及扣完不为正时回退用户输入值，由发送时的链上校验兜底。
  /// 非 MAX 场景（含代币 MAX）恒为用户输入的金额。
  String _sendableAmount(ListedAsset asset, String from) {
    if (!_deductsFee || from.isEmpty) return widget.amount;
    // 只认新鲜报价：落盘的旧 baseFee 可能差出几倍，拿它算可发送额会误导用户。
    final fee = _freshMaxFee(asset, from);
    // 第三个键位固定传 null（原生币）：MAX 是「余额 − 手续费」，而手续费以原生币计价。
    final balance = ref.watch(balanceProvider((asset.chain.id, from, null))).value?.amount;
    if (fee == null || balance == null) return widget.amount;
    try {
      final net = parseUnits(balance, asset.chain.decimals) - fee;
      return net <= BigInt.zero ? widget.amount : formatUnits(net, asset.chain.decimals);
    } on FormatException {
      return widget.amount;
    }
  }

  /// 代币转账时校验原生币够不够付 gas；不足返回提示文案，否则返回 null。
  ///
  /// 原生币转账不用这条：它的「金额 + 费用」是同一本账，已由 [_sendableAmount]
  /// 与链上校验覆盖。报价或余额未就绪时返回 null——估费只是前置提醒，
  /// 不确定就放行，最终由 [EvmTransactionService] 在链上数据前把关。
  String? _feeShortfall(ListedAsset asset, String from) {
    if (asset.token == null || from.isEmpty) return null;
    final fee = _freshMaxFee(asset, from);
    final nativeBalance = ref.watch(balanceProvider((asset.chain.id, from, null))).value?.amount;
    if (fee == null || nativeBalance == null) return null;
    try {
      if (parseUnits(nativeBalance, asset.chain.decimals) >= fee) return null;
    } on FormatException {
      return null;
    }
    // 「需约」是网络费，截断展示；「可用」是余额，与确认页金额一样给全精度。
    return '${asset.chain.symbol} 不足以支付网络费：需约 ${formatTokenAmount(formatUnits(fee, asset.chain.decimals))} '
        '${asset.chain.symbol}，可用 $nativeBalance';
  }

  /// 当前档位的费用上限；报价缺失或已过期时返回 null。
  BigInt? _freshMaxFee(ListedAsset asset, String from) {
    final view = ref.watch(evmFeeProvider(_feeKey(asset, from)));
    return view.stale ? null : view.quotes?[_feeSpeed]?.maxFee;
  }

  /// 网络费选择器：展示所选档位的预计实付，点击可切换档位。
  /// 查询失败该行回退 `--`——估费只是展示，不阻塞发送，最终由节点把关。
  Widget _feeSelector(ListedAsset asset, String from) {
    // 手续费按原生币折算，所以取的是原生币单价（第三个键位为 null），与 asset 是不是代币无关。
    final price = from.isEmpty ? 0.0 : ref.watch(balanceProvider((asset.chain.id, from, null))).value?.price ?? 0.0;
    final view = ref.watch(evmFeeProvider(_feeKey(asset, from)));
    return NetworkFeeSelector(
      quotes: view.quotes,
      stale: view.stale,
      speed: _feeSpeed,
      onSpeedChanged: (speed) => setState(() => _feeSpeed = speed),
      decimals: asset.chain.decimals,
      symbol: asset.chain.symbol,
      fiatPrice: price,
      currencySymbol: ref.watch(currencySymbolProvider),
      enabled: !_submitting,
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
    // 代币转账：原生币不够付 gas 就别让用户白等一次链上报错。
    final shortfall = _feeShortfall(asset, from);

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
                      // 刻意不走 formatTokenAmount：这是即将上链的金额，
                      // 用户必须能核对到最后一位，截断会藏掉真正要发出去的数。
                      '$sendable ${asset.symbol}',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4.s),
                    Text(
                      asset.chain.name,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    // —— 全额转出：说明金额已扣除网络费用 —— //
                    if (_deductsFee) ...[
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
                          _feeSelector(asset, from),
                        ],
                      ),
                    ),
                    // —— 原生币不足以付 gas：说明原因并禁用发送 —— //
                    if (shortfall != null) ...[
                      SizedBox(height: 16.s),
                      Text(
                        shortfall,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      ),
                    ],
                    SizedBox(height: 24.s),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submitting || shortfall != null ? null : _submit,
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
