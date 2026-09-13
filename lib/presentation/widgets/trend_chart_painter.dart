import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Reusable smoothed line-chart-with-gradient-fill painter, generalized
/// from the CustomPainter originally built for PriceManagementScreen's
/// trend chart (which was hardcoded to PriceRecordModel). This version
/// takes plain values so it works for any admin report's trend line —
/// revenue, harvest volume, loan collections, etc. — while keeping the
/// exact same visual language already established in the app.
///
/// Axis labels (xLabels, yValueFormatter) are optional and backward
/// compatible — a caller that doesn't pass them gets exactly the same
/// bare line-and-fill rendering as before. Callers should only pass
/// xLabels when their trend has a well-defined, stable per-point meaning
/// (e.g. "trailing N months ending now") — a still period-filtered trend
/// (where the same N points can mean different months depending on the
/// selected period) shouldn't be labeled until its own data source is
/// fixed to a stable window, or the labels would misrepresent the data.
class TrendChartPainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  final Color gradientColor;
  final List<String>? xLabels;
  final String Function(double)? yValueFormatter;

  const TrendChartPainter({
    required this.values,
    required this.lineColor,
    required this.gradientColor,
    this.xLabels,
    this.yValueFormatter,
  });

  static const double _yAxisReserve = 34;
  static const double _xAxisReserve = 16;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final hasLabels = xLabels != null && xLabels!.length == values.length;
    final leftInset = hasLabels ? _yAxisReserve : 0.0;
    final bottomInset = hasLabels ? _xAxisReserve : 0.0;
    final plotWidth = size.width - leftInset;
    final plotHeight = size.height - bottomInset;

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final valueRange = (maxValue - minValue).abs();
    final effectiveRange = valueRange < 1 ? 1.0 : valueRange;
    final padding = effectiveRange * 0.15;

    final lo = minValue - padding;
    final hi = maxValue + padding;
    final range = hi - lo;

    double xAt(int i) => leftInset + plotWidth * i / (values.length - 1);
    double yAt(double v) => plotHeight * (1 - (v - lo) / range);

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
      ..lineTo(xAt(values.length - 1), plotHeight)
      ..lineTo(leftInset, plotHeight)
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
        ).createShader(Rect.fromLTWH(leftInset, 0, plotWidth, plotHeight)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    if (!hasLabels) return;

    final format = yValueFormatter ?? (v) => v.toStringAsFixed(0);
    final labelStyle = TextStyle(fontSize: 9, color: lineColor.withValues(alpha: 0.7));

    void drawText(String text, Offset offset, {TextAlign align = TextAlign.left}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: leftInset - 2);
      painter.paint(canvas, offset);
    }

    // Y-axis: max at top, min at bottom, right-aligned within the reserved
    // left gutter.
    drawText(format(maxValue), const Offset(0, 0), align: TextAlign.right);
    drawText(format(minValue), Offset(0, plotHeight - 10), align: TextAlign.right);

    // X-axis: first, middle, and last labels only — a label per point would
    // overcrowd a 6-point trend at typical card widths.
    final xIndices = values.length <= 3
        ? List.generate(values.length, (i) => i)
        : [0, (values.length / 2).floor(), values.length - 1];
    for (final i in xIndices) {
      final painter = TextPainter(
        text: TextSpan(text: xLabels![i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (xAt(i) - painter.width / 2).clamp(leftInset, size.width - painter.width);
      painter.paint(canvas, Offset(x, plotHeight + 2));
    }
  }

  @override
  bool shouldRepaint(covariant TrendChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gradientColor != gradientColor ||
        oldDelegate.xLabels != xLabels;
  }
}