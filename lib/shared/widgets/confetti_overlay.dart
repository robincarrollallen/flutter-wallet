import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 纯自绘的礼花效果：零依赖，铺满父容器。
/// 进入成功页时播放一次，从顶部两侧抛洒彩色纸屑后下落淡出。
class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({
    super.key,
    this.pieces = 80,
    this.duration = const Duration(milliseconds: 2600),
  });

  /// 纸屑数量。
  final int pieces;

  /// 单次播放时长。
  final Duration duration;

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration)..forward();

  late final List<_Piece> _pieces = _buildPieces();

  // 用固定种子，避免依赖被禁用的 Math.random 之外还能稳定复现布局。
  List<_Piece> _buildPieces() {
    final rnd = math.Random(42);
    const colors = [
      Color(0xFFE53935),
      Color(0xFF8E24AA),
      Color(0xFF3949AB),
      Color(0xFF00ACC1),
      Color(0xFF43A047),
      Color(0xFFFDD835),
      Color(0xFFFB8C00),
      Color(0xFFEC407A),
    ];
    return List.generate(widget.pieces, (i) {
      return _Piece(
        // 起点横向分布在全宽，纵向略高于顶部。
        startX: rnd.nextDouble(),
        startY: -0.1 - rnd.nextDouble() * 0.15,
        // 水平漂移与下落幅度。
        driftX: (rnd.nextDouble() - 0.5) * 0.6,
        fallY: 0.9 + rnd.nextDouble() * 0.4,
        color: colors[i % colors.length],
        size: 6.0 + rnd.nextDouble() * 8.0,
        rotations: (rnd.nextDouble() - 0.5) * 8,
        delay: rnd.nextDouble() * 0.25,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_pieces, _controller.value),
        ),
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.startX,
    required this.startY,
    required this.driftX,
    required this.fallY,
    required this.color,
    required this.size,
    required this.rotations,
    required this.delay,
  });

  final double startX; // 0..1，相对宽度
  final double startY; // 相对高度
  final double driftX;
  final double fallY;
  final Color color;
  final double size;
  final double rotations;
  final double delay; // 0..1，起始延迟占比
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.progress);

  final List<_Piece> pieces;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in pieces) {
      // 按各自延迟把整体进度归一化到 0..1。
      final t = ((progress - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;

      // 重力感：下落随时间加速。
      final eased = t * t;
      final x = (p.startX + p.driftX * t) * size.width;
      final y = (p.startY + p.fallY * eased) * size.height;

      // 尾段淡出。
      final opacity = (1.0 - t).clamp(0.0, 1.0);
      paint.color = p.color.withValues(alpha: opacity);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotations * t * math.pi);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.55,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}
