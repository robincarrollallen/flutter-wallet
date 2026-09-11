import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasource/local/secure_wallet_storage.dart';
import '../../blockchain/chain_registry.dart';
import '../../services/evm_transaction_service.dart';
import '../../services/history/transaction_history_service.dart';
import '../../services/transfer/evm_transfer_service.dart';
import '../../services/transfer/tron_transfer_service.dart';
import '../../services/tron_transaction_service.dart';
import '../../services/wallet_commit_service.dart';
import '../../services/private_key_resolver.dart';
import '../../services/wallet_service.dart';
import '../modules/asset/token_catalog_provider.dart';
import '../modules/wallet/wallet_provider.dart';

/// services 层的装配处。
///
/// service 类自身不认识 Riverpod（`lib/services/` 下不 import flutter_riverpod，
/// 由 `test/layering_test.dart` 守着），依赖一律走构造注入，谁跟谁组装只在这里决定。

/// 导出私钥 / 签名等流程的私钥解析入口。
final privateKeyResolverProvider = Provider<PrivateKeyResolver>(
  (ref) => PrivateKeyResolver(ref.watch(secureWalletStorageProvider)),
);

/// 转账编排入口。接入新链时在 map 里加一行即可。
final walletServiceProvider = Provider<WalletService>((ref) {
  final keyResolver = ref.watch(privateKeyResolverProvider);

  return WalletService(
    transferServices: {ChainKind.evm: EvmTransferService(keyResolver), ChainKind.tron: TronTransferService(keyResolver)},
    catalog: ref.watch(tokenCatalogProvider),
  );
});

/// 远程交易历史查询入口。
///
/// 目前没有任何链接入区块浏览器 / 索引器，map 为空 ⇒ `fetchAll` 恒返回空列表，
/// 历史页只显示本地记录。接入某条链时在这里加一行实现即可，页面无需改动。
final transactionHistoryServiceProvider = Provider<TransactionHistoryService>(
  (ref) => const TransactionHistoryService(),
);

/// 新钱包落盘的「事务」封装，创建与导入共用。
final walletCommitServiceProvider = Provider<WalletCommitService>(
  (ref) => WalletCommitService(ref.watch(walletRegistryProvider), ref.watch(secureWalletStorageProvider)),
);

/// EVM 链上读写（估费、gasLimit、发交易）。
final evmTransactionServiceProvider = Provider<EvmTransactionService>((ref) => const EvmTransactionService());

/// Tron 链上读写（带宽 / 能量估算、发交易）。
final tronTransactionServiceProvider = Provider<TronTransactionService>((ref) => const TronTransactionService());
