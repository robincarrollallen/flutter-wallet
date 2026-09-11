import '../domain/wallet.dart';
import '../data/datasource/local/secure_wallet_storage.dart';
import 'wallet_registry.dart';

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
/// 1. 打提交意图标记
/// 2. 写敏感数据 → 立刻回读校验
/// 3. 钱包入列表
/// 4. 设为当前选中
/// 5. 撤下提交意图标记
///
/// 顺序上敏感数据先行：两种残留态里，孤儿密钥（用户看不见，且会被
/// [SecureWalletStorage.purgeOrphanSecrets] 在下次启动清掉）远优于砖块钱包
/// （用户看得见、能查余额，点转账 / 导出才发现签不了名）。
///
/// 首尾两步的标记是这份「孤儿可被清理」的前提：对账认标记而不认钱包列表，因为列表
/// 会随 App 删除一起消失，而 Keychain 不会——详见 [SecureWalletStorage.purgeOrphanSecrets]。
///
/// 任一步失败都逆序撤销，调用方只需处理 [WalletCommitException]。
class WalletCommitService {
  const WalletCommitService(this._registry, this._secureStorage);

  final WalletRegistry _registry;
  final SecureWalletStorage _secureStorage;

  /// 原子地提交一个新钱包：敏感数据 + 元数据 + 选中态要么全部生效，要么什么都不留。
  ///
  /// [mnemonic] 与 [privateKey] 按钱包来源二选一：助记词钱包只存助记词
  /// （私钥在签名 / 导出时现场派生，不预存）；私钥导入钱包只存私钥。
  Future<void> commit({required Wallet wallet, String? mnemonic, String? privateKey}) async {
    // 记下提交前的选中项，回滚时恢复——不能想当然地置 null，用户可能本来就选着别的钱包。
    final previousSelectedId = _registry.currentWalletId;

    try {
      // 安全存储单独一层 try：无论是抛异常还是回读不到，都归因为 secretWriteFailed，
      // 不能和后面的元数据落盘失败混为一谈——两者对用户的含义不同。
      try {
        // 提交意图标记先行：只有带着它的敏感数据，才有资格在下次启动被当作中断残留清掉。
        // 标记写不上就不能继续写密钥——那会造出一条谁也认不出、因而永远清不掉的孤儿。
        await _secureStorage.markPendingCommit(wallet.id);
        await _secureStorage.saveSecrets(walletId: wallet.id, mnemonic: mnemonic, privateKey: privateKey);
        // write 不抛异常不代表真的写进去了，回读确认后才继续。
        if (!await _secureStorage.hasSecrets(wallet.id)) {
          throw const WalletCommitException(WalletCommitFailure.secretWriteFailed);
        }
      } catch (_) {
        throw const WalletCommitException(WalletCommitFailure.secretWriteFailed);
      }

      _registry.add(wallet);
      // 严格排在入列表之后：保证选中 id 永远能在列表里找到对应项。
      _registry.select(wallet.id);
    } on WalletCommitException {
      await _rollback(wallet: wallet, previousSelectedId: previousSelectedId);
      rethrow;
    } catch (_) {
      await _rollback(wallet: wallet, previousSelectedId: previousSelectedId);
      throw const WalletCommitException(WalletCommitFailure.persistFailed);
    }

    // 元数据已全部生效，撤下标记——从此这份敏感数据不再具备被对账删除的资格。
    // 这一步失败不改变提交结果（用户视角就是成功了），遗留标记会在下次对账时被
    // 识别为陈旧并单独清掉，不会牵连密钥。
    try {
      await _secureStorage.clearPendingCommit(wallet.id);
    } catch (_) {}
  }

  /// 逆序撤销：选中项 → 钱包列表 → 敏感数据。
  ///
  /// 每一步都先确认「确实做过」再撤销，因为失败可能发生在任意阶段。
  /// 回滚自身再失败也不向外抛出：原始失败原因更有价值，而残留的孤儿密钥
  /// 会被下次启动的对账清掉。
  Future<void> _rollback({required Wallet wallet, required String? previousSelectedId}) async {
    try {
      if (_registry.currentWalletId == wallet.id) {
        _registry.select(previousSelectedId);
      }

      if (_registry.contains(wallet.id)) {
        // remove 内部已包含 deleteSecrets。
        await _registry.remove(wallet.id);
      } else {
        await _secureStorage.deleteSecrets(wallet.id);
      }
    } catch (_) {
      // 回滚失败不掩盖原始错误。
    }
  }

  /// 启动对账：清理上次被中断的提交在安全存储里留下的敏感数据。
  ///
  /// 只清「带提交意图标记」的那些，且要求钱包列表本身可信——详见
  /// [SecureWalletStorage.purgeOrphanSecrets]。
  Future<int> purgeOrphanSecrets() {
    return _secureStorage.purgeOrphanSecrets(
      knownWalletIds: _registry.knownWalletIds,
      registryTrusted: _registry.walletListTrusted,
    );
  }
}
