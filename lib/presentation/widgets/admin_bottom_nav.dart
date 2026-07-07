import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/animations/app_animations.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import 'animated_pressable.dart';

/// Shared animated bottom navigation for the admin shell.
/// Mirrors [FarmerBottomNav] exactly — same structure, different tabs.
class AdminBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AdminBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    final items = [
      _NavItem(icon: Icons.dashboard_rounded,    label: l10n.adminNavDashboard),
      _NavItem(icon: Icons.groups_rounded,        label: l10n.adminNavFarmers),
      _NavItem(icon: Icons.storefront_outlined,   label: l10n.adminNavListings),
      _NavItem(icon: Icons.eco_outlined,          label: l10n.adminNavLoans),
      _NavItem(icon: Icons.bar_chart_rounded,     label: l10n.adminNavReports),
    ];

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: sagana.navBarBackground,
            border: Border(
              top: BorderSide(color: sagana.glassBorder),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final isActive = index == currentIndex;

                  return Expanded(
                    child: AnimatedPressable(
                      onTap: () => onTap(index),
                      scaleDown: 0.94,
                      child: AnimatedContainer(
                        duration: AppAnimations.tabSwitch,
                        curve: AppAnimations.easeOut,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppConstants.primaryContainer
                              : Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusMd),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSwitcher(
                              duration: AppAnimations.tabSwitch,
                              transitionBuilder: (child, animation) =>
                                  ScaleTransition(
                                      scale: animation, child: child),
                              child: Icon(
                                item.icon,
                                key: ValueKey('admin-$index-$isActive'),
                                size: 22,
                                color: isActive
                                    ? AppConstants.onPrimaryContainer
                                    : Theme.of(context).colorScheme.outline,
                              ),
                            ),
                            const SizedBox(height: 2),
                            AnimatedDefaultTextStyle(
                              duration: AppAnimations.tabSwitch,
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: isActive
                                    ? AppConstants.onPrimaryContainer
                                    : Theme.of(context).colorScheme.outline,
                              ),
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
