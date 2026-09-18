import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wallet_core/chains.dart';
import 'package:wallet_core/wallet_core.dart';
import '../../core/service_provider.dart';
import '../asset/token_catalog_provider.dart';

/// 一次 Aptos 费用报价的查询键。
///
/// 没有 `amount`：一笔转账消耗多少 gas 与转多少无关，估费本身也是拿固定的探测金额
/// 去模拟的（见 `AptosTransactionService` 的 `_probeAmount`）。把金额放进键里只会
/// 让用户每敲一个数字就多发三轮请求，换不来任何精度。
///
/// [to] 必须在键里：收款方账户存不存在决定了要不要顺带建号，而建号那一步的 gas
/// 比纯转账高出一截。
///
/// [tokenIdentifier] 为 null 表示原生 APT。代币与原生的 gas 量级差得远，
/// 不带它会让两者共用一份报价。
typedef AptosFeeKey = ({String chainId, String from, String to, String? tokenIdentifier});

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

  final service = ref.watch(aptosTransactionServiceProvider);

  final identifier = key.tokenIdentifier;
  if (identifier == null) {
    return service.estimateNativeFee(chain: chain, from: key.from, to: key.to);
  }

  // 目录里查不到就报错，绝不降级成原生币估算——那会把一笔 USDC 转账的费用说成
  // APT 转账的费用（两者的 gas 上限差两个数量级）。与 Solana / Tron 同一处理。
  final token = ref.watch(tokenCatalogProvider).findToken(key.chainId, identifier);
  if (token == null) {
    throw StateError('代币目录中找不到 $identifier（${chain.name}）');
  }
  return service.estimateTokenFee(chain: chain, token: token, from: key.from, to: key.to);
}, retry: _noRetry);

/// 关掉自动重试：报价只是展示，失败就显示 `--`，不值得在后台反复重试。
Duration? _noRetry(int retryCount, Object error) => null;
