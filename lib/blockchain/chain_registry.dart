import 'package:blockchain_utils/blockchain_utils.dart';

import '../enums/btc_script_type.dart';
import '../enums/chain_kind.dart';
import '../enums/rpc_method.dart';

export '../enums/btc_script_type.dart';
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
    this.btcScriptType = BtcScriptType.p2wpkh,
    this.evmChainId,
    this.nativeBalanceRpcMethod,
    this.coinGeckoPlatformId,
    this.supportsRpcBatch = true,
  }) : assert(
         (kind == ChainKind.evm || kind == ChainKind.solana || kind == ChainKind.sui) ==
             (nativeBalanceRpcMethod != null),
         'JSON-RPC 链（evm/solana/sui）必须配置 nativeBalanceRpcMethod，REST 链必须留空',
       );

  final String id; // 链的唯一标识符(用于查找链配置、保存用户选择、做数据关联, byId 就靠它)
  final String name; // 链的名称(UI 展示给用户看)
  final String symbol; // 原生币符号，例如 ETH / BTC / SOL(余额、资产列表、转账页面等地方显示币种简称)
  final ChainKind kind; // 链的类型(决定“用哪套逻辑”去派生地址、查余额、调用接口和签名)
  final Bip44Coins coin; // BIP44 币种枚举(决定助记词派生路径；同一助记词在不同链会因为这个值派生出不同地址, EVM 多链共用 ethereum)
  final String endpoint; // 该链的节点/API 地址(实际网络请求入口, EVM/Solana 通常是 RPC，Bitcoin 是区块浏览器 API)
  final String coinGeckoId; // CoinGecko 里的币种 ID (拉取价格<通常是 USD 单价>, 做资产估值)
  final int decimals; // 原生币最小单位精度<如 ETH=18，BTC=8>(金额换算: 链上最小单位 <-> 人类可读金额)
  final BtcScriptType btcScriptType; // BTC 脚本类型/派生路径方案(仅 ChainKind.bitcoin 有意义，其余链忽略)
  final int? evmChainId; // EVM 链的 chainId<数字>(EIP-155 签名必需, 非 EVM 链为空)
  final RpcMethod? nativeBalanceRpcMethod; // 原生币余额 RPC 方法（非 JSON-RPC 链为空）
  final String? coinGeckoPlatformId; // CoinGecko asset_platforms 的平台 id，用于取该链自己的图标(如 Base / Arbitrum 都有 ETH)

  /// 该链的节点是否接受批量 JSON-RPC（一个请求体里发多条调用）。
  ///
  /// 绝大多数节点都支持，所以默认为 true；个别公共节点会明确拒绝，
  /// 这时多代币查询退回「并发发单条」——见 [ChainBalanceApi]。
  /// 与协议无关，纯粹是节点实现的差异，所以挂在链（= 一个具体 endpoint）上而不是 kind 上。
  final bool supportsRpcBatch;

  /// 该链的派生方案：地址派生只认它，链的其余配置（endpoint / 价格 id 等）都与派生无关。
  DerivationScheme get derivation =>
      DerivationScheme(coin: coin, btcScriptType: kind == ChainKind.bitcoin ? btcScriptType : null);
}

/// 一组「能唯一决定一个地址」的派生参数。多条链共用同一方案时只需派生一次（EVM 多链即如此）。
class DerivationScheme {
  const DerivationScheme({required this.coin, this.btcScriptType});

  final Bip44Coins coin; // 币种，决定 coin_type 与地址编码所用的网络参数
  final BtcScriptType? btcScriptType; // BTC 脚本类型，决定走 BIP44/84/86；非 BTC 链为空

  @override
  bool operator ==(Object other) =>
      other is DerivationScheme && other.coin == coin && other.btcScriptType == btcScriptType;

  @override
  int get hashCode => Object.hash(coin, btcScriptType);
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
    name: 'Bitcoin Testnet4',
    symbol: 'BTC',
    kind: ChainKind.bitcoin,
    coin: Bip44Coins.bitcoinTestnet,
    endpoint: 'https://mempool.space/testnet4/api',
    coinGeckoId: 'bitcoin',
    decimals: 8,
    btcScriptType: BtcScriptType.p2wpkh,
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

  // —— 以下三条非 EVM 链的原生币与代币余额查询均已接入（Tron/Sui/Aptos）。 ——

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
    // 这个公共节点明确拒绝批量请求（-32005 Batched requests are not supported by this server），
    // 而 Sui 官方 fullnode 的 JSON-RPC 已整体弃用（-32601，要求迁移到 gRPC/GraphQL），
    // 换端点解决不了。多代币查询走并发单条。
    supportsRpcBatch: false,
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

  /// 派生地址时去重后的方案（EVM 多链共用同一方案 -> 同一地址，只派生一次）。
  static List<DerivationScheme> get distinctDerivations {
    final seen = <DerivationScheme>[];
    for (final chain in all) {
      if (!seen.contains(chain.derivation)) seen.add(chain.derivation);
    }
    return seen;
  }

  static Chain byId(String id) => all.firstWhere((c) => c.id == id);
}
