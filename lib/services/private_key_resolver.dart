import 'package:flutter/foundation.dart';
import '../blockchain/chain_registry.dart';

import '../domain/wallet.dart';
import 'mnemonic_service.dart';
import 'private_key_service.dart';
import '../data/datasource/local/secure_wallet_storage.dart';

/// - 私钥/助记词明文按需取用、用完即弃，绝不进入 Riverpod 状态、日志或持久化；
/// - 助记词钱包**不额外存私钥**，每次现场派生（攻击面最小），派生在后台 isolate；
/// - 私钥导入 / 硬件钱包没有助记词，回退到读取已存的单一私钥。
/// 钱包私钥的统一解析入口：按钱包来源决定「现场派生」还是「读取已存」(供导出私钥、交易签名 / 授权等所有需要私钥的场景共用)
class PrivateKeyResolver {
  const PrivateKeyResolver(this._storage);

  final SecureWalletStorage _storage;

  /// 解析某钱包在某链上「可导出 / 展示」的私钥字符串（各链规范可移植格式：
  /// EVM/Tron/Aptos 十六进制、Solana base58、Sui bech32、Bitcoin WIF）。
  ///
  /// 助记词缺失 / 私钥缺失时抛异常，交由调用方展示失败态。
  ///
  /// [chain] 决定派生路径：助记词钱包按各链自己的 BIP44 coin_type 派生
  /// （Tron 是 195、EVM 是 60），所以必须传**当前真正要用的那条链**。
  /// EVM 各链共用同一派生方案，传其中任意一条结果都相同。
  ///
  /// 这是**面向展示**的编码格式。签名请走 [resolveSigningKeyBytes]，
  /// 别复用这里的字符串——理由见那个方法的注释。
  Future<String> resolveExportKey(Wallet wallet, Chain chain) async {
    if (wallet.hasMnemonic) {
      final mnemonic = await _storage.readMnemonic(wallet.id);
      if (mnemonic == null || mnemonic.isEmpty) {
        throw StateError('缺少助记词');
      }
      // 后台 isolate 现场派生，避免 PBKDF2 种子推导阻塞 UI。
      return compute(derivePrivateKeyInBackground, (mnemonic, chain.id));
    }

    final privateKey = await _storage.readPrivateKey(wallet.id);
    if (privateKey == null || privateKey.isEmpty) {
      throw StateError('缺少私钥');
    }
    return privateKey;
  }

  /// 解析某钱包在 [chain] 上的**原始 32 字节**私钥，供签名直接使用。
  ///
  /// 与 [resolveExportKey] 同源同路径，区别只在不做编码——签名不必再走
  /// 「编码成字符串 → 解码回字节」这趟往返：
  ///
  /// - **少一处签错的机会**：hex 无所谓，但 Sui 的 bech32 首字节是曲线方案标志、
  ///   BTC 的 WIF 夹着网络字节，每次解码都可能解错，且错得很安静；
  /// - **明文暴露面更小**：Dart 的 `String` 不可变、由 GC 决定何时回收，没法清零；
  ///   字节数组可以在用完后覆写。
  ///
  /// [chain] 语义同 [resolveExportKey]：必须是当前真正要签的那条链。
  /// 结果仅供本次签名使用，用完即弃，不得存进字段、状态或日志。
  Future<List<int>> resolveSigningKeyBytes(Wallet wallet, Chain chain) async {
    if (wallet.hasMnemonic) {
      final mnemonic = await _storage.readMnemonic(wallet.id);
      if (mnemonic == null || mnemonic.isEmpty) {
        throw StateError('缺少助记词');
      }
      // 后台 isolate 现场派生，避免 PBKDF2 种子推导阻塞 UI。
      return compute(derivePrivateKeyBytesInBackground, (mnemonic, chain.id));
    }

    // 私钥导入的钱包没有助记词，只能取回存下的原始格式再解码。
    final privateKey = await _storage.readPrivateKey(wallet.id);
    if (privateKey == null || privateKey.isEmpty) {
      throw StateError('缺少私钥');
    }
    return PrivateKeyService.decodeToBytes(privateKey);
  }
}

/// 把私钥字节就地清零。签名结束后立刻调用（放 `finally`，异常路径也要清）。
///
/// **这只覆盖我们自己持有的那份缓冲区**，做不到「私钥从进程内彻底消失」：
///
/// - 签名器（`ETHPrivateKey` / `TronPrivateKey`）在 `fromBytes` 时把密钥转成了
///   `ECDSAPrivateKey.secretMultiplier`，一个 **`final BigInt`**。Dart 的 BigInt
///   不可变、无清除接口，字段还是 final——所以 on_chain / blockchain_utils 两个包
///   全库都没有 dispose/wipe 这类接口，**不是漏做，是做不到**：纯 Dart 的椭圆曲线
///   运算靠大数，而 Dart 的大数擦不掉。别去翻库找清除方法了，没有；
/// - Dart 的 GC 是**移动式**的，存活对象会在半空间之间被复制，旧位置直接废弃、
///   不清零——所以我们清掉的只是它当前所在的那一处；
/// - 助记词本身是从安全存储读出来的 `String`，同样无法清零，而它比单条链的
///   私钥更敏感；
/// - Dart 没有 mlock/VirtualLock，内存页可能被换页到磁盘或进入崩溃转储。
///
/// 因此这是**缩短暴露窗口**的纵深防御，不是保证。真要把剩下那半关掉，得让私钥
/// 根本不进 Dart 堆：走 FFI 在原生侧（Rust/C）用可清零、可 mlock 的缓冲区签名，
/// Dart 只拿句柄；或直接交给硬件钱包。iOS Secure Enclave / Android Keystore
/// 这条路走不通——它们不支持 secp256k1 / ed25519 这些币圈用的曲线。
void wipeKey(List<int> key) {
  // 传进来的若是不可写视图（如 UnmodifiableUint8ListView），清零会抛；
  // 清不掉不该让一笔已经成功的转账失败，所以吞掉异常。
  try {
    key.fillRange(0, key.length, 0);
  } catch (_) {}
}
