/// 导入输入的类型：助记词 / 私钥 / 无法识别。
enum SecretType { mnemonic, privateKey, unknown }

/// 助记词或私钥校验失败的类型。文案在 UI 层按当前语言翻译，逻辑层只返回类型与数据。
/// [saveFailed] 是唯一与输入内容无关的一项：助记词/私钥本身合法，但落盘失败（已回滚，可重试）。
enum MnemonicErrorKind {
  empty,
  nonEnglish,
  wordCount,
  invalidWords,
  checksum,
  invalidPrivateKey,
  deriveFailed,
  saveFailed,
}
