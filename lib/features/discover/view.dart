import 'package:flutter/material.dart';

import '../../i18n/translations.g.dart';

/// 发现 tab：占位页，后续逐步实现真实发现功能。
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(t.tabs.discover),
      ),
      body: Center(child: Text(t.placeholder.wip)),
    );
  }
}
