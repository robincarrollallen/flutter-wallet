import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../blockchain/chain_registry.dart';

import '../domain/wallet.dart';
import 'mnemonic_service.dart';
import '../data/datasource/local/secure_wallet_storage.dart';

/// 钱包私钥的统一解析入口：按钱包来源决定「现场派生」还是「读取已存」，
/// 供导出私钥、（将来的）交易签名 / 授权等所有需要私钥的场景共用。
///
/// 设计原则：
/// - 私钥/助记词明文按需取用、用完即弃，绝不进入 Riverpod 状态、日志或持久化；
/// - 助记词钱包**不额外存私钥**，每次现场派生（攻击面最小），派生在后台 isolate；
/// - 私钥导入 / 硬件钱包没有助记词，回退到读取已存的单一私钥。
class WalletKeyService {
  const WalletKeyService(this._storage);

  final SecureWalletStorage _storage;

  /// 解析某钱包在某链上「可导出 / 展示」的私钥字符串（各链规范可移植格式：
  /// EVM/Tron/Aptos 十六进制、Solana base58、Sui bech32、Bitcoin WIF）。
  ///
  /// 助记词缺失 / 私钥缺失时抛异常，交由调用方展示失败态。
  ///
  /// 注意：这是给「用户查看 / 外部钱包回导」的编码格式。真实签名应改用原始 32 字节私钥 / 账户对象，避免编码-解码往返（后续实现签名时再补对应方法）。
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

  /// 解析某钱包的 EVM 签名私钥（0x + secp256k1 十六进制）。
  ///
  /// 助记词钱包按默认路径现场派生（后台 isolate）；私钥导入钱包直接读取已存
  /// 的主私钥（本身即 EVM hex）。结果仅供签名一次性使用，用完即弃。
  Future<String> resolveEvmSigningKey(Wallet wallet) async {
    if (wallet.hasMnemonic) {
      final mnemonic = await _storage.readMnemonic(wallet.id);
      if (mnemonic == null || mnemonic.isEmpty) {
        throw StateError('缺少助记词');
      }
      // 与导出共用同一派生定义：EVM 主链的规范格式即 0x hex，可直接签名。
      return compute(derivePrivateKeyInBackground, (mnemonic, SupportedChains.ethereumSepolia.id));
    }

    final privateKey = await _storage.readPrivateKey(wallet.id);
    if (privateKey == null || privateKey.isEmpty) {
      throw StateError('缺少私钥');
    }
    return privateKey;
  }
}

/// 定义 provider，供导出私钥 / 签名等流程注入使用。
final walletKeyServiceProvider = Provider<WalletKeyService>(
  (ref) => WalletKeyService(ref.watch(secureWalletStorageProvider)),
);
