import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../blockchain/chain_registry.dart';
import '../../domain/tron_fee.dart';
import '../../services/tron_transaction_service.dart';

/// 一次 Tron 费用报价的查询键。
///
/// 带上 [amount]：金额的 varint 长度会影响交易字节数，进而影响带宽消耗——
/// 虽然只差几个字节，但正好可能落在「够不够免费额度」的边界上。
/// [to] 也必须在键里：收款方是否已激活决定了那笔 1 TRX 的账户创建费。
typedef TronFeeKey = ({String chainId, String from, String to, String amount});

/// Tron 原生转账的费用报价。
///
/// **刻意不照搬 [evmFeeProvider] 那套轮询 + 落盘缓存**：EVM 的 baseFee 每个区块都在
/// 变，所以要 12 秒轮询、要 stale 标记、要落盘垫底；而 Tron 这边带宽按 24 小时线性
/// 恢复、链参数几乎不变，进确认页取一次就够。少一套缓存就少一处会过期骗人的状态。
///
/// 与仓库其余 FutureProvider 一致地关掉 Riverpod 3 的自动重试：估费失败就让 UI
/// 回退 `--`，不阻塞发送，最终由链上把关。
final tronFeeProvider = FutureProvider.autoDispose.family<TronFeeEstimate, TronFeeKey>((ref, key) {
  final chain = SupportedChains.byId(key.chainId);
  if (chain.kind != ChainKind.tron) {
    throw ArgumentError('tronFeeProvider 只服务 Tron 链，收到 ${chain.id}');
  }
  return const TronTransactionService().estimateNativeFee(
    chain: chain,
    from: key.from,
    to: key.to,
    amount: key.amount,
  );
}, retry: _noRetry);

/// 关掉自动重试：报价只是展示，失败就显示 `--`，不值得在后台反复重试。
Duration? _noRetry(int retryCount, Object error) => null;
