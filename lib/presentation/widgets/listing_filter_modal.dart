import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/repositories/admin_listing_repository.dart';
import '../../data/repositories/category_repository.dart';
import 'management_modal.dart';

/// Localized label for an [AdminListingModel] status — kept here rather
/// than on the repository model (which has no BuildContext) so every
/// screen that shows a listing's status shares one translation instead of
/// AdminListingModel.statusLabel's hardcoded English.
String listingStatusLabel(AppLocalizations l10n, String status) {
  switch (status) {
    case 'pending_review':
      return l10n.buyerOrderDetailPendingTimestamp;
    case 'approved':
      return l10n.marketplaceFilterLive;
    case 'changes_required':
      return l10n.marketplaceChangesRequired;
    case 'sold':
      return l10n.marketplaceFilterSold;
    case 'rejected':
      return l10n.farmerMgmtStatusRejectedLabel;
    default:
      return status;
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
              child: CircularProgressIndicator(strokeWidth: 2),
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
              child: CircularProgressIndicator(strokeWidth: 2),
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

/// Color-coded chip used for the applied-filter summary row on the
/// screen itself (outside the modal). Matches pending_approvals_screen.dart's
/// original _FilterChip exactly (no count badge). all_listings_screen.dart's
/// own status chip has an extra count badge this shared version does not
/// support, so that screen intentionally keeps its own local _FilterChip
/// rather than using this one — see M-10 divergence note.
class ListingStatusFilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final ColorScheme cs;

  const ListingStatusFilterChip({
    super.key,
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Colors.white : cs.onSurface,
          ),
        ),
      ),
    );
  }
}
