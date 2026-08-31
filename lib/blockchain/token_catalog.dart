import 'chain_registry.dart';
import 'token.dart';

/// 当前可展示的代币目录：按 [SupportedChains.all] 的链顺序，每条链 = 原生币 + 该链代币。
///
/// 数据从哪来（远程 / 自定义 / 以后链上发现）由 [merge] 决定；查询方只读这一份。
class TokenCatalog {
  const TokenCatalog({required this.chains, required Map<String, List<Token>> tokensByChain})
    : _tokensByChain = tokensByChain;

  /// 目录覆盖的链，顺序与合并时传入的 [chains] 一致。
  final List<Chain> chains;
  final Map<String, List<Token>> _tokensByChain;

  /// 指定链上的代币（不含原生币）。未知 [chainId] 返回空列表。
  List<Token> tokensOf(String chainId) => _tokensByChain[chainId] ?? const [];

  /// 全部 (链, 代币) 对，按链顺序展开。不含原生币。
  Iterable<(Chain, Token)> get tokens => [
    for (final c in chains)
      for (final tk in tokensOf(c.id)) (c, tk),
  ];

  /// 全部可展示资产：每条链先原生币（[Token] 为 null），再跟该链代币。
  List<(Chain, Token?)> get allAssets => [
    for (final c in chains) ...[(c, null), for (final tk in tokensOf(c.id)) (c, tk)],
  ];

  /// [chain] 为空时等同 [allAssets]，否则只返回该链的原生币 + 代币。
  List<(Chain, Token?)> assetsOf(Chain? chain) {
    if (chain == null) return allAssets;
    return [(chain, null), for (final tk in tokensOf(chain.id)) (chain, tk)];
  }

  /// 行情批量拉取用：原生币 id ∪ 目录中全部代币 id（去重，插入序）。
  /// 自定义代币可以没有 CoinGecko id，空字符串不进这份清单。
  Iterable<String> get coinGeckoIds => {
    for (final c in chains) c.coinGeckoId,
    for (final tk in tokens)
      if (tk.$2.coinGeckoId.isNotEmpty) tk.$2.coinGeckoId,
  };

  /// 给 Riverpod `select` 用：内容相同则字符串相等，避免目录对象重建触发行情重拉。
  String get coinGeckoIdsKey => coinGeckoIds.join(',');

  /// 合并远程目录与自定义代币。
  ///
  /// - 身份键：`(chainId, 规范化 identifier)`。ERC-20 / TRC-20 地址忽略大小写。
  /// - 只保留 [chains] 里有的链；未知 `chainId` 直接丢弃。
  /// - 同键时 [custom] 覆盖 [remote]，且留在 remote 原来的位置。
  /// - 自定义独有的代币追加到该链代币列表末尾。
  factory TokenCatalog.merge({
    required List<Chain> chains,
    required List<Token> remote,
    List<Token> custom = const [],
  }) {
    final chainIds = {for (final c in chains) c.id};
    final byChain = <String, Map<String, Token>>{for (final c in chains) c.id: <String, Token>{}};

    void putAll(List<Token> source) {
      for (final t in source) {
        if (!chainIds.contains(t.chainId)) continue;
        byChain[t.chainId]![_normalizedIdentifier(t)] = t;
      }
    }

    putAll(remote);
    putAll(custom);

    return TokenCatalog(
      chains: chains,
      tokensByChain: {for (final c in chains) c.id: byChain[c.id]!.values.toList(growable: false)},
    );
  }

  /// 扁平列表去重用：`chainId` + 规范化 identifier。
  static String identityKey(Token t) => '${t.chainId}::${_normalizedIdentifier(t)}';

  /// ERC-20 / TRC-20 合约地址大小写不敏感；其余标准保持原样（Solana mint 区分大小写）。
  static String _normalizedIdentifier(Token t) => switch (t.standard) {
    TokenStandard.erc20 || TokenStandard.trc20 => t.identifier.toLowerCase(),
    _ => t.identifier,
  };
}
