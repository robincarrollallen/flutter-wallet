import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/wallet/domain/account_balance.dart';
import '../../features/wallet/domain/chain.dart';
import '../../features/wallet/domain/wallet.dart';
import '../../features/wallet/data/wallet_service.dart';
import '../prefs_provider.dart';
import 'wallet_provider.dart';

/// 单例 service，供各 provider 注入使用。
final walletServiceProvider = Provider<WalletService>(
  (ref) => const WalletService(),
);

/// 行情类型别名：coinGeckoId -> (美元单价, 图标 URL)。
typedef Markets = Map<String, ({double usd, String? logoUrl})>;

/// 行情缓存在 SharedPreferences 中的存储键。
const _marketsCacheKey = 'markets_cache';

/// 行情缓存有效期。CoinGecko 免费档约 5~15 次/分钟，超限返回 429，
/// 因此宁可让价格滞后 5 分钟，也不要把配额耗在来回切页上。
const _marketsTtl = Duration(minutes: 5);

/// 全部受支持链币种的实时行情：coinGeckoId -> (美元单价, 图标 URL)。
/// 一次请求覆盖所有链，避免每张卡片重复请求行情。
///
/// 三层防护，逐层兜底：
/// 1. [Ref.keepAlive] 保住内存缓存——Riverpod 3.x 默认 autoDispose，
///    不保活的话每次离开首页缓存即销毁，回来就是一次全新请求。
/// 2. 落盘缓存 + TTL：[_marketsTtl] 内直接返回磁盘数据，完全不发请求，冷启动也命中。
/// 3. 请求失败（含 429）时回退到过期的旧缓存——旧价格远好过 $0.00 和首字母图标。
final marketsProvider = FutureProvider<Markets>((ref) async {
  ref.keepAlive();
  final prefs = ref.watch(sharedPrefsProvider);

  final (cached, cachedAt) = _readCache(prefs);
  if (cached != null &&
      DateTime.now().difference(cachedAt!) < _marketsTtl) {
    return cached;
  }

  final service = ref.watch(walletServiceProvider);
  final ids = SupportedChains.all.map((c) => c.coinGeckoId);
  final fresh = await service.fetchMarkets(ids);

  // fetchMarkets 吞掉异常后返回空 map，空即代表失败：退回旧缓存，别用 $0.00 覆盖 UI。
  if (fresh.isEmpty) return cached ?? const {};

  await _writeCache(prefs, fresh);
  return fresh;
});

/// 读取落盘的行情缓存。返回 (数据, 写入时刻)；无缓存或脏数据时返回 (null, null)。
(Markets?, DateTime?) _readCache(SharedPreferences prefs) {
  final raw = prefs.getString(_marketsCacheKey);
  if (raw == null) return (null, null);
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final at = DateTime.fromMillisecondsSinceEpoch(json['at'] as int);
    final data = (json['data'] as Map<String, dynamic>).map(
      (id, v) => MapEntry(id, (
        usd: (v['usd'] as num).toDouble(),
        logoUrl: v['logoUrl'] as String?,
      )),
    );
    return (data, at);
  } catch (_) {
    // 脏数据 / 结构变更：当作没缓存过，走网络重取。
    return (null, null);
  }
}

/// 把行情连同写入时刻落盘。
Future<void> _writeCache(SharedPreferences prefs, Markets markets) {
  final json = {
    'at': DateTime.now().millisecondsSinceEpoch,
    'data': {
      for (final e in markets.entries)
        e.key: {'usd': e.value.usd, 'logoUrl': e.value.logoUrl},
    },
  };
  return prefs.setString(_marketsCacheKey, jsonEncode(json));
}

/// 下拉刷新：强制重取行情与余额。返回的 Future 完成即代表刷新结束，
/// 直接交给 RefreshIndicator.onRefresh 驱动指示器的转动与收起。
///
/// 刻意不走「先删缓存、再 invalidate」那条路：那样一旦请求失败，
/// 兜底用的旧缓存已经被删掉，页面会直接掉到 $0.00。
/// 这里改为先把新数据拿到手，成功才覆盖缓存——失败时旧缓存原封不动，维持旧价格。
Future<void> refreshHomeData(WidgetRef ref, {String? walletId}) async {
  final ids = SupportedChains.all.map((c) => c.coinGeckoId);
  final fresh = await ref.read(walletServiceProvider).fetchMarkets(ids);

  // 空即代表失败（fetchMarkets 吞异常后返回空 map）：跳过写盘与 invalidate，
  // marketsProvider 保持原值，UI 上的价格不动。
  if (fresh.isNotEmpty) {
    await _writeCache(ref.read(sharedPrefsProvider), fresh);
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
final balanceProvider = FutureProvider.family<AccountBalance, (String, String)>(
  (ref, key) async {
    final (chainId, address) = key;
    final chain = SupportedChains.byId(chainId);
    final service = ref.watch(walletServiceProvider);

    final base = await service.fetchBalance(chain, address);
    final markets = await ref.watch(marketsProvider.future);
    final market = markets[chain.coinGeckoId];

    return AccountBalance(
      address: address,
      amount: base.amount,
      symbol: base.symbol,
      priceUsd: market?.usd ?? 0,
      logoUrl: market?.logoUrl,
    );
  },
);

/// 单个钱包跨链折算后的总资产价值（美元）。按 walletId 查询。
final walletTotalProvider = FutureProvider.family<double, String>((
  ref,
  walletId,
) async {
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
    final balance = await ref.watch(
      balanceProvider((chain.id, address)).future,
    );
    total += balance.fiatValue;
  }
  return total;
});

/// 全部钱包 × 全部链折算后的总资产价值（美元）。
/// 任一钱包、链余额或行情变化都会自动重算。
final portfolioTotalProvider = FutureProvider<double>((ref) async {
  final wallets = ref.watch(walletListProvider);
  var total = 0.0;
  for (final w in wallets) {
    for (final chain in SupportedChains.all) {
      final address = w.addressFor(chain);
      if (address == null) continue;
      final balance = await ref.watch(
        balanceProvider((chain.id, address)).future,
      );
      total += balance.fiatValue;
    }
  }
  return total;
});
