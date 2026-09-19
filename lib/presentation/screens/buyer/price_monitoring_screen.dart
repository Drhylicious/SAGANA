import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
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
import '../../widgets/management_modal.dart';

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
  Map<String, String> _cropCategories = {}; // cropId -> category
  int _unreadCount = 0;
  BuyerProfileModel? _buyerProfile;

  // ─── Filters ────────────────────────────────────────────────────────────
  String? _priceTypeFilter;   // price-source chip row — null = All
  String? _categoryFilter;    // filter panel
  String? _cropIdFilter;      // filter panel

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
      _priceRepo.fetchCropCategories(),
      _notificationRepo.fetchUnreadCount(),
    ]);
    if (!mounted) return;
    setState(() {
      _latestPrices = results[0] as List<PriceRecordModel>;
      _listedCrops = results[1] as Set<String>;
      _cropCategories = results[2] as Map<String, String>;
      _unreadCount = results[3] as int;
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
      if (_cropIdFilter != null && p.cropId != _cropIdFilter) return false;
      if (_categoryFilter != null && _cropCategories[p.cropId] != _categoryFilter) return false;
      return true;
    }).toList();
  }

  bool get _hasPanelFilters => _categoryFilter != null || _cropIdFilter != null;

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

  Future<void> _openFilterPanel() async {
    final categories = _cropCategories.values.toSet().toList()..sort();
    final result = await showManagementModal<_FilterResult>(
      context: context,
      builder: (_) => _PriceFilterPanel(
        categories: categories,
        crops: _latestPrices,
        cropCategories: _cropCategories,
        initialCategory: _categoryFilter,
        initialCropId: _cropIdFilter,
      ),
    );
    if (result == null) return;
    setState(() {
      _categoryFilter = result.category;
      _cropIdFilter = result.cropId;
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

  Widget _buildSearchRow(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 8, AppConstants.spacingSafeH, 0),
      child: Row(
        children: [
          Expanded(
            child: AppTextField(
              controller: _searchController,
              label: l10n.buyerPriceSearchLabel,
              hint: l10n.buyerPriceSearchHint,
              prefixIcon: Icons.search,
            ),
          ),
          const SizedBox(width: 10),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: context.saganaColors.cardBackground,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(color: AppConstants.outline.withValues(alpha: 0.5)),
                ),
                child: IconButton(
                  icon: const Icon(Icons.tune_rounded),
                  color: AppConstants.primaryGreen,
                  onPressed: _openFilterPanel,
                ),
              ),
              if (_hasPanelFilters)
                Positioned(
                  top: -2, right: -2,
                  child: Container(
                    width: 10, height: 10,
                    decoration: const BoxDecoration(color: AppConstants.errorRed, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceTypeChips(AppLocalizations l10n) {
    const types = [null, 'open_market', 'sp3_cooperative'];
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
            final label = type == null ? l10n.buyerPriceFilterAll : _priceTypeLabel(type, l10n);
            return ChoiceChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) => setState(() => _priceTypeFilter = type),
              labelStyle: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppConstants.onSurfaceVariant,
              ),
              selectedColor: AppConstants.primaryGreen,
              backgroundColor: context.saganaColors.cardBackground,
              side: BorderSide(color: AppConstants.outline.withValues(alpha: 0.3)),
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
                _categoryFilter = null;
                _cropIdFilter = null;
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

// Buyer-local label mapping — deliberately not using
// PriceRecordModel.priceTypeLabel, since that model is shared read-only
// with Admin's PriceManagementRepository. Operates on the model's public
// raw priceType field instead.
String _priceTypeLabel(String type, AppLocalizations l10n) {
  switch (type) {
    case 'sp3_cooperative': return l10n.buyerPriceTypeSp3;
    default:                return l10n.buyerPriceTypeMarketRef;
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
          decoration: BoxDecoration(
            color: context.saganaColors.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: isExpanded ? Border.all(color: AppConstants.primaryGreen, width: 1.5) : null,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(l10n),
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

  Widget _buildHeader(AppLocalizations l10n) {
    final imageUrl = price.cropImageUrl;
    return Row(
      children: [
        // Same crop image Admin's Price Management shows — referenced
        // only (from Crop Management), never uploaded from here.
        ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          child: Container(
            width: 40, height: 40,
            color: AppConstants.limeGreen,
            child: (imageUrl != null && imageUrl.isNotEmpty)
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.storefront_outlined, size: 18, color: AppConstants.primaryGreen),
                  )
                : const Icon(Icons.storefront_outlined, size: 18, color: AppConstants.primaryGreen),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(price.cropName, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
              Text(_priceTypeLabel(price.priceType, l10n), style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(price.formattedPrice,
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
            if (price.previousPrice != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    price.isUp ? Icons.arrow_upward_rounded : price.isDown ? Icons.arrow_downward_rounded : Icons.remove_rounded,
                    size: 12,
                    color: price.isUp ? AppConstants.successGreen : price.isDown ? AppConstants.errorRed : AppConstants.outline,
                  ),
                  Text('₱${price.priceDifference!.abs().toStringAsFixed(2)}',
                      style: GoogleFonts.inter(fontSize: 10,
                          color: price.isUp ? AppConstants.successGreen : price.isDown ? AppConstants.errorRed : AppConstants.outline)),
                ],
              ),
          ],
        ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Filter panel — Category + Crop, mirroring Farmer's two-tier structure but
// sourced from Buyer's own already-fetched price data + the new
// fetchCropCategories() lookup, not a full separate crop-catalog fetch.
// Deliberately simpler than Farmer's version: only crops that actually
// have a price record appear here, since filtering to an empty category
// wouldn't serve any purpose on this screen.
// ─────────────────────────────────────────────────────────────────────────────

class _FilterResult {
  final String? category;
  final String? cropId;
  const _FilterResult({this.category, this.cropId});
}

class _PriceFilterPanel extends StatefulWidget {
  final List<String> categories;
  final List<PriceRecordModel> crops;
  final Map<String, String> cropCategories;
  final String? initialCategory;
  final String? initialCropId;

  const _PriceFilterPanel({
    required this.categories,
    required this.crops,
    required this.cropCategories,
    this.initialCategory,
    this.initialCropId,
  });

  @override
  State<_PriceFilterPanel> createState() => _PriceFilterPanelState();
}

class _PriceFilterPanelState extends State<_PriceFilterPanel> {
  String? _category;
  String? _cropId;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _cropId = widget.initialCropId;
  }

  List<PriceRecordModel> get _cropsForCategory {
    if (_category == null) return widget.crops;
    return widget.crops.where((c) => widget.cropCategories[c.cropId] == _category).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ManagementModalShell(
      title: l10n.buyerPriceFilterPanelTitle,
      subtitle: l10n.buyerPriceFilterPanelSubtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.buyerPriceFilterCategoryLabel, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppConstants.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: widget.categories.map((cat) {
              final selected = _category == cat;
              return _FilterChip(
                label: cat,
                selected: selected,
                onTap: () => setState(() {
                  _category = selected ? null : cat;
                  _cropId = null; // changing category clears the more-specific crop pick
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Text(l10n.buyerPriceFilterCropLabel, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppConstants.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _cropsForCategory.map((c) {
              final selected = _cropId == c.cropId;
              return _FilterChip(
                label: c.cropName,
                selected: selected,
                onTap: () => setState(() => _cropId = selected ? null : c.cropId),
              );
            }).toList(),
          ),
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, const _FilterResult()),
              child: Text(l10n.buyerPriceResetAll),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              label: l10n.buyerPriceApplyFilters,
              height: 44,
              onPressed: () => Navigator.pop(context, _FilterResult(category: _category, cropId: _cropId)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppConstants.primaryGreen : AppConstants.limeGreen.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
        child: Text(label,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppConstants.charcoal)),
      ),
    );
  }
}