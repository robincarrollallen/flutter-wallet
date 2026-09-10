/// 代币规格：决定余额查询 / 转账的调用方式，也决定 [Token.identifier] 的形态。
enum TokenStandard {
  /// ERC-20 代币标准 
  erc20,

  /// SPL 代币标准
  spl,

  /// TRC-20 代币标准
  trc20,

  /// SUI 代币标准
  suiCoin,

  /// APTOS 代币标准
  aptosCoin
}
