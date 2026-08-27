import '../../../blockchain/chain_registry.dart';
import '../../../blockchain/listed_asset.dart';
import '../../../blockchain/token_catalog.dart';

/// 接收弹窗的纯逻辑：构建与过滤可接收资产列表，不依赖 UI/状态框架。
class ReceiveLogic {
  const ReceiveLogic._();

  /// 顶部 Tab 顺序即首页链顺序。
  static List<Chain> get chains => SupportedChains.all;

  /// 指定链的可接收资产（原生币 + 该链代币）；[chain] 为空表示全部链。
  /// 代币来自 [catalog]。
  static List<ListedAsset> assetsOf(Chain? chain, TokenCatalog catalog) =>
      ListedAsset.fromCatalog(catalog, chain: chain);

  /// 按关键词过滤（匹配符号 / 名称 / 链名，忽略大小写）。
  static List<ListedAsset> filter(List<ListedAsset> assets, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return assets;
    return assets.where((a) {
      return a.symbol.toLowerCase().contains(q) ||
          a.name.toLowerCase().contains(q) ||
          a.chain.name.toLowerCase().contains(q);
    }).toList();
  }
}
