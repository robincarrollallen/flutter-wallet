import 'package:flutter/material.dart';

import '../core/responsive/screen_adapter.dart';
import '../enums/toast_position.dart';

/// 全局轻提示：基于 [Overlay] 实现，可指定显示位置（默认顶部），
/// 自动消失、淡入 + 轻微位移动画，连续调用会替换上一条。
///
/// 用法：`AppToast.show(context, '备份完成');`
/// 指定位置：`AppToast.show(context, '已复制', position: ToastPosition.center);`
class AppToast {
  AppToast._();

  /// 当前显示中的提示，用于连续调用时先移除旧的，避免堆叠。
  static OverlayEntry? _current;

  static void show(
    BuildContext context,
    String message, {
    ToastPosition position = ToastPosition.top,
    Duration duration = const Duration(seconds: 2),
  }) {
    // 用根 Overlay <rootOverlay>(局部 Overlay 里被上层弹窗盖住)
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _dismiss();

    final entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        message: message,
        position: position,
        duration: duration,
        // 动画退场结束后由自身回调移除，确保淡出可见。
        onDismissed: _dismiss,
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  /// 立即移除当前提示（若有）。
  static void _dismiss() {
    _current?.remove();
    _current = null;
  }
}

/// Toast 视图：负责进出场动画与定位，到时间后触发 [onDismissed]。
class _ToastWidget extends StatefulWidget {
  const _ToastWidget({
    required this.message,
    required this.position,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final ToastPosition position;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    // 展示时长结束后反向播放退场动画，结束再从 Overlay 移除。
    Future.delayed(widget.duration, _startExit);
  }

  Future<void> _startExit() async {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    // 顶部从上方滑入，底部从下方滑入，居中则纯淡入。
    final beginOffset = switch (widget.position) {
      ToastPosition.top => const Offset(0, -0.2),
      ToastPosition.bottom => const Offset(0, 0.2),
      ToastPosition.center => Offset.zero,
    };

    final card = FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: Tween<Offset>(begin: beginOffset, end: Offset.zero).animate(_opacity),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16.s, vertical: 12.s),
          decoration: BoxDecoration(color: theme.colorScheme.inverseSurface, borderRadius: BorderRadius.circular(10.s)),
          child: Text(
            widget.message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onInverseSurface),
          ),
        ),
      ),
    );

    // 不拦截点击（IgnorePointer），提示期间用户仍可操作界面。
    return IgnorePointer(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.s),
        child: switch (widget.position) {
          ToastPosition.top => Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: media.padding.top + 12.s),
              child: card,
            ),
          ),
          ToastPosition.center => Center(child: card),
          ToastPosition.bottom => Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: media.padding.bottom + 24.s),
              child: card,
            ),
          ),
        },
      ),
    );
  }
}
