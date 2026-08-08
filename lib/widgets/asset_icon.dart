import 'package:flutter/material.dart';

import '../core/responsive/screen_adapter.dart';
import 'token_icon.dart';

/// 资产图标：主体为币/代币图标，右下角叠加所在链的小图标徽标。
/// 多链资产场景通用（接收弹窗、搜索等）。
class AssetIcon extends StatelessWidget {
  const AssetIcon({
    super.key,
    required this.symbol,
    required this.tokenLogoUrl,
    required this.chainSymbol,
    required this.chainLogoUrl,
    this.size,
  });

  final String symbol;
  final String? tokenLogoUrl;
  final String chainSymbol;
  final String? chainLogoUrl;

  /// 主图标尺寸，默认 40，链徽标按 2/5 等比缩放。
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final side = size ?? 40.s;
    final badge = side * 0.4;
    return SizedBox(
      width: side,
      height: side,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          TokenIcon(symbol: symbol, logoUrl: tokenLogoUrl, size: side),
          // 右下角链徽标：包一圈背景色描边，与主图标视觉分离。
          Positioned(
            right: -2.s,
            bottom: -2.s,
            child: Container(
              padding: EdgeInsets.all(1.5.s),
              decoration: BoxDecoration(color: theme.colorScheme.surface, shape: BoxShape.circle),
              child: TokenIcon(symbol: chainSymbol, logoUrl: chainLogoUrl, size: badge),
            ),
          ),
        ],
      ),
    );
  }
}
