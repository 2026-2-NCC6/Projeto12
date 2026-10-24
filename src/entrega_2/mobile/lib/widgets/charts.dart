import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Anel de progresso / donut. Arco começa no topo (−90°); espessura = 20% do
/// raio externo.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.size,
    required this.fraction,
    this.child,
    this.track = AppColors.bgBrandSoft,
    this.arc = AppColors.bgBrand,
  });

  final double size;
  final double fraction;
  final Widget? child;
  final Color track;
  final Color arc;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(fraction: fraction, track: track, arc: arc),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.track,
    required this.arc,
  });

  final double fraction;
  final Color track;
  final Color arc;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = size.shortestSide / 2;
    final stroke = outer * 0.2;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: outer - stroke / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * fraction.clamp(0, 1),
      false,
      paint
        ..color = arc
        // Anel cheio: sem ponta arredondada (evita o "dente" no topo).
        ..strokeCap = fraction >= 1 ? StrokeCap.butt : StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.track != track || old.arc != arc;
}

/// Arco fino aberto (cronômetro da sessão em andamento).
class ArcPainter extends CustomPainter {
  ArcPainter({required this.color, required this.sweep, this.strokeWidth = 4});

  final Color color;

  /// Abertura do arco, em radianos (começa em −90°).
  final double sweep;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - strokeWidth / 2,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(ArcPainter old) =>
      old.color != color ||
      old.sweep != sweep ||
      old.strokeWidth != strokeWidth;
}

/// Barra tracejada (batidas de calibração ainda não feitas).
class DashedRRectPainter extends CustomPainter {
  DashedRRectPainter({
    required this.color,
    this.strokeWidth = 1.5,
    this.radius = 8,
    this.dash = 4,
    this.gap = 3,
  });

  final Color color;
  final double strokeWidth;
  final double radius;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(strokeWidth / 2),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedRRectPainter old) => old.color != color;
}
