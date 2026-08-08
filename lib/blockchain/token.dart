import '../enums/token_standard.dart';

export '../enums/token_standard.dart';

/// 挂在某条链上的单个代币的静态配置。
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

  final String symbol; // 代币简称(列表、余额、转账页面展示短名称)
  final String name; // 代币全称(用于更完整的展示和区分)
  final TokenStandard standard; // 代币标准/协议类型(决定怎么查余额、怎么构造转账调用)
  final String identifier; // 代币标识：EVM/Tron 为合约地址，Solana 为 mint，Sui/Aptos 为 coin type 字符串。
  final String coinGeckoId; // 用于查实时美元单价（测试币按对应主网币计价）。
  final int decimals; // 代币精度（每个代币独立，勿复用链的 decimals）。
  final String? logoUrl; // 可选静态图标；为空时回退到 CoinGecko 动态图标。
}
