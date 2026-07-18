/// 合约 Tab 的纯匹配逻辑（占位）。
///
/// 目前没有合约检索数据源，匹配恒为空；后续接入后在此实现按合约名/地址匹配。
class ContractSearchLogic {
  const ContractSearchLogic._();

  /// 入参 [q] 为已规整关键词。暂无数据源，返回空列表。
  static List<Object> match(String q) => const [];

  /// 热门合约（空词时展示）：静态占位数据，待接入后替换。
  static List<String> hotItems() =>
      const ['USDT', 'USDC', 'WETH', 'DAI', 'UNI'];
}
