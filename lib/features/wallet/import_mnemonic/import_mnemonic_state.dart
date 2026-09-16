import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wallet_core/wallet_core.dart';
import '../../../providers/core/service_provider.dart';
import '../../../services/wallet_commit_service.dart';
import '../../../i18n/translations.g.dart';
import 'import_mnemonic_logic.dart';

/// 页面 UI 状态（不可变）。
///
/// **刻意不持有助记词/私钥明文。** 用户输入的密钥只存在于页面的
/// `TextEditingController` 里，提交时作为参数一次性传进来、用完即弃。
///
/// 理由不是「会落盘」——这个 provider 是 autoDispose 且非 PersistentNotifier，
/// 从不写磁盘；而是 Riverpod 的 `ProviderObserver` / DevTools 会把每次状态变更
/// 打出来。密钥躺在一个可观测容器里，任何人日后加一个日志型 observer 就会直接
/// 把助记词写进日志。对照 `create_wallet_state.dart`：那边一直是对的，
/// 助记词只是局部变量。
class ImportMnemonicState {
  const ImportMnemonicState({this.error, this.submitting = false});

  final MnemonicError? error;
  final bool submitting;

  ImportMnemonicState copyWith({MnemonicError? error, bool clearError = false, bool? submitting}) {
    return ImportMnemonicState(
      error: clearError ? null : (error ?? this.error),
      submitting: submitting ?? this.submitting,
    );
  }
}

/// 页面私有状态管理：离开页面自动销毁，下次进入是干净状态。
final importMnemonicProvider = NotifierProvider.autoDispose<ImportMnemonicNotifier, ImportMnemonicState>(
  ImportMnemonicNotifier.new,
);

class ImportMnemonicNotifier extends Notifier<ImportMnemonicState> {
  @override
  ImportMnemonicState build() => const ImportMnemonicState();

  /// 输入变化：清除上一次的错误。
  ///
  /// **不接收输入内容**——密钥留在页面的 controller 里，不进状态。
  void onInputChanged() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }

  /// 提交导入。校验通过则写入钱包列表并选中，返回 true。
  ///
  /// [secret] 是用户输入的助记词或私钥，由页面在点击时一次性传入。
  /// 它是方法的局部变量，不会进入 [state]——见 [ImportMnemonicState] 的注释。
  Future<bool> submit(String secret) async {
    final error = ImportMnemonicLogic.validate(secret);
    if (error != null) {
      state = state.copyWith(error: error);
      return false;
    }

    state = state.copyWith(submitting: true, clearError: true);

    // 按类型在后台 isolate 派生（BIP44 重运算 / 私钥派生均避免阻塞 UI）。
    final bool isPrivateKey = ImportMnemonicLogic.detectType(secret) == SecretType.privateKey;
    // 私钥：保留大小写原样；助记词：规整为小写单空格。
    final String normalized = isPrivateKey
        ? PrivateKeyService.normalize(secret)
        : ImportMnemonicLogic.normalize(secret);

    final DerivedWallet derived;
    try {
      if (isPrivateKey) {
        final kind = PrivateKeyService.detect(normalized);
        derived = await compute(deriveFromPrivateKeyInBackground, (kind, normalized));
      } else {
        derived = await compute(deriveWalletInBackground, normalized);
      }
    } catch (_) {
      state = state.copyWith(submitting: false, error: const MnemonicError(MnemonicErrorKind.deriveFailed));
      return false;
    }

    final wallet = Wallet(
      id: newWalletId(),
      name: t.import.mnemonic.walletName,
      source: isPrivateKey ? WalletSource.importedPrivateKey : WalletSource.imported,
      addresses: derived.addresses,
      createdAt: DateTime.now(),
      backupMethods: const {BackupMethod.manual}, // 导入钱包视为用户已掌握密钥。
    );

    // 敏感数据 + 元数据 + 选中态原子提交，失败则完整回滚、不留半成品钱包。
    // 敏感数据进安全存储（Keychain / Keystore），不进入状态。
    // 私钥导入：只存私钥；助记词导入：只存助记词（私钥按需现场派生，不预存）。
    try {
      await ref
          .read(walletCommitServiceProvider)
          .commit(
            wallet: wallet,
            mnemonic: isPrivateKey ? null : normalized,
            privateKey: isPrivateKey ? derived.primaryPrivateKey : null,
          );
    } on WalletCommitException {
      state = state.copyWith(submitting: false, error: const MnemonicError(MnemonicErrorKind.saveFailed));
      return false;
    }

    state = state.copyWith(submitting: false);
    return true;
  }
}
