import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 统一的代币图标渲染：优先渲染 CoinGecko 动态图标（带磁盘缓存），
/// 加载中 / 缺失 / 失败时回退为首字母圆底。
class TokenIcon extends StatelessWidget {
  const TokenIcon({
    super.key,
    required this.symbol,
    this.logoUrl,
    this.size = 28,
  });

  /// 币种符号，回退时取其首字母。
  final String symbol;

  /// CoinGecko 图标地址；为空时直接走回退，不发起网络请求。
  final String? logoUrl;

  final double size;

  @override
  Widget build(BuildContext context) {
    final url = logoUrl;
    if (url == null || url.isEmpty) return _fallback(context);

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, _) => _fallback(context),
        errorWidget: (context, _, _) => _fallback(context),
      ),
    );
  }

  /// 首字母圆底，与 [WalletAvatar] 的失败回退保持一致的视觉。
  Widget _fallback(BuildContext context) {
    final theme = Theme.of(context);
    final label = symbol.isEmpty ? '' : symbol.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontSize: size * 0.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
