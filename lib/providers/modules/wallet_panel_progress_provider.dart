import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 钱包管理面板展开进度：0=关闭(首页正常) → 1=展开(首页缩小)。
/// 由 WalletManagementScreen 写入，HomeScreen 监听做缩放 + 圆角。
final walletPanelProgressProvider = Provider<ValueNotifier<double>>((ref) {
  final notifier = ValueNotifier<double>(0);
  ref.onDispose(notifier.dispose);
  return notifier;
});
