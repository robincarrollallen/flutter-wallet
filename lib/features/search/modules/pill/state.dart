import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 搜索关键词：由搜索输入框写入，各结果 Tab 读取。
/// autoDispose：离开搜索页自动清空，下次进入是干净状态。
final searchQueryProvider =
    NotifierProvider.autoDispose<SearchQueryNotifier, String>(
        SearchQueryNotifier.new);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  /// 输入变化时写入。
  void update(String value) => state = value;

  /// 清空（点击清除按钮）。
  void clear() => state = '';
}
