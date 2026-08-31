import '../enums/token_standard.dart';

export '../enums/token_standard.dart';

/// 某条链上的单个代币。身份键是 (chainId, identifier)，由 TokenCatalog 合并去重。
class Token {
  const Token({
    required this.chainId,
    required this.symbol,
    required this.name,
    required this.standard,
    required this.identifier,
    required this.coinGeckoId,
    required this.decimals,
    this.logoUrl,
  });

  final String chainId; // 所属链的 [Chain.id]，目录合并与按链查询都靠它。
  final String symbol; // 代币简称(列表、余额、转账页面展示短名称)
  final String name; // 代币全称(用于更完整的展示和区分)
  final TokenStandard standard; // 代币标准/协议类型(决定怎么查余额、怎么构造转账调用)
  final String identifier; // 代币标识：EVM/Tron 为合约地址，Solana 为 mint，Sui/Aptos 为 coin type 字符串。
  final String coinGeckoId; // 用于查实时美元单价（测试币按对应主网币计价）。
  final int decimals; // 代币精度（每个代币独立，勿复用链的 decimals）。
  final String? logoUrl; // 可选静态图标；为空时回退到 CoinGecko 动态图标。

  Map<String, dynamic> toJson() => {
    'chainId': chainId,
    'symbol': symbol,
    'name': name,
    'standard': standard.name,
    'identifier': identifier,
    'coinGeckoId': coinGeckoId,
    'decimals': decimals,
    if (logoUrl != null) 'logoUrl': logoUrl,
  };

  factory Token.fromJson(Map<String, dynamic> json) {
    final t = tryFromJson(json);
    if (t == null) throw FormatException('Invalid Token JSON: $json');
    return t;
  }

  /// 字段缺失或非法时返回 null，供远程 JSON / 缓存逐条跳过脏数据。
  static Token? tryFromJson(Map<String, dynamic> json) {
    final chainId = json['chainId'];
    final symbol = json['symbol'];
    final name = json['name'];
    final identifier = json['identifier'];
    final standard = TokenStandard.values.asNameMap()[json['standard']];
    final decimals = (json['decimals'] as num?)?.toInt();
    if (chainId is! String ||
        chainId.isEmpty ||
        symbol is! String ||
        symbol.isEmpty ||
        name is! String ||
        name.isEmpty ||
        identifier is! String ||
        identifier.isEmpty ||
        standard == null ||
        decimals == null) {
      return null;
    }
    final coinGeckoId = json['coinGeckoId'];
    final logoUrl = json['logoUrl'];
    return Token(
      chainId: chainId,
      symbol: symbol,
      name: name,
      standard: standard,
      identifier: identifier,
      coinGeckoId: coinGeckoId is String ? coinGeckoId : '',
      decimals: decimals,
      logoUrl: logoUrl is String ? logoUrl : null,
    );
  }

  /// 远程目录 JSON：顶层可以是代币数组，或 `{ "tokens": [ ... ] }`。
  static List<Token> listFromJson(dynamic raw) {
    final list = switch (raw) {
      List l => l,
      Map m when m['tokens'] is List => m['tokens'] as List,
      _ => const [],
    };
    return [
      for (final item in list)
        if (item is Map) ?tryFromJson(Map<String, dynamic>.from(item)),
    ];
  }
}
