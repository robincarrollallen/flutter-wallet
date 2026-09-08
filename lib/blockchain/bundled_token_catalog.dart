import 'chain_registry.dart';
import 'token.dart';

/// 打包进应用的代币目录：远程拉取失败或未配置远端 URL 时，由 RemoteTokensNotifier 回退到这里。
///
/// 测试网合约没有公开的通用 token list API；远端 JSON 成功后优先用远端结果，这份列表不再参与合并。
class BundledTokenCatalog {
  const BundledTokenCatalog._();

  static final List<Token> all = [
    Token(
      chainId: SupportedChains.ethereumSepolia.id,
      symbol: 'USDC',
      name: 'USD Coin',
      standard: TokenStandard.erc20,
      identifier: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
      coinGeckoId: 'usd-coin',
      decimals: 6,
    ),
    Token(
      chainId: SupportedChains.polygonAmoy.id,
      symbol: 'USDC',
      name: 'USD Coin',
      standard: TokenStandard.erc20,
      identifier: '0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582',
      coinGeckoId: 'usd-coin',
      decimals: 6,
    ),
    Token(
      chainId: SupportedChains.baseSepolia.id,
      symbol: 'USDC',
      name: 'USD Coin',
      standard: TokenStandard.erc20,
      identifier: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
      coinGeckoId: 'usd-coin',
      decimals: 6,
    ),
    Token(
      chainId: SupportedChains.arbitrumSepolia.id,
      symbol: 'USDC',
      name: 'USD Coin',
      standard: TokenStandard.erc20,
      identifier: '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d',
      coinGeckoId: 'usd-coin',
      decimals: 6,
    ),
    Token(
      chainId: SupportedChains.solanaDevnet.id,
      symbol: 'USDC',
      name: 'USD Coin',
      standard: TokenStandard.spl,
      identifier: '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
      coinGeckoId: 'usd-coin',
      decimals: 6,
    ),
    Token(
      chainId: SupportedChains.suiTestnet.id,
      symbol: 'USDC',
      name: 'USD Coin',
      standard: TokenStandard.suiCoin,
      identifier: '0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC',
      coinGeckoId: 'usd-coin',
      decimals: 6,
    ),
    Token(
      chainId: SupportedChains.aptosTestnet.id,
      symbol: 'USDC',
      name: 'USD Coin',
      standard: TokenStandard.aptosCoin,
      identifier: '0x69091fbab5f7d635ee7ac5098cf0c1efbe31d68fec0f2cd565e8d168daf52832',
      coinGeckoId: 'usd-coin',
      decimals: 6,
    ),
    // Nile 测试网的官方 USDT。合约元数据已上链核对过：
    // name=Tether USD / symbol=USDT / decimals=6。
    // 这里是 USDT 而非 USDC——Nile 水龙头发的就是它，Tron 生态的稳定币也以它为主。
    Token(
      chainId: SupportedChains.tronNile.id,
      symbol: 'USDT',
      name: 'Tether USD',
      standard: TokenStandard.trc20,
      identifier: 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf',
      coinGeckoId: 'tether',
      decimals: 6,
    ),
  ];
}
