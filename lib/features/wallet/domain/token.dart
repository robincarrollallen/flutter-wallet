/// 代币规格：决定余额查询 / 转账的调用方式，也决定 [Token.identifier] 的形态。
///
/// - [erc20]：EVM 链，identifier = 0x 合约地址（调用 `balanceOf`）。
/// - [spl]：Solana，identifier = mint 地址（调用 `getTokenAccountsByOwner`）。
/// - [trc20]：Tron，identifier = T... 合约地址。
/// - [suiCoin]：Sui，identifier = coin type，如 `0x2::sui::SUI`。
/// - [aptosCoin]：Aptos，identifier = coin type，如 `0x1::aptos_coin::AptosCoin`。
enum TokenStandard { erc20, spl, trc20, suiCoin, aptosCoin }

/// 挂在某条链上的单个代币的静态配置。
///
/// 与原生币（由 Chain 自身字段承载）区别在于：代币靠 [identifier] 标识，
/// 且 [decimals] 因币而异（USDT/USDC=6，多数=18），不能复用链的 decimals。
class Token {
  const Token({
    required this.symbol,
    required this.name,
    required this.standard,
    required this.identifier,
    required this.coinGeckoId,
    required this.decimals,
    this.logoUrl,
  });

  final String symbol;
  final String name;
  final TokenStandard standard;

  /// 代币标识：EVM/Tron 为合约地址，Solana 为 mint，Sui/Aptos 为 coin type 字符串。
  final String identifier;

  /// 用于查实时美元单价（测试币按对应主网币计价）。
  final String coinGeckoId;

  /// 该代币精度（每个代币独立，勿复用链的 decimals）。
  final int decimals;

  /// 可选静态图标；为空时回退到 CoinGecko 动态图标。
  final String? logoUrl;
}
