import 'package:flutter/material.dart';

import '../../../../../../core/responsive/screen_adapter.dart';

/// 面板内子页的统一脚手架：顶部头部（可选返回箭头 + 标题 + 关闭）+ 内容。
/// 不套 Scaffold，背景透明，靠外层面板 Container 提供底色，保留圆角。
class PanelPage extends StatelessWidget {
  const PanelPage({
    super.key,
    required this.title,
    required this.child,
    this.showBack = false,
  });

  final String title;
  final Widget child;

  /// true=显示返回箭头（嵌套 pop 回上一页）；false=列表根页只显示关闭。
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 不透明 surface 背景：滑入时像卡片盖住下层页面，而非透明的纯文字飘入。
    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              !!showBack
              ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(), // 嵌套 pop：回到面板内上一页（如钱包列表）
              )
              : SizedBox(width: 12.s),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: '关闭',
                // 关到首页：pop 根 Navigator（整个面板路由）。
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(),
              ),
            ],
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
