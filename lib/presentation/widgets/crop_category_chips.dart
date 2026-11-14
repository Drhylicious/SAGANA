import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/localized_labels.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import 'listing_filter_modal.dart'
    show MarketplaceFilterBar, MarketplaceFilterOption;

// ─────────────────────────────────────────────────────────────────────────────
// Crop Category Chips
// Shared "All + live categories" filter row, reused across Record New
// Harvest, Crop Roster, and Harvest History — one implementation instead of
// three, so the three screens can never visually or behaviorally drift apart.
//
// The row itself is the shared MarketplaceFilterBar: the same "Label (n)"
// chip, height, spacing and selected state the Manager / Officer screens and
// the Farmer's Manage Inventory use, so every filter row in the app looks and
// behaves the same.
//
// Deliberately stateless: [categories] and [counts] are supplied by the
// caller, which already holds the records it loaded, so the numbers always
// follow what is on the screen. "All" is prepended internally so every call
// site shares one literal string instead of three independently-typed copies.
//
// Source of the category list: the caller's own loaded crops / harvests (each
// carries its category from the admin-managed crop_categories table).
// ─────────────────────────────────────────────────────────────────────────────

class CropCategoryChips extends StatelessWidget {
  static const String all = 'All';

  final List<String> categories;
  final String active;
  final ValueChanged<String> onSelected;

  /// How many records each chip holds, keyed by category, with [all] for the
  /// total. Shown as "Label (n)". A category missing from the map shows 0.
  final Map<String, int> counts;

  const CropCategoryChips({
    super.key,
    required this.categories,
    required this.active,
    required this.onSelected,
    required this.counts,
  });

  /// The counts for a list of records: one per category plus the total.
  static Map<String, int> countBy<T>(
    Iterable<T> items,
    String Function(T item) categoryOf,
  ) {
    final out = <String, int>{all: 0};
    for (final item in items) {
      out[all] = out[all]! + 1;
      final category = categoryOf(item);
      out[category] = (out[category] ?? 0) + 1;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MarketplaceFilterBar<String>(
      selected: active,
      onSelected: onSelected,
      options: [
        for (final category in [all, ...categories])
          MarketplaceFilterOption(
            value: category,
            label: localizeBuiltinLabel(l10n, category),
            count: counts[category] ?? 0,
            color: AppConstants.primaryGreen,
          ),
      ],
    );
  }
}
