import 'package:flutter/material.dart';

import '../../../../core/responsive/screen_adapter.dart';
import '../../../../i18n/translations.g.dart';

/// 首页「代币」区块头部：左侧标题，右侧配置按钮（功能稍后补）。
class TokenSectionHeader extends StatelessWidget {
  const TokenSectionHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.t;
    return Padding(
      padding: EdgeInsets.fromLTRB(4.s, 8.s, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(t.home.tokens, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: Icon(Icons.tune, size: 22.s),
            tooltip: t.home.manageTokens,
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}
