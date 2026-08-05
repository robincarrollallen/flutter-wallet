import 'package:wallet/core/blockchain/chain_registry.dart';
import 'package:wallet/core/blockchain/token.dart';

/// 一个可接收的资产条目：链上的原生币或其某个代币。
///
/// [token] 为空表示该链的原生币（符号/名称取自 [chain] 自身）。
class ReceiveAsset {
  const ReceiveAsset({required this.chain, this.token});

  final Chain chain;
  final Token? token;

  /// 展示用符号：代币优先取代币符号，否则取链的原生币符号。
  String get symbol => token?.symbol ?? chain.symbol;

  /// 展示用名称：代币取代币名，原生币取链名。
  String get name => token?.name ?? chain.name;

  /// 查行情图标用的 CoinGecko id。
  String get coinGeckoId => token?.coinGeckoId ?? chain.coinGeckoId;
}
