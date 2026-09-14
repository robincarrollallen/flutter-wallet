import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../blockchain/chain_registry.dart';
import '../../../domain/solana_fee.dart';
import '../../core/service_provider.dart';

/// 一次 Solana 费用报价的查询键。
///
/// 带上 [amount] 与 [to]：费用本身与两者无关（签名数 × 每签名费），但同一次查询还要
/// 回答「转这么多给这个地址，够不够租金豁免线」——那两项都必须进键，否则改了金额
/// 或收款方还会命中旧结果，提示就会说假话。
typedef SolanaFeeKey = ({String chainId, String from, String to, String amount});

/// Solana 原生转账的费用与租金豁免报价。
///
/// **刻意不照搬 [evmFeeProvider] 那套轮询 + 落盘缓存**（理由同 [tronFeeProvider]）：
/// Solana 的每签名费是链上参数、租金豁免线由 rent 参数算出，两者都几乎不变，
/// 进确认页取一次就够。少一套缓存就少一处会过期骗人的状态。
///
/// 与仓库其余 FutureProvider 一致地关掉 Riverpod 3 的自动重试：估费失败就让 UI
/// 回退 `--`，不阻塞发送，最终由链上把关。
final solanaFeeProvider = FutureProvider.autoDispose.family<SolanaFeeEstimate, SolanaFeeKey>((ref, key) {
  final chain = SupportedChains.byId(key.chainId);
  if (chain.kind != ChainKind.solana) {
    throw ArgumentError('solanaFeeProvider 只服务 Solana 链，收到 ${chain.id}');
  }

  return ref
      .watch(solanaTransactionServiceProvider)
      .estimateNativeFee(chain: chain, from: key.from, to: key.to, amount: key.amount);
}, retry: _noRetry);

/// 关掉自动重试：报价只是展示，失败就显示 `--`，不值得在后台反复重试。
Duration? _noRetry(int retryCount, Object error) => null;
