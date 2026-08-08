/// 钱包来源：新建助记词 / 助记词导入 / 私钥导入 / 硬件钱包。
/// 注意：`imported` 历史上即表示助记词导入，旧持久化数据据此沿用，无需迁移。
enum WalletSource { mnemonic, imported, importedPrivateKey, hardware }

/// 钱包来源的中文标签（创建方式）。新建/导入/详情页统一调用，避免重复。
String walletSourceLabel(WalletSource source) => switch (source) {
  WalletSource.mnemonic => '新建助记词',
  WalletSource.imported => '助记词导入',
  WalletSource.importedPrivateKey => '私钥导入',
  WalletSource.hardware => '硬件钱包',
};
