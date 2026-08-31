import 'package:flutter/material.dart';

/// 单个头像选项：默认项用 Material 图标，品牌项用 webp 资产 + 品牌色。
/// 钱包通过 [WalletAvatarOption.key] 字符串持久化头像，便于映射。
class WalletAvatarOption {
  const WalletAvatarOption({required this.key, required this.label, this.icon, this.asset, this.color});

  /// 持久化到 [Wallet.icon] 的字符串标识。
  final String key;

  /// 资产加载失败时的回退首字母 / 展示用名称。
  final String label;

  /// Material 图标（默认项）。
  final IconData? icon;

  /// 品牌资产路径（品牌项）。
  final String? asset;

  /// 品牌色（用于资产回退底色）。
  final Color? color;
}

/// 头像目录：默认钱包图标 + 项目内品牌图标（assets/icons/wallets/*.webp）。
class WalletAvatarCatalog {
  const WalletAvatarCatalog._();

  static const defaultKey = 'account_balance_wallet';

  static const all = <WalletAvatarOption>[
    WalletAvatarOption(key: defaultKey, label: '默认', icon: Icons.account_balance_wallet),
    WalletAvatarOption(
      key: 'metamask',
      label: 'M',
      asset: 'assets/icons/wallets/metamask.webp',
      color: Color(0xFFF6851B),
    ),
    WalletAvatarOption(key: 'trust', label: 'T', asset: 'assets/icons/wallets/trust.webp', color: Color(0xFF3375BB)),
    WalletAvatarOption(
      key: 'coinbase',
      label: 'C',
      asset: 'assets/icons/wallets/coinbase.webp',
      color: Color(0xFF0052FF),
    ),
    WalletAvatarOption(key: 'bitget', label: 'B', asset: 'assets/icons/wallets/bitget.webp', color: Color(0xFF00F0FF)),
    WalletAvatarOption(key: 'okx', label: 'O', asset: 'assets/icons/wallets/okx.webp', color: Color(0xFF000000)),
    WalletAvatarOption(key: 'ledger', label: 'L', asset: 'assets/icons/wallets/ledger.webp', color: Color(0xFF000000)),
    WalletAvatarOption(key: 'trezor', label: 'T', asset: 'assets/icons/wallets/trezor.webp', color: Color(0xFF00C389)),
    WalletAvatarOption(
      key: 'keystone',
      label: 'K',
      asset: 'assets/icons/wallets/keystone.webp',
      color: Color(0xFFFF5C00),
    ),
    WalletAvatarOption(
      key: 'safepal',
      label: 'S',
      asset: 'assets/icons/wallets/safepal.webp',
      color: Color(0xFF4A6CF7),
    ),
    WalletAvatarOption(key: 'onekey', label: 'O', asset: 'assets/icons/wallets/onekey.webp', color: Color(0xFF00B812)),
  ];

  /// 按 key 解析头像；找不到回退默认项。
  static WalletAvatarOption resolve(String key) {
    for (final o in all) {
      if (o.key == key) return o;
    }
    return all.first;
  }
}

/// 统一的钱包头像渲染：默认项渲染 Material 图标，品牌项渲染圆形资产图（失败回退首字母）。
class WalletAvatar extends StatelessWidget {
  const WalletAvatar({super.key, required this.iconName, this.size = 28, this.color});

  final String iconName;
  final double size;

  /// 仅作用于默认 Material 图标项；品牌项使用自身品牌色。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final option = WalletAvatarCatalog.resolve(iconName);

    if (option.asset != null) {
      return ClipOval(
        child: Image.asset(
          option.asset!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            color: option.color ?? theme.colorScheme.primary,
            child: Text(
              option.label,
              style: TextStyle(color: Colors.white, fontSize: size * 0.5, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );
    }

    return Icon(option.icon ?? Icons.account_balance_wallet, size: size, color: color ?? theme.colorScheme.primary);
  }
}
