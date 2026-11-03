import 'package:flutter/material.dart';

/// The SAGANA logo in the top bar of a role's primary screens, followed by a thin
/// divider and then the screen title:
///
///   (logo) | Home
///
/// Shared by the Manager/Officer, Farmer, Buyer and Pending Applicant bars, so the
/// four roles draw it identically. Secondary screens keep their back button.
class SaganaLogoMark extends StatelessWidget {
  /// Opens the Navigation Drawer on the screens that have one.
  final VoidCallback? onTap;

  /// For a bar drawn over a dark background (the Farmer hero screens).
  final bool overlay;

  const SaganaLogoMark({super.key, this.onTap, this.overlay = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.95),
          border: Border.all(
            color: overlay
                ? Colors.white.withValues(alpha: 0.45)
                : cs.outline.withValues(alpha: 0.30),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ClipOval(
          child: Image.asset(
            'assets/images/sagana_icon.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
      ),
    );
  }
}

/// The thin vertical line between the logo and the title, with the same space on
/// both sides (12 px).
class SaganaLogoDivider extends StatelessWidget {
  final bool overlay;
  const SaganaLogoDivider({super.key, this.overlay = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        key: const ValueKey('logo-title-divider'),
        width: 1,
        height: 24,
        color: overlay
            ? Colors.white.withValues(alpha: 0.35)
            : cs.outline.withValues(alpha: 0.35),
      ),
    );
  }
}
