import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/prefs_provider.dart';
import '../datasource/local/chain_icons_cache.dart';
import '../datasource/local/markets_cache.dart';
import '../datasource/remote/coingecko_api.dart';

/// 行情与链图标的统一入口：对上只回答「给我数据」，
/// 走缓存还是走网络、失败了怎么办，都在这里决定。
///
/// 行情与图标的取数流程完全一致，差别只有 TTL 与缓存键，
/// 因此共用 [_readThrough]——这也是引入本层的直接动机。
class MarketRepository {
  const MarketRepository({
    required CoinGeckoApi api,
    required MarketsCache marketsCache,
    required ChainIconsCache iconsCache,
  }) : _api = api,
       _marketsCache = marketsCache,
       _iconsCache = iconsCache;

  final CoinGeckoApi _api;
  final MarketsCache _marketsCache;
  final ChainIconsCache _iconsCache;

  /// 行情缓存有效期。CoinGecko 免费档约 5~15 次/分钟，超限返回 429，
  /// 因此宁可让价格滞后 5 分钟，也不要把配额耗在来回切页上。
  static const _marketsTtl = Duration(minutes: 5);

  /// 链图标缓存有效期。链 logo 基本不变，没有任何实时性要求，
  /// 给足 7 天把这次请求摊薄到可忽略——它与行情共用 CoinGecko 的限流配额。
  static const _iconsTtl = Duration(days: 7);

  /// 取行情：TTL 内直接返回落盘缓存，过期则重取，失败回退旧缓存。
  Future<Markets> getMarkets({required String currency, required Iterable<String> ids}) => _readThrough(
    read: () => _marketsCache.read(currency),
    ttl: _marketsTtl,
    fetch: () => _api.fetchMarkets(ids, vsCurrency: currency),
    write: (fresh) => _marketsCache.write(currency, fresh),
  );

  /// 取链图标：同上，只是 TTL 长得多。
  Future<ChainIcons> getChainIcons(Iterable<String> platformIds) => _readThrough(
    read: _iconsCache.read,
    ttl: _iconsTtl,
    fetch: () => _api.fetchChainIcons(platformIds),
    write: _iconsCache.write,
  );

  /// 下拉刷新专用：无视 TTL 强制重取，成功才覆盖缓存。
  ///
  /// 返回是否取到了新数据。刻意**不**在失败时清缓存——调用方据此决定要不要
  /// 刷新 UI，失败时旧价格原封不动，不会掉到 $0.00。
  Future<bool> refreshMarkets({required String currency, required Iterable<String> ids}) async {
    final fresh = await _api.fetchMarkets(ids, vsCurrency: currency);
    if (fresh.isEmpty) return false;
    await _marketsCache.write(currency, fresh);
    return true;
  }

  /// 读透缓存的统一流程，行情与图标共用：
  ///
  /// 1. 缓存未过期 → 直接返回，完全不发请求（冷启动也命中）
  /// 2. 过期或无缓存 → 发请求
  /// 3. 请求失败（数据源约定：空 map 即失败）→ 回退旧缓存，
  ///    旧价格远好过 $0.00 和首字母图标
  /// 4. 成功 → 落盘并返回
  Future<T> _readThrough<T extends Map<Object, Object?>>({
    required (T?, DateTime?) Function() read,
    required Duration ttl,
    required Future<T> Function() fetch,
    required Future<void> Function(T) write,
  }) async {
    final (cached, cachedAt) = read();
    if (cached != null && DateTime.now().difference(cachedAt!) < ttl) {
      return cached;
    }

    final fresh = await fetch();
    // 空即代表失败：退回旧缓存；没有旧缓存时 fresh 本身就是空 map，正好作为空结果。
    if (fresh.isEmpty) return cached ?? fresh;

    await write(fresh);
    return fresh;
  }
}

/// 定义 provider，供各 provider / UI 注入使用。
final marketRepositoryProvider = Provider<MarketRepository>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return MarketRepository(
    api: const CoinGeckoApi(),
    marketsCache: MarketsCache(prefs),
    iconsCache: ChainIconsCache(prefs),
  );
});
