import '../i18n/translations.g.dart';

/// 钱包来源：新建助记词 / 助记词导入 / 私钥导入 / 硬件钱包
enum WalletSource { mnemonic, imported, importedPrivateKey, hardware }

/// 钱包来源的展示标签（创建方式）。新建/导入/详情页统一调用，避免重复。
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
