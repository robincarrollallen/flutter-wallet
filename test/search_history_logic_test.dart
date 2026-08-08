import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/features/search/modules/history/logic.dart';

void main() {
  group('normalizeTerm', () {
    test('去首尾空白、保留大小写', () {
      expect(normalizeTerm('  ETH  '), 'ETH');
    });
  });

  group('mergeHistory', () {
    test('新词置顶', () {
      expect(mergeHistory(['a', 'b'], 'c'), ['c', 'a', 'b']);
    });

    test('已存在则去重置顶（大小写不敏感）', () {
      expect(mergeHistory(['a', 'b', 'c'], 'B'), ['B', 'a', 'c']);
    });

    test('空词返回原列表', () {
      expect(mergeHistory(['a'], '   '), ['a']);
    });

    test('超过上限被截断', () {
      final old = List.generate(10, (i) => 'w$i');
      final result = mergeHistory(old, 'new', max: 10);
      expect(result.length, 10);
      expect(result.first, 'new');
      expect(result.contains('w9'), isFalse); // 最旧的被挤出
    });
  });
}
