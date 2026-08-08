import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../blockchain/chain_registry.dart';
import '../../data/datasource/remote/coingecko_api.dart' show ChainIcons;
import '../../data/repository/market_repository.dart';

export '../../data/datasource/remote/coingecko_api.dart' show ChainIcons;

/// 各链自己的图标：平台 id -> 图标 URL。
///
/// 与 [marketsProvider] 同样由 [MarketRepository] 承担落盘 TTL 与失败回退，
/// 只是 TTL 长得多。刻意不参与下拉刷新：图标不是行情，没有刷新的必要。
final chainIconsProvider = FutureProvider<ChainIcons>((ref) async {
  ref.keepAlive();

  // 只取配置里实际用到的平台，其余 400 多个不进缓存。
  final ids = SupportedChains.all.map((c) => c.coinGeckoPlatformId).whereType<String>();

  return ref.watch(marketRepositoryProvider).getChainIcons(ids);
});
