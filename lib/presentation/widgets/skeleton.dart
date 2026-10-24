import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';

/// Animated placeholder shown while content loads. Use in place of a spinner
/// wherever the final layout is known (lists, cards, dashboard sections).
class SkeletonBlock extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;

  const SkeletonBlock({
    super.key,
    required this.height,
    this.width,
    this.radius = 16,
  });

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final highlight = Theme.of(context).colorScheme.surface;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * t, 0),
              end: Alignment(1.0 + 2.0 * t, 0),
              colors: [base, highlight, base],
              stops: const [0.3, 0.5, 0.7],
            ),
          ),
        );
      },
    );
  }
}

/// A stacked set of skeleton rows, for list screens while the first page loads.
class SkeletonList extends StatelessWidget {
  final int count;
  final double rowHeight;
  final double spacing;

  const SkeletonList({
    super.key,
    this.count = 4,
    this.rowHeight = 88,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // In a bounded slot (a short card, a header area) draw only the rows
        // that fit, instead of overflowing it. Unbounded slots keep all rows.
        var rows = count;
        if (constraints.hasBoundedHeight) {
          final fit = ((constraints.maxHeight + spacing) / (rowHeight + spacing)).floor();
          rows = fit.clamp(0, count);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows; i++) ...[
              SkeletonBlock(height: rowHeight, radius: AppConstants.radiusLg),
              if (i < rows - 1) SizedBox(height: spacing),
            ],
          ],
        );
      },
    );
  }
}
