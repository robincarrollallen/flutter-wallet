import 'package:flutter/material.dart';
// ContentSensitivity 在 services 里，SensitiveContent 在 widgets（由 material 转出）。
import 'package:flutter/services.dart' show ContentSensitivity;

import '../core/responsive/screen_adapter.dart';

/// 包住私钥 / 助记词这类明文，尽可能减少它被旁路截取的机会。
///
/// 叠了两层，各自覆盖不同的泄漏路径，**缺一不可**：
///
/// 1. **框架的 [SensitiveContent]**（Flutter 自带）：把这棵子树标记为敏感内容，
///    系统在屏幕共享 / 录屏时自动打码。只在 **Android 15（API 35）及以上**生效，
///    iOS 与更低版本上是空操作——所以它不能单独使用。
///
/// 2. **离开前台时遮罩**（本组件自己做）：系统在 App 切后台的瞬间会截一张图放进
///    应用切换器，那张图会把屏幕上的助记词一并留下，任何拿到设备的人按一下 Home
///    就能看见。这一层在所有平台都生效，正好补上第 1 层够不着的地方。
///
/// **两层都不是保证。** 第 1 层挡不住普通截屏（它针对的是 media projection），
/// 第 2 层能否赶在系统取缩略图之前完成重绘取决于时序。真正彻底的截屏拦截要走原生
/// （Android 的 `FLAG_SECURE`；iOS 没有等价开关，只能监听 `UIScreen.isCaptured`），
/// 那是另一件需要真机验证的事。这里做的是把成本低、收益确定的部分先拿到手。
class SecretGuard extends StatefulWidget {
  const SecretGuard({super.key, required this.child});

  final Widget child;

  @override
  State<SecretGuard> createState() => _SecretGuardState();
}

class _SecretGuardState extends State<SecretGuard> with WidgetsBindingObserver {
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 只有 resumed 才算安全。inactive 是 iOS 上「即将进入后台 / 正在被截图」
    // 的那一刻，也正是系统取缩略图的时机，必须一并遮住。
    final obscured = state != AppLifecycleState.resumed;
    if (obscured != _obscured) setState(() => _obscured = obscured);
  }

  @override
  Widget build(BuildContext context) {
    return SensitiveContent(
      sensitivity: ContentSensitivity.sensitive,
      child: _obscured ? _mask(context) : widget.child,
    );
  }

  Widget _mask(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        // 保留原内容占位，避免遮罩前后布局尺寸跳动。
        Opacity(opacity: 0, child: widget.child),
        Positioned.fill(
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8.s),
            ),
            child: Icon(Icons.visibility_off_outlined, size: 24.s, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
