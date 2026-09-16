import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet_core/wallet_core.dart';

/// 安全存储的注入口。
///
/// 这两个 provider 原本写在各自的存储类文件末尾。搬进 wallet_core 时留在那里，
/// 会把 flutter_riverpod 拖进安全包——审计就得连带看一遍状态管理的生命周期
/// 才能确认密钥什么时候被读写。现在包内只有纯类，"谁在什么时候持有它"是 app 的事。
///
/// 两个都是全局单例：secure storage 的句柄没有按页面区分的必要，
/// 多份实例反而会让「同一个 key 被并发读写」这种问题更难复现。

/// 助记词 / 私钥的安全存储，供创建、导入、签名流程注入使用。
final secureWalletStorageProvider = Provider<SecureWalletStorage>((ref) => SecureWalletStorage());

/// 安全码记录的安全存储。
final securityPasswordStorageProvider = Provider<SecurityPasswordStorage>((ref) => SecurityPasswordStorage());
