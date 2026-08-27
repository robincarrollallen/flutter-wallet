import 'chain_registry.dart';
import 'token.dart';
import 'token_catalog.dart';

/// 目录中的一条可展示资产：链上的原生币或其某个代币。
///
/// [token] 为空表示该链的原生币（符号/名称取自 [chain] 自身）。
/// 首页代币列表与接收页共用，避免两套 symbol / name 派生。
class ListedAsset {
  const ListedAsset({required this.chain, this.token});

  final Chain chain;
  final Token? token;

  /// 展示用符号：代币优先取代币符号，否则取链的原生币符号。
  String get symbol => token?.symbol ?? chain.symbol;

  /// 展示用名称：代币取代币名，原生币取链名。
  String get name => token?.name ?? chain.name;

  /// 查行情图标用的 CoinGecko id。
  String get coinGeckoId => token?.coinGeckoId ?? chain.coinGeckoId;

  /// 从 [catalog] 展开：每条链原生币 + 该链代币。[chain] 为空表示全部链。
  static List<ListedAsset> fromCatalog(TokenCatalog catalog, {Chain? chain}) => [
    for (final (c, tk) in catalog.assetsOf(chain)) ListedAsset(chain: c, token: tk),
  ];
}
