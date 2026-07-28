import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/wallet.dart';
import '../../domain/wallet_id.dart';
import '../../../../providers/modules/wallet_provider.dart';
import '../../services/mnemonic_service.dart';
import '../../services/private_key_service.dart';
import '../../services/secure_wallet_storage.dart';
import '../../../../i18n/translations.g.dart';
import 'import_mnemonic_logic.dart';

/// 页面 UI 状态（不可变）。
class ImportMnemonicState {
  const ImportMnemonicState({
    this.mnemonic = '',
    this.error,
    this.submitting = false,
  });

  final String mnemonic;
  final MnemonicError? error;
  final bool submitting;

  int get wordCount => ImportMnemonicLogic.wordCount(mnemonic);

  /// 当前正在输入的单词对应的 BIP39 候选词（用于键盘上方候选栏）。
  List<String> get suggestions => ImportMnemonicLogic.suggestions(mnemonic);

  /// 输入达到合法词数即可点击导入。
  bool get canSubmit =>
      !submitting && ImportMnemonicLogic.validate(mnemonic) == null;

  ImportMnemonicState copyWith({
    String? mnemonic,
    MnemonicError? error,
    bool clearError = false,
    bool? submitting,
  }) {
    return ImportMnemonicState(
      mnemonic: mnemonic ?? this.mnemonic,
      error: clearError ? null : (error ?? this.error),
      submitting: submitting ?? this.submitting,
    );
  }
}

/// 页面私有状态管理：离开页面自动销毁，下次进入是干净状态。
final importMnemonicProvider = NotifierProvider.autoDispose<
    ImportMnemonicNotifier, ImportMnemonicState>(ImportMnemonicNotifier.new);

class ImportMnemonicNotifier extends Notifier<ImportMnemonicState> {
  @override
  ImportMnemonicState build() => const ImportMnemonicState();

  /// 输入变化：实时更新并清除上一次的错误。
  void onMnemonicChanged(String value) {
    state = state.copyWith(mnemonic: value, clearError: true);
  }

  /// 提交导入。校验通过则写入钱包列表并选中，返回 true。
  Future<bool> submit() async {
    final error = ImportMnemonicLogic.validate(state.mnemonic);
    if (error != null) {
      state = state.copyWith(error: error);
      return false;
    }

    state = state.copyWith(submitting: true, clearError: true);

    // 按类型在后台 isolate 派生（BIP44 重运算 / 私钥派生均避免阻塞 UI）。
    final bool isPrivateKey =
        ImportMnemonicLogic.detectType(state.mnemonic) == SecretType.privateKey;
    // 私钥：保留大小写原样；助记词：规整为小写单空格。
    final String normalized = isPrivateKey
        ? PrivateKeyService.normalize(state.mnemonic)
        : ImportMnemonicLogic.normalize(state.mnemonic);

    final DerivedWallet derived;
    try {
      if (isPrivateKey) {
        final kind = PrivateKeyService.detect(normalized);
        derived =
            await compute(deriveFromPrivateKeyInBackground, (kind, normalized));
      } else {
        derived = await compute(deriveWalletInBackground, normalized);
      }
    } catch (_) {
      state = state.copyWith(
        submitting: false,
        error: const MnemonicError(MnemonicErrorKind.deriveFailed),
      );
      return false;
    }

    final wallet = Wallet(
      id: newWalletId(),
      name: t.import.mnemonic.walletName,
      address: derived.primaryAddress,
      source:
          isPrivateKey ? WalletSource.importedPrivateKey : WalletSource.imported,
      addresses: derived.addresses,
      createdAt: DateTime.now(),
      backupMethods: const {BackupMethod.manual}, // 导入钱包视为用户已掌握密钥。
    );

    // 敏感数据写入安全存储（Keychain / Keystore），不进入状态。
    // 私钥导入：只存私钥；助记词导入：只存助记词（私钥按需现场派生，不预存）。
    await ref.read(secureWalletStorageProvider).saveSecrets(
          walletId: wallet.id,
          mnemonic: isPrivateKey ? null : normalized,
          privateKey: isPrivateKey ? derived.primaryPrivateKey : null,
        );

    ref.read(walletListProvider.notifier).add(wallet);
    ref.read(currentWalletIdProvider.notifier).select(wallet.id);

    state = state.copyWith(submitting: false);
    return true;
  }
}
