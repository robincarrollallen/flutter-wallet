import 'package:flutter/material.dart';

import '../../i18n/translations.g.dart';

/// 市场 tab：占位页，后续逐步实现真实行情功能。
class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(t.tabs.market),
      ),
      body: Center(child: Text(t.placeholder.wip)),
    );
  }
}
