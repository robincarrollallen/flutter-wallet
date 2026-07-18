import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../i18n/translations.g.dart';
import '../hot_term_list.dart';
import '../pill/state.dart';
import '../search_hint.dart';
import 'logic.dart';
import 'state.dart';

/// Dapp Tab：空词展示热门 Dapp（占位），输入关键词后显示结果（暂无数据源）。
class DappTabView extends ConsumerWidget {
  const DappTabView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final isEmptyQuery = ref.watch(searchQueryProvider).trim().isEmpty;
    final results = ref.watch(dappResultsProvider);

    if (isEmptyQuery) return HotTermList(terms: DappSearchLogic.hotItems());
    if (results.isEmpty) return SearchHint(text: t.search.noResult);
    // TODO: 接入 Dapp 检索数据源后在此渲染结果列表。
    return const SizedBox.shrink();
  }
}
