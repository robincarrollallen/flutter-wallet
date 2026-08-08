import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../blockchain/chain_registry.dart';
import '../../data/datasource/remote/coingecko_api.dart' show Markets;
import '../../data/repository/balance_repository.dart';
import '../../data/repository/market_repository.dart';
import '../../domain/account_balance.dart';
import '../../domain/wallet.dart';
import '../../services/evm_transaction_service.dart';
import 'currency_provider.dart';
import 'wallet_provider.dart';

export '../../data/datasource/remote/coingecko_api.dart' show Markets;

/// chainId -> EVM 原生转账的预估费用上限（wei）。
/// autoDispose：仅发送流程使用，进确认页才查、离开即弃，不常驻缓存。
final evmFeeProvider = FutureProvider.autoDispose.family<BigInt, String>(
  (ref, chainId) => const EvmTransactionService().estimateNativeFee(SupportedChains.byId(chainId)),
);

/// 全部受支持链币种与代币的 coinGeckoId 集合，行情按这份清单一次取全。
Iterable<String> _allCoinGeckoIds() => {
  ...SupportedChains.all.map((c) => c.coinGeckoId),
  ...SupportedChains.allTokens.map((e) => e.$2.coinGeckoId),
};

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
  return ref.watch(marketRepositoryProvider).getMarkets(currency: currency, ids: _allCoinGeckoIds());
});

/// 下拉刷新：强制重取行情与余额。返回的 Future 完成即代表刷新结束，
/// 直接交给 RefreshIndicator.onRefresh 驱动指示器的转动与收起。
///
/// 刻意不走「先删缓存、再 invalidate」那条路：那样一旦请求失败，
/// 兜底用的旧缓存已经被删掉，页面会直接掉到 $0.00。
/// 这里改为先把新数据拿到手，成功才覆盖缓存——失败时旧缓存原封不动，维持旧价格。
Future<void> refreshHomeData(WidgetRef ref, {String? walletId}) async {
  final currency = ref.read(currencyProvider);
  final updated = await ref.read(marketRepositoryProvider).refreshMarkets(currency: currency, ids: _allCoinGeckoIds());

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
final balanceProvider = FutureProvider.family<AccountBalance, (String, String)>((ref, key) async {
  final (chainId, address) = key;
  final chain = SupportedChains.byId(chainId);

  final base = await ref.watch(balanceRepositoryProvider).getBalance(chain, address);
  final markets = await ref.watch(marketsProvider.future);
  final market = markets[chain.coinGeckoId];

  return AccountBalance(
    address: address,
    amount: base.amount,
    symbol: base.symbol,
    price: market?.price ?? 0,
    logoUrl: market?.logoUrl,
  );
});

/// 单个钱包跨链折算后的总资产价值（当前计价法币）。按 walletId 查询。
final walletTotalProvider = FutureProvider.family<double, String>((ref, walletId) async {
  final wallets = ref.watch(walletListProvider);
  Wallet? wallet;
  for (final w in wallets) {
    if (w.id == walletId) {
      wallet = w;
      break;
    }
  }
  if (wallet == null) return 0;
  var total = 0.0;
  for (final chain in SupportedChains.all) {
    final address = wallet.addressFor(chain);
    if (address == null) continue;
    final balance = await ref.watch(balanceProvider((chain.id, address)).future);
    total += balance.fiatValue;
  }
  return total;
});

/// 全部钱包 × 全部链折算后的总资产价值（当前计价法币）。
/// 任一钱包、链余额或行情变化都会自动重算。
final portfolioTotalProvider = FutureProvider<double>((ref) async {
  final wallets = ref.watch(walletListProvider);
  var total = 0.0;
  for (final w in wallets) {
    for (final chain in SupportedChains.all) {
      final address = w.addressFor(chain);
      if (address == null) continue;
      final balance = await ref.watch(balanceProvider((chain.id, address)).future);
      total += balance.fiatValue;
    }
  }
  return total;
});
