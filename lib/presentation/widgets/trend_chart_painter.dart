import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Reusable smoothed line-chart-with-gradient-fill painter, generalized
/// from the CustomPainter originally built for PriceManagementScreen's
/// trend chart (which was hardcoded to PriceRecordModel). This version
/// takes plain values so it works for any admin report's trend line —
/// revenue, harvest volume, loan collections, etc. — while keeping the
/// exact same visual language already established in the app.
class TrendChartPainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  final Color gradientColor;

  const TrendChartPainter({
    required this.values,
    required this.lineColor,
    required this.gradientColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final valueRange = (maxValue - minValue).abs();
    final effectiveRange = valueRange < 1 ? 1.0 : valueRange;
    final padding = effectiveRange * 0.15;

    final lo = minValue - padding;
    final hi = maxValue + padding;
    final range = hi - lo;

    double xAt(int i) => size.width * i / (values.length - 1);
    double yAt(double v) => size.height * (1 - (v - lo) / range);

    final path = Path();
    path.moveTo(xAt(0), yAt(values[0]));
    for (int i = 1; i < values.length; i++) {
      final x0 = xAt(i - 1);
      final y0 = yAt(values[i - 1]);
      final x1 = xAt(i);
      final y1 = yAt(values[i]);
      final cpx = (x0 + x1) / 2;
      path.cubicTo(cpx, y0, cpx, y1, x1, y1);
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            gradientColor.withValues(alpha: 0.20),
            gradientColor.withValues(alpha: 0.00),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant TrendChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gradientColor != gradientColor;
  }
}