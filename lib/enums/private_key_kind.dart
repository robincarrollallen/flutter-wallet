/// 自动判断出的私钥类型。
/// - [evmHex]：secp256k1 的 64 位十六进制（可带 0x），同一把私钥可还原全部 EVM 链 + Tron 地址。
/// - [solanaBase58]：Solana ed25519 私钥（base58，32 或 64 字节）。
/// - [suiBech32]：Sui 私钥（`suiprivkey1...` bech32）。
/// - [unknown]：无法识别。
enum PrivateKeyKind { evmHex, solanaBase58, suiBech32, unknown }
