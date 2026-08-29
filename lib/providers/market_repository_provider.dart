import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/datasource/local/markets_cache.dart';
import '../data/datasource/remote/coingecko_api.dart';
import '../data/repository/market_repository.dart';
import 'prefs_provider.dart';

/// CoinGecko 数据源。单独成 provider 是为了让测试能整体替身——
/// 链图标那条链路（chainIconsProvider）直接用它，不再经过 repository。
final coinGeckoApiProvider = Provider<CoinGeckoApi>((ref) => const CoinGeckoApi());

/// 组装 [MarketRepository]：prefs 来自 [sharedPrefsProvider]，API 与 cache 在此接线。
final marketRepositoryProvider = Provider<MarketRepository>((ref) {
  return MarketRepository(
    api: ref.watch(coinGeckoApiProvider),
    marketsCache: MarketsCache(ref.watch(sharedPrefsProvider)),
  );
});
