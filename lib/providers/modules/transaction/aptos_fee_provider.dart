import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wallet_core/chains.dart';
import 'package:wallet_core/wallet_core.dart';
import '../../core/service_provider.dart';

/// 一次 Aptos 费用报价的查询键。
///
/// 没有 `amount`：一笔转账消耗多少 gas 与转多少无关，估费本身也是拿固定的探测金额
/// 去模拟的（见 `AptosTransactionService` 的 `_probeAmount`）。把金额放进键里只会
/// 让用户每敲一个数字就多发三轮请求，换不来任何精度。
///
/// [to] 必须在键里：收款方账户存不存在决定了要不要顺带建号，而建号那一步的 gas
/// 比纯转账高出一截。
typedef AptosFeeKey = ({String chainId, String from, String to});

/// Aptos 原生转账的费用报价。
///
/// 照 [tronFeeProvider] 的一次性查询形态，**不照搬 [evmFeeProvider] 那套轮询 + 落盘
/// 缓存**：EVM 的 baseFee 每个区块都在变，所以要轮询、要 stale 标记；Aptos 的
/// `/estimate_gas_price` 取的是最近区块的统计值，进确认页取一次就够。
/// 少一套缓存就少一处会过期骗人的状态。
///
/// 与仓库其余 FutureProvider 一致地关掉 Riverpod 3 的自动重试：估费失败就让 UI
/// 回退 `--`，不阻塞发送，最终由链上把关。
final aptosFeeProvider = FutureProvider.autoDispose.family<AptosFeeEstimate, AptosFeeKey>((ref, key) {
  final chain = SupportedChains.byId(key.chainId);
  if (chain.kind != ChainKind.aptos) {
    throw ArgumentError('aptosFeeProvider 只服务 Aptos 链，收到 ${chain.id}');
  }

  // 没有代币分支：Aptos 目前只实现了原生币转账（AptosTransferService.supportsToken
  // 为 false），代币压根进不了发送列表，也就走不到估费这一步。
  return ref
      .watch(aptosTransactionServiceProvider)
      .estimateNativeFee(chain: chain, from: key.from, to: key.to);
}, retry: _noRetry);

/// 关掉自动重试：报价只是展示，失败就显示 `--`，不值得在后台反复重试。
Duration? _noRetry(int retryCount, Object error) => null;
