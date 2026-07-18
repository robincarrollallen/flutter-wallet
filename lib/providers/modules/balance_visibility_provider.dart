import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../persistent_notifier.dart';

/// 全局金额隐私开关：true=隐藏所有法币金额与代币数量（显示为掩码）。
/// 只持久化「是否隐藏」；掩码符号与长度不入缓存（由展示端 AmountText 决定）。
class BalanceHiddenNotifier extends Notifier<bool>
    with PersistentNotifier<bool> {
  @override
  String get persistKey => 'balance_hidden';

  @override
  Map<String, dynamic> toJson(bool state) => {'hidden': state};

  @override
  bool fromJson(Map<String, dynamic> json, bool fallback) =>
      json['hidden'] as bool? ?? fallback;

  @override
  bool build() => restore(false);

  void toggle() => state = !state; // 自动落盘
}

final balanceHiddenProvider = NotifierProvider<BalanceHiddenNotifier, bool>(
  BalanceHiddenNotifier.new,
);
