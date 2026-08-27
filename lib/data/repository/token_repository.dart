import '../../blockchain/bundled_token_catalog.dart';
import '../../blockchain/token.dart';
import '../datasource/local/token_catalog_cache.dart';
import '../datasource/remote/token_catalog_api.dart';

/// 远程代币目录的统一入口：对上只回答「给我列表」，
/// 走缓存还是走网络、失败了怎么办，都在这里决定。
///
/// 流程对标 [MarketRepository]：
/// 1. 缓存未过期 → 直接返回
/// 2. 过期或无缓存 → 发请求
/// 3. 请求失败（空列表）→ 回退旧缓存；没有旧缓存则回退 [bundled]
/// 4. 成功 → 落盘并返回
///
/// [bundled] 不会写入缓存，以免把打包目录当成远端结果、挡住下次重试。
class TokenRepository {
  TokenRepository({required TokenCatalogApi api, required TokenCatalogCache cache, List<Token>? bundled})
    : _api = api,
      _cache = cache,
      _bundled = bundled ?? BundledTokenCatalog.all;

  final TokenCatalogApi _api;
  final TokenCatalogCache _cache;
  final List<Token> _bundled;

  /// 目录缓存有效期。代币合约列表很少变，远宽于行情的 5 分钟。
  static const ttl = Duration(hours: 24);

  Future<List<Token>> getCatalog() async {
    final (cached, cachedAt) = _cache.read();
    if (cached != null && DateTime.now().difference(cachedAt!) < ttl) {
      return cached;
    }

    final fresh = await _api.fetchCatalog();
    if (fresh.isEmpty) return cached ?? _bundled;

    await _cache.write(fresh);
    return fresh;
  }

  /// 下拉刷新专用：无视 TTL 强制重取，成功才覆盖缓存。
  /// 失败返回 false，调用方不 invalidate，界面继续用旧目录。
  Future<bool> refreshCatalog() async {
    final fresh = await _api.fetchCatalog();
    if (fresh.isEmpty) return false;
    await _cache.write(fresh);
    return true;
  }
}
