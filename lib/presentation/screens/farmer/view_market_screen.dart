import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/farmer_market_rate_model.dart';
import '../../../data/repositories/farmer_market_rates_repository.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/price_display_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../../data/services/market_types_service.dart';
import '../../widgets/shared_widgets.dart';

/// Farmer → Market Rates: the cooperative's reference prices for BOTH markets
/// (Public and Cooperative). Laid out like Buyer → Prices (summary header, crops
/// grouped by category, the same card), except that a tap opens the Market Rate
/// Details screen, which carries the price trend.
class ViewMarketScreen extends StatefulWidget {
  const ViewMarketScreen({super.key});

  @override
  State<ViewMarketScreen> createState() => _ViewMarketScreenState();
}

class _ViewMarketScreenState extends State<ViewMarketScreen> {
  final _ratesRepo = FarmerMarketRatesRepository();
  final _searchController = TextEditingController();

  List<FarmerMarketRateModel> _rates = [];
  bool _isLoading = true;
  bool _isOnline = true;

  // ─── Active filters ─────────────────────────────────────────────────────
  // Both are applied to the list already loaded, so changing a chip or typing
  // never waits on the network. null = All markets.
  String? _marketType;

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
    final rates = await _ratesRepo.fetchMarketRates();
    if (!mounted) return;
    setState(() {
      _rates = rates;
      _isLoading = false;
    });
  }

  List<FarmerMarketRateModel> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    final list = _rates.where((r) {
      if (_marketType != null && r.priceType != _marketType) return false;
      if (query.isNotEmpty && !r.cropName.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();
    list.sort((a, b) {
      final byName = a.cropName.toLowerCase().compareTo(
        b.cropName.toLowerCase(),
      );
      return byName != 0 ? byName : a.priceType.compareTo(b.priceType);
    });
    return list;
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() => _marketType = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 72),
              CachedDataNotice(
                screen: FarmerMarketRatesRepository.cacheScreen(),
                isOnline: _isOnline,
                offlineMessage: l10n.farmerDashOfflineBanner,
              ),
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
    );
  }

  Widget _buildSearchRow(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingSafeH,
        8,
        AppConstants.spacingSafeH,
        0,
      ),
      child: AppTextField(
        controller: _searchController,
        label: l10n.buyerPriceSearchLabel,
        hint: l10n.buyerPriceSearchHint,
        prefixIcon: Icons.search,
      ),
    );
  }

  // One row of separate chips that scrolls sideways when they do not all fit.
  // The side padding is inside the list, so the chips scroll edge to edge
  // while the first one still lines up with the search field.
  Widget _buildMarketTypeChips(AppLocalizations l10n) {
    final types = <String?>[
      null,
      ...MarketTypes.instance.activeTypes.map((t) => t.code),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingSafeH,
          ),
          itemCount: types.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final type = types[index];
            return Center(
              child: _MarketChip(
                label: type == null
                    ? l10n.buyerPriceFilterAll
                    : MarketTypeDisplay.label(l10n, type),
                color: type == null
                    ? AppConstants.primaryGreen
                    : MarketTypeDisplay.color(context, type),
                selected: _marketType == type,
                onTap: () => setState(() => _marketType = type),
              ),
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
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: flatCardDecoration(context),
            child: const SkeletonBlock(width: double.infinity, height: 64),
          ),
        ),
      );
    }

    if (_rates.isEmpty) {
      return _EmptyState(
        icon: Icons.trending_up_rounded,
        message: l10n.farmerDashNoMarketPrices,
      );
    }

    final filtered = _filtered;
    if (filtered.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off_rounded,
        message: l10n.farmerViewMarketNoResults,
        actionLabel: l10n.buyerPriceClearFilters,
        onAction: _clearFilters,
      );
    }

    final groups = groupPricesByCategory<FarmerMarketRateModel>(
      filtered,
      // The model falls back to the English word 'Other' for a crop with no
      // category; hand that to the grouping as "no category" so it is
      // labelled in the app's language and listed last.
      (r) => r.cropCategory == 'Other' ? null : r.cropCategory,
      l10n.buyerPriceCategoryOther,
    );
    final markets = filtered.map((r) => r.priceType).toSet();
    final singleMarket = markets.length == 1 ? markets.first : null;
    final newest = filtered
        .map((r) => r.recordedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    return RefreshIndicator(
      color: AppConstants.primaryGreen,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingSafeH,
          8,
          AppConstants.spacingSafeH,
          40,
        ),
        children: [
          PriceMarketHeader(
            title: singleMarket != null
                ? l10n.buyerPriceHeaderTitle(
                    MarketTypes.instance.label(singleMarket),
                  )
                : l10n.farmerDashMarketRates,
            subtitle: l10n.buyerPriceHeaderSubtitle,
            cropCount: filtered.length,
            updated: AppUtils.formatRelativeTime(newest, l10n),
            accent: singleMarket != null
                ? MarketTypeDisplay.color(context, singleMarket)
                : AppConstants.primaryGreen,
          ),
          for (final group in groups) ...[
            const SizedBox(height: 20),
            PriceCategoryHeader(title: group.key, count: group.value.length),
            const SizedBox(height: 10),
            for (int i = 0; i < group.value.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _MarketRateCard(
                rate: group.value[i],
                // The header already names the market when only one is shown.
                showMarketBadge: singleMarket == null,
                onTap: () => context.pushRoute(
                  AppRoutes.marketRateDetails,
                  extra: group.value[i],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pieces
// ─────────────────────────────────────────────────────────────────────────────

class _MarketChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _MarketChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
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
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.outline.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.primaryGreen,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Same card as Buyer → Prices (image, name, freshness, price with its change),
/// plus the market badge when both markets are listed together, and a chevron
/// because a tap opens the details screen rather than expanding in place.
class _MarketRateCard extends StatelessWidget {
  final FarmerMarketRateModel rate;
  final bool showMarketBadge;
  final VoidCallback onTap;

  const _MarketRateCard({
    required this.rate,
    required this.showMarketBadge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final color = MarketTypeDisplay.color(context, rate.priceType);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: flatCardDecoration(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PriceCropThumb(imageUrl: rate.cropImageUrl, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rate.cropName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  if (showMarketBadge) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull,
                        ),
                      ),
                      child: Text(
                        MarketTypeDisplay.label(l10n, rate.priceType),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    l10n.priceUpdatedPrefix(
                      AppUtils.formatRelativeTime(rate.recordedAt, l10n),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            PriceAmountColumn(price: rate.price),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, color: cs.outline, size: 22),
          ],
        ),
      ),
    );
  }
}
