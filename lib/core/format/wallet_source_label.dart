import 'package:wallet_core/wallet_core.dart';

import '../../i18n/translations.g.dart';

/// 钱包来源的展示标签（创建方式）。新建/导入/详情页统一调用，避免重复。
///
/// 和 [WalletSource] 枚举分家：枚举是安全核心的判定依据（决定私钥从哪来），
/// 标签只是它的一种呈现，依赖 i18n。把它留在 app 侧，安全包才能不认识 Flutter 的本地化。
String walletSourceLabel(WalletSource source, Translations t) => switch (source) {
  /// 新建助记词
  WalletSource.mnemonic => t.walletSource.mnemonic,

  /// 助记词导入
  WalletSource.imported => t.walletSource.imported,

  /// 私钥导入
  WalletSource.importedPrivateKey => t.walletSource.importedPrivateKey,

  /// 硬件钱包
  WalletSource.hardware => t.walletSource.hardware,
};
