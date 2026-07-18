import 'package:uuid/uuid.dart';

/// 生成钱包唯一标识符（UUID v4，加密随机，几乎零碰撞）。
///
/// 注意：仅用于「新建 / 导入」时生成 id。已存在钱包的 id 必须保持不变，
/// 因为 secure storage 的 key 按 `wallet.{id}.mnemonic` 拼接，改 id 会读不到助记词/私钥。
String newWalletId() => const Uuid().v4();
