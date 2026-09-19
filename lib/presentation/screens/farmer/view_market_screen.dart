import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/farmer_market_rate_model.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/repositories/farmer_market_rates_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/management_modal.dart';

class ViewMarketScreen extends StatefulWidget {
  const ViewMarketScreen({super.key});

  @override
  State<ViewMarketScreen> createState() => _ViewMarketScreenState();
}

class _ViewMarketScreenState extends State<ViewMarketScreen> {
  final _ratesRepo = FarmerMarketRatesRepository();
  final _cropRepo = CropRepository();
  final _searchController = TextEditingController();

  List<FarmerMarketRateModel> _rates = [];
  List<Map<String, dynamic>> _cropCatalog = [];
  bool _isLoading = true;
  bool _isOnline = true;

  // ─── Active filters ─────────────────────────────────────────────────────
  String? _marketType;   // price_type chip — independent of the panel below
  String? _cropCategory; // filter panel
  String? _cropId;       // filter panel

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _ratesRepo.fetchMarketRates(
        marketType: _marketType,
        cropCategory: _cropCategory,
        cropId: _cropId,
        searchQuery: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      ),
      _cropRepo.fetchCropCatalog(),
    ]);
    if (!mounted) return;
    setState(() {
      _rates = results[0] as List<FarmerMarketRateModel>;
      _cropCatalog = results[1] as List<Map<String, dynamic>>;
      _isLoading = false;
    });
  }

  void _setMarketType(String? type) {
    setState(() => _marketType = type);
    _load();
  }

  bool get _hasPanelFilters => _cropCategory != null || _cropId != null;

  Future<void> _openFilterPanel() async {
    final result = await showManagementModal<_FilterResult>(
      context: context,
      builder: (_) => _FilterPanel(
        cropCatalog: _cropCatalog,
        initialCategory: _cropCategory,
        initialCropId: _cropId,
      ),
    );
    if (result == null) return; // dismissed without applying
    setState(() {
      _cropCategory = result.cropCategory;
      _cropId = result.cropId;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Column(
        children: [
          if (!_isOnline)
            OfflineBanner(message: l10n.farmerDashOfflineBanner),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 72),
                    _buildSearchRow(l10n),
                    _buildMarketTypeChips(l10n),
                    const SizedBox(height: 8),
                    Expanded(child: _buildResults(l10n)),
                  ],
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: FarmerTopBar(
                    title: l10n.farmerDashMarketRates,
                    onBack: () => Navigator.of(context).pop(),
                    hideProfileAvatar: true,
                    onProfileTap: () {},
                    onNotificationTap: () {},
                    showNotificationButton: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchRow(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: AppTextField(
              controller: _searchController,
              label: l10n.buyerPriceSearchLabel,
              hint: l10n.buyerPriceSearchHint,
              prefixIcon: Icons.search,
              onChanged: (_) => _load(),
            ),
          ),
          const SizedBox(width: 10),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppConstants.white,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(
                    color: AppConstants.outline.withValues(alpha: 0.5),
                  ),
                ),
                child: IconButton(
                  icon: const Icon(Icons.tune_rounded),
                  color: AppConstants.primaryGreen,
                  onPressed: _openFilterPanel,
                ),
              ),
              if (_hasPanelFilters)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppConstants.errorRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMarketTypeChips(AppLocalizations l10n) {
    const types = [
      null,
      'sp3_cooperative',
      'open_market',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: types.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final type = types[index];
            final selected = _marketType == type;
            final label = type == null ? l10n.buyerPriceFilterAll : MarketTypeDisplay.label(l10n, type);
            final color = type == null
                ? AppConstants.primaryGreen
                : MarketTypeDisplay.color(context, type);
            return ChoiceChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) => _setMarketType(type),
              labelStyle: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : color,
              ),
              selectedColor: color,
              backgroundColor: color.withValues(alpha: 0.10),
              side: BorderSide(color: color.withValues(alpha: 0.3)),
              showCheckmark: false,
            );
          },
        ),
      ),
    );
  }

  Widget _buildResults(AppLocalizations l10n) {
    if (_isLoading) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        itemCount: 5,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: GlassCard(
            padding: EdgeInsets.all(16),
            child: _Shimmer(width: double.infinity, height: 56),
          ),
        ),
      );
    }

    if (_rates.isEmpty) {
      final hasActiveFilter = _marketType != null ||
          _hasPanelFilters ||
          _searchController.text.trim().isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined,
                  size: 40, color: AppConstants.outline),
              const SizedBox(height: 16),
              Text(
                hasActiveFilter
                    ? l10n.farmerViewMarketNoResults
                    : l10n.farmerDashNoMarketPrices,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppConstants.primaryGreen,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        itemCount: _rates.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _MarketRateListTile(
          rate: _rates[index],
          onTap: () => context.pushRoute(
            AppRoutes.marketRateDetails,
            extra: _rates[index],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Result row
// ─────────────────────────────────────────────────────────────────────────────

class _MarketRateListTile extends StatelessWidget {
  final FarmerMarketRateModel rate;
  final VoidCallback onTap;

  const _MarketRateListTile({required this.rate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = MarketTypeDisplay.color(context, rate.priceType);
    final imageUrl = rate.cropImageUrl;
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Same crop image Crop Management/Price Management show —
            // referenced only, never uploaded from here. Falls back to the
            // market-type-colored icon when the crop has none set.
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: 44,
                height: 44,
                color: color.withValues(alpha: 0.12),
                child: (imageUrl != null && imageUrl.isNotEmpty)
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.storefront_outlined, color: color, size: 20),
                      )
                    : Icon(Icons.storefront_outlined, color: color, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rate.cropName,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.charcoal,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${MarketTypeDisplay.label(l10n, rate.priceType)} · ${l10n.priceUpdatedPrefix(AppUtils.formatRelativeTime(rate.recordedAt, l10n))}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppConstants.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              rate.formattedPrice,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppConstants.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter panel — Crop Category + Crop, independent of the Market Type
// chips above, per the earlier terminology decision. Opened via
// showManagementModal() as a centered dialog rather than a bottom sheet.
// ─────────────────────────────────────────────────────────────────────────────

class _FilterResult {
  final String? cropCategory;
  final String? cropId;
  const _FilterResult({this.cropCategory, this.cropId});
}

class _Shimmer extends StatefulWidget {
  final double width;
  final double height;

  const _Shimmer({required this.width, required this.height});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _animation = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: [
              (_animation.value - 1).clamp(0.0, 1.0),
              _animation.value.clamp(0.0, 1.0),
              (_animation.value + 1).clamp(0.0, 1.0),
            ],
            colors: [
              Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.35),
              Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.45),
              Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.35),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPanel extends StatefulWidget {
  final List<Map<String, dynamic>> cropCatalog;
  final String? initialCategory;
  final String? initialCropId;

  const _FilterPanel({
    required this.cropCatalog,
    this.initialCategory,
    this.initialCropId,
  });

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  String? _category;
  String? _cropId;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _cropId = widget.initialCropId;
  }

  List<Map<String, dynamic>> get _cropsForCategory {
    if (_category == null) return widget.cropCatalog;
    return widget.cropCatalog
        .where((c) => c['category'] == _category)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return ManagementModalShell(
      title: l10n.farmerMarketFilterTitle,
      subtitle: l10n.buyerPriceFilterPanelSubtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.buyerPriceFilterCategoryLabel,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: cs.outline,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: {for (final c in widget.cropCatalog) c['category'] as String}
                .toList()
                .map((cat) {
              final selected = _category == cat;
              return _Chip(
                label: cat,
                active: selected,
                cs: cs,
                onTap: () => setState(() {
                  _category = selected ? null : cat;
                  // Dropping the category may orphan a crop selection
                  // that no longer belongs to it — clear it rather
                  // than silently filtering on a mismatched pair.
                  if (_cropId != null &&
                      !_cropsForCategory.any((c) => c['id'] == _cropId)) {
                    _cropId = null;
                  }
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.buyerPriceFilterCropLabel,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: cs.outline,
            ),
          ),
          const SizedBox(height: 10),
          if (_cropsForCategory.isEmpty)
            Text(l10n.listingFilterNoCropsInCategory,
                style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _cropsForCategory.map((c) {
                final cropId = c['id'] as String;
                final selected = _cropId == cropId;
                return _Chip(
                  label: c['crop_name'] as String,
                  active: selected,
                  cs: cs,
                  onTap: () => setState(() => _cropId = selected ? null : cropId),
                );
              }).toList(),
            ),
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
              onPressed: () =>
                  Navigator.of(context).pop(const _FilterResult()),
              child: Text(
                l10n.buyerPriceResetAll,
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
              onPressed: () => Navigator.of(context).pop(
                _FilterResult(cropCategory: _category, cropId: _cropId),
              ),
              child: Text(
                l10n.buyerPriceApplyFilters,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _Chip({
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