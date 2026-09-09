import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../blockchain/chain_registry.dart';
import '../../data/datasource/local/secure_wallet_storage.dart';
import '../../services/evm_transaction_service.dart';
import '../../services/transfer/evm_transfer_service.dart';
import '../../services/transfer/tron_transfer_service.dart';
import '../../services/tron_transaction_service.dart';
import '../../services/wallet_commit_service.dart';
import '../../services/wallet_key_service.dart';
import '../../services/wallet_service.dart';
import '../modules/asset/token_catalog_provider.dart';
import '../modules/wallet/wallet_provider.dart';

/// services 层的装配处。
///
/// service 类自身不认识 Riverpod（`lib/services/` 下不 import flutter_riverpod，
/// 由 `test/layering_test.dart` 守着），依赖一律走构造注入，谁跟谁组装只在这里决定。

/// 导出私钥 / 签名等流程的私钥解析入口。
final walletKeyServiceProvider = Provider<WalletKeyService>(
  (ref) => WalletKeyService(ref.watch(secureWalletStorageProvider)),
);

/// 转账编排入口。各链转账实现在这里注册：接入新链时在 map 里加一行即可。
final walletServiceProvider = Provider<WalletService>((ref) {
  final keyService = ref.watch(walletKeyServiceProvider);
  return WalletService(
    transferServices: {
      ChainKind.evm: EvmTransferService(keyService),
      ChainKind.tron: TronTransferService(keyService),
    },
    catalog: ref.watch(tokenCatalogProvider),
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
