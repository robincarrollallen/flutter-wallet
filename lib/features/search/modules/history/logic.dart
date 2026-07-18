// 搜索历史纯逻辑：与状态/UI 无关，便于单测与复用。

/// 历史记录默认上限。
const int kSearchHistoryMax = 10;

/// 规整搜索词：去首尾空白（保留大小写，便于原样回显）。
String normalizeTerm(String raw) => raw.trim();

/// 把新词并入历史：去重置顶 + 截断到 [max]。空词返回原列表。
List<String> mergeHistory(List<String> old, String term, {int max = kSearchHistoryMax}) {
  final t = normalizeTerm(term);
  if (t.isEmpty) return old;
  return [
    t,
    for (final e in old)
      if (e.toLowerCase() != t.toLowerCase()) e,
  ].take(max).toList(growable: false);
}
