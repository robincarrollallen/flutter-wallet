import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wallet_core/chains.dart';
import '../../../../core/format/amount_formatter.dart';
import '../../../../core/format/token_amount_formatter.dart';
import '../../../../core/responsive/screen_adapter.dart';
import '../../../../widgets/app_toast.dart';
import '../../../../widgets/asset_icon.dart';
import '../../../../widgets/network_fee_selector.dart';
import 'package:wallet_core/wallet_core.dart';
import '../../../../providers/modules/asset/balance_provider.dart';
import '../../../../providers/modules/transaction/evm_fee_provider.dart';
import '../../../../providers/modules/transaction/solana_fee_provider.dart';
import '../../../../providers/modules/transaction/tron_fee_provider.dart';
import '../../../../providers/core/service_provider.dart';
import '../../../../providers/modules/market/currency_provider.dart';
import '../../../../providers/modules/transaction/recent_address_provider.dart';
import '../../../../providers/modules/transaction/transaction_history_provider.dart';
import '../../../../domain/transaction_record.dart';
import '../../../../providers/modules/wallet/wallet_provider.dart';
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
            SendTransactionRequest(
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
              // 带上失效高度，历史页回填时才判得出这笔是「还在等」还是「已经过期」。
              validUntilBlock: result.validUntilBlock,
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
    final fee = _nativeCostOf(asset, from);
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

  /// 本次转账会花掉的原生币总额：网络费，**外加** Solana 代币转账可能要垫付的 ATA 租金。
  ///
  /// 与 [_freshMaxFee] 分开而不是合并：那个的约定是「网络费」，要拿去算 MAX 的可发送额，
  /// 把租金掺进去会让原生 SOL 的 MAX 少发一大截。这个的约定是「一共要花多少」，
  /// 只给 [_feeShortfall] 判「原生币够不够」用。两个问题不同，答案也不同。
  BigInt? _nativeCostOf(ListedAsset asset, String from) {
    if (asset.chain.kind == ChainKind.solana) {
      // 为收款方创建代币账户的租金也从 SOL 里出，漏掉它会在「刚好不够」时放行一笔
      // 注定失败的交易——而那笔租金比网络费本身大几百倍，漏算不是小数点的事。
      return ref.watch(solanaFeeProvider(_solanaFeeKey(asset, from))).value?.lamportsCostFor(_feeSpeed);
    }
    return _freshMaxFee(asset, from);
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
    if (asset.chain.kind == ChainKind.solana) {
      // 同 Tron：solanaFeeProvider 不轮询也不落盘，拿到即新鲜。
      // 这条分支是 MAX 全额转出能正确扣费的关键——缺了它会落到下面的 EVM 分支拿到
      // null，于是确认页显示全额、链上却照扣手续费。
      // 取**当前档位**的报价：优先费随档位变，拿别的档去算 MAX 会差出那笔优先费。
      return ref.watch(solanaFeeProvider(_solanaFeeKey(asset, from))).value?.quoteFor(_feeSpeed).maxFee;
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
  ///
  /// **Solana 也有三档**，但分的不是同一样东西：它的签名费固定（5000 lamport × 签名数，
  /// 加价也不会更快），可竞价的只有优先费（优先单价 × 计算单元）。档位取的是近期区块
  /// 优先费的分位数，所以「按近期区块中位小费出价」这套解释对它同样成立，
  /// 直接复用 [_feeSelector] 那个选择器。链不拥堵时三档都是 0 优先费、显示同一个数，
  /// 那是**事实**——此时确实加价也没用。
  Widget _feeRow(ListedAsset asset, String from) => switch (asset.chain.kind) {
    ChainKind.evm || ChainKind.solana => _feeSelector(asset, from),
    ChainKind.tron => _tronFeeRow(asset, from),
    _ => const _DetailRow(label: '网络费', value: '由网络决定'),
  };

  /// 当前链的三档报价；该链没有分档模型或报价还没到时返回 null。
  Map<FeeSpeed, FeeQuote>? _quotesOf(ListedAsset asset, String from) {
    if (from.isEmpty) return null;
    if (asset.chain.kind == ChainKind.solana) {
      return ref.watch(solanaFeeProvider(_solanaFeeKey(asset, from))).value?.quotes;
    }
    return ref.watch(evmFeeProvider(_feeKey(asset, from))).quotes;
  }

  SolanaFeeKey _solanaFeeKey(ListedAsset asset, String from) => (
    chainId: asset.chain.id,
    from: from,
    to: widget.toAddress,
    amount: widget.amount,
    tokenIdentifier: asset.token?.identifier,
  );

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
    // 与费用选择器同一口径：不足一分的费用显示 `<$0.01`，不舍成会被误解的 `$0.00`。
    final fiat = price <= 0
        ? ''
        : '（${formatFiatFee(double.parse(fee) * price, symbol: ref.watch(currencySymbolProvider))}）';
    return _DetailRow(label: '网络费', value: '≈ ${formatTokenAmount(fee)} ${asset.chain.symbol}$fiat');
  }

  TronFeeKey _tronFeeKey(ListedAsset asset, String from) => (
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
  /// 本次发送注定会在链上失败的原因；没有则返回 null。发送键据此禁用。
  ///
  /// 目前两条，都是「链上必然拒绝」而非「可能有风险」——只有这种确定性的失败才配
  /// 禁用按钮。不确定的一律放行，由各链的交易服务在发送那一刻的链上数据前把关。
  String? _blockingShortfall(ListedAsset asset, String from) =>
      _feeShortfall(asset, from) ?? _rentShortfall(asset, from);

  /// Solana 的租金豁免校验：不满足时返回提示文案，满足或无从判断时返回 null。
  ///
  /// Solana 要求每个账户余额不低于租金豁免线，否则账户会被链上回收。两种必然失败：
  /// - 转入后收款方仍达不到豁免线 → 收款账户创建不出来；
  /// - 转出后自己只剩一点点（不是转空）→ 自己的账户被回收。
  ///
  /// 与服务层 `SolanaTransactionService._verifyRentExempt` 是同一套规则的两处实现：
  /// 这里让按钮提前变灰并说明原因，那里用发送那一刻的链上数据兜底。**两处都要有**——
  /// 只有这里会被过期几秒的报价骗到，只有那里则要用户点下去才知道发不出。
  String? _rentShortfall(ListedAsset asset, String from) {
    // 代币的租金是另一本账：SPL 转账不改变收款方的 SOL 余额，这里两条判断都无从谈起
    // （估费那边也已把 rentExemptMinimum / recipientBalance 置 0 让它们天然失效）。
    // 代币那笔 ATA 租金走的是 [_feeShortfall]（能不能付）与 [_activationNotice]（提前告知）。
    if (asset.chain.kind != ChainKind.solana || asset.token != null || from.isEmpty) return null;
    final estimate = ref.watch(solanaFeeProvider(_solanaFeeKey(asset, from))).value;
    if (estimate == null) return null;

    // 用 MAX 扣费后的实际发送额，而不是用户输入值——否则全额转出会按未扣费的金额判。
    final BigInt amount;
    try {
      amount = parseUnits(_sendableAmount(asset, from), asset.chain.decimals);
    } on FormatException {
      return null;
    }

    if (estimate.shortfallFor(amount) > BigInt.zero) {
      final minimum = formatTokenAmount(
        formatUnits(estimate.rentExemptMinimum - estimate.recipientBalance, asset.chain.decimals),
      );
      return '收款方是新账户，Solana 要求账户余额不低于租金豁免线，'
          '本次至少需转 $minimum ${asset.chain.symbol}';
    }

    // 发送方转出后的余额：0 是合法的（账户清空并回收，这是 MAX 的正常结果），
    // 卡在 0 与豁免线之间才是要拦的——那会让账户被动消失。
    final balance = ref.watch(balanceProvider((asset.chain.id, from, null))).value?.amount;
    if (balance == null) return null;
    final BigInt remaining;
    try {
      // 用当前档位的费用：优先费随档位变，拿错档会让这条判断在边界上判反。
      remaining = parseUnits(balance, asset.chain.decimals) - amount - estimate.quoteFor(_feeSpeed).expectedFee;
    } on FormatException {
      return null;
    }
    if (remaining > BigInt.zero && remaining < estimate.rentExemptMinimum) {
      final line = formatTokenAmount(formatUnits(estimate.rentExemptMinimum, asset.chain.decimals));
      return '转出后余额将低于租金豁免线（$line ${asset.chain.symbol}），账户可能被链上回收。'
          '请减少转出金额，或改用「最大」全额转出';
    }
    return null;
  }

  /// 「这笔转账会为收款方新建一个账户，并为此多花一笔钱」的提示；无需提示时返回 null。
  ///
  /// 两条链各有一套，但对用户是同一件事，所以合在一处、显示在同一个位置。
  String? _activationNotice(ListedAsset asset, String from) {
    if (from.isEmpty) return null;
    return switch (asset.chain.kind) {
      ChainKind.tron => _tronActivationNotice(asset, from),
      ChainKind.solana => _splAccountNotice(asset, from),
      _ => null,
    };
  }

  String? _tronActivationNotice(ListedAsset asset, String from) {
    final estimate = ref.watch(tronFeeProvider(_tronFeeKey(asset, from))).value;
    if (estimate == null || !estimate.activatesRecipient) return null;
    final activation = formatTokenAmount(formatUnits(estimate.activationFeeSun, asset.chain.decimals));
    return '收款方账户尚未激活，网络费中已包含 $activation ${asset.chain.symbol} 激活费';
  }

  /// SPL：收款方没有这个币的代币账户（ATA）时，本次会顺带创建一个，租金由发送方垫付。
  ///
  /// 措辞与 Tron 那条刻意不同——那笔激活费**已含在**上方网络费里，而这笔租金**没有**
  /// （它不是网络费，见 `SolanaFeeEstimate.ataRentLamports`），所以这里要说「另需」。
  /// 也必须说明不退还：这笔钱是存进新账户里的，用户看到余额少了一块会来问。
  String? _splAccountNotice(ListedAsset asset, String from) {
    final token = asset.token;
    if (token == null) return null;
    final estimate = ref.watch(solanaFeeProvider(_solanaFeeKey(asset, from))).value;
    if (estimate == null || !estimate.createsTokenAccount) return null;
    final rent = formatTokenAmount(formatUnits(estimate.ataRentLamports, asset.chain.decimals));
    return '收款方还没有 ${token.symbol} 代币账户，本次将为其创建，'
        '另需 $rent ${asset.chain.symbol} 租金（存入该账户，不退还）';
  }

  /// 网络费选择器：展示所选档位的预计实付，点击可切换档位。
  /// 查询失败该行回退 `--`——估费只是展示，不阻塞发送，最终由节点把关。
  Widget _feeSelector(ListedAsset asset, String from) {
    // 手续费按原生币折算，所以取的是原生币单价（第三个键位为 null），与 asset 是不是代币无关。
    final price = from.isEmpty ? 0.0 : ref.watch(balanceProvider((asset.chain.id, from, null))).value?.price ?? 0.0;
    // stale 只有 EVM 才有：它的 baseFee 每 12 秒一变、报价会落盘，所以要标「更新中」。
    // Solana 的报价不落盘也不轮询，拿到即新鲜，恒为 false。
    final stale = asset.chain.kind == ChainKind.evm && ref.watch(evmFeeProvider(_feeKey(asset, from))).stale;
    return NetworkFeeSelector(
      quotes: _quotesOf(asset, from),
      stale: stale,
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
    // 注定失败的转账（代币的 gas 不够 / Solana 的租金豁免不满足）：
    // 别让用户白等一次链上报错，直接禁用发送键并说明原因。
    final shortfall = _blockingShortfall(asset, from);
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
                    // —— 注定失败的转账（gas 不够 / 租金豁免不满足）：说明原因并禁用发送 —— //
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
