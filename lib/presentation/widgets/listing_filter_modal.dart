import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/repositories/admin_listing_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/services/market_types_service.dart';
import 'management_modal.dart';
import 'skeleton.dart';

/// Small pill naming a listing's market: Public Market (also open to Buyers)
/// or Cooperative Market (farmers and staff only). Renders nothing when the
/// market type is unknown (an offline snapshot from before it was fetched).
class ListingMarketBadge extends StatelessWidget {
  final String? marketType;

  const ListingMarketBadge({super.key, required this.marketType});

  @override
  Widget build(BuildContext context) {
    if (marketType == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final color = MarketTypeDisplay.color(context, marketType!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        MarketTypeDisplay.label(l10n, marketType!),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Market chip row for All Listings: All Markets / Cooperative Market /
/// Public Market, each with how many listings it holds. [value] is null for
/// "All Markets", otherwise a crop_type value. [counts] is listings per
/// crop_type and [total] every listing; filtering is done by the caller on the
/// already-loaded list.
class ListingMarketFilterRow extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final Map<String, int> counts;
  final int total;

  const ListingMarketFilterRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.counts = const {},
    this.total = 0,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return MarketplaceFilterBar<String?>(
      selected: value,
      onSelected: onChanged,
      options: [
        MarketplaceFilterOption<String?>(
          value: null,
          label: l10n.marketplaceFilterAllMarkets,
          count: total,
          color: cs.primary,
        ),
        for (final t in MarketTypes.instance.activeTypes)
          MarketplaceFilterOption<String?>(
            value: t.code,
            label: MarketTypes.instance.label(t.code),
            count: counts[t.code] ?? 0,
            color: MarketTypeDisplay.color(context, t.code),
          ),
      ],
    );
  }
}

// ─── Listing Filter Modal (category → scoped crop list, AND-combined) ─────
// Opened via showManagementModal() as a centered dialog, matching the
// Filter Members reference pattern (header + subtitle, sectioned body,
// Reset All / Apply Filters footer). Shared between Pending Approvals and
// All Listings — was previously duplicated identically in both screens
// (M-10, Admin Marketplace review, Phase 7).
class ListingFilterModal extends StatefulWidget {
  final AdminListingRepository repo;
  final String? initialCategory;
  final String? initialCrop;

  const ListingFilterModal({
    super.key,
    required this.repo,
    this.initialCategory,
    this.initialCrop,
  });

  @override
  State<ListingFilterModal> createState() => _ListingFilterModalState();
}

class _ListingFilterModalState extends State<ListingFilterModal> {
  final CategoryRepository _categoryRepo = CategoryRepository();

  String? _category;
  String? _crop;
  List<String> _crops = [];
  bool _isLoading = true;

  List<String> _categories = [];
  bool _categoriesLoading = true;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _crop = widget.initialCrop;
    _loadCategories();
    _loadCrops();
  }

  // Categories now come from the admin-managed crop_categories lookup
  // table (see CategoryRepository) instead of the previously hardcoded
  // AdminListingRepository.cropCategories list — so a category added in
  // Crop Management (or removed, like the old "Other" catch-all) shows up
  // here automatically, no code change required.
  Future<void> _loadCategories() async {
    final categories = await _categoryRepo.fetchCropCategories();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _categoriesLoading = false;
    });
  }

  Future<void> _loadCrops() async {
    setState(() => _isLoading = true);
    final crops = await widget.repo.fetchCropsByCategory(category: _category);
    if (!mounted) return;
    setState(() {
      _crops = crops;
      // Category change narrows the crop list — drop the previously
      // selected crop if it no longer belongs to the new category.
      if (_crop != null && !_crops.contains(_crop)) _crop = null;
      _isLoading = false;
    });
  }

  void _onCategorySelected(String? category) {
    setState(() => _category = category);
    _loadCrops();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return ManagementModalShell(
      title: l10n.listingFilterTitle,
      subtitle: l10n.buyerPriceFilterPanelSubtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.buyerPriceFilterCategoryLabel,
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 0.6, color: cs.outline)),
          const SizedBox(height: 10),
          if (_categoriesLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SkeletonBlock(height: 36),
            )
          else if (_categories.isEmpty)
            Text(l10n.listingFilterNoCategoriesYet,
                style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              ..._categories.map((c) =>
                  ListingCropFilterChip(label: c, active: _category == c,
                      onTap: () => _onCategorySelected(_category == c ? null : c), cs: cs)),
            ]),
          const SizedBox(height: 20),
          Text(l10n.listingFilterCropsLabel,
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 0.6, color: cs.outline)),
          const SizedBox(height: 10),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SkeletonBlock(height: 36),
            )
          else if (_crops.isEmpty)
            Text(l10n.listingFilterNoCropsInCategory,
                style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              ..._crops.map((c) =>
                  ListingCropFilterChip(label: c, active: _crop == c,
                      onTap: () => setState(() => _crop = _crop == c ? null : c), cs: cs)),
            ]),
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: cs.outline.withValues(alpha: 0.30)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              onPressed: () => Navigator.pop(context, (null, null)),
              child: Text(
                l10n.farmerMgmtResetAll,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, (_category, _crop)),
              child: Text(
                l10n.farmerMgmtApplyFilters,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Generic active/inactive chip used inside the filter modal body
/// (crop category / crop selection). Not to be confused with
/// [ListingStatusFilterChip], which renders the applied-filter summary
/// row on the screen itself.
class ListingCropFilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final ColorScheme cs;

  const ListingCropFilterChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Colors.white : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// The one filter chip of every Marketplace screen (All Listings, Listing
/// Approvals, Order Management, Market Linking, Market Linking Enrollments,
/// Offer to Cooperative). [count], when given, is printed after the label as
/// "Label (n)". Use [MarketplaceFilterBar] to lay a row of them out, so the
/// height, spacing and selected state are the same everywhere.
class ListingStatusFilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final ColorScheme cs;

  /// How many records the chip holds, shown as "Label (n)". Null shows the
  /// label alone.
  final int? count;

  const ListingStatusFilterChip({
    super.key,
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
    required this.cs,
    this.count,
  });

  /// The text on the chip: "Pending (3)".
  String get text => count == null ? label : '$label ($count)';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: text,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active ? color : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            border: Border.all(
              color: active ? color : cs.outline.withValues(alpha: 0.12),
            ),
          ),
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? Colors.white : cs.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

/// One option of a [MarketplaceFilterBar].
class MarketplaceFilterOption<T> {
  final T value;
  final String label;
  final int count;
  final Color color;

  const MarketplaceFilterOption({
    required this.value,
    required this.label,
    required this.count,
    required this.color,
  });
}

/// A horizontally scrolling row of filter chips with their record counts. The
/// same row, height, spacing and selected state on every Marketplace screen.
/// [selected] is compared with each option's value, so "All" is just an option
/// whose value is null (or an enum's `all`). The caller computes the counts
/// from the records it loaded, so they follow the database, not a constant.
class MarketplaceFilterBar<T> extends StatelessWidget {
  final List<MarketplaceFilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  /// Side padding, for screens whose list is not already padded.
  final EdgeInsetsGeometry padding;

  const MarketplaceFilterBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 34,
      child: ListView.separated(
        padding: padding,
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final o = options[i];
          return ListingStatusFilterChip(
            label: o.label,
            count: o.count,
            active: o.value == selected,
            color: o.color,
            onTap: () => onSelected(o.value),
            cs: cs,
          );
        },
      ),
    );
  }
}
