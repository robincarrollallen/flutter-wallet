import 'package:blockchain_utils/blockchain_utils.dart';

import '../enums/chain_kind.dart';
import '../enums/rpc_method.dart';

export '../enums/chain_kind.dart';
export '../enums/rpc_method.dart';

/// 一条受支持链的静态配置。代币不挂在链上，由 TokenCatalog 单独提供。
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
    this.evmChainId,
    this.nativeBalanceRpcMethod,
    this.coinGeckoPlatformId,
  });

  final String id; // 链的唯一标识符(用于查找链配置、保存用户选择、做数据关联, byId 就靠它)
  final String name; // 链的名称(UI 展示给用户看)
  final String symbol; // 原生币符号，例如 ETH / BTC / SOL(余额、资产列表、转账页面等地方显示币种简称)
  final ChainKind kind; // 链的类型(决定“用哪套逻辑”去派生地址、查余额、调用接口和签名)
  final Bip44Coins coin; // BIP44 币种枚举(决定助记词派生路径；同一助记词在不同链会因为这个值派生出不同地址, EVM 多链共用 ethereum)
  final String endpoint; // 该链的节点/API 地址(实际网络请求入口, EVM/Solana 通常是 RPC，Bitcoin 是区块浏览器 API)
  final String coinGeckoId; // CoinGecko 里的币种 ID (拉取价格<通常是 USD 单价>, 做资产估值)
  final int decimals; // 原生币最小单位精度<如 ETH=18，BTC=8>(金额换算: 链上最小单位 <-> 人类可读金额)
  final int? evmChainId; // EVM 链的 chainId<数字>(EIP-155 签名必需, 非 EVM 链为空)
  final RpcMethod? nativeBalanceRpcMethod; // 原生币余额 RPC 方法（非 JSON-RPC 链为空）
  final String? coinGeckoPlatformId; // CoinGecko asset_platforms 的平台 id，用于取该链自己的图标(如 Base / Arbitrum 都有 ETH)
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
    evmChainId: 11155111,
    nativeBalanceRpcMethod: RpcMethod.ethGetBalance,
    coinGeckoPlatformId: 'ethereum',
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
    evmChainId: 80002,
    nativeBalanceRpcMethod: RpcMethod.ethGetBalance,
    coinGeckoPlatformId: 'polygon-pos',
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
    evmChainId: 97,
    nativeBalanceRpcMethod: RpcMethod.ethGetBalance,
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
    evmChainId: 84532,
    nativeBalanceRpcMethod: RpcMethod.ethGetBalance,
    coinGeckoPlatformId: 'base',
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
    evmChainId: 421614,
    nativeBalanceRpcMethod: RpcMethod.ethGetBalance,
    coinGeckoPlatformId: 'arbitrum-one',
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
    evmChainId: 9746,
    nativeBalanceRpcMethod: RpcMethod.ethGetBalance,
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
    nativeBalanceRpcMethod: RpcMethod.solGetBalance,
    coinGeckoPlatformId: 'solana',
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
    nativeBalanceRpcMethod: RpcMethod.suiGetBalance,
    coinGeckoPlatformId: 'sui',
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
}
