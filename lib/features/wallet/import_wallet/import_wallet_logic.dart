import 'package:flutter/painting.dart';
import '../../../enums/import_kind.dart';

/// 钱包品牌数据：决定卡片里展示哪些 logo。
/// 新增/删除钱包只改这份数据，无需改动 UI。
class WalletBrand {
  const WalletBrand({required this.asset, required this.fallbackLabel, required this.fallbackColor});

  final String asset;
  final String fallbackLabel;
  final Color fallbackColor;
}

/// 导入入口选项：标题 + 该入口展示的品牌列表。
class ImportOption {
  const ImportOption({required this.kind, required this.brands});

  final ImportKind kind;
  final List<WalletBrand> brands;
}

/// 导入页的纯数据/逻辑：与状态/UI 无关。
class ImportWalletLogic {
  const ImportWalletLogic._();

  static const softwareWallets = <WalletBrand>[
    WalletBrand(asset: 'assets/icons/wallets/metamask.webp', fallbackLabel: 'M', fallbackColor: Color(0xFFF6851B)),
    WalletBrand(asset: 'assets/icons/wallets/trust.webp', fallbackLabel: 'T', fallbackColor: Color(0xFF3375BB)),
    WalletBrand(asset: 'assets/icons/wallets/coinbase.webp', fallbackLabel: 'C', fallbackColor: Color(0xFF0052FF)),
    WalletBrand(asset: 'assets/icons/wallets/bitget.webp', fallbackLabel: 'B', fallbackColor: Color(0xFF00F0FF)),
    WalletBrand(asset: 'assets/icons/wallets/okx.webp', fallbackLabel: 'O', fallbackColor: Color(0xFF000000)),
  ];

  static const hardwareWallets = <WalletBrand>[
    WalletBrand(asset: 'assets/icons/wallets/ledger.webp', fallbackLabel: 'L', fallbackColor: Color(0xFF000000)),
    WalletBrand(asset: 'assets/icons/wallets/trezor.webp', fallbackLabel: 'T', fallbackColor: Color(0xFF00C389)),
    WalletBrand(asset: 'assets/icons/wallets/keystone.webp', fallbackLabel: 'K', fallbackColor: Color(0xFFFF5C00)),
    WalletBrand(asset: 'assets/icons/wallets/safepal.webp', fallbackLabel: 'S', fallbackColor: Color(0xFF4A6CF7)),
    WalletBrand(asset: 'assets/icons/wallets/onekey.webp', fallbackLabel: 'O', fallbackColor: Color(0xFF00B812)),
  ];

  /// 页面要展示的导入入口（顺序即展示顺序）。
  static const options = <ImportOption>[
    ImportOption(kind: ImportKind.software, brands: softwareWallets),
    ImportOption(kind: ImportKind.hardware, brands: hardwareWallets),
  ];
}
