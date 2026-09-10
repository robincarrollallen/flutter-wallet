/// 链的类型，决定余额查询方式与地址派生曲线。
enum ChainKind {
  /// EVM 系
  evm,

  /// 比特币
  bitcoin,
  
  /// 索拉纳
  solana,

  /// 波场
  tron,

  /// Sui
  sui,
  
  /// Aptos
  aptos
}
