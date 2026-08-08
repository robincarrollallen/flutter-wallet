import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/wallet.dart';
import '../../../domain/wallet_id.dart';
import '../../../services/mnemonic_service.dart';
import '../../../data/datasource/local/secure_wallet_storage.dart';
import '../../../providers/modules/wallet_provider.dart';
import '../../../i18n/translations.g.dart';

/// 创建钱包的阶段：生成中 / 成功 / 失败。
enum CreatePhase { generating, success, failed }

/// 创建钱包页面状态（不可变）。
class CreateWalletState {
  const CreateWalletState({this.phase = CreatePhase.generating, this.walletId});

  final CreatePhase phase;

  /// 创建成功后新钱包的 id。
  final String? walletId;

  CreateWalletState copyWith({CreatePhase? phase, String? walletId}) {
    return CreateWalletState(phase: phase ?? this.phase, walletId: walletId ?? this.walletId);
  }
}

/// 页面私有状态：离开页面自动销毁。
final createWalletProvider = NotifierProvider.autoDispose<CreateWalletNotifier, CreateWalletState>(
  CreateWalletNotifier.new,
);

class CreateWalletNotifier extends Notifier<CreateWalletState> {
  @override
  CreateWalletState build() => const CreateWalletState();

  /// 真正执行创建：生成助记词 -> 派生地址 -> 写入钱包列表并选中。
  /// 期间保持 generating 阶段，UI 据此播放过渡动画并屏蔽其他操作。
  Future<void> create() async {
    state = const CreateWalletState(phase: CreatePhase.generating);

    try {
      // 生成全新的 BIP39 助记词，并在后台 isolate 派生全部链地址（避免阻塞 UI）。
      final mnemonic = MnemonicService.generate();
      final derived = await compute(deriveWalletInBackground, mnemonic);

      // 让过渡动画至少完整播放一段，避免一闪而过。
      await Future<void>.delayed(const Duration(milliseconds: 1800));

      // 首个钱包用基名；已有钱包则加序号（新钱包索引+1 = 当前列表长度+1）。
      final base = t.create.walletName;
      final existing = ref.read(walletListProvider).length;
      final name = existing == 0 ? base : '$base ${existing + 1}';

      final wallet = Wallet(
        id: newWalletId(),
        name: name,
        address: derived.primaryAddress,
        source: WalletSource.mnemonic,
        addresses: derived.addresses,
        createdAt: DateTime.now(),
      );

      // 助记词写入安全存储（Keychain / Keystore），不进入状态；
      // 私钥不预存，签名/导出时由助记词按需现场派生。
      await ref.read(secureWalletStorageProvider).saveSecrets(walletId: wallet.id, mnemonic: mnemonic);

      ref.read(walletListProvider.notifier).add(wallet);
      ref.read(currentWalletIdProvider.notifier).select(wallet.id);

      state = state.copyWith(phase: CreatePhase.success, walletId: wallet.id);
    } catch (_) {
      state = state.copyWith(phase: CreatePhase.failed);
    }
  }
}
