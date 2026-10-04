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
  List<PriceRecordModel> _latestPrices = [];
  Set<String> _listedCrops = {};
  int _unreadCount = 0;
  BuyerProfileModel? _buyerProfile;

  // ─── Filters ────────────────────────────────────────────────────────────
  // Search + the price-type chip row only — matches Farmer's View Market
  // Rates screen exactly, which has no separate filter-panel affordance.
  String? _priceTypeFilter;   // price-source chip row — null = All

  // ─── Exclusive inline expansion ─────────────────────────────────────────
  String? _expandedCropId;
  List<PriceRecordModel> _trend = [];
  bool _isTrendLoading = false;

  @override
  void initState() {
    super.initState();
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
      if (query.isNotEmpty && !p.cropName.toLowerCase().contains(query)) return false;
      if (_priceTypeFilter != null && p.priceType != _priceTypeFilter) return false;
      return true;
    }).toList();
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
    final trend = await _priceRepo.fetchTrendForCrop(cropId);
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
              Expanded(
                child: SafeArea(
                  top: false,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: Column(
                            children: [
                              _buildSearchRow(l10n),
                              const SizedBox(height: 10),
                              _buildPriceTypeChips(l10n),
                              const SizedBox(height: 8),
                              Expanded(
                                child: _latestPrices.isEmpty
                                    ? _buildEmptyState(l10n)
                                    : filtered.isEmpty
                                        ? _buildNoResultsState(l10n)
                                        : ListView.separated(
                                            padding: const EdgeInsets.fromLTRB(
                                                AppConstants.spacingSafeH, 8, AppConstants.spacingSafeH, 100),
                                            itemCount: filtered.length,
                                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                                            itemBuilder: (context, i) => _CropCard(
                                              price: filtered[i],
                                              isExpanded: filtered[i].cropId == _expandedCropId,
                                              isListed: _listedCrops.contains(filtered[i].cropName.toLowerCase()),
                                              trend: _trend,
                                              isTrendLoading: _isTrendLoading,
                                              onTap: () => _toggleExpand(filtered[i].cropId),
                                            ),
                                          ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0, left: 0, right: 0,
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
      padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 8, AppConstants.spacingSafeH, 0),
      child: AppTextField(
        controller: _searchController,
        label: l10n.buyerPriceSearchLabel,
        hint: l10n.buyerPriceSearchHint,
        prefixIcon: Icons.search,
      ),
    );
  }

  // Same per-type coloring as Farmer's View Market Rates chip row
  // (MarketTypeDisplay) — was always plain green regardless of which
  // market type was selected, unlike Farmer's screen distinguishing
  // Cooperative vs Public Market by color.
  Widget _buildPriceTypeChips(AppLocalizations l10n) {
    const types = [null, 'sp3_cooperative', 'open_market'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSafeH),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: types.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final type = types[i];
            final selected = _priceTypeFilter == type;
            final label = type == null ? l10n.buyerPriceFilterAll : MarketTypeDisplay.label(l10n, type);
            final color = type == null ? AppConstants.primaryGreen : MarketTypeDisplay.color(context, type);
            return ChoiceChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) => setState(() => _priceTypeFilter = type),
              labelStyle: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w600,
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

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.trending_up_rounded, size: 56, color: AppConstants.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(l10n.buyerPriceEmptyTitle, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(l10n.buyerPriceEmptyBody,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
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
            Icon(Icons.search_off_rounded, size: 48, color: AppConstants.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(l10n.buyerPriceNoResultsTitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => setState(() {
                _searchController.clear();
                _priceTypeFilter = null;
              }),
              child: Text(l10n.buyerPriceClearFilters,
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
            ),
          ],
        ),
      ),
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
            border: isExpanded ? Border.all(color: AppConstants.primaryGreen, width: 1.5) : null,
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

  // Same row shape as Farmer's _MarketRateListTile — 72x72 crop image,
  // name + market-type badge on one line, a relative "Updated X ago"
  // line, then the price — so both screens genuinely read as the same
  // presentation of the same underlying price_records data, not two
  // different-looking pages that happen to show similar numbers.
  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    final color = MarketTypeDisplay.color(context, price.priceType);
    final imageUrl = price.cropImageUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Same crop image Admin's Price Management shows — referenced
        // only (from Crop Management), never uploaded from here.
        ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          child: SizedBox(
            width: 72, height: 72,
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
                      price.cropName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppConstants.charcoal),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppConstants.radiusFull)),
                    child: Text(MarketTypeDisplay.label(l10n, price.priceType),
                        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l10n.priceUpdatedPrefix(AppUtils.formatRelativeTime(price.recordedAt, l10n)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(price.formattedPrice,
                      style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
                  if (price.previousPrice != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      price.isUp ? Icons.arrow_upward_rounded : price.isDown ? Icons.arrow_downward_rounded : Icons.remove_rounded,
                      size: 12,
                      color: price.isUp ? AppConstants.successGreen : price.isDown ? AppConstants.errorRed : AppConstants.outline,
                    ),
                    Text('₱${price.priceDifference!.abs().toStringAsFixed(2)}',
                        style: GoogleFonts.inter(fontSize: 10,
                            color: price.isUp ? AppConstants.successGreen : price.isDown ? AppConstants.errorRed : AppConstants.outline)),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            color: Theme.of(context).colorScheme.outline, size: 22),
      ],
    );
  }

  Widget _buildStatusTag(AppLocalizations l10n) {
    final color = isListed ? AppConstants.successGreen : AppConstants.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppConstants.radiusSm)),
      child: Text(isListed ? l10n.buyerPriceListedTag : l10n.buyerPriceNotListedTag,
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _buildTrendArea(AppLocalizations l10n) {
    final prices = trend.map((p) => p.price).toList();
    return SizedBox(
      height: 100,
      width: double.infinity,
      child: isTrendLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : prices.length < 2
              ? Center(
                  child: Text(l10n.buyerPriceNoTrendHistory,
                      style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)))
              : CustomPaint(
                  painter: _SparklinePainter(prices: prices, color: AppConstants.primaryGreen),
                  size: Size.infinite,
                ),
    );
  }

  Widget _buildStatsRow(AppLocalizations l10n) {
    final prices = trend.map((p) => p.price).toList();
    final high = prices.isEmpty ? price.price : prices.reduce((a, b) => a > b ? a : b);
    final low = prices.isEmpty ? price.price : prices.reduce((a, b) => a < b ? a : b);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _statColumn(l10n.buyerPriceStatHigh, '₱${high.toStringAsFixed(2)}', AppConstants.successGreen),
        _statColumn(l10n.buyerPriceStatLow, '₱${low.toStringAsFixed(2)}', AppConstants.errorRed),
        _statColumn(l10n.buyerPriceStatCurrent, price.formattedPrice, AppConstants.primaryGreen),
      ],
    );
  }

  Widget _statColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant)),
        Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
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