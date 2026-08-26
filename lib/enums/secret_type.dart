/// 导入输入的类型：助记词 / 私钥 / 无法识别。
enum SecretType { mnemonic, privateKey, unknown }

/// 助记词或私钥校验失败的类型。文案在 UI 层按当前语言翻译，逻辑层只返回类型与数据。
enum MnemonicErrorKind { empty, nonEnglish, wordCount, invalidWords, checksum, invalidPrivateKey, deriveFailed }
