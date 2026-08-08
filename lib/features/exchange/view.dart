import 'package:flutter/material.dart';

import '../../i18n/translations.g.dart';

/// 兑换 tab：占位页，后续逐步实现真实兑换功能。
class ExchangeScreen extends StatelessWidget {
  const ExchangeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      appBar: AppBar(backgroundColor: Theme.of(context).colorScheme.inversePrimary, title: Text(t.tabs.exchange)),
      body: Center(child: Text(t.placeholder.wip)),
    );
  }
}
