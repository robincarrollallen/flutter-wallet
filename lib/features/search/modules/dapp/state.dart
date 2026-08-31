import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pill/logic.dart';
import '../pill/state.dart';
import 'logic.dart';

/// Dapp Tab 检索结果（占位）：随关键词重算，当前恒为空。
final dappResultsProvider = Provider.autoDispose<List<Object>>((ref) {
  final q = normalizeQuery(ref.watch(searchQueryProvider));
  return DappSearchLogic.match(q);
});
