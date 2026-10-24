import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/buyer_profile_model.dart';
import '../../../data/models/price_record_model.dart';
import '../../../data/repositories/buyer_profile_repository.dart';
import '../../../data/repositories/price_management_repository.dart';
import '../../../data/repositories/buyer_marketplace_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_navigation_drawer.dart';
import '../../widgets/buyer_top_bar.dart';
import '../../widgets/shared_widgets.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/skeleton.dart';
import '../../../data/services/market_types_service.dart';

class PriceMonitoringScreen extends StatefulWidget {
  const PriceMonitoringScreen({super.key});

  @override
  State<PriceMonitoringScreen> createState() => _PriceMonitoringScreenState();
}

class _PriceMonitoringScreenState extends State<PriceMonitoringScreen> {
  final _priceRepo = PriceManagementRepository();
  final _marketRepo = BuyerMarketplaceRepository();
  final _notificationRepo = NotificationRepository();
  final _profileRepo = BuyerProfileRepository();
  final _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isOnline = ConnectivityService.instance.isOnline;
  List<PriceRecordModel> _latestPrices = [];
  Set<String> _listedCrops = {};
  int _unreadCount = 0;
  BuyerProfileModel? _buyerProfile;

  // ─── Exclusive inline expansion ─────────────────────────────────────────
  String? _expandedCropId;
  List<PriceRecordModel> _trend = [];
  bool _isTrendLoading = false;

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _searchController.addListener(() => setState(() {}));
    _load();
    _loadBuyerProfile();
  }

  Future<void> _loadBuyerProfile() async {
    final profile = await _profileRepo.fetchProfile();
    if (!mounted) return;
    setState(() => _buyerProfile = profile);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _priceRepo.fetchLatestPricePerCrop(),
      _marketRepo.fetchListedCropNames(),
      _notificationRepo.fetchUnreadCount(),
    ]);
    if (!mounted) return;
    setState(() {
      _latestPrices = results[0] as List<PriceRecordModel>;
      _listedCrops = results[1] as Set<String>;
      _unreadCount = results[2] as int;
      _isLoading = false;
    });
  }

  // Separate, dedicated unread-count refresh — matches the one screen in
  // this whole set (MarketplaceBrowseScreen) that already had this
  // correctly isolated, rather than re-running the full price load just to
  // refresh a badge.
  Future<void> _loadUnreadCount() async {
    final count = await _notificationRepo.fetchUnreadCount();
    if (!mounted) return;
    setState(() => _unreadCount = count);
  }

  List<PriceRecordModel> get _filteredPrices {
    final query = _searchController.text.trim().toLowerCase();
    return _latestPrices.where((p) {
      // Buyers see Public Market prices only: a farmer-only market's prices are
      // not shown here, whatever the data layer returned.
      if (!MarketTypes.instance.isBuyerVisible(p.priceType)) return false;
      if (query.isNotEmpty && !p.cropName.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// The visible prices grouped under their crop category, categories in
  /// alphabetical order with uncategorised crops last.
  List<MapEntry<String, List<PriceRecordModel>>> _groupByCategory(
    List<PriceRecordModel> prices,
    String otherLabel,
  ) {
    final groups = <String, List<PriceRecordModel>>{};
    for (final p in prices) {
      final c = p.cropCategory?.trim();
      groups
          .putIfAbsent(c == null || c.isEmpty ? otherLabel : c, () => [])
          .add(p);
    }
    final entries = groups.entries.toList()
      ..sort((a, b) {
        if (a.key == otherLabel) return 1;
        if (b.key == otherLabel) return -1;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });
    return entries;
  }

  Future<void> _toggleExpand(String cropId) async {
    if (_expandedCropId == cropId) {
      setState(() => _expandedCropId = null);
      return;
    }
    setState(() {
      _expandedCropId = cropId;
      _isTrendLoading = true;
      _trend = [];
    });
    // Trend lines for Buyers come from Public Market prices only.
    final trend = (await _priceRepo.fetchTrendForCrop(cropId))
        .where((p) => MarketTypes.instance.isBuyerVisible(p.priceType))
        .toList();
    if (!mounted) return;
    setState(() {
      _trend = trend;
      _isTrendLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final filtered = _filteredPrices;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      drawer: AppNavigationDrawer(
        photoUrl: _buyerProfile?.profilePhotoUrl,
        displayName: _buyerProfile?.fullName ?? 'Buyer',
        contactEmail: _buyerProfile?.contactEmail,
        phoneNumber: _buyerProfile?.phoneNumber,
        onEditProfile: () {
          Navigator.pop(context);
          context.push(AppRoutes.buyerEditProfile);
        },
        onMyAddresses: () {
          Navigator.pop(context);
          context.push(AppRoutes.myAddresses);
        },
        onSignOut: () => confirmBuyerSignOut(context),
        onAboutSagana: () => context.push(AppRoutes.aboutSagana),
        onAboutOrganization: () => context.push(AppRoutes.aboutCooperative),
        onPrivacyPolicy: () => context.push(AppRoutes.privacyPolicy),
        onTermsOfUse: () => context.push(AppRoutes.termsOfUse),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              CachedDataNotice(
                screen: 'latest_prices',
                isOnline: _isOnline,
                offlineMessage: l10n.offlineBuyerBody,
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: SkeletonList(),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: Column(
                            children: [
                              _buildSearchRow(l10n),
                              const SizedBox(height: 8),
                              Expanded(
                                child: _latestPrices.isEmpty
                                    ? _buildEmptyState(l10n)
                                    : filtered.isEmpty
                                    ? _buildNoResultsState(l10n)
                                    : _buildPriceList(l10n, filtered),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: BuyerTopBar(
              title: l10n.buyerPriceTitle,
              unreadCount: _unreadCount,
              onNotificationTap: () async {
                await context.push(AppRoutes.buyerNotifications);
                _loadUnreadCount();
              },
              enableMenu: true,
            ),
          ),
        ],
      ),
    );
  }

  // Plain full-width search field, no separate filter-icon affordance —
  // matches Farmer's View Market Rates screen exactly, which filters only
  // by search text and the market-type chip row below.
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

  // A summary header (which market, how many crops, how fresh), then the
  // crops grouped under their category.
  Widget _buildPriceList(
    AppLocalizations l10n,
    List<PriceRecordModel> filtered,
  ) {
    final groups = _groupByCategory(filtered, l10n.buyerPriceCategoryOther);
    final markets = filtered.map((p) => p.priceType).toSet();
    final title = markets.length == 1
        ? l10n.buyerPriceHeaderTitle(MarketTypes.instance.label(markets.first))
        : l10n.buyerPriceTitle;
    final newest = filtered
        .map((p) => p.recordedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingSafeH,
          8,
          AppConstants.spacingSafeH,
          100,
        ),
        children: [
          _MarketHeader(
            title: title,
            subtitle: l10n.buyerPriceHeaderSubtitle,
            cropCount: filtered.length,
            updated: AppUtils.formatRelativeTime(newest, l10n),
          ),
          for (final group in groups) ...[
            const SizedBox(height: 20),
            _CategoryHeader(title: group.key, count: group.value.length),
            const SizedBox(height: 10),
            for (int i = 0; i < group.value.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _CropCard(
                price: group.value[i],
                isExpanded: group.value[i].cropId == _expandedCropId,
                isListed: _listedCrops.contains(
                  group.value[i].cropName.toLowerCase(),
                ),
                trend: _trend,
                isTrendLoading: _isTrendLoading,
                onTap: () => _toggleExpand(group.value[i].cropId),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.trending_up_rounded,
              size: 56,
              color: AppConstants.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.buyerPriceEmptyTitle,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.buyerPriceEmptyBody,
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

  Widget _buildNoResultsState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: AppConstants.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.buyerPriceNoResultsTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => setState(_searchController.clear),
              child: Text(
                l10n.buyerPriceClearFilters,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.primaryGreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// List header + category header
// ─────────────────────────────────────────────────────────────────────────────

/// Names the market the prices below belong to, says what they are, and gives
/// a quick count and freshness.
class _MarketHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final int cropCount;
  final String updated;

  const _MarketHeader({
    required this.title,
    required this.subtitle,
    required this.cropCount,
    required this.updated,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    const accent = AppConstants.primaryGreen;

    Widget pill(IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.14),
            accent.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  size: 22,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.35,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              pill(Icons.eco_rounded, l10n.buyerPriceCropCount(cropCount)),
              pill(Icons.update_rounded, l10n.priceUpdatedPrefix(updated)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final String title;
  final int count;

  const _CategoryHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: cs.outline.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Divider(height: 1, color: cs.outline.withValues(alpha: 0.15)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Collapsed/expanded crop card — exclusive inline expansion
// ─────────────────────────────────────────────────────────────────────────────

class _CropCard extends StatelessWidget {
  final PriceRecordModel price;
  final bool isExpanded;
  final bool isListed;
  final List<PriceRecordModel> trend;
  final bool isTrendLoading;
  final VoidCallback onTap;

  const _CropCard({
    required this.price,
    required this.isExpanded,
    required this.isListed,
    required this.trend,
    required this.isTrendLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: Container(
          padding: const EdgeInsets.all(14),
          // Same flatCardDecoration Farmer's View Market Rates tile uses —
          // only the expanded-state accent border is Buyer-specific (this
          // card expands in place; Farmer's pushes to a detail screen
          // instead, so it has no equivalent state to mark).
          decoration: flatCardDecoration(context).copyWith(
            border: isExpanded
                ? Border.all(color: AppConstants.primaryGreen, width: 1.5)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, l10n),
              if (isExpanded) ...[
                const SizedBox(height: 10),
                _buildStatusTag(l10n),
                const SizedBox(height: 14),
                _buildTrendArea(l10n),
                const SizedBox(height: 12),
                _buildStatsRow(l10n),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Image, crop name and freshness on the left; the price (the thing a Buyer
  // is here for) right-aligned with its change since the previous entry.
  // Every price on this screen is a Public Market price, so the card carries
  // no per-card market badge — the header above the list names the market.
  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    final color = MarketTypeDisplay.color(context, price.priceType);
    final imageUrl = price.cropImageUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final cs = Theme.of(context).colorScheme;
    final deltaColor = price.isUp
        ? AppConstants.successGreen
        : price.isDown
        ? AppConstants.errorRed
        : AppConstants.outline;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Same crop image Admin's Price Management shows — referenced
        // only (from Crop Management), never uploaded from here.
        ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          child: SizedBox(
            width: 64,
            height: 64,
            child: hasImage
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: color.withValues(alpha: 0.12),
                      child: Icon(Icons.eco_outlined, size: 26, color: color),
                    ),
                  )
                : Container(
                    color: color.withValues(alpha: 0.12),
                    child: Icon(Icons.eco_outlined, size: 26, color: color),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                price.cropName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.priceUpdatedPrefix(
                  AppUtils.formatRelativeTime(price.recordedAt, l10n),
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₱${price.price.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppConstants.primaryGreen,
              ),
            ),
            Text(
              '/${price.unit}',
              style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
            ),
            if (price.previousPrice != null) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    price.isUp
                        ? Icons.arrow_upward_rounded
                        : price.isDown
                        ? Icons.arrow_downward_rounded
                        : Icons.remove_rounded,
                    size: 12,
                    color: deltaColor,
                  ),
                  Text(
                    '₱${price.priceDifference!.abs().toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: deltaColor,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(width: 4),
        Icon(
          isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
          color: cs.outline,
          size: 22,
        ),
      ],
    );
  }

  Widget _buildStatusTag(AppLocalizations l10n) {
    final color = isListed ? AppConstants.successGreen : AppConstants.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      child: Text(
        isListed ? l10n.buyerPriceListedTag : l10n.buyerPriceNotListedTag,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildTrendArea(AppLocalizations l10n) {
    final prices = trend.map((p) => p.price).toList();
    return SizedBox(
      height: 100,
      width: double.infinity,
      child: isTrendLoading
          ? const SkeletonBlock(height: 100)
          : prices.length < 2
          ? Center(
              child: Text(
                l10n.buyerPriceNoTrendHistory,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
            )
          : CustomPaint(
              painter: _SparklinePainter(
                prices: prices,
                color: AppConstants.primaryGreen,
              ),
              size: Size.infinite,
            ),
    );
  }

  Widget _buildStatsRow(AppLocalizations l10n) {
    final prices = trend.map((p) => p.price).toList();
    final high = prices.isEmpty
        ? price.price
        : prices.reduce((a, b) => a > b ? a : b);
    final low = prices.isEmpty
        ? price.price
        : prices.reduce((a, b) => a < b ? a : b);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _statColumn(
          l10n.buyerPriceStatHigh,
          '₱${high.toStringAsFixed(2)}',
          AppConstants.successGreen,
        ),
        _statColumn(
          l10n.buyerPriceStatLow,
          '₱${low.toStringAsFixed(2)}',
          AppConstants.errorRed,
        ),
        _statColumn(
          l10n.buyerPriceStatCurrent,
          price.formattedPrice,
          AppConstants.primaryGreen,
        ),
      ],
    );
  }

  Widget _statColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: AppConstants.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Minimal local sparkline — unchanged from the original screen.
class _SparklinePainter extends CustomPainter {
  final List<double> prices;
  final Color color;
  const _SparklinePainter({required this.prices, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final min = prices.reduce((a, b) => a < b ? a : b);
    final max = prices.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs() < 0.01 ? 1.0 : max - min;

    final path = Path();
    final stepX = size.width / (prices.length - 1);
    for (int i = 0; i < prices.length; i++) {
      final x = i * stepX;
      final y = size.height - ((prices[i] - min) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.08));
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.prices != prices || oldDelegate.color != color;
}
