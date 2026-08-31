import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/datasource/remote/coingecko_api.dart';

/// CoinGecko 数据源。单独成 provider 是为了让测试能整体替身——
/// 行情（[marketsProvider]）与链图标（[chainIconsProvider]）都直接用它：
/// 两条链路各自的落盘缓存、TTL 与失败回退都由对应的 PersistentNotifier 承担，
/// 中间不再有 repository 层。
final coinGeckoApiProvider = Provider<CoinGeckoApi>((ref) => const CoinGeckoApi());
