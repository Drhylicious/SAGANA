import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/sagana_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Crop Category Chips
// Shared "All + live categories" filter row, reused across Record New
// Harvest, Crop Roster, and Harvest History (Farmer-Harvest tab revision
// round, Revision B0) — one implementation instead of three, so the three
// screens can never visually or behaviorally drift apart.
//
// Deliberately stateless: [categories] is supplied by the caller, which
// already has its own top-level loading state and its own Future.wait()-
// based load method (matching every other screen in this codebase) —
// fetching categories there, alongside whatever else that screen already
// loads, avoids a second, nested loading state living inside this widget.
// "All" is prepended internally so every call site shares one literal
// string instead of three independently-typed copies.
//
// Source of the category list: CategoryRepository.fetchCropCategories(),
// which queries the live, admin-managed crop_categories table — so any
// category an admin adds, or that a farmer's crop set gains (directly or
// via crop-request approval), shows up the next time the screen loads,
// with no separate sync step required.
// ─────────────────────────────────────────────────────────────────────────────

class CropCategoryChips extends StatelessWidget {
  static const String all = 'All';

  final List<String> categories;
  final String active;
  final ValueChanged<String> onSelected;

  const CropCategoryChips({
    super.key,
    required this.categories,
    required this.active,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final options = [all, ...categories];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((category) {
          final isActive = category == active;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelected(category),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppConstants.primaryContainer.withValues(alpha: 0.12)
                      : sagana.cardBackground,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  border: isActive
                      ? Border.all(
                          color: AppConstants.primaryContainer.withValues(
                            alpha: 0.30,
                          ),
                        )
                      : null,
                ),
                child: Text(
                  category,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? AppConstants.primaryContainer
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
