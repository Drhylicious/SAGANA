import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/sagana_colors.dart';

/// The ONE filter button of the app: a square "tune" icon that sits beside a search bar.
/// A dot shows that a filter other than the default is applied. Members, Order Management and
/// every other list that filters through a modal use this same button.
class FilterIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool active;
  final String semanticLabel;
  final Key? buttonKey;
  final Key? dotKey;

  const FilterIconButton({
    super.key,
    required this.onTap,
    required this.active,
    this.semanticLabel = 'Filter',
    this.buttonKey,
    this.dotKey,
  });

  /// Same height as the search field it sits beside.
  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        key: buttonKey,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: active ? cs.primary.withValues(alpha: 0.10) : sagana.cardBackground,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(
                  color: active ? cs.primary.withValues(alpha: 0.55) : cs.outline.withValues(alpha: 0.25),
                ),
              ),
              child: Icon(
                Icons.tune_rounded,
                size: 22,
                color: active ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            if (active)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  key: dotKey,
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: sagana.cardBackground, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
