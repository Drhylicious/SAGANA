import 'dart:math' as math;
import 'dart:ui';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter/material.dart';
import '../../widgets/cached_data_notice.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/price_record_model.dart';
import '../../../data/repositories/price_management_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../widgets/add_unit_dialog.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/utils/input_validation_utils.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/skeleton.dart';
import '../../../data/services/market_types_service.dart';
import '../../widgets/report_summary_widgets.dart'
    show ReportIconStatCard, ReportSectionCard;

/// The market the Add Price sheet opens on: the first market whose prices the
/// Manager sets, otherwise the first market in the table.
String _initialPriceType() {
  final types = MarketTypes.instance.activeTypes;
  for (final t in types) {
    if (t.managerSetsPrice) return t.code;
  }
  return types.isEmpty ? '' : types.first.code;
}

// Presentation-layer mapping for PriceRecordModel.priceTypeLabel — the
// model getter (lib/data/models/price_record_model.dart) has no
// BuildContext to call AppLocalizations from, so the localized text is
// derived here instead, off the same priceType string, rather than
// changing the model.
String _priceTypeFullLabel(AppLocalizations l10n, String priceType) =>
    MarketTypes.instance.isBuyerVisible(priceType)
    ? l10n.priceTypePublicFull
    : l10n.priceTypeCooperativeFull;

// ─── Screen ───────────────────────────────────────────────────────────────────

class PriceManagementScreen extends StatefulWidget {
  const PriceManagementScreen({super.key});

  @override
  State<PriceManagementScreen> createState() => _PriceManagementScreenState();
}

class _PriceManagementScreenState extends State<PriceManagementScreen> {
  final _repo = PriceManagementRepository();
  final _unitRepo = UnitRepository();

  List<PriceRecordModel> _latestPrices = [];
  List<Map<String, dynamic>> _availableCrops = [];
  List<String> _units = UnitRepository.fallbackUnits;
  bool _isLoading = true;
  bool _isOnline = true;

  // ── Market Trends modal state ────────────────────────────────────────────
  // The crop whose trend is showing (a crop_id), the market (a market_types
  // code) whose line is drawn when that crop has prices in more than one, and
  // the crop's recent price records.
  String? _selectedCropIdForChart;
  String? _trendMarket;
  List<PriceRecordModel> _trendData = [];
  bool _loadingTrend = false;

  // ── Search + market filter ────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  // null = All (every market's reference prices shown); otherwise narrows to
  // one market_types code.
  String? _marketFilter;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppTheme.applySystemOverlay(context);
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchLatestPricePerCrop(),
      _repo.fetchAvailableCrops(),
      _unitRepo.fetchUnits(),
    ]);
    if (!mounted) return;
    final prices = results[0] as List<PriceRecordModel>;
    final crops = results[1] as List<Map<String, dynamic>>;
    final units = results[2] as List<String>;
    setState(() {
      _latestPrices = prices;
      _availableCrops = crops;
      _units = units;
      _isLoading = false;
      // Auto-select first crop for chart
      if (_selectedCropIdForChart == null && prices.isNotEmpty) {
        _selectedCropIdForChart = prices.first.cropId;
        _loadTrend(prices.first.cropId);
      }
    });
  }

  Future<void> _loadTrend(String cropId) async {
    setState(() => _loadingTrend = true);
    final data = await _repo.fetchTrendForCrop(cropId);
    if (!mounted) return;
    setState(() {
      _trendData = data;
      _loadingTrend = false;
    });
  }

  // ── Open update sheet ─────────────────────────────────────────────────────

  void _openUpdateSheet(PriceRecordModel price) {
    if (!_isOnline) {
      _showSnack(AppLocalizations.of(context).priceOfflineWarning);
      return;
    }
    showManagementModal(
      context: context,
      builder: (_) =>
          UpdatePriceSheet(price: price, repo: _repo, onSaved: _loadAll),
    );
  }

  // ── Open add sheet ────────────────────────────────────────────────────────

  void _openAddSheet() {
    if (!_isOnline) {
      _showSnack(AppLocalizations.of(context).priceOfflineWarning);
      return;
    }
    showManagementModal(
      context: context,
      builder: (_) => AddPriceEntrySheet(
        availableCrops: _availableCrops,
        units: _units,
        onUnitAdded: (u) {
          if (mounted && !_units.contains(u)) setState(() => _units = [..._units, u]);
        },
        repo: _repo,
        onSaved: _loadAll,
      ),
    );
  }

  // ── Market Trends (top-bar icon) ──────────────────────────────────────────
  // Behind an icon rather than an inline section: the screen already carries
  // KPIs, search, filter chips and the reference-price grids, so a chart plus
  // history list inline would push everything else further down. Mirrors the
  // pattern of a secondary feature living behind a top-bar icon (e.g.
  // Broadcast's campaign icon on the other admin root screens).
  void _openMarketTrends() {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    showManagementModal(
      context: context,
      // StatefulBuilder is required here: showManagementModal's builder
      // runs once when the modal opens, so without a local setState the
      // modal never redraws when a crop chip is tapped — the parent
      // screen's own setState rebuilds price_management_screen behind the
      // modal, not the modal route itself. setModalState mirrors that state
      // into the visible sheet.
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final matchingPrices = _latestPrices
              .where((p) => p.cropId == _selectedCropIdForChart)
              .toList();
          final selectedName = matchingPrices.isEmpty
              ? null
              : matchingPrices.first.cropName;
          return ManagementModalShell(
            title: l10n.priceMarketTrends,
            subtitle: selectedName,
            // The shell scrolls the body (the card is taller than the modal on
            // a phone); bodyIsScrollable would pin it to a fixed height and
            // overflow.
            body: MarketTrendsCard(
              prices: _latestPrices,
              trendData: _trendData,
              selectedCropId: _selectedCropIdForChart,
              selectedMarket: _trendMarket,
              loadingTrend: _loadingTrend,
              onMarketSelected: (code) {
                setState(() => _trendMarket = code);
                setModalState(() {});
              },
              onCropSelected: (cropId) async {
                if (_selectedCropIdForChart == cropId) return;
                setState(() {
                  _selectedCropIdForChart = cropId;
                  _trendMarket = null;
                  _loadingTrend = true;
                });
                setModalState(() {});
                final data = await _repo.fetchTrendForCrop(cropId);
                if (!mounted) return;
                setState(() {
                  _trendData = data;
                  _loadingTrend = false;
                });
                setModalState(() {});
              },
              cs: cs,
              sagana: sagana,
              l10n: l10n,
            ),
          );
        },
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
      ),
    );
  }

  // ── KPI cards ─────────────────────────────────────────────────────────────
  // Reference-price statistics only, all computed from the same latest-price
  // rows the grids below show (one row per crop and market): how many
  // reference prices each market holds, how many were set or changed in the
  // last 7 days, and when the most recent change was.
  Widget _buildPriceKpiCards(AppLocalizations l10n) {
    final markets = MarketTypes.instance.activeTypes;
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final updatedThisWeek = _latestPrices
        .where((p) => p.recordedAt.isAfter(weekAgo))
        .length;
    DateTime? newest;
    for (final p in _latestPrices) {
      if (newest == null || p.recordedAt.isAfter(newest)) newest = p.recordedAt;
    }

    final cards = <Widget>[
      for (final t in markets)
        ReportIconStatCard(
          icon: t.buyerVisible ? Icons.storefront_rounded : Icons.groups_rounded,
          accent: t.buyerVisible
              ? AppConstants.buyerBlue
              : AppConstants.primaryGreen,
          label: l10n.priceKpiMarketRef(MarketTypes.instance.shortLabel(t.code)),
          value: '${_latestPrices.where((p) => p.priceType == t.code).length}',
        ),
      ReportIconStatCard(
        icon: Icons.update_rounded,
        accent: AppConstants.amber,
        label: l10n.priceKpiUpdatedWeek,
        value: '$updatedThisWeek',
      ),
      ReportIconStatCard(
        icon: Icons.schedule_rounded,
        accent: AppConstants.warningAmber,
        label: l10n.priceKpiLastUpdate,
        value: newest == null
            ? '—'
            : AppUtils.formatRelativeTime(newest, l10n),
      ),
    ];

    // One horizontally scrolling row of equal-size cards, the same treatment
    // the other Management modules (Crop, Program) use for their KPI cards.
    return ReportSectionCard(
      title: l10n.priceKpiOverviewTitle,
      icon: Icons.sell_rounded,
      accent: AppConstants.buyerBlue,
      child: SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, __) =>
              const SizedBox(width: AppConstants.spacingSm),
          itemBuilder: (_, i) => SizedBox(width: 150, child: cards[i]),
        ),
      ),
    );
  }

  List<PriceRecordModel> _pricesFor(String marketCode) {
    return _latestPrices
        .where(
          (p) =>
              p.priceType == marketCode &&
              (_searchQuery.isEmpty ||
                  p.cropName.toLowerCase().contains(_searchQuery)),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final markets = MarketTypes.instance.activeTypes;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadAll,
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: SkeletonList(),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                          children: [
                            // ── Offline warning ──────────────────────────
                            CachedDataNotice(
                              screen: 'latest_prices',
                              isOnline: _isOnline,
                              offlineMessage: l10n.priceSystemOfflineBody,
                            ),

                            // ── KPI cards ────────────────────────────────
                            _buildPriceKpiCards(l10n),
                            const SizedBox(height: 20),

                            // ── Search bar ───────────────────────────────
                            TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: l10n.priceSearchHint,
                                prefixIcon: const Icon(Icons.search_rounded),
                                filled: true,
                                fillColor: sagana.cardBackground,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.radiusLg,
                                  ),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ── Filter chips — All, then one per market's
                            // Reference Prices. Wraps onto a second line on a
                            // narrow screen rather than scrolling sideways.
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _SectionChip(
                                  label: l10n.reportsAll,
                                  isSelected: _marketFilter == null,
                                  onTap: () =>
                                      setState(() => _marketFilter = null),
                                  cs: cs,
                                  sagana: sagana,
                                ),
                                for (final t in markets)
                                  _SectionChip(
                                    label: l10n.priceFilterMarketRef(
                                      MarketTypes.instance.shortLabel(t.code),
                                    ),
                                    isSelected: _marketFilter == t.code,
                                    onTap: () =>
                                        setState(() => _marketFilter = t.code),
                                    cs: cs,
                                    sagana: sagana,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // ── Reference Prices, one block per market ────
                            // Live farmer listings are not managed here: they
                            // live under Marketplace.
                            for (final t in markets)
                              if (_marketFilter == null ||
                                  _marketFilter == t.code) ...[
                                _SectionLabel(
                                  text: l10n.priceMarketReferenceTitle(
                                    MarketTypes.instance.label(t.code),
                                  ),
                                  count: _pricesFor(t.code).length,
                                  cs: cs,
                                ),
                                const SizedBox(height: 10),
                                _PriceGrid(
                                  prices: _pricesFor(t.code),
                                  isSearching: _searchQuery.isNotEmpty,
                                  isOnline: _isOnline,
                                  onTap: _openUpdateSheet,
                                  cs: cs,
                                  sagana: sagana,
                                ),
                                const SizedBox(height: 24),
                              ],

                            // Reserves room for the floating Add Price
                            // Entry button (Positioned bottom: 24, its own
                            // ~56px height) so scrolling to the end never
                            // leaves it sitting behind the FAB.
                            const SizedBox(height: 72),
                          ],
                        ),
                ),
              ),
            ],
          ),

          // ── Top App Bar ───────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopAppBar(
              title: l10n.priceManagementTitle,
              onBack: () => context.pop(),
              onMarketTrends: _openMarketTrends,
              marketTrendsTooltip: l10n.priceMarketTrendsTooltip,
              cs: cs,
              sagana: sagana,
            ),
          ),

          // ── FAB: Add New Price Entry ───────────────────────────────────────
          Positioned(
            bottom: 24,
            right: 20,
            child: FloatingActionButton.extended(
              onPressed: _openAddSheet,
              backgroundColor: _isOnline
                  ? AppConstants.primaryGreen
                  : cs.outline,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                l10n.priceAddNew,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top App Bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopAppBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onMarketTrends;
  final String marketTrendsTooltip;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _TopAppBar({
    required this.title,
    required this.onBack,
    required this.onMarketTrends,
    required this.marketTrendsTooltip,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: onBack,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.show_chart_rounded, color: cs.primary),
                tooltip: marketTrendsTooltip,
                onPressed: onMarketTrends,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Price Grid
// ─────────────────────────────────────────────────────────────────────────────

class _PriceGrid extends StatelessWidget {
  final List<PriceRecordModel> prices;
  final bool isSearching;
  final bool isOnline;
  final ValueChanged<PriceRecordModel> onTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _PriceGrid({
    required this.prices,
    required this.isSearching,
    required this.isOnline,
    required this.onTap,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    if (prices.isEmpty) return _EmptyPrices(cs: cs, isSearching: isSearching);
    // Two-column card grid — deliberately echoes Crop Management's grid
    // rhythm (see _CropCard in crop_management_screen.dart) so the two
    // screens read as one system, without reusing the same widget: a
    // price card's headline datum is the price, not a category label, so
    // the text block underneath the image is shaped differently.
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: prices.length,
      itemBuilder: (_, i) {
        final p = prices[i];
        return _PriceCard(
          price: p,
          isOnline: isOnline,
          onTap: () => onTap(p),
          cs: cs,
          sagana: sagana,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter chip + section label
// ─────────────────────────────────────────────────────────────────────────────

// Same filter-chip style already established for Inventory Management,
// Loan Item Catalog, Crop Management, and Program Management — a separate
// local copy here rather than a shared extraction, matching that same
// convention.
class _SectionChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _SectionChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outline.withValues(alpha: 0.20),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final int count;
  final ColorScheme cs;

  const _SectionLabel({
    required this.text,
    required this.count,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            text,
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
            color: cs.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
        ),
      ],
    );
  }
}


class _PriceCard extends StatelessWidget {
  final PriceRecordModel price;
  final bool isOnline;
  final VoidCallback onTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _PriceCard({
    required this.price,
    required this.isOnline,
    required this.onTap,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final badgeData = _badge(l10n, price.priceType);
    final deltaData = _delta(price);
    final updatedStr = _updatedLabel(price.recordedAt);
    final hasImage =
        price.cropImageUrl != null && price.cropImageUrl!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image fills the top of the card — the crop's identity comes
            // first, the price is what you read once you know what it is.
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  hasImage
                      ? Image.network(
                          price.cropImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.4,
                            ),
                            child: Icon(
                              Icons.eco_rounded,
                              size: 32,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                        )
                      : Container(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.4,
                          ),
                          child: Icon(
                            Icons.eco_rounded,
                            size: 32,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeData.bg,
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull,
                        ),
                      ),
                      child: Text(
                        badgeData.label,
                        style: GoogleFonts.inter(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: badgeData.fg,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.edit_rounded,
                        size: 13,
                        color: isOnline ? Colors.white : Colors.white54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Crop name + price + delta + freshness — below the image, same
            // information as before, resized so the image (not the price)
            // is what draws the eye first.
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    price.cropName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          '₱${price.price.toStringAsFixed(2)}',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                        ),
                      ),
                      Text(
                        '/${price.unit}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: cs.outline,
                        ),
                      ),
                      if (deltaData != null) ...[
                        const Spacer(),
                        Icon(deltaData.icon, size: 12, color: deltaData.color),
                        Text(
                          deltaData.label,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: deltaData.color,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.priceUpdatedPrefix(updatedStr),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 9, color: cs.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _BadgeData _badge(AppLocalizations l10n, String priceType) {
    final label = MarketTypes.instance.label(priceType).toUpperCase();
    // Styled by whether Buyers can see the market, not by its name.
    if (!MarketTypes.instance.isBuyerVisible(priceType)) {
      return _BadgeData(
        label: label,
        bg: AppConstants.primaryContainer,
        fg: AppConstants.onPrimaryContainer,
      );
    }
    return _BadgeData(
      label: label,
      bg: AppConstants.secondaryContainer.withValues(alpha: 0.25),
      fg: const Color(0xFF694300),
    );
  }

  _DeltaData? _delta(PriceRecordModel p) {
    final diff = p.priceDifference;
    if (diff == null || p.previousPrice == null || p.previousPrice == 0) {
      return null;
    }
    final pct = (diff / p.previousPrice!) * 100;
    if (pct.abs() < 0.01) {
      return const _DeltaData(
        icon: Icons.horizontal_rule_rounded,
        label: '0%',
        color: AppConstants.outline,
      );
    }
    return _DeltaData(
      icon: pct > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
      label: '${pct.abs().toStringAsFixed(1)}%',
      color: pct > 0 ? AppConstants.successGreen : AppConstants.errorRed,
    );
  }

  String _updatedLabel(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

class _BadgeData {
  final String label;
  final Color bg;
  final Color fg;
  const _BadgeData({required this.label, required this.bg, required this.fg});
}

class _DeltaData {
  final IconData icon;
  final String label;
  final Color color;
  const _DeltaData({
    required this.icon,
    required this.label,
    required this.color,
  });
}

class _EmptyPrices extends StatelessWidget {
  final ColorScheme cs;
  // True when the list is empty because of the search box, not because the
  // market has no reference prices yet.
  final bool isSearching;
  const _EmptyPrices({required this.cs, required this.isSearching});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 100,
      alignment: Alignment.center,
      child: Text(
        isSearching ? l10n.buyerPriceNoResultsTitle : l10n.priceNoRecordsYet,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Market Trends Card (current price + 30-day chart + recent entries)
// ─────────────────────────────────────────────────────────────────────────────

Color _marketAccent(ColorScheme cs, String priceType) =>
    MarketTypes.instance.isBuyerVisible(priceType)
    ? AppConstants.buyerBlue
    : cs.primary;

class _TrendLabel extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  const _TrendLabel({required this.text, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: cs.outline,
      ),
    );
  }
}

/// The Market Trends body. Public so its layout can be widget-tested.
class MarketTrendsCard extends StatelessWidget {
  final List<PriceRecordModel> prices;
  final List<PriceRecordModel> trendData;
  final String? selectedCropId;
  final String? selectedMarket;
  final bool loadingTrend;
  final ValueChanged<String> onCropSelected;
  final ValueChanged<String> onMarketSelected;
  final ColorScheme cs;
  final SaganaColors sagana;
  final AppLocalizations l10n;

  const MarketTrendsCard({
    super.key,
    required this.prices,
    required this.trendData,
    required this.selectedCropId,
    required this.selectedMarket,
    required this.loadingTrend,
    required this.onCropSelected,
    required this.onMarketSelected,
    required this.cs,
    required this.sagana,
    required this.l10n,
  });

  BoxDecoration get _cardDecoration => BoxDecoration(
    color: sagana.cardBackground,
    borderRadius: BorderRadius.circular(AppConstants.radiusXl),
    border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
    boxShadow: [
      BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10),
    ],
  );

  @override
  Widget build(BuildContext context) {
    // Dedupe by crop_id, not crop_name — since prices are now one row per
    // (crop_id, price_type), the same crop name can appear more than once.
    final seenIds = <String>{};
    final crops = <({String id, String name})>[];
    for (final p in prices) {
      if (seenIds.add(p.cropId)) {
        crops.add((id: p.cropId, name: p.cropName));
      }
    }

    if (crops.isEmpty) {
      return Container(
        decoration: _cardDecoration,
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.show_chart_rounded,
              size: 40,
              color: cs.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.priceMarketTrendsNoData,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // The crop's current reference price in each market it has one, in the
    // markets' own display order. When it has more than one, the cards double
    // as the selector for which market the chart and entries below describe.
    final order = MarketTypes.instance.activeTypes.map((t) => t.code).toList();
    int rank(String code) {
      final i = order.indexOf(code);
      return i < 0 ? order.length : i;
    }

    final cropPrices =
        prices.where((p) => p.cropId == selectedCropId).toList()..sort(
          (a, b) => rank(a.priceType).compareTo(rank(b.priceType)),
        );
    final activeMarket = cropPrices.any((p) => p.priceType == selectedMarket)
        ? selectedMarket
        : (cropPrices.isEmpty ? null : cropPrices.first.priceType);

    // One market's line only: a crop priced in both markets must not be drawn
    // as a single zig-zag between two different price lists.
    final series = trendData
        .where((p) => p.priceType == activeMarket)
        .toList();

    return Container(
      decoration: _cardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Crop selector — wraps onto extra lines instead of scrolling
          // sideways.
          _TrendLabel(text: l10n.priceTrendCropLabel, cs: cs),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final crop in crops)
                _SectionChip(
                  label: crop.name,
                  isSelected: selectedCropId == crop.id,
                  onTap: () => onCropSelected(crop.id),
                  cs: cs,
                  sagana: sagana,
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Current price — one card per market the selected crop has a
          // reference price in.
          if (cropPrices.isNotEmpty) ...[
            _TrendLabel(text: l10n.priceTrendCurrentLabel, cs: cs),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 10.0;
                final many = cropPrices.length > 1;
                final w = many
                    ? (constraints.maxWidth - gap) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final p in cropPrices)
                      SizedBox(
                        width: w,
                        child: _PriceSummaryMiniCard(
                          price: p,
                          selected: many && p.priceType == activeMarket,
                          onTap: many
                              ? () => onMarketSelected(p.priceType)
                              : null,
                          cs: cs,
                          l10n: l10n,
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
          ],

          // Trend chart
          _TrendLabel(text: l10n.priceMarketTrendsChartLabel, cs: cs),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: cs.outline.withValues(alpha: 0.08)),
            ),
            child: loadingTrend
                ? const SkeletonBlock(height: 150)
                : series.length < 2
                ? _TrendEmpty(cs: cs, l10n: l10n)
                : _TrendChart(series: series, cs: cs, l10n: l10n),
          ),
          const SizedBox(height: 20),

          // Recent entries — the selected crop in the selected market only.
          _TrendLabel(text: l10n.priceMarketTrendsHistoryLabel, cs: cs),
          const SizedBox(height: 10),
          _HistoryTable(
            entries: series.reversed.take(10).toList(),
            loading: loadingTrend,
            cs: cs,
          ),
        ],
      ),
    );
  }
}

/// Shown in place of the chart when the selected crop has fewer than two price
/// entries in the selected market, so there is no line to draw yet.
class _TrendEmpty extends StatelessWidget {
  final ColorScheme cs;
  final AppLocalizations l10n;
  const _TrendEmpty({required this.cs, required this.l10n});

  @override
  Widget build(BuildContext context) {
    // At least as tall as the chart it replaces, but free to grow if the text
    // wraps on a narrow screen.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 150),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.show_chart_rounded,
              size: 30,
              color: cs.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.priceTrendEmptyTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.priceTrendEmptyBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<PriceRecordModel> series; // oldest → newest, at least 2
  final ColorScheme cs;
  final AppLocalizations l10n;
  const _TrendChart({
    required this.series,
    required this.cs,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final values = series.map((p) => p.price).toList();
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final avg = values.reduce((a, b) => a + b) / values.length;
    final dateStyle = GoogleFonts.inter(fontSize: 10, color: cs.outline);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SizedBox(
            height: 140,
            width: double.infinity,
            child: CustomPaint(
              painter: _TrendChartPainter(
                data: series,
                lineColor: cs.primary,
                gradientColor: cs.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  AppUtils.formatDate(series.first.recordedAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: dateStyle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  AppUtils.formatDate(series.last.recordedAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: dateStyle,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TrendStat(
                label: l10n.buyerPriceStatLow,
                value: '₱${low.toStringAsFixed(2)}',
                color: AppConstants.errorRed,
                cs: cs,
              ),
            ),
            Expanded(
              child: _TrendStat(
                label: l10n.priceTrendAverage,
                value: '₱${avg.toStringAsFixed(2)}',
                color: cs.onSurface,
                cs: cs,
              ),
            ),
            Expanded(
              child: _TrendStat(
                label: l10n.buyerPriceStatHigh,
                value: '₱${high.toStringAsFixed(2)}',
                color: AppConstants.successGreen,
                cs: cs,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TrendStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final ColorScheme cs;
  const _TrendStat({
    required this.label,
    required this.value,
    required this.color,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontSize: 10, color: cs.outline),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// One market's current reference price for the selected crop. When the crop
/// has prices in more than one market the card is also the market selector.
class _PriceSummaryMiniCard extends StatelessWidget {
  final PriceRecordModel price;
  final bool selected;
  final VoidCallback? onTap;
  final ColorScheme cs;
  final AppLocalizations l10n;

  const _PriceSummaryMiniCard({
    required this.price,
    required this.selected,
    required this.onTap,
    required this.cs,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _marketAccent(cs, price.priceType);
    final delta = price.priceDifference;
    final deltaColor = price.isUp
        ? AppConstants.successGreen
        : price.isDown
        ? AppConstants.errorRed
        : cs.outline;
    final deltaIcon = price.isUp
        ? Icons.arrow_upward_rounded
        : price.isDown
        ? Icons.arrow_downward_rounded
        : Icons.remove_rounded;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.08)
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: selected ? accent : cs.outline.withValues(alpha: 0.08),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                    child: Text(
                      MarketTypes.instance.shortLabel(price.priceType),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                ),
                if (selected) ...[
                  const Spacer(),
                  Icon(Icons.check_circle_rounded, size: 16, color: accent),
                ],
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '₱${price.price.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    TextSpan(
                      text: ' /${price.unit}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (delta != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(deltaIcon, size: 12, color: deltaColor),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      '₱${delta.abs().toStringAsFixed(2)} ${l10n.priceVsPrevious}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 10, color: deltaColor),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Text(
              l10n.priceUpdatedPrefix(AppUtils.formatDate(price.recordedAt)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 10, color: cs.outline),
            ),
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Trend Chart Painter
// ─────────────────────────────────────────────────────────────────────────────

class _TrendChartPainter extends CustomPainter {
  final List<PriceRecordModel> data;
  final Color lineColor;
  final Color gradientColor;

  const _TrendChartPainter({
    required this.data,
    required this.lineColor,
    required this.gradientColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final prices = data.map((d) => d.price).toList();
    final minPrice = prices.reduce(math.min);
    final maxPrice = prices.reduce(math.max);
    final priceRange = (maxPrice - minPrice).abs();
    final effectiveRange = priceRange < 1 ? 1.0 : priceRange;
    final padding = effectiveRange * 0.15;

    final lo = minPrice - padding;
    final hi = maxPrice + padding;
    final range = hi - lo;

    double xAt(int i) => size.width * i / (data.length - 1);
    double yAt(double v) => size.height * (1 - (v - lo) / range);

    final path = Path();
    path.moveTo(xAt(0), yAt(data[0].price));
    for (int i = 1; i < data.length; i++) {
      final x0 = xAt(i - 1);
      final y0 = yAt(data[i - 1].price);
      final x1 = xAt(i);
      final y1 = yAt(data[i].price);
      final cpx = (x0 + x1) / 2;
      path.cubicTo(cpx, y0, cpx, y1, x1, y1);
    }

    // Gradient fill
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            gradientColor.withValues(alpha: 0.20),
            gradientColor.withValues(alpha: 0.00),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Line
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Dot at last point
    canvas.drawCircle(
      Offset(xAt(data.length - 1), yAt(data.last.price)),
      4,
      Paint()..color = lineColor,
    );
    canvas.drawCircle(
      Offset(xAt(data.length - 1), yAt(data.last.price)),
      4,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Price label at last point
    final tp = TextPainter(
      text: TextSpan(
        text: '₱${data.last.price.toStringAsFixed(2)}',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: lineColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        (xAt(data.length - 1) - tp.width / 2).clamp(0, size.width - tp.width),
        math.max(0, yAt(data.last.price) - tp.height - 8),
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter old) =>
      old.data != data || old.lineColor != lineColor;
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent entries (Market Trends)
// ─────────────────────────────────────────────────────────────────────────────

/// The most recent price entries for one crop in one market, newest first.
/// Each row shows the date and time on the left, the price and its change from
/// the entry before it on the right.
class _HistoryTable extends StatelessWidget {
  final List<PriceRecordModel> entries; // newest first
  final bool loading;
  final ColorScheme cs;

  const _HistoryTable({
    required this.entries,
    required this.loading,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.08)),
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SkeletonBlock(height: 96),
            )
          : entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Text(
                l10n.priceNoHistoryYet,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              children: [
                for (int i = 0; i < entries.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: cs.outline.withValues(alpha: 0.10),
                    ),
                  _HistoryRow(
                    price: entries[i],
                    // Change from the entry before it; the oldest one shown
                    // falls back to the previous price stored with it.
                    change: i + 1 < entries.length
                        ? entries[i].price - entries[i + 1].price
                        : entries[i].priceDifference,
                    cs: cs,
                  ),
                ],
              ],
            ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final PriceRecordModel price;
  final double? change;
  final ColorScheme cs;

  const _HistoryRow({
    required this.price,
    required this.change,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final up = change != null && change! > 0.004;
    final down = change != null && change! < -0.004;
    final changeColor = up
        ? AppConstants.successGreen
        : down
        ? AppConstants.errorRed
        : cs.outline;
    final changeIcon = up
        ? Icons.arrow_upward_rounded
        : down
        ? Icons.arrow_downward_rounded
        : Icons.remove_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppUtils.formatDate(price.recordedAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('h:mm a').format(price.recordedAt),
                  style: GoogleFonts.inter(fontSize: 10, color: cs.outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₱${price.price.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              if (change != null) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(changeIcon, size: 11, color: changeColor),
                    const SizedBox(width: 2),
                    Text(
                      '₱${change!.abs().toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: changeColor,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Update Price Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

/// The Update Price form for an existing reference price. Public so its
/// validation can be widget-tested without the screen's offline cache.
class UpdatePriceSheet extends StatefulWidget {
  final PriceRecordModel price;
  final PriceManagementRepository repo;
  final VoidCallback onSaved;

  const UpdatePriceSheet({
    super.key,
    required this.price,
    required this.repo,
    required this.onSaved,
  });

  @override
  State<UpdatePriceSheet> createState() => _UpdatePriceSheetState();
}

// ─────────────────────────────────────────────────────────────────────────────
// Field rules and widgets shared by Add Price Entry and Update Price, so both
// forms validate and look the same.
// ─────────────────────────────────────────────────────────────────────────────

String? _priceFieldError(AppLocalizations l10n, String? text) {
  final t = (text ?? '').trim();
  if (t.isEmpty) return l10n.priceRequired;
  final value = double.tryParse(t);
  if (value == null) return l10n.priceInvalidPriceError;
  if (value <= 0) return l10n.priceMustBePositive;
  if (!isValidCurrencyValue(t)) return l10n.priceTooManyDecimals;
  if (value > _kMaxReferencePrice) {
    return l10n.priceTooHigh(_kMaxReferencePrice.toStringAsFixed(0));
  }
  return null;
}

/// Source / Reference is required: empty or whitespace-only is refused.
String? _sourceFieldError(AppLocalizations l10n, String? text) {
  final t = (text ?? '').trim();
  if (t.isEmpty) return l10n.priceSourceRequired;
  if (t.length > _kMaxPriceSourceLength) {
    return l10n.priceSourceTooLong(_kMaxPriceSourceLength);
  }
  return null;
}

String? _dateFieldError(AppLocalizations l10n, DateTime? d) {
  if (d == null) return l10n.priceDateRequired;
  final latest = DateTime.now().add(
    const Duration(days: _kMaxEffectiveDaysAhead),
  );
  if (d.isAfter(latest) || d.isBefore(DateTime(2020))) {
    return l10n.priceDateOutOfRange(_kMaxEffectiveDaysAhead);
  }
  return null;
}

/// The Effective Date box: tap to pick, red border and a red message under it
/// when the date is not acceptable.
class _EffectiveDateField extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  const _EffectiveDateField({required this.date, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final l10n = AppLocalizations.of(context);

    return FormField<DateTime>(
      initialValue: date,
      validator: (d) => _dateFieldError(l10n, d),
      builder: (field) {
        final shown = field.value ?? date;
        final hasError = field.hasError;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: shown,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(
                    const Duration(days: _kMaxEffectiveDaysAhead),
                  ),
                );
                if (picked != null) {
                  field.didChange(picked);
                  onChanged(picked);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: hasError
                        ? AppConstants.errorRed
                        : cs.outline.withValues(alpha: 0.50),
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  color: sagana.cardBackground,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 16,
                      color: hasError ? AppConstants.errorRed : cs.outline,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${shown.month}/${shown.day}/${shown.year}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 12),
                child: Text(
                  field.errorText!,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppConstants.errorRed,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _UpdatePriceSheetState extends State<UpdatePriceSheet> {
  late final TextEditingController _priceCtrl;
  late final TextEditingController _sourceCtrl;
  DateTime _effectiveDate = DateTime.now();
  bool _isSaving = false;
  bool _showWarning = false;

  // Same inline validation as Add Price Entry: a Form, red borders and red
  // messages under each bad field, re-checked as they are fixed once a first
  // save has been attempted.
  final _formKey = GlobalKey<FormState>();
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
      text: widget.price.price.toStringAsFixed(2),
    );
    _sourceCtrl = TextEditingController();
    _validatePrice(widget.price.price.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _sourceCtrl.dispose();
    super.dispose();
  }

  void _validatePrice(String value) {
    final newVal = double.tryParse(value);
    if (newVal == null || widget.price.price == 0) {
      setState(() => _showWarning = false);
      return;
    }
    final diff = (newVal - widget.price.price).abs() / widget.price.price;
    setState(() => _showWarning = diff > 0.20);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _submitted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final newPrice = double.parse(_priceCtrl.text.trim());
    setState(() => _isSaving = true);
    try {
      final saved = await widget.repo.upsertPrice(
        cropId: widget.price.cropId,
        cropName: widget.price.cropName,
        price: newPrice,
        priceType: widget.price.priceType,
        unit: widget.price.unit,
        source: _sourceCtrl.text.trim(),
        effectiveDate: _effectiveDate,
      );
      // Broadcast notification to farmers
      await widget.repo.broadcastPriceNotification(
        previousPrice: saved.previousPrice,
        cropName: widget.price.cropName,
        newPrice: newPrice,
        unit: widget.price.unit,
        priceType: widget.price.priceType,
      );
      if (mounted) Navigator.pop(context);
      widget.onSaved();
    } catch (_) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.priceUpdateFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return ManagementModalShell(
      title: widget.price.cropName,
      subtitle: _priceTypeFullLabel(l10n, widget.price.priceType),
      body: Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Read-only crop summary — image, market type, crop name,
          // category, unit are all locked here; only price, effective
          // date, and source/reference (below) are editable.
          _ReadOnlyCropSummary(price: widget.price, l10n: l10n, cs: cs),
          const SizedBox(height: 16),

          // >20% warning
          if (_showWarning)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(color: cs.error.withValues(alpha: 0.20)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: cs.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.priceSignificantChangeWarning,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Price + Date row. Top-aligned so an error message under one
          // field never pushes the other out of line.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(
                      label: l10n.priceNewPriceLabel,
                      cs: cs,
                      required: true,
                    ),
                    TextFormField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ),
                      ],
                      onChanged: _validatePrice,
                      validator: (v) => _priceFieldError(l10n, v),
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixText: '₱ ',
                        prefixStyle: GoogleFonts.poppins(
                          fontSize: 22,
                          color: cs.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(
                      label: l10n.priceEffectiveDateLabel,
                      cs: cs,
                      required: true,
                    ),
                    _EffectiveDateField(
                      date: _effectiveDate,
                      onChanged: (d) => setState(() => _effectiveDate = d),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _FieldLabel(label: l10n.priceSourceRefDocLabel, cs: cs, required: true),
          TextFormField(
            controller: _sourceCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: l10n.priceSourceRefDocHint,
              hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
            ),
            validator: (v) => _sourceFieldError(l10n, v),
          ),
          const SizedBox(height: 16),

          // What saving will do. Deliberately no member count: it changed
          // with every sign-up and read as a promise about who exactly is told.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: cs.primary,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.priceUpdateNotifyNote,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
      footer: ManagementModalActions(
        primaryLabel: _isSaving ? l10n.saving : l10n.priceUpdatePriceAction,
        isLoading: _isSaving,
        onPrimary: _save,
      ),
    );
  }
}

// Read-only crop identity block for the Update Price sheet — image, market
// type, crop name, category, and unit are all locked (only price,
// effective date, and source/reference are editable elsewhere in that
// sheet); the Add Price sheet is a separate flow and doesn't use this.
class _ReadOnlyCropSummary extends StatelessWidget {
  final PriceRecordModel price;
  final AppLocalizations l10n;
  final ColorScheme cs;

  const _ReadOnlyCropSummary({
    required this.price,
    required this.l10n,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage =
        price.cropImageUrl != null && price.cropImageUrl!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            child: SizedBox(
              width: 52,
              height: 52,
              child: hasImage
                  ? Image.network(
                      price.cropImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
          ),
          const SizedBox(width: 12),
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
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 13,
                      color: cs.outline,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _priceTypeFullLabel(l10n, price.priceType),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (price.cropCategory != null &&
                        price.cropCategory!.isNotEmpty)
                      _LockedTag(label: price.cropCategory!, cs: cs),
                    _LockedTag(label: price.unit, cs: cs),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
      child: Icon(
        Icons.eco_rounded,
        size: 22,
        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

class _LockedTag extends StatelessWidget {
  final String label;
  final ColorScheme cs;

  const _LockedTag({required this.label, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
        border: Border.all(color: cs.outline.withValues(alpha: 0.20)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add New Price Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

/// The Add Price Entry form. Public so its validation can be widget-tested
/// without the screen's offline cache.
class AddPriceEntrySheet extends StatefulWidget {
  final List<Map<String, dynamic>> availableCrops;
  // Unit-of-measure options (the shared units table).
  final List<String> units;
  // Told when the Manager adds a unit here, so the screen keeps it too.
  final ValueChanged<String>? onUnitAdded;
  final PriceManagementRepository repo;
  final VoidCallback onSaved;

  const AddPriceEntrySheet({
    super.key,
    required this.availableCrops,
    required this.units,
    this.onUnitAdded,
    required this.repo,
    required this.onSaved,
  });

  @override
  State<AddPriceEntrySheet> createState() => _AddPriceEntrySheetState();
}

/// Highest reference price the form accepts. The column is DECIMAL(10,2); this
/// is a sanity ceiling well inside it, so a slipped key (an extra zero) is
/// caught before it is broadcast to every member.
const double _kMaxReferencePrice = 100000;

/// Longest Source / Reference the form accepts (same limit as an inventory
/// item's Source).
const int _kMaxPriceSourceLength = kInventorySourceMaxLength;

/// Furthest ahead an effective date may be set.
const int _kMaxEffectiveDaysAhead = 30;

class _AddPriceEntrySheetState extends State<AddPriceEntrySheet> {
  // Same inline-validation pattern as Crop Management → Add New Crop: a Form
  // with a validator on every field. Submitting an incomplete form marks each
  // bad field with a red border and a red message under it (no Snackbar);
  // after the first attempt the fields re-check as the Manager fixes them.
  final _formKey = GlobalKey<FormState>();
  bool _submitted = false;

  final _priceCtrl = TextEditingController();
  final _sourceCtrl = TextEditingController();
  Map<String, dynamic>? _selectedCrop;
  // Market Type is the first field the admin picks, driving which crops the
  // Crop Name field offers. Starts on the market whose prices the Manager sets
  // (the first such type in market_types), else the first market; never a
  // hardcoded code. Null only if the table has no active market.
  String? _priceType = _initialPriceType().isEmpty
      ? null
      : _initialPriceType();
  String? _unit = 'kg';
  DateTime _date = DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _priceCtrl.dispose();
    _sourceCtrl.dispose();
    super.dispose();
  }

  /// "e.g. A, B, C" built from the crops actually in the catalog for the chosen
  /// market, so no crop name is written into the app.
  String _cropHint(AppLocalizations l10n) {
    final names = _cropsForMarketType
        .map((c) => c['crop_name'] as String)
        .take(3)
        .toList();
    return names.isEmpty
        ? l10n.priceCropNameLabel
        : l10n.priceCropHintExamples(names.join(', '));
  }

  List<Map<String, dynamic>> get _cropsForMarketType => widget.availableCrops
      .where((c) => (c['crop_type'] as String?) == _priceType)
      .toList();

  // Unit options: the shared list, plus any unit added in this sheet, plus the
  // currently chosen unit if it somehow is not in the list.
  late List<String> _unitList = List<String>.of(widget.units);
  final _unitRepo = UnitRepository();

  List<String> get _unitOptions => [
    ..._unitList,
    if (_unit != null && !_unitList.contains(_unit)) _unit!,
  ];

  Future<String?> _addUnit() async {
    final added = await promptAddUnit(
      context,
      repo: _unitRepo,
      existing: _unitOptions,
    );
    if (added == null) return null;
    setState(() {
      if (!_unitList.contains(added)) _unitList = [..._unitList, added];
    });
    widget.onUnitAdded?.call(added);
    return added;
  }

  void _onMarketTypeChanged(String? type) {
    setState(() {
      _priceType = type;
      // A crop picked under the previous market type won't belong to this
      // one — clear it rather than keep a mismatched crop/market pair.
      if (_selectedCrop != null &&
          (_selectedCrop!['crop_type'] as String?) != type) {
        _selectedCrop = null;
      }
    });
  }

  // ── Validators ────────────────────────────────────────────────────────────

  String? _validateMarketType(AppLocalizations l10n, String? v) {
    if (v == null || MarketTypes.instance.byCode(v) == null) {
      return l10n.priceMarketTypeRequired;
    }
    return null;
  }

  String? _validateCrop(AppLocalizations l10n, String? text) {
    final typed = (text ?? '').trim();
    if (typed.isEmpty) return l10n.priceCropNameRequired;
    if (_selectedCrop == null) {
      // The name was typed in full without tapping the suggestion: accept it
      // when it matches a crop of this market exactly.
      final exact = _cropsForMarketType.where(
        (c) => (c['crop_name'] as String).toLowerCase() == typed.toLowerCase(),
      );
      if (exact.isEmpty) return l10n.priceSelectCropError;
      _selectedCrop = exact.first;
    }
    return null;
  }

  String? _validateUnit(AppLocalizations l10n, String? v) =>
      v == null || v.isEmpty ? l10n.priceUnitRequired : null;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _submitted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final price = double.parse(_priceCtrl.text.trim());
    final cropId = _selectedCrop!['id'] as String;
    final cropName = _selectedCrop!['crop_name'] as String;
    final priceType = _priceType!;
    final unit = _unit!;
    setState(() => _isSaving = true);
    try {
      final saved = await widget.repo.upsertPrice(
        cropId: cropId,
        cropName: cropName,
        price: price,
        priceType: priceType,
        unit: unit,
        source: _sourceCtrl.text.trim(),
        effectiveDate: _date,
      );
      await widget.repo.broadcastPriceNotification(
        previousPrice: saved.previousPrice,
        cropName: cropName,
        newPrice: price,
        unit: unit,
        priceType: priceType,
      );
      if (mounted) Navigator.pop(context);
      widget.onSaved();
    } catch (_) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.priceAddFailed)));
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return ManagementModalShell(
      title: l10n.priceAddNew,
      body: Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _FieldLabel(label: l10n.priceMarketTypeLabel, cs: cs, required: true),
            AppDropdownField<String>(
              value: _priceType,
              hintText: l10n.priceSelectMarketTypeHint,
              items: MarketTypes.instance.activeTypes
                  .map((t) => t.code)
                  .toList(),
              itemLabel: (t) => MarketTypes.instance.label(t),
              onChanged: _onMarketTypeChanged,
              validator: (v) => _validateMarketType(l10n, v),
            ),
            const SizedBox(height: 14),

            _FieldLabel(label: l10n.priceCropNameLabel, cs: cs, required: true),
            // Keyed on the selected market type — Autocomplete owns its own
            // internal TextEditingController (the `ctrl` fieldViewBuilder
            // hands back) and only recomputes options on text edits, so a
            // crop typed/selected under one market could stay displayed (and
            // its stale suggestions cached) after switching markets. A fresh
            // key recreates the widget on every market switch, so the crop
            // field can never carry over a selection from the previous market.
            Autocomplete<Map<String, dynamic>>(
              key: ValueKey(_priceType),
              displayStringForOption: (c) => c['crop_name'] as String,
              optionsBuilder: (v) => _cropsForMarketType.where(
                (c) => (c['crop_name'] as String).toLowerCase().contains(
                  v.text.toLowerCase(),
                ),
              ),
              onSelected: (c) => setState(() {
                _selectedCrop = c;
              }),
              fieldViewBuilder: (ctx, ctrl, focusNode, onSubmit) =>
                  TextFormField(
                    controller: ctrl,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      hintText: _cropHint(l10n),
                      hintStyle: GoogleFonts.inter(
                        fontSize: 13,
                        color: cs.outline,
                      ),
                    ),
                    onChanged: (v) {
                      // Typing away from the selected option invalidates it —
                      // a valid crop_id must come from picking a suggestion.
                      if (_selectedCrop != null &&
                          _selectedCrop!['crop_name'] != v) {
                        setState(() => _selectedCrop = null);
                      }
                    },
                    validator: (v) => _validateCrop(l10n, v),
                  ),
            ),
            if (_priceType != null && _cropsForMarketType.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l10n.priceNoCropsInCatalog(
                    MarketTypes.instance.label(_priceType),
                  ),
                  style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
                ),
              ),
            const SizedBox(height: 14),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel(
                        label: l10n.priceFieldPrice,
                        cs: cs,
                        required: true,
                      ),
                      TextFormField(
                        controller: _priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'),
                          ),
                        ],
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: const InputDecoration(
                          prefixText: '₱ ',
                          hintText: '0.00',
                        ),
                        validator: (v) => _priceFieldError(l10n, v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel(
                        label: l10n.priceUnitLabel,
                        cs: cs,
                        required: true,
                      ),
                      AppDropdownField<String>(
                        value: _unit,
                        hintText: l10n.priceSelectUnitHint,
                        items: _unitOptions,
                        itemLabel: (u) => u,
                        onChanged: (v) => setState(() => _unit = v),
                        validator: (v) => _validateUnit(l10n, v),
                        // The field is narrow, so the add row is a compact
                        // "+ Unit" (it carries its own plus, no extra icon).
                        addNewLabel: l10n.unitAddCompact,
                        addNewShowIcon: false,
                        onAddNew: _addUnit,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            _FieldLabel(
              label: l10n.priceEffectiveDateLabel,
              cs: cs,
              required: true,
            ),
            _EffectiveDateField(
              date: _date,
              onChanged: (d) => setState(() => _date = d),
            ),
            const SizedBox(height: 14),

            _FieldLabel(
              label: l10n.priceSourceRefLabel,
              cs: cs,
              required: true,
            ),
            TextFormField(
              controller: _sourceCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: l10n.priceSourceRefHint,
                hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              ),
              validator: (v) => _sourceFieldError(l10n, v),
            ),
          ],
        ),
      ),
      footer: ManagementModalActions(
        primaryLabel: _isSaving ? l10n.saving : l10n.priceAddNew,
        isLoading: _isSaving,
        onPrimary: _save,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared field label
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String label;
  final ColorScheme cs;
  // Adds the " *" marker used on required fields (as in Add New Crop).
  final bool required;

  const _FieldLabel({
    required this.label,
    required this.cs,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: label,
          children: [if (required) const TextSpan(text: ' *')],
        ),
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: cs.onSurface,
        ),
      ),
    );
  }
}
