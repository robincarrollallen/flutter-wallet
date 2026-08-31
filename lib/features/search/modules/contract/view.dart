import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../i18n/translations.g.dart';
import '../hot_term_list.dart';
import '../pill/state.dart';
import '../search_hint.dart';
import 'logic.dart';
import 'state.dart';

/// 合约 Tab：空词展示热门合约（占位），输入关键词后显示结果（暂无数据源）。
class ContractTabView extends ConsumerWidget {
  const ContractTabView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final isEmptyQuery = ref.watch(searchQueryProvider).trim().isEmpty;
    final results = ref.watch(contractResultsProvider);

    if (isEmptyQuery) return HotTermList(terms: ContractSearchLogic.hotItems());
    if (results.isEmpty) return SearchHint(text: t.search.noResult);
    // TODO: 接入合约检索数据源后在此渲染结果列表。
    return const SizedBox.shrink();
  }
}
