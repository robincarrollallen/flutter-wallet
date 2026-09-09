import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 分层守卫：services 层不认识状态管理，也不反向依赖 providers。
///
/// 依赖方向只能是 providers → services → data。service 需要读写状态时，
/// 在 services 层定义端口（如 `WalletRegistry`）、由 providers 层提供实现；
/// service 的组装一律放在 `lib/providers/service_provider.dart`。
void main() {
  test('lib/services 下不出现 Riverpod 与 providers 层依赖', () {
    final offenders = <String>[];

    for (final entity in Directory('lib/services').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('flutter_riverpod')) {
        offenders.add('${entity.path}：import 了 flutter_riverpod');
      }
      if (source.contains("'../providers/") || source.contains("'../../providers/")) {
        offenders.add('${entity.path}：import 了 providers 层');
      }
    }

    expect(offenders, isEmpty, reason: '违反分层：\n${offenders.join('\n')}');
  });
}
