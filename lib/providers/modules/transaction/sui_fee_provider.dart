import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wallet_core/chains.dart';
import 'package:wallet_core/wallet_core.dart';

import '../../core/service_provider.dart';
import '../asset/token_catalog_provider.dart';

/// 一次 Sui 费用报价的查询键。
///
/// **不带 `amount`**，与 [aptosFeeProvider] 同形：一笔转账花多少钱与转多少无关。
/// 这是 2026-09-18 在 testnet 上实测确认的——同一份 coin 与预算下，转 1 MIST 与
/// 转 0.01 SUI 的 dry run 结果一字不差。（最初的版本把 amount 放进了键里，
/// 理由是「金额写在 split 出来的 coin 对象里、会影响存储费」——这个推理是错的：
/// coin 对象是定宽的，金额只是里面的一个 u64。）
///
/// 把金额放进键里会让用户每敲一个数字就多发一轮 dry run，换不来任何精度。
///
/// [to] 留在键里：收款方不同会换一笔不同的交易，估价不该跨收款方复用。
///
/// [tokenIdentifier] 为 null 表示原生 SUI，非 null 表示 `Coin<T>` 代币。
/// **代币路径同样不带 `amount`**：`SuiTransactionService` 选取代币 coin 时不看金额
/// （见那边 `_selectTokenCoins` 的说明），所以金额进不了费用结果。
typedef SuiFeeKey = ({String chainId, String from, String to, String? tokenIdentifier});

/// Sui 转账的费用报价（原生与代币共用）。
///
/// 照 [tronFeeProvider] / [aptosFeeProvider] 的一次性查询形态，**不照搬
/// [evmFeeProvider] 那套轮询 + 落盘缓存**：EVM 的 baseFee 每个区块都在变，所以要轮询、
/// 要 stale 标记；Sui 的 reference gas price 在一个 epoch（约一天）内**恒定**，
/// 进确认页取一次就够。少一套缓存就少一处会过期骗人的状态。
///
/// 与仓库其余 FutureProvider 一致地关掉 Riverpod 3 的自动重试：估费失败就让 UI
/// 回退 `--`，不阻塞发送，最终由链上把关。
final suiFeeProvider = FutureProvider.autoDispose.family<SuiFeeEstimate, SuiFeeKey>((ref, key) {
  final chain = SupportedChains.byId(key.chainId);
  if (chain.kind != ChainKind.sui) {
    throw ArgumentError('suiFeeProvider 只服务 Sui 链，收到 ${chain.id}');
  }

  final service = ref.watch(suiTransactionServiceProvider);

  final identifier = key.tokenIdentifier;
  if (identifier == null) {
    return service.estimateNativeFee(chain: chain, from: key.from, to: key.to);
  }

  // 目录里查不到就报错，绝不降级成原生币估算——那会把一笔 USDC 转账的费用说成
  // SUI 转账的费用（代币要多合并若干个 coin 对象，量级对不上）。与 Aptos / Solana / Tron 同一处理。
  final token = ref.watch(tokenCatalogProvider).findToken(key.chainId, identifier);
  if (token == null) {
    throw StateError('代币目录中找不到 $identifier（${chain.name}）');
  }
  return service.estimateTokenFee(chain: chain, token: token, from: key.from, to: key.to);
}, retry: _noRetry);

/// 关掉自动重试：报价只是展示，失败就显示 `--`，不值得在后台反复重试。
Duration? _noRetry(int retryCount, Object error) => null;
