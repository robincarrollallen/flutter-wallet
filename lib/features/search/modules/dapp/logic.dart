/// Dapp Tab 的纯匹配逻辑（占位）。
///
/// 目前没有 Dapp 检索数据源，匹配恒为空；后续接入后在此实现按名称/分类匹配。
class DappSearchLogic {
  const DappSearchLogic._();

  /// 入参 [q] 为已规整关键词。暂无数据源，返回空列表。
  static List<Object> match(String q) => const [];

  /// 热门 Dapp（空词时展示）：静态占位数据，待接入后替换。
  static List<String> hotItems() =>
      const ['Uniswap', 'OpenSea', 'Aave', 'PancakeSwap', 'Lido'];
}
