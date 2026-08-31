import 'package:flutter/material.dart';

import '../../i18n/translations.g.dart';

/// 合约 tab：占位页，后续逐步实现真实合约功能。
class ContractScreen extends StatelessWidget {
  const ContractScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      appBar: AppBar(backgroundColor: Theme.of(context).colorScheme.inversePrimary, title: Text(t.tabs.contract)),
      body: Center(child: Text(t.placeholder.wip)),
    );
  }
}
