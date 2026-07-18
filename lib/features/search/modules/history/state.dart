import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/persistent_notifier.dart';
import 'logic.dart';

/// 搜索历史：最近搜索词，持久化到 SharedPreferences（去重置顶、有上限）。
class SearchHistoryNotifier extends Notifier<List<String>>
    with PersistentNotifier<List<String>> {
  @override
  List<String> build() => restore(const []);

  @override
  String get persistKey => 'search.history';

  @override
  Map<String, dynamic> toJson(List<String> state) => {'items': state};

  @override
  List<String> fromJson(Map<String, dynamic> json, List<String> fallback) {
    final raw = json['items'];
    if (raw is! List) return fallback;
    return raw.whereType<String>().toList(growable: false);
  }

  /// 记录一次搜索（去重置顶、截断上限）。
  void add(String term) => state = mergeHistory(state, term);

  /// 删除单条。
  void remove(String term) =>
      state = state.where((e) => e != term).toList(growable: false);

  /// 清空全部。
  void clear() => state = const [];
}

final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(
        SearchHistoryNotifier.new);
