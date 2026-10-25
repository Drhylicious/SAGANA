import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/models/farmer_market_rate_model.dart';
import '../../../data/models/price_record_model.dart';
import '../../../data/repositories/farmer_market_rates_repository.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/price_display_widgets.dart';
import '../../widgets/shared_widgets.dart';
import '../../../data/services/connectivity_service.dart';

/// One crop's reference price in one market: the current price, its price
/// trend, the effective date and source, and the crop's price in the other
/// market (tap it to switch the whole screen, trend included, to that market).
class MarketRateDetailsScreen extends StatefulWidget {
  final FarmerMarketRateModel? rate;

  const MarketRateDetailsScreen({super.key, required this.rate});

  @override
  State<MarketRateDetailsScreen> createState() =>
      _MarketRateDetailsScreenState();
}

class _MarketRateDetailsScreenState extends State<MarketRateDetailsScreen> {
  final _ratesRepo = FarmerMarketRatesRepository();

  // The market currently shown. Starts as the rate that was tapped; tapping the
  // crop's price in another market switches it.
  FarmerMarketRateModel? _rate;

  // Every market this crop is priced in (the current one included), read once,
  // so switching markets needs no second read.
  List<FarmerMarketRateModel> _allRates = [];
  List<FarmerMarketRateModel> _otherRates = [];

  List<PriceRecordModel> _trend = [];
  bool _isTrendLoading = true;
  int _trendRequest = 0;

  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _rate = widget.rate;
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    final rate = _rate;
    if (rate != null) {
      _loadOtherRates(rate);
      _loadTrend(rate);
    }
  }

  Future<void> _loadOtherRates(FarmerMarketRateModel rate) async {
    final rows = await _ratesRepo.fetchMarketRates(cropId: rate.cropId);
    if (!mounted) return;
    _allRates = rows;
    _syncOtherRates();
  }

  void _syncOtherRates() {
    final current = _rate;
    if (current == null) return;
    setState(() {
      _otherRates = _allRates
          .where((r) => r.priceType != current.priceType)
          .toList();
    });
  }

  Future<void> _loadTrend(FarmerMarketRateModel rate) async {
    final request = ++_trendRequest;
    setState(() {
      _isTrendLoading = true;
      _trend = [];
    });
    final trend = await _ratesRepo.fetchTrend(rate.cropId, rate.priceType);
    // A different market may have been picked while this one was loading.
    if (!mounted || request != _trendRequest) return;
    setState(() {
      _trend = trend;
      _isTrendLoading = false;
    });
  }

  void _switchTo(FarmerMarketRateModel other) {
    setState(() => _rate = other);
    _syncOtherRates();
    _loadTrend(other);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rate = _rate;
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          if (rate != null) _buildHeroBackground(context) else const SizedBox(),
          Column(
            children: [
              SizedBox(height: 64 + MediaQuery.of(context).padding.top),
              CachedDataNotice(
                screen: FarmerMarketRatesRepository.cacheScreen(
                  cropId: rate?.cropId,
                ),
                isOnline: _isOnline,
                offlineMessage: l10n.farmerMarketRateOfflineBanner,
              ),
              Expanded(
                child: rate == null
                    ? _buildMissingState(context)
                    : _buildDetails(context, rate),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              overlay: rate != null,
              title: rate?.cropName ?? l10n.farmerMarketRateDetailsTitle,
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

  // Fixed backdrop directly behind the top bar only — sized to exactly
  // match its height (see the SizedBox spacer in build()). The rest of
  // the hero gradient now scrolls together with the card that overlaps
  // it (see _buildDetails) instead of sitting on a second, independently
  // fixed background. That mismatch was the root cause of the seam that
  // used to cut through the card's header text mid-scroll: since the
  // card is translucent, whatever sits behind a given line — fixed
  // green above the old 200px boundary, plain white below it — showed
  // through differently, and different lines crossed that fixed
  // boundary as the card scrolled past it.
  Widget _buildHeroBackground(BuildContext context) {
    return Container(
      height: 64 + MediaQuery.of(context).padding.top,
      color: AppConstants.primaryGreen,
    );
  }

  Widget _buildMissingState(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 40, color: cs.outline),
            const SizedBox(height: 16),
            Text(
              l10n.farmerMarketRateNotLoaded,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.farmerDetailsGoBack),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context, FarmerMarketRateModel rate) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final icon = FarmerCropModel.iconForCategory(rate.cropCategory);

    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Hero content (badge, icon, crop name) ─────────────────
          // Stays solid AppConstants.primaryGreen (not a gradient) so it
          // exactly matches the fixed strip behind the top bar — a gradient
          // here would reintroduce the scroll seam described in
          // _buildHeroBackground's comment above.
          _buildHeroContent(context, rate, icon),

          Transform.translate(
            offset: const Offset(0, -16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // ─── Current price ──────────────────────────────────
                  _buildPricingCard(context, rate),
                  const SizedBox(height: 16),

                  // ─── Price trend (this crop, this market) ───────────
                  _buildTrendCard(context, rate),
                  const SizedBox(height: 16),

                  // ─── Effective date, source ─────────────────────────
                  _buildDetailsCard(context, rate),

                  if (_otherRates.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _SectionLabel(
                      text: l10n.farmerMarketRateOtherPricesFor(
                        rate.cropName.toUpperCase(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._otherRates.map(
                      (other) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _OtherPriceRow(
                          rate: other,
                          onTap: () => _switchTo(other),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  _SectionLabel(
                    text: l10n.farmerMarketRateAboutCrop(
                      rate.cropName.toUpperCase(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: flatCardDecoration(context),
                    child: Text(
                      rate.cropDescription?.trim().isNotEmpty == true
                          ? rate.cropDescription!
                          : l10n.farmerMarketRateNoDescription,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.5,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ─── Guidance note ──────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryGreen.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusLg,
                      ),
                      border: Border.all(
                        color: AppConstants.primaryGreen.withValues(
                          alpha: 0.12,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: AppConstants.primaryGreen,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.farmerMarketRateGuidanceNote,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w500,
                              height: 1.5,
                              color: AppConstants.primaryGreen.withValues(
                                alpha: 0.9,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Hero content: badge + icon + crop name, living directly in the
  // green hero instead of a separate floating card. ───────────────────────
  Widget _buildHeroContent(
    BuildContext context,
    FarmerMarketRateModel rate,
    IconData icon,
  ) {
    final l10n = AppLocalizations.of(context);
    final imageUrl = rate.cropImageUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(32),
        bottomRight: Radius.circular(32),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
        color: AppConstants.primaryGreen,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 88,
              height: 88,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(22),
              ),
              child: hasImage
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Icon(icon, color: Colors.white, size: 36),
                    )
                  : Icon(icon, color: Colors.white, size: 36),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      MarketTypeDisplay.label(l10n, rate.priceType),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    rate.cropName,
                    style: GoogleFonts.poppins(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rate.cropCategory,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Pricing card: label, big price, change since the previous entry ──
  Widget _buildPricingCard(BuildContext context, FarmerMarketRateModel rate) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final hasPreviousPrice = rate.price.previousPrice != null;
    // "Stable trend" means we compared against a previous price and it
    // didn't move. When there's no previous price at all, that's not the
    // same thing as stable — there's simply nothing to compare against yet.
    final trendColor = !hasPreviousPrice
        ? AppConstants.outline
        : rate.isUp
        ? AppConstants.successGreen
        : rate.isDown
        ? AppConstants.errorRed
        : AppConstants.outline;
    final trendIcon = !hasPreviousPrice
        ? Icons.fiber_new_rounded
        : rate.isUp
        ? Icons.trending_up_rounded
        : rate.isDown
        ? Icons.trending_down_rounded
        : Icons.trending_flat_rounded;
    final trendLabel = !hasPreviousPrice
        ? l10n.farmerMarketRateTrendNew
        : rate.isUp
        ? l10n.farmerMarketRateTrendUp
        : rate.isDown
        ? l10n.farmerMarketRateTrendDown
        : l10n.farmerMarketRateTrendStable;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: flatCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.farmerMarketRateCurrentLabel,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₱${rate.priceValue.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '/${rate.unit}',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          // Always shown, but the label reflects whether we actually have
          // a previous price to compare against — "New rate" when we
          // don't, so it's never confused with a genuinely unchanged
          // ("Stable trend") price.
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: trendColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(trendIcon, size: 16, color: trendColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    trendLabel,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: trendColor,
                    ),
                  ),
                ),
                if (hasPreviousPrice) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      l10n.farmerMarketRateVsPrevious(
                        rate.price.priceDifference!.abs().toStringAsFixed(2),
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: trendColor.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Trend card: this crop's price history in THIS market only ─────────
  Widget _buildTrendCard(BuildContext context, FarmerMarketRateModel rate) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final marketColor = MarketTypeDisplay.color(context, rate.priceType);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: flatCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.farmerMarketRateTrendTitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: marketColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  MarketTypeDisplay.label(l10n, rate.priceType),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: marketColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PriceTrendPanel(
            trend: _trend,
            isLoading: _isTrendLoading,
            current: rate.price,
            // The current price is the big figure above, so the third figure
            // here is the average, and nothing is repeated when there is no
            // history to chart yet.
            showAverage: true,
            showStatsWithoutHistory: false,
          ),
        ],
      ),
    );
  }

  // ─── Details card: effective date + source, in matching icon-tile rows
  Widget _buildDetailsCard(BuildContext context, FarmerMarketRateModel rate) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: flatCardDecoration(context),
      child: Column(
        children: [
          _DetailRow(
            icon: Icons.calendar_today_rounded,
            label: l10n.priceEffectiveDateLabel,
            value: AppUtils.formatDate(rate.recordedAt, l10n.localeName),
          ),
          Divider(
            height: 1,
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.15),
          ),
          _DetailRow(
            icon: Icons.description_outlined,
            label: l10n.priceSourceRefLabel,
            value: rate.source?.trim().isNotEmpty == true
                ? rate.source!
                : l10n.commonNotSpecified,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppConstants.gold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: Theme.of(context).colorScheme.outline,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppConstants.primaryGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: AppConstants.primaryGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The crop's price in another market. Tapping it switches this screen to that
/// market.
class _OtherPriceRow extends StatelessWidget {
  final FarmerMarketRateModel rate;
  final VoidCallback onTap;
  const _OtherPriceRow({required this.rate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final color = MarketTypeDisplay.color(context, rate.priceType);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: flatCardDecoration(context),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                MarketTypeDisplay.label(l10n, rate.priceType),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            const Spacer(),
            Text(
              rate.formattedPrice,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppConstants.primaryGreen,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: cs.outline, size: 20),
          ],
        ),
      ),
    );
  }
}
