import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/screen_adapter.dart';
import 'pill/state.dart';

/// 热门词列表（合约 / Dapp 等无结构化数据的 Tab 共用）：
/// 点击某项即以其文本发起搜索。
class HotTermList extends ConsumerWidget {
  const HotTermList({super.key, required this.terms});

  final List<String> terms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: EdgeInsets.all(8.s),
      children: [
        for (final term in terms)
          ListTile(
            leading: const Icon(Icons.local_fire_department_outlined),
            title: Text(term),
            onTap: () => ref.read(searchQueryProvider.notifier).update(term),
          ),
      ],
    );
  }
}
