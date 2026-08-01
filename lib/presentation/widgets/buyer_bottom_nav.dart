import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/animations/app_animations.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import 'animated_pressable.dart';
import 'web_safe_blur_container.dart';

/// Shared animated bottom navigation for the buyer shell.
///
/// Built on WebSafeBlurContainer rather than mirroring FarmerBottomNav's
/// raw ClipRect+BackdropFilter — WebSafeBlurContainer is the established
/// convention for every new nav/top bar going forward. Kept as its own
/// file rather than a shared AppBottomNav: Farmer (5 items), Admin
/// (5 items), and Buyer (4 items) differ in count and are expected to
/// keep evolving independently — extraction can happen later on a
/// genuine third-use trigger, not preemptively.
class BuyerBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BuyerBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final items = [
      _NavItem(
        icon: Icons.storefront_outlined,
        activeIcon: Icons.storefront_rounded,
        label: l10n.buyerNavBrowse,
      ),
      _NavItem(
        icon: Icons.receipt_long_outlined,
        activeIcon: Icons.receipt_long_rounded,
        label: l10n.buyerNavOrders,
      ),
      _NavItem(
        icon: Icons.trending_up_rounded,
        activeIcon: Icons.trending_up_rounded,
        label: l10n.buyerNavPrices,
      ),
      _NavItem(
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: l10n.buyerNavAccount,
      ),
    ];

    return WebSafeBlurContainer(
      decoration: BoxDecoration(
        color: sagana.navBarBackground,
        border: Border(top: BorderSide(color: sagana.glassBorder)),
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
                              ScaleTransition(scale: animation, child: child),
                          child: Icon(
                            isActive ? item.activeIcon : item.icon,
                            key: ValueKey('$index-$isActive'),
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
                            fontWeight:
                                isActive ? FontWeight.w700 : FontWeight.w400,
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
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
