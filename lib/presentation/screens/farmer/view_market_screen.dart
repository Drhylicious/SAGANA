import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/farmer_market_rate_model.dart';
import '../../../data/repositories/farmer_market_rates_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';

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
  String? _marketType; // price_type chip: All / Cooperative Market / Public Market

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
    final rates = await _ratesRepo.fetchMarketRates(
      marketType: _marketType,
      searchQuery: _searchController.text.trim().isEmpty
          ? null
          : _searchController.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _rates = rates;
      _isLoading = false;
    });
  }

  void _setMarketType(String? type) {
    setState(() => _marketType = type);
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
      child: AppTextField(
        controller: _searchController,
        label: l10n.buyerPriceSearchLabel,
        hint: l10n.buyerPriceSearchHint,
        prefixIcon: Icons.search,
        onChanged: (_) => _load(),
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
    final cs = Theme.of(context).colorScheme;
    final color = MarketTypeDisplay.color(context, rate.priceType);
    final imageUrl = rate.cropImageUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: flatCardDecoration(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Same crop image Crop Management/Price Management show —
            // referenced only, never uploaded from here. Sized to match
            // Admin All Listings' thumbnail so the crop is clearly
            // recognizable, not a cramped icon-sized square.
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: SizedBox(
                width: 72,
                height: 72,
                child: hasImage
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: color.withValues(alpha: 0.12),
                          child: Icon(Icons.eco_outlined, size: 28, color: color),
                        ),
                      )
                    : Container(
                        color: color.withValues(alpha: 0.12),
                        child: Icon(Icons.eco_outlined, size: 28, color: color),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          rate.cropName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppConstants.charcoal,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                        ),
                        child: Text(
                          MarketTypeDisplay.label(l10n, rate.priceType),
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.priceUpdatedPrefix(AppUtils.formatRelativeTime(rate.recordedAt, l10n)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppConstants.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    rate.formattedPrice,
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppConstants.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: cs.outline, size: 20),
          ],
        ),
      ),
    );
  }
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
