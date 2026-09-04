import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/wallet.dart';
import '../data/datasource/local/secure_wallet_storage.dart';
import '../providers/modules/wallet_provider.dart';

/// 提交失败的原因，供页面区分提示文案。
enum WalletCommitFailure {
  /// 敏感数据写入安全存储失败（抛异常，或写入后回读不到）。
  secretWriteFailed,

  /// 钱包元数据落盘失败。
  persistFailed,
}

/// 新钱包落盘失败。抛出时保证已完成回滚，不会残留半成品钱包。
class WalletCommitException implements Exception {
  const WalletCommitException(this.reason);

  final WalletCommitFailure reason;

  @override
  String toString() => 'WalletCommitException($reason)';
}

/// 新钱包落盘的「事务」封装：创建与导入共用。
///
/// 敏感数据在 Keychain / Keystore，元数据在 SharedPreferences，两套独立存储之间
/// 无法做真正的跨存储事务。这里用**严格的提交顺序 + 回读校验 + 失败回滚**逼近原子性：
///
/// 1. 写敏感数据 → 立刻回读校验
/// 2. 钱包入列表
/// 3. 设为当前选中
///
/// 顺序上敏感数据先行：两种残留态里，孤儿密钥（用户看不见，且会被
/// [SecureWalletStorage.purgeOrphanSecrets] 在下次启动清掉）远优于砖块钱包
/// （用户看得见、能查余额，点转账 / 导出才发现签不了名）。
///
/// 任一步失败都逆序撤销，调用方只需处理 [WalletCommitException]。
class WalletCommitService {
  const WalletCommitService(this._ref);

  final Ref _ref;

  /// 原子地提交一个新钱包：敏感数据 + 元数据 + 选中态要么全部生效，要么什么都不留。
  ///
  /// [mnemonic] 与 [privateKey] 按钱包来源二选一：助记词钱包只存助记词
  /// （私钥在签名 / 导出时现场派生，不预存）；私钥导入钱包只存私钥。
  Future<void> commit({required Wallet wallet, String? mnemonic, String? privateKey}) async {
    final secureStorage = _ref.read(secureWalletStorageProvider);
    // 记下提交前的选中项，回滚时恢复——不能想当然地置 null，用户可能本来就选着别的钱包。
    final previousSelectedId = _ref.read(currentWalletIdProvider);

    try {
      // 安全存储单独一层 try：无论是抛异常还是回读不到，都归因为 secretWriteFailed，
      // 不能和后面的元数据落盘失败混为一谈——两者对用户的含义不同。
      try {
        await secureStorage.saveSecrets(walletId: wallet.id, mnemonic: mnemonic, privateKey: privateKey);
        // write 不抛异常不代表真的写进去了，回读确认后才继续。
        if (!await secureStorage.hasSecrets(wallet.id)) {
          throw const WalletCommitException(WalletCommitFailure.secretWriteFailed);
        }
      } catch (_) {
        throw const WalletCommitException(WalletCommitFailure.secretWriteFailed);
      }

      _ref.read(walletListProvider.notifier).add(wallet);
      // 严格排在入列表之后：保证选中 id 永远能在列表里找到对应项。
      _ref.read(currentWalletIdProvider.notifier).select(wallet.id);
    } on WalletCommitException {
      await _rollback(wallet: wallet, previousSelectedId: previousSelectedId);
      rethrow;
    } catch (_) {
      await _rollback(wallet: wallet, previousSelectedId: previousSelectedId);
      throw const WalletCommitException(WalletCommitFailure.persistFailed);
    }
  }

  /// 逆序撤销：选中项 → 钱包列表 → 敏感数据。
  ///
  /// 每一步都先确认「确实做过」再撤销，因为失败可能发生在任意阶段。
  /// 回滚自身再失败也不向外抛出：原始失败原因更有价值，而残留的孤儿密钥
  /// 会被下次启动的对账清掉。
  Future<void> _rollback({required Wallet wallet, required String? previousSelectedId}) async {
    try {
      if (_ref.read(currentWalletIdProvider) == wallet.id) {
        _ref.read(currentWalletIdProvider.notifier).select(previousSelectedId);
      }

      if (_ref.read(walletListProvider).any((w) => w.id == wallet.id)) {
        // remove 内部已包含 deleteSecrets。
        _ref.read(walletListProvider.notifier).remove(wallet.id);
      } else {
        await _ref.read(secureWalletStorageProvider).deleteSecrets(wallet.id);
      }
    } catch (_) {
      // 回滚失败不掩盖原始错误。
    }
  }

  /// 启动对账：清理上次被中断的提交在安全存储里留下的、无钱包引用的敏感数据。
  Future<int> purgeOrphanSecrets() {
    final knownIds = _ref.read(walletListProvider).map((w) => w.id).toSet();
    return _ref.read(secureWalletStorageProvider).purgeOrphanSecrets(knownIds);
  }
}

final walletCommitServiceProvider = Provider<WalletCommitService>(WalletCommitService.new);
