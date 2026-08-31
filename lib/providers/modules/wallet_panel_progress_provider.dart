import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 钱包管理面板展开状态：0=关闭(首页正常) → 1=展开(首页缩小), 由 WalletManagementScreen 写入，HomeScreen 监听做缩放 + 圆角。
final walletPanelProgressProvider = Provider<ValueNotifier<double>>((ref) {
  final notifier = ValueNotifier<double>(0); // 创建一个 ValueNotifier 对象，初始值为 0
  ref.onDispose(notifier.dispose); // 在 Provider 被释放时自动释放 ValueNotifier 占用的资源
  return notifier;
});
