import '../../../../blockchain/chain_registry.dart';

/// 一个可发送的资产条目：目前仅支持各链原生币（代币发送尚未接入）。
class SendAsset {
  const SendAsset({required this.chain});

  final Chain chain;

  /// 展示用符号：链的原生币符号。
  String get symbol => chain.symbol;

  /// 展示用名称：链名。
  String get name => chain.name;

  /// 查行情图标用的 CoinGecko id。
  String get coinGeckoId => chain.coinGeckoId;
}
