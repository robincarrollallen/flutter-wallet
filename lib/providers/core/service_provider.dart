import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wallet_core/wallet_core.dart';
import 'package:wallet_core/chains.dart';
import '../../services/history/bitcoin_transaction_history_service.dart';
import '../../services/history/evm_transaction_history_service.dart';
import '../../services/history/solana_transaction_history_service.dart';
import '../../services/history/transaction_history_service.dart';
import '../../services/history/tron_transaction_history_service.dart';
import '../modules/asset/token_catalog_provider.dart';
import '../modules/wallet/wallet_provider.dart';
import 'storage_provider.dart';
import '../../config/app_config.dart';

/// services 层的装配处。
///
/// service 类自身不认识 Riverpod（`lib/services/` 下不 import flutter_riverpod，
/// 由 `test/layering_test.dart` 守着），依赖一律走构造注入，谁跟谁组装只在这里决定。

/// 导出私钥 / 签名等流程的私钥解析入口。
final privateKeyResolverProvider = Provider<PrivateKeyResolver>(
  (ref) => PrivateKeyResolver(ref.watch(secureWalletStorageProvider)),
);

/// 安全码的设置与校验。UI 一律走这里，不直接打安全存储。
final securityPasswordServiceProvider = Provider<SecurityPasswordService>(
  (ref) => SecurityPasswordService(ref.watch(securityPasswordStorageProvider)),
);

/// 转账编排入口。接入新链时在 map 里加一行即可。
final walletServiceProvider = Provider<WalletService>((ref) {
  final keyResolver = ref.watch(privateKeyResolverProvider);

  return WalletService(
    transferServices: {
      ChainKind.evm: EvmTransferService(keyResolver),
      ChainKind.tron: TronTransferService(keyResolver),
      ChainKind.solana: SolanaTransferService(keyResolver),
      ChainKind.aptos: AptosTransferService(keyResolver),
    },
    catalog: ref.watch(tokenCatalogProvider),
  );
});

/// 远程交易历史查询入口。接入新链时在 map 里加一行即可，页面无需改动。
///
/// key 在装配处注入而不是让 service 自己去读配置：service 不认识配置来源，
/// 和它不认识 Riverpod 是同一个道理——配置从哪来只有装配处知道。
/// 这也是为什么历史查询留在 app 而没有进 wallet_core：它是唯一的 key 消费者，
/// 把它和 key 一起留在边界外，安全包就能保持"不读任何配置"。
final transactionHistoryServiceProvider = Provider<TransactionHistoryService>((ref) {
  return TransactionHistoryService(
    chainServices: {
      ChainKind.evm: EvmTransactionHistoryService(apiKey: AppConfig.etherscanApiKey),
      ChainKind.solana: const SolanaTransactionHistoryService(),
      ChainKind.tron: const TronTransactionHistoryService(),
      ChainKind.bitcoin: const BitcoinTransactionHistoryService(),
    },
  );
});

/// 新钱包落盘的「事务」封装，创建与导入共用。
final walletCommitServiceProvider = Provider<WalletCommitService>(
  (ref) => WalletCommitService(ref.watch(walletRegistryProvider), ref.watch(secureWalletStorageProvider)),
);

/// EVM 链上读写（估费、gasLimit、发交易）。
final evmTransactionServiceProvider = Provider<EvmTransactionService>((ref) => const EvmTransactionService());

/// Tron 链上读写（带宽 / 能量估算、发交易）。
final tronTransactionServiceProvider = Provider<TronTransactionService>((ref) => const TronTransactionService());

/// Solana 链上读写（费用与租金豁免估算、发交易）。
final solanaTransactionServiceProvider = Provider<SolanaTransactionService>((ref) => const SolanaTransactionService());

/// Aptos 链上读写（gas 行情与模拟执行、发交易）。
final aptosTransactionServiceProvider = Provider<AptosTransactionService>((ref) => const AptosTransactionService());
