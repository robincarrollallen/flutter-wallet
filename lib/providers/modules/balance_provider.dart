import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../blockchain/chain_registry.dart';
import '../../blockchain/token.dart';
import '../../blockchain/token_catalog.dart';
import '../../data/datasource/remote/chain_balance_api.dart';
import '../../data/repository/balance_repository.dart';
import '../../domain/account_balance.dart';
import '../../domain/wallet.dart';
import '../../domain/wallet_total.dart';
import '../token_catalog_provider.dart';
import 'markets_provider.dart';
import 'wallet_provider.dart';

export 'markets_provider.dart';

/// 下拉刷新：强制重取行情与余额。返回的 Future 完成即代表刷新结束，
/// 直接交给 RefreshIndicator.onRefresh 驱动指示器的转动与收起。
///
/// 刻意不走「先删缓存、再 invalidate」那条路：那样一旦请求失败，
/// 兜底用的旧缓存已经被删掉，页面会直接掉到 $0.00。
/// [RemoteTokensNotifier.refresh] 与 [MarketsNotifier.refresh] 都是先把新数据拿到手、
/// 成功才覆盖——失败时旧目录与旧价格原封不动，也不必再 invalidate：
/// 拿到新数据它们会直接改 state，watcher 自动重建。
Future<void> refreshHomeData(WidgetRef ref, {String? walletId}) async {
  await ref.read(remoteTokensProvider.notifier).refresh();

  await ref.read(marketsProvider.notifier).refresh();

  // 余额没有 TTL，每次下拉都重查。整个 family 一起 invalidate，
  // 依赖它的 walletTotalProvider 会级联重算。
  // 代币余额来自另一个聚合 family，balanceProvider 只是读它，不会连带失效，要单独点名。
  ref.invalidate(chainTokenBalancesProvider);
  ref.invalidate(balanceProvider);

  // 等首页真正要显示的总资产算完，指示器才收起，避免转完了数字还在跳。
  if (walletId != null) {
    await ref.read(walletTotalProvider(walletId).future);
  }
}

/// 某条链上某地址持有的**全部代币**余额，键为 [TokenCatalog.identityKey]。
///
/// 为什么按链聚合而不是一个代币一个 provider：代币余额是逐个合约 `balanceOf`，
/// 一条链上十几个代币各发一次就是十几次握手，六条 EVM 链同时刷首页会明显卡顿。
/// 这里合成一次批量 JSON-RPC，[balanceProvider] 再从结果里取自己那份——
/// UI 仍是逐资产的独立 AsyncValue，请求却只有一个。
///
/// 取的是完整目录而非 [visibleAssetsProvider]：隐藏项只是不进列表和总额，
/// 若哪天有页面要看隐藏代币的余额，不该因为它被隐藏就查不到；反正合并进同一批
/// 请求，多带几个代币不多一次往返。未接入的代币标准在此就地滤掉——
/// 混进去会让整批抛 [UnimplementedError]，把同链已支持的代币一起拖下水。
final chainTokenBalancesProvider = FutureProvider.family<Map<String, AccountBalance>, (String, String)>((
  ref,
  key,
) async {
  final (chainId, address) = key;
  final chain = SupportedChains.byId(chainId);
  final tokens = [
    for (final token in ref.watch(tokenCatalogProvider).tokensOf(chainId))
      if (ChainBalanceApi.supportsTokenBalance(chain, token.standard)) token,
  ];
  if (tokens.isEmpty) return const {};
  return const BalanceRepository(ChainBalanceApi()).getTokenBalances(chain, tokens, address);
}, retry: _noRetry);

/// 按 (chainId, address, tokenIdentifier) 查询单个资产的余额，并附带实时单价。
/// [tokenIdentifier] 为 null 表示该链原生币。AsyncValue 自动提供 loading / error / data 三态。
///
/// 键做成资产维度而不是链维度，是为了让原生币与代币共用同一条读取路径：
/// UI 只认 [ListedAsset]，不必在每个调用点分「这是币还是代币」。
///
/// 同步段写法（与 [walletTotalProvider] 一致）：ref.watch 必须跑在第一个 await
/// 之前，否则余额一失败就登记不上对 [marketsProvider] 的依赖，行情刷新时这条链
/// 不会重算。顺带让余额与行情两个请求并发，首屏不必串行等两个往返。
final balanceProvider = FutureProvider.family<AccountBalance, (String, String, String?)>((ref, key) async {
  final (chainId, address, tokenIdentifier) = key;
  final chain = SupportedChains.byId(chainId);
  final token = tokenIdentifier == null ? null : _findToken(ref, chainId, tokenIdentifier);

  /// 同步并发执行(异步调用方法不立即 await)
  //
  // 行情现在是同步 Notifier：有缓存的话这一行就已经拿到价格，一个往返都不用等。
  // 只有「一份缓存都没有」的冷启动才退回 await——见 [MarketsNotifier.ready]。
  final markets = ref.watch(marketsProvider).markets;
  final marketsFuture = markets.isNotEmpty ? null : (ref.read(marketsProvider.notifier).ready..ignore());
  final baseFuture = token == null
      ? const BalanceRepository(ChainBalanceApi()).getBalance(chain, address)
      : _tokenBalance(ref, chain, token, address);

  // 先 await 裸 Future：两个 Future 谁都没有内部监听者，晾在一边先等对方时，
  // 中途失败就是一次「无人处理的异步错误」——ready 上的 ignore() 正是为此，
  // 它只消掉这个报告，await 时该抛还是会抛。
  // 这个顺序保留了原有的错误优先级——余额错误盖过行情错误。
  final base = await baseFuture;
  final market = (marketsFuture == null ? markets : await marketsFuture)[token?.coinGeckoId ?? chain.coinGeckoId];

  return AccountBalance(
    address: address,
    amount: base.amount,
    symbol: base.symbol,
    price: market?.price ?? 0,
    logoUrl: market?.logoUrl,
  );
}, retry: _noRetry);

/// 从目录里按 identifier 找回代币。目录里没有（自定义代币刚被删除等）就当原生币处理，
/// 由调用方的 chain 兜底——总好过抛一个用户看不懂的错。
Token? _findToken(Ref ref, String chainId, String identifier) {
  final normalized = identifier.toLowerCase();
  for (final token in ref.watch(tokenCatalogProvider).tokensOf(chainId)) {
    if (token.identifier == identifier || token.identifier.toLowerCase() == normalized) return token;
  }
  return null;
}

/// 单个代币余额：从本链的批量结果里取。
///
/// 未接入的标准不在批量结果里（[chainTokenBalancesProvider] 已滤掉），
/// 落到 `?? 零余额` 这条路，按 0 展示——与接入前的行为一致。
/// 已支持的标准若地址真的没持仓，`balanceOf` 返回的也是 0，同样走这里，语义无歧义。
Future<AccountBalance> _tokenBalance(Ref ref, Chain chain, Token token, String address) async {
  final balances = await ref.watch(chainTokenBalancesProvider((chain.id, address)).future);
  return balances[TokenCatalog.identityKey(token)] ??
      AccountBalance(address: address, amount: '0', symbol: token.symbol);
}

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
/// 直接遍历 [visibleAssetsProvider]——它已经按 [hiddenAssetsProvider] 过滤过，
/// 这里不必再判一遍；原生币与代币在这一层没有区别，都是一条 [ListedAsset]。
/// 被跳过的资产不算「失败」，不进 failedChainIds。
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
  // 报成 0 元 + 一句部分失败提示是误导。有旧价格就直接往下走，一份都没有才等这次请求，
  // 失败则由 ready 抛 MarketsUnavailable，UI 走 error 态。
  final markets = ref.watch(marketsProvider).markets;
  final marketsFuture = markets.isNotEmpty ? null : (ref.read(marketsProvider.notifier).ready..ignore());

  // —— 同步段：只登记依赖、取 Future，一个 await 都不能有 —— //
  // 无地址的链（该钱包未派生出地址）整条跳过：查不了也不算失败。
  final pending = <(String, Future<AccountBalance>)>[
    for (final asset in ref.watch(visibleAssetsProvider(null)))
      if (wallet.addressFor(asset.chain) case final address?)
        (asset.chain.id, ref.watch(balanceProvider((asset.chain.id, address, asset.token?.identifier)).future)),
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

/// 把逐资产结果折成总额 + 失败清单。
/// 抽成纯函数，测试不必起 ProviderContainer 就能覆盖聚合规则。
///
/// 失败清单仍按**链**去重：一条链上多个代币一起失败通常是同一次 RPC 故障，
/// 逐个列出来只会把提示语堆成一长串重复的链名。
WalletTotal aggregateWalletTotal(List<(String, AccountBalance?)> results) {
  var value = 0.0;
  final failed = <String>{};
  for (final (chainId, balance) in results) {
    if (balance == null) {
      failed.add(chainId);
    } else {
      value += balance.fiatValue;
    }
  }
  return WalletTotal(value: value, failedChainIds: failed.toList(growable: false));
}
