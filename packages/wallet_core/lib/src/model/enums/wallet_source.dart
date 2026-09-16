/// 钱包来源：新建助记词 / 助记词导入 / 私钥导入 / 硬件钱包
///
/// 这是安全核心的判定依据而不只是展示字段：`PrivateKeyResolver` 靠它决定
/// 「现场从助记词派生」还是「从安全存储读导入的私钥」。
/// 对应的展示标签依赖 i18n，留在 app 侧（`lib/core/format/wallet_source_label.dart`）。
enum WalletSource { mnemonic, imported, importedPrivateKey, hardware }
