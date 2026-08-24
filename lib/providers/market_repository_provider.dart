import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/datasource/local/chain_icons_cache.dart';
import '../data/datasource/local/markets_cache.dart';
import '../data/datasource/remote/coingecko_api.dart';
import '../data/repository/market_repository.dart';
import 'prefs_provider.dart';

/// 组装 [MarketRepository]：prefs 来自 [sharedPrefsProvider]，API 与两份 cache 在此接线。
final marketRepositoryProvider = Provider<MarketRepository>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return MarketRepository(
    api: const CoinGeckoApi(),
    marketsCache: MarketsCache(prefs),
    iconsCache: ChainIconsCache(prefs),
  );
});
