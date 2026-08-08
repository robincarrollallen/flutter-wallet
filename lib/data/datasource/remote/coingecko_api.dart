import 'package:flutter/foundation.dart';

import '../../../constants/currency_symbols.dart';
import 'rest_client.dart';

/// 行情类型别名：coinGeckoId -> (当前计价币种下的单价, 图标 URL)。
typedef Markets = Map<String, ({double price, String? logoUrl})>;

/// 链图标类型别名：CoinGecko 平台 id -> 图标 URL。
typedef ChainIcons = Map<String, String>;

/// CoinGecko 远程数据源：只负责发请求与解析响应，不做缓存、不做回退决策。
///
/// **失败约定**：两个方法都吞掉异常并返回空 map，由上层 repository 据此回退旧缓存。
/// 这个约定是 repository 缓存逻辑的前提，改动前先确认调用方。
class CoinGeckoApi {
  const CoinGeckoApi();

  static const _base = 'https://api.coingecko.com/api/v3';

  /// 批量查询多个 CoinGecko 币种的行情：coinGeckoId -> (单价, 图标 URL)。
  /// 一次 coins/markets 请求同时取回价格与图标，替代旧的 simple/price。
  ///
  /// [vsCurrency] 为计价法币代码（大小写不限，如 'USD' / 'CNY'），
  /// 由接口原生按该币种返回价格，不做本地汇率换算；
  /// 传入接口不支持的币种会拿到空数组，等同一次失败。
  Future<Markets> fetchMarkets(Iterable<String> coinGeckoIds, {String vsCurrency = defaultCurrencyCode}) async {
    final ids = coinGeckoIds.toSet().join(',');
    final uri = Uri.parse(
      '$_base/coins/markets'
      '?vs_currency=${vsCurrency.toLowerCase()}&ids=$ids',
    );
    try {
      final list = await getJsonArray(uri);
      return {
        for (final item in list.whereType<Map>())
          item['id'] as String: (
            price: (item['current_price'] as num?)?.toDouble() ?? 0,
            logoUrl: item['image'] as String?,
          ),
      };
    } catch (e) {
      // 上层只能从空 map 得知「失败了」，得不到原因（限流 429 / 证书 / 解析错误），
      // 这行是唯一的线索来源。
      debugPrint('⚠️ fetchMarkets failed: $e');
      return const {};
    }
  }

  /// 拉取指定链平台的图标：platformId -> 图标 URL。
  ///
  /// 与 [fetchMarkets] 的币图标不同：Base / Arbitrum 这类链虽然都按 ETH 计价，
  /// 在这里各有自己的 logo，地址列表才能把它们区分开。
  ///
  /// 该接口不支持按 id 过滤，461 个平台的整包响应（约 184 KB）省不掉；
  /// [platformIds] 只用于裁剪返回值，免得 400 多个用不上的平台一路带进缓存、
  /// 拖累每次冷启动的 SharedPreferences 读取。
  /// 返回空 map 即代表失败，交由上层回退旧缓存（与 [fetchMarkets] 约定一致）。
  Future<ChainIcons> fetchChainIcons(Iterable<String> platformIds) async {
    final wanted = platformIds.toSet();
    final uri = Uri.parse('$_base/asset_platforms');
    try {
      final list = await getJsonArray(uri);
      return {
        for (final item in list.whereType<Map>())
          if (item['id'] is String && wanted.contains(item['id']))
            if (item['image'] is Map && (item['image'] as Map)['large'] is String)
              item['id'] as String: (item['image'] as Map)['large'] as String,
      };
    } catch (e) {
      debugPrint('⚠️ fetchChainIcons failed: $e');
      return const {};
    }
  }
}
