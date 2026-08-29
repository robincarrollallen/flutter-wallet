import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../blockchain/chain_registry.dart';
import '../../blockchain/listed_asset.dart';
import '../../data/datasource/remote/chain_balance_api.dart';
import '../../data/datasource/remote/coingecko_api.dart' show Markets;
import '../../data/repository/balance_repository.dart';
import '../../domain/account_balance.dart';
import '../../domain/wallet.dart';
import '../../domain/wallet_total.dart';
import '../../services/evm_transaction_service.dart';
import '../market_repository_provider.dart';
import '../token_catalog_provider.dart';
import 'currency_provider.dart';
import 'wallet_provider.dart';

export '../../data/datasource/remote/coingecko_api.dart' show Markets;

/// (chainId, from, to) -> EVM 原生转账的预估费用上限（wei）。
/// autoDispose：仅发送流程使用，进确认页才查、离开即弃，不常驻缓存。
final evmFeeProvider = FutureProvider.autoDispose.family<BigInt, (String, String, String)>((ref, key) {
  final (chainId, from, to) = key;
  return const EvmTransactionService().estimateNativeFee(SupportedChains.byId(chainId), from: from, to: to);
});

/// 全部受支持链币种的实时行情：coinGeckoId -> (单价, 图标 URL)。
/// 一次请求覆盖所有链，避免每张卡片重复请求行情。
///
/// 单价按 [currencyProvider] 选定的法币由 CoinGecko 直接返回（无本地汇率换算），
/// 切换法币即重取——缓存按币种分键，不会互相覆盖。
///
/// 落盘缓存、TTL 与失败回退全部下沉到 [MarketRepository]；这里只保留
/// [Ref.keepAlive]——Riverpod 3.x 默认 autoDispose，不保活的话每次离开首页
/// 缓存即销毁，回来就是一次全新请求。
final marketsProvider = FutureProvider<Markets>((ref) async {
  ref.keepAlive();
  final currency = ref.watch(currencyProvider);
  // select 字符串：远程 loading→data 若 id 集合不变，不会重拉行情。
  final idsKey = ref.watch(tokenCatalogProvider.select((c) => c.coinGeckoIdsKey));
  return ref.watch(marketRepositoryProvider).getMarkets(currency: currency, ids: idsKey.split(','));
});

/// 下拉刷新：强制重取行情与余额。返回的 Future 完成即代表刷新结束，
/// 直接交给 RefreshIndicator.onRefresh 驱动指示器的转动与收起。
///
/// 刻意不走「先删缓存、再 invalidate」那条路：那样一旦请求失败，
/// 兜底用的旧缓存已经被删掉，页面会直接掉到 $0.00。
/// 这里改为先把新数据拿到手，成功才覆盖缓存——失败时旧缓存原封不动，维持旧价格。
Future<void> refreshHomeData(WidgetRef ref, {String? walletId}) async {
  final catalogUpdated = await ref.read(tokenRepositoryProvider).refreshCatalog();
  if (catalogUpdated) {
    ref.invalidate(remoteTokensProvider);
    await ref.read(remoteTokensProvider.future);
  }

  final currency = ref.read(currencyProvider);
  final ids = ref.read(tokenCatalogProvider).coinGeckoIds;
  final updated = await ref.read(marketRepositoryProvider).refreshMarkets(currency: currency, ids: ids);

  // 取数失败时跳过 invalidate，marketsProvider 保持原值，UI 上的价格不动。
  if (updated) {
    // 让 marketsProvider 重读刚落盘的数据。此刻 TTL 尚新，它会直接命中缓存返回，
    // 不会因为这次 invalidate 再多发一次请求。
    ref.invalidate(marketsProvider);
  }

  // 余额没有 TTL，每次下拉都重查。整个 family 一起 invalidate，
  // 依赖它的 walletTotalProvider 会级联重算。
  ref.invalidate(balanceProvider);

  // 等首页真正要显示的总资产算完，指示器才收起，避免转完了数字还在跳。
  if (walletId != null) {
    await ref.read(walletTotalProvider(walletId).future);
  }
}

/// 按 (chainId, address) 查询某链余额，并附带实时单价。
/// AsyncValue 自动提供 loading / error / data 三态。
///
/// 同步段写法（与 [walletTotalProvider] 一致）：ref.watch 必须跑在第一个 await
/// 之前，否则余额一失败就登记不上对 [marketsProvider] 的依赖，行情刷新时这条链
/// 不会重算。顺带让余额与行情两个请求并发，首屏不必串行等两个往返。
final balanceProvider = FutureProvider.family<AccountBalance, (String, String)>((ref, key) async {
  final (chainId, address) = key;
  final chain = SupportedChains.byId(chainId);

  /// 同步并发执行(异步调用方法不立即 await)
  final marketsFuture = ref.watch(marketsProvider.future);
  final baseFuture = const BalanceRepository(ChainBalanceApi()).getBalance(chain, address);

  // 先 await 裸 Future：baseFuture 没有任何内部监听者，若把它晾在一边先等行情，
  // 它中途失败就是一次「无人处理的异步错误」。marketsFuture 由 Riverpod 托管，
  // 挂着不动是安全的。这个顺序同时保留了原有的错误优先级——余额错误盖过行情错误。
  final base = await baseFuture;
  final markets = await marketsFuture;
  final market = markets[chain.coinGeckoId];

  return AccountBalance(
    address: address,
    amount: base.amount,
    symbol: base.symbol,
    price: market?.price ?? 0,
    logoUrl: market?.logoUrl,
  );
}, retry: _noRetry);

/// 关掉 Riverpod 3.x 的自动重试。
///
/// 默认策略是最多重试 10 次、指数退避 200ms→6.4s，一条链失败要耗掉近 40 秒才
/// 落定成 error；这期间 provider 停在「带着错误的 loading」态，`.future` 迟迟不完成——
/// 总资产会一直转圈，下拉刷新的指示器也收不起来。11 条链 × 多个钱包同时重试更是雪上加霜。
///
/// 本应用有明确的手动重试入口（下拉刷新），失败时直接把错误交出去、让对应的链显示
/// 「--」要诚实得多。这也是当初 Sui/Tron/Aptos 把异常吞成「余额 0」的根因——
/// 那是在绕开这个卡顿，代价是谎报余额；现在从源头关掉重试，才好把那些 catch 拆掉。
Duration? _noRetry(int retryCount, Object error) => null;

/// 单个钱包跨链折算后的总资产价值（当前计价法币）。按 walletId 查询。
///
/// **并发拉取**：先在同步段把每条链的 Future 全部取出来，再统一 await。
/// ref.watch 必须跑在第一个 await 之前——否则 Riverpod 3.x 的依赖登记与
/// autoDispose 都会失准；而且写成循环内 await 的话，下一条链要等上一条 resolve
/// 才开始发请求，十来条链的耗时直接变成累加。
///
/// **容错**：单链失败不拖垮整体——跳过它，用成功的链先给出总额，
/// 并把失败的链 id 带回给 UI 提示「数据不完整」。逐链的错误展示仍归
/// [balanceProvider] 自己负责（各 _ChainTile 的 .when(error:)），
/// 容错只发生在汇总这一层，不会污染下游。
///
/// **隐藏项不计入**：用户在管理代币页关掉的资产不进总额，口径与列表一致。
/// 目前只有原生币有余额来源（代币余额尚未接入，恒为 0），所以这里等价于
/// 跳过原生币被隐藏的链；代币余额接入后需在此一并过滤。
/// 被跳过的链不算「失败」，不进 failedChainIds。
final walletTotalProvider = FutureProvider.family<WalletTotal, String>((ref, walletId) async {
  final wallets = ref.watch(walletListProvider);
  Wallet? wallet;
  for (final w in wallets) {
    if (w.id == walletId) {
      wallet = w;
      break;
    }
  }
  if (wallet == null) return WalletTotal.empty;

  // 行情整体失败属于「全盘没数据」，不是「部分链失败」：此时每条链都会失败，
  // 报成 0 元 + 一句部分失败提示是误导。先在这里让它抛出去，UI 走 error 态。
  final marketsFuture = ref.watch(marketsProvider.future);

  // —— 同步段：只登记依赖、取 Future，一个 await 都不能有 —— //
  final hidden = ref.watch(hiddenAssetsProvider);
  final pending = <(String, Future<AccountBalance>)>[
    for (final chain in wallet.chainsWithAddress)
      if (!hidden.contains(ListedAsset.nativeKey(chain)))
        (chain.id, ref.watch(balanceProvider((chain.id, wallet.addressFor(chain)!)).future)),
  ];

  await marketsFuture;

  // 不能直接把原始 Future 交给 Future.wait：它虽然默认 eagerError=false，
  // 但仍会在全部完成后重新抛出第一个错误，一条链失败就整单归零。
  // 所以在进 wait 之前就把异常就地转成 null，wait 本身永远看不到错误。
  final results = await Future.wait([
    for (final (chainId, future) in pending)
      future.then<(String, AccountBalance?)>((b) => (chainId, b), onError: (_, _) => (chainId, null)),
  ]);

  return aggregateWalletTotal(results);
});

/// 把逐链结果折成总额 + 失败清单。
/// 抽成纯函数，测试不必起 ProviderContainer 就能覆盖聚合规则。
WalletTotal aggregateWalletTotal(List<(String, AccountBalance?)> results) {
  var value = 0.0;
  final failed = <String>[];
  for (final (chainId, balance) in results) {
    if (balance == null) {
      failed.add(chainId);
    } else {
      value += balance.fiatValue;
    }
  }
  return WalletTotal(value: value, failedChainIds: failed);
}
