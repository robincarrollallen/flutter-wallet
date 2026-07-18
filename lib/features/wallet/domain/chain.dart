import 'package:blockchain_utils/blockchain_utils.dart';

import 'token.dart';

/// 链的类型，决定余额查询方式与地址派生曲线。
enum ChainKind { evm, bitcoin, solana, tron, sui, aptos }

/// 一条受支持链的静态配置。
///
/// - [coin]：BIP44 派生用的币种（同一助记词据此派生各链地址）。
///   所有 EVM 链共用 [Bip44Coins.ethereum]（同一个 0x 地址）。
/// - [endpoint]：EVM/Solana 为 JSON-RPC 地址；Bitcoin 为区块浏览器 API 根地址。
/// - [coinGeckoId]：用于查实时美元单价（测试币按对应主网币计价）。
/// - [coinGeckoPlatformId]：用于查链图标（测试网映射到对应主网平台）。
class Chain {
  const Chain({
    required this.id,
    required this.name,
    required this.symbol,
    required this.kind,
    required this.coin,
    required this.endpoint,
    required this.coinGeckoId,
    required this.decimals,
    this.coinGeckoPlatformId,
    this.tokens = const [],
  });

  final String id;
  final String name;
  final String symbol;
  final ChainKind kind;
  final Bip44Coins coin;
  final String endpoint;
  final String coinGeckoId;
  final int decimals;

  /// CoinGecko asset_platforms 的平台 id，用于取该链自己的图标——
  /// 这是 Base / Arbitrum 这类共用 ETH 计价的链能显示各自 logo 的关键。
  /// 为空表示该链不是 CoinGecko 的资产平台（如 Bitcoin），此时降级用币图标。
  final String? coinGeckoPlatformId;

  /// 该链上受支持的代币（默认空 = 仅原生币）。
  final List<Token> tokens;
}

/// 全部受支持链（均为测试网）。
class SupportedChains {
  const SupportedChains._();

  static const ethereumSepolia = Chain(
    id: 'ethereum-sepolia',
    name: 'Ethereum Sepolia',
    symbol: 'ETH',
    kind: ChainKind.evm,
    coin: Bip44Coins.ethereum,
    endpoint: 'https://ethereum-sepolia-rpc.publicnode.com',
    coinGeckoId: 'ethereum',
    decimals: 18,
    coinGeckoPlatformId: 'ethereum',
    tokens: [
      Token(
        symbol: 'USDC',
        name: 'USD Coin',
        standard: TokenStandard.erc20,
        identifier: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
        coinGeckoId: 'usd-coin',
        decimals: 6,
      ),
    ],
  );

  static const polygonAmoy = Chain(
    id: 'polygon-amoy',
    name: 'Polygon Amoy',
    symbol: 'POL',
    kind: ChainKind.evm,
    coin: Bip44Coins.ethereum,
    endpoint: 'https://polygon-amoy-bor-rpc.publicnode.com',
    coinGeckoId: 'matic-network',
    decimals: 18,
    coinGeckoPlatformId: 'polygon-pos',
    tokens: [
      Token(
        symbol: 'USDC',
        name: 'USD Coin',
        standard: TokenStandard.erc20,
        identifier: '0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582',
        coinGeckoId: 'usd-coin',
        decimals: 6,
      ),
    ],
  );

  static const bscTestnet = Chain(
    id: 'bsc-testnet',
    name: 'BSC Testnet',
    symbol: 'BNB',
    kind: ChainKind.evm,
    coin: Bip44Coins.ethereum,
    endpoint: 'https://bsc-testnet-rpc.publicnode.com',
    coinGeckoId: 'binancecoin',
    decimals: 18,
    coinGeckoPlatformId: 'binance-smart-chain',
  );

  static const baseSepolia = Chain(
    id: 'base-sepolia',
    name: 'Base Sepolia',
    symbol: 'ETH',
    kind: ChainKind.evm,
    coin: Bip44Coins.ethereum,
    endpoint: 'https://base-sepolia-rpc.publicnode.com',
    coinGeckoId: 'ethereum',
    decimals: 18,
    coinGeckoPlatformId: 'base',
    tokens: [
      Token(
        symbol: 'USDC',
        name: 'USD Coin',
        standard: TokenStandard.erc20,
        identifier: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
        coinGeckoId: 'usd-coin',
        decimals: 6,
      ),
    ],
  );

  static const arbitrumSepolia = Chain(
    id: 'arbitrum-sepolia',
    name: 'Arbitrum Sepolia',
    symbol: 'ETH',
    kind: ChainKind.evm,
    coin: Bip44Coins.ethereum,
    endpoint: 'https://arbitrum-sepolia-rpc.publicnode.com',
    coinGeckoId: 'ethereum',
    decimals: 18,
    coinGeckoPlatformId: 'arbitrum-one',
    tokens: [
      Token(
        symbol: 'USDC',
        name: 'USD Coin',
        standard: TokenStandard.erc20,
        identifier: '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d',
        coinGeckoId: 'usd-coin',
        decimals: 6,
      ),
    ],
  );

  static const plasmaTestnet = Chain(
    id: 'plasma-testnet',
    name: 'Plasma Testnet',
    symbol: 'XPL',
    kind: ChainKind.evm,
    coin: Bip44Coins.ethereum,
    endpoint: 'https://testnet-rpc.plasma.to',
    coinGeckoId: 'plasma',
    decimals: 18,
    coinGeckoPlatformId: 'plasma',
  );

  static const bitcoinTestnet = Chain(
    id: 'bitcoin-testnet',
    name: 'Bitcoin Testnet',
    symbol: 'BTC',
    kind: ChainKind.bitcoin,
    coin: Bip44Coins.bitcoinTestnet,
    endpoint: 'https://blockstream.info/testnet/api',
    coinGeckoId: 'bitcoin',
    decimals: 8,
  );

  static const solanaDevnet = Chain(
    id: 'solana-devnet',
    name: 'Solana Devnet',
    symbol: 'SOL',
    kind: ChainKind.solana,
    coin: Bip44Coins.solana,
    endpoint: 'https://api.devnet.solana.com',
    coinGeckoId: 'solana',
    decimals: 9,
    coinGeckoPlatformId: 'solana',
    tokens: [
      Token(
        symbol: 'USDC',
        name: 'USD Coin',
        standard: TokenStandard.spl,
        identifier: '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
        coinGeckoId: 'usd-coin',
        decimals: 6,
      ),
    ],
  );

  // —— 以下三条非 EVM 链的原生币余额查询已接入（Tron/Sui/Aptos）；代币查询暂未接入。 ——

  static const tronShasta = Chain(
    id: 'tron-shasta',
    name: 'Tron Shasta',
    symbol: 'TRX',
    kind: ChainKind.tron,
    coin: Bip44Coins.tron,
    endpoint: 'https://api.shasta.trongrid.io',
    coinGeckoId: 'tron',
    decimals: 6,
    coinGeckoPlatformId: 'tron',
  );

  static const suiTestnet = Chain(
    id: 'sui-testnet',
    name: 'Sui Testnet',
    symbol: 'SUI',
    kind: ChainKind.sui,
    coin: Bip44Coins.sui,
    endpoint: 'https://sui-testnet-rpc.publicnode.com',
    coinGeckoId: 'sui',
    decimals: 9,
    coinGeckoPlatformId: 'sui',
    tokens: [
      Token(
        symbol: 'USDC',
        name: 'USD Coin',
        standard: TokenStandard.suiCoin,
        identifier:
            '0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC',
        coinGeckoId: 'usd-coin',
        decimals: 6,
      ),
    ],
  );

  static const aptosTestnet = Chain(
    id: 'aptos-testnet',
    name: 'Aptos Testnet',
    symbol: 'APT',
    kind: ChainKind.aptos,
    coin: Bip44Coins.aptos,
    endpoint: 'https://fullnode.testnet.aptoslabs.com',
    coinGeckoId: 'aptos',
    decimals: 8,
    coinGeckoPlatformId: 'aptos',
    tokens: [
      Token(
        symbol: 'USDC',
        name: 'USD Coin',
        standard: TokenStandard.aptosCoin,
        identifier:
            '0x69091fbab5f7d635ee7ac5098cf0c1efbe31d68fec0f2cd565e8d168daf52832',
        coinGeckoId: 'usd-coin',
        decimals: 6,
      ),
    ],
  );

  /// 首页展示顺序。
  static const List<Chain> all = [
    ethereumSepolia,
    polygonAmoy,
    bscTestnet,
    baseSepolia,
    arbitrumSepolia,
    plasmaTestnet,
    bitcoinTestnet,
    solanaDevnet,
    tronShasta,
    suiTestnet,
    aptosTestnet,
  ];

  /// 派生地址时去重的币种（EVM 多链共用同一币种 -> 同一地址，只派生一次）。
  static List<Bip44Coins> get distinctCoins {
    final seen = <Bip44Coins>[];
    for (final c in all) {
      if (!seen.contains(c.coin)) seen.add(c.coin);
    }
    return seen;
  }

  static Chain byId(String id) => all.firstWhere((c) => c.id == id);

  /// 遍历全部 (链, 代币) 对，供余额列表 / 行情批量拉取使用。
  static Iterable<(Chain, Token)> get allTokens =>
      all.expand((c) => c.tokens.map((t) => (c, t)));

}
