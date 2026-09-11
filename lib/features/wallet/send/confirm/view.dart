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
import '../../../../providers/modules/asset/balance_provider.dart';
import '../../../../providers/modules/transaction/evm_fee_provider.dart';
import '../../../../providers/modules/transaction/tron_fee_provider.dart';
import '../../../../providers/core/service_provider.dart';
import '../../../../providers/modules/market/currency_provider.dart';
import '../../../../providers/modules/transaction/recent_address_provider.dart';
import '../../../../providers/modules/transaction/transaction_history_provider.dart';
import '../../../../domain/transaction_record.dart';
import '../../../../providers/modules/wallet/wallet_provider.dart';
import '../../../../dto/request/send_tx_request.dart';
import '../../../../blockchain/chain_registry.dart';
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
      final result = await ref.read(walletServiceProvider)
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
      // 记入交易历史。金额取链上实际发出的值——MAX 扣费后可能小于用户输入。
      ref
          .read(transactionHistoryProvider.notifier)
          .record(
            TransactionRecord(
              transactionHash: result.hash,
              walletId: wallet.id,
              chainId: widget.asset.chain.id,
              tokenIdentifier: widget.asset.token?.identifier,
              symbol: widget.asset.symbol,
              fromAddress: from,
              toAddress: widget.toAddress,
              amount: result.sentAmount,
              submittedAt: DateTime.now(),
              status: result.status,
            ),
          );
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

  /// 费用尚未就绪、但本次**会**从转出额里扣费。
  ///
  /// 这是唯一必须挡住发送的费用状态：[_sendableAmount] 在拿不到报价时回退成全额，
  /// 而 `deductFeeFromAmount` 已经传给了服务层，链上照样会扣——于是确认页显示
  /// 全额、实际发出的却更少，**用户确认的数字不是将要发生的事**。
  ///
  /// 只挡这一种。手输金额时费用未知只是信息不全，不是说了假话（输入多少就发多少），
  /// 此时仍按仓库惯例放行：估费不阻塞发送，最终由链上把关；否则估费接口一挂，
  /// 用户连本可成功的交易都发不出去。
  ///
  /// 注意 [_freshMaxFee] 对 EVM 的 **stale 报价**也返回 null，所以这条同时覆盖
  /// 「报价过期」——两条链共用。
  bool _feePendingForDeduction(ListedAsset asset, String from) =>
      _deductsFee && from.isNotEmpty && _freshMaxFee(asset, from) == null;

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
  /// 不确定就放行，最终由各链的交易服务在链上数据前把关。
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

  /// 本次转账的费用上限（以**原生币**计价）；报价缺失或已过期时返回 null。
  ///
  /// [_sendableAmount] 与 [_feeShortfall] 都经由这里，所以它是「费用如何影响金额与
  /// 可发送性」的唯一入口——按链分流放在这一处，两条路径就一起通了。
  BigInt? _freshMaxFee(ListedAsset asset, String from) {
    if (asset.chain.kind == ChainKind.tron) {
      // Tron 没有 stale 这一说：tronFeeProvider 不轮询也不落盘，拿到即新鲜。
      // feeSun 以 TRX 计价，与本方法「原生币计价」的约定一致。
      return ref.watch(tronFeeProvider(_tronFeeKey(asset, from))).value?.feeSun;
    }
    final view = ref.watch(evmFeeProvider(_feeKey(asset, from)));
    return view.stale ? null : view.quotes?[_feeSpeed]?.maxFee;
  }

  /// 网络费一行，按链的费用模型分流。
  ///
  /// **只有 EVM 有「gasPrice × gasLimit + 三档」这套模型**，所以只有它显示可切换的
  /// 档位选择器。给 Tron 套三档会是三重误导：三档都是 `--`（[evmFeeProvider] 对非 EVM
  /// 直接 return，压根不查）、档位解释「小费 / 区块中位小费 / 优先被打包」全是
  /// EIP-1559 概念，而 Tron 按带宽计费、**加价也不会更快**，且 `TronTransferService`
  /// 根本忽略 speed。所以 Tron 走自己的单值行 [_tronFeeRow]。
  Widget _feeRow(ListedAsset asset, String from) => switch (asset.chain.kind) {
    ChainKind.evm => _feeSelector(asset, from),
    ChainKind.tron => _tronFeeRow(asset, from),
    _ => const _DetailRow(label: '网络费', value: '由网络决定'),
  };

  /// Tron 的费用行：单一数值，不可切换（这条链没有档位可选）。
  ///
  /// 带宽够就是真的免费，所以「免费」要说得明确，并把剩余带宽一并给出——
  /// 否则用户无从判断下一笔还免不免费。查询中/失败一律回退 `--`：
  /// 估费只是展示，不阻塞发送，最终由链上把关。
  Widget _tronFeeRow(ListedAsset asset, String from) {
    if (from.isEmpty) return const _DetailRow(label: '网络费', value: '--');
    final estimate = ref.watch(tronFeeProvider(_tronFeeKey(asset, from))).value;
    if (estimate == null) return const _DetailRow(label: '网络费', value: '--');

    if (estimate.isFree) {
      // 代币转账的免费是「能量也够」，与原生币只看带宽不是一回事，说清楚是哪一项。
      final detail = estimate.energyNeeded > 0
          ? '剩余能量 ${estimate.energyAvailable}，本次需 ${estimate.energyNeeded}'
          : '剩余带宽 ${estimate.bandwidthAvailable}，本次需 ${estimate.bandwidthNeeded}';
      return _DetailRow(label: '网络费', value: '免费（$detail）');
    }

    final price = ref.watch(balanceProvider((asset.chain.id, from, null))).value?.price ?? 0.0;
    final fee = formatUnits(estimate.feeSun, asset.chain.decimals);
    final fiat = price <= 0
        ? ''
        : '（${ref.watch(currencySymbolProvider)}${(double.parse(fee) * price).toStringAsFixed(2)}）';
    return _DetailRow(label: '网络费', value: '≈ ${formatTokenAmount(fee)} ${asset.chain.symbol}$fiat');
  }

  TronFeeKey _tronFeeKey(ListedAsset asset, String from) =>
      (
        chainId: asset.chain.id,
        from: from,
        to: widget.toAddress,
        amount: widget.amount,
        tokenIdentifier: asset.token?.identifier,
      );

  /// 收款方账户未激活的提示；无需提示时返回 null。
  ///
  /// 向一个从未上链的地址转 TRX，会被扣一笔账户创建费（主网 1 TRX）。不说的话，
  /// 用户只会在事后发现余额对不上。
  ///
  /// 措辞是「网络费中已包含」而不是「额外消耗」：这笔钱**已经算在**上方那行网络费
  /// 里了，说「额外」会让用户以为要在网络费之外再付一次。
  ///
  /// 金额只取 [TronFeeEstimate.activationFeeSun] 而非 `feeSun`：后者在带宽也不足时
  /// 还混着带宽欠费（1 TRX 激活 + 0.1 TRX 带宽 = 1.1），拿总额去说「为其激活」
  /// 会把这笔说大。
  String? _activationNotice(ListedAsset asset, String from) {
    if (asset.chain.kind != ChainKind.tron || from.isEmpty) return null;
    final estimate = ref.watch(tronFeeProvider(_tronFeeKey(asset, from))).value;
    if (estimate == null || !estimate.activatesRecipient) return null;
    final activation = formatTokenAmount(formatUnits(estimate.activationFeeSun, asset.chain.decimals));
    return '收款方账户尚未激活，网络费中已包含 $activation ${asset.chain.symbol} 激活费';
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
    // Tron：收款方未激活会被额外扣账户创建费，发送前必须让用户看到。
    final activationNotice = _activationNotice(asset, from);
    // MAX 且费用未就绪：此时展示的是全额，而链上会扣——先挡住，别让用户确认一个
    // 不会发生的数字。
    final feePending = _feePendingForDeduction(asset, from);

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
                    // 条件按「真的扣掉了」判，而不是「本次允许扣」：报价未就绪，
                    // 以及 Tron 这类没有 gas 报价模型的链，sendable 会原样等于输入值，
                    // 此时再说「已扣除网络费用」就是假话。
                    if (_deductsFee && sendable != widget.amount) ...[
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
                          _feeRow(asset, from),
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
                    // —— 全额转出但费用还没算出来：说明为什么发送键是灰的 —— //
                    // 不给理由的禁用按钮会被当成卡死，用户只会反复点。
                    if (feePending) ...[
                      SizedBox(height: 16.s),
                      Text(
                        '正在估算网络费，稍候即可发送',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                    // —— Tron 收款方未激活：会被额外扣一笔账户创建费 —— //
                    // 用 tertiary 而不是 error：这不是错误，交易能成，只是要多花钱，
                    // 但用户有权在按下发送前知道。
                    if (activationNotice != null) ...[
                      SizedBox(height: 16.s),
                      Text(
                        activationNotice,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary),
                      ),
                    ],
                    SizedBox(height: 24.s),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submitting || shortfall != null || feePending ? null : _submit,
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
