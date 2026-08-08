import 'package:flutter/material.dart';

/// 面板内子页转场：横向滑入，体现「面板内切换」。
/// 被新页覆盖时（secondaryAnimation 0→1）淡出下层旧页，
/// 避免子页背景透明时新旧内容重叠。
Route<T> panelSlideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return _coveredFade(
        secondaryAnimation,
        FadeTransition(
          // 新页渐显：滑到一半即完全不透明，避免滑入早期与下层旧页串字，
          // 又不让文字在整段滑动中发虚。
          opacity: CurvedAnimation(parent: animation, curve: const Interval(0.0, 0.5)),
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

/// 面板根页（钱包列表）路由：无进入动画，但被子页覆盖时同样淡出，
/// 与 [panelSlideRoute] 保持一致，避免列表与透明子页重叠。
Route<T> panelRootRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, _, secondaryAnimation, child) => _coveredFade(secondaryAnimation, child),
  );
}

/// 当本页被新页覆盖（secondaryAnimation 0→1）时，让其 opacity 1→0 淡出。
Widget _coveredFade(Animation<double> secondaryAnimation, Widget child) {
  return FadeTransition(opacity: Tween<double>(begin: 1, end: 0).animate(secondaryAnimation), child: child);
}
