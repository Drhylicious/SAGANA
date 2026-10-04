import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/price_record_model.dart';
import '../../../data/repositories/price_management_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/report_summary_widgets.dart'
    show ReportIconStatCard, ReportSectionCard;

// ─── Section filter ───────────────────────────────────────────────────────────
// The 4 groups the screen already splits data into — one filter chip per
// group, plus an implicit "All" (null) that shows every section.

enum _PriceSection { publicRef, coopRef, publicListings, coopListings }

// ─── Price type constants ─────────────────────────────────────────────────────

class _PriceTypes {
  static const sp3      = 'sp3_cooperative';
  static const market   = 'open_market';

  static String label(AppLocalizations l10n, String type) {
    switch (type) {
      case sp3:
        return l10n.priceCooperativeMarket;
      case market:
        return l10n.pricePublicMarket;
      default:
        return type;
    }
  }
}

// Presentation-layer mapping for PriceRecordModel.priceTypeLabel — the
// model getter (lib/data/models/price_record_model.dart) has no
// BuildContext to call AppLocalizations from, so the localized text is
// derived here instead, off the same priceType string, rather than
// changing the model.
String _priceTypeFullLabel(AppLocalizations l10n, String priceType) {
  switch (priceType) {
    case 'sp3_cooperative':
      return l10n.priceTypeCooperativeFull;
    case 'da_amad_market':
      return l10n.priceTypeDaAmadFull;
    default:
      return l10n.priceTypePublicFull;
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class PriceManagementScreen extends StatefulWidget {
  const PriceManagementScreen({super.key});

  @override
  State<PriceManagementScreen> createState() => _PriceManagementScreenState();
}

class _PriceManagementScreenState extends State<PriceManagementScreen> {
  final _repo = PriceManagementRepository();

  List<PriceRecordModel> _latestPrices          = [];
  List<PriceRecordModel> _history               = [];
  List<Map<String, dynamic>> _availableCrops    = [];
  List<Map<String, dynamic>> _liveListings      = [];
  bool _isLoading  = true;
  bool _isOnline   = true;

  // ── Selected crop for trend chart (holds a crop_id) ──────────────────────
  String? _selectedCropIdForChart;
  List<PriceRecordModel> _trendData = [];
  bool _loadingTrend = false;

  // ── Search + section filter ───────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  // null = All (every section shown); otherwise narrows to one of the 4
  // groups the screen already splits data into.
  _PriceSection? _sectionFilter;

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
      _repo.fetchPriceHistory(),
      _repo.fetchAvailableCrops(),
      _repo.fetchLiveListings(),
    ]);
    if (!mounted) return;
    final prices   = results[0] as List<PriceRecordModel>;
    final history  = results[1] as List<PriceRecordModel>;
    final crops    = results[2] as List<Map<String, dynamic>>;
    final listings = results[3] as List<Map<String, dynamic>>;
    setState(() {
      _latestPrices    = prices;
      _history         = history;
      _availableCrops  = crops;
      _liveListings    = listings;
      _isLoading       = false;
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
      _trendData    = data;
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
          _UpdatePriceSheet(price: price, repo: _repo, onSaved: _loadAll),
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
      builder: (_) => _AddPriceSheet(
        availableCrops: _availableCrops,
        repo: _repo,
        onSaved: _loadAll,
      ),
    );
  }

  // ── Live listing details (both markets) ───────────────────────────────
  // Reuses ListingReviewScreen exactly as All Listings does (same route,
  // same readOnly:true extra) rather than building a separate details
  // screen — a live listing here is always status 'approved', so
  // showActions there is already false regardless of readOnly (Approve/
  // Reject only ever show for a pending listing). Public's small edit-price
  // icon stays absent (editable:false); Cooperative's stays as its own
  // separate affordance on the card, unchanged.
  void _openListingDetails(Map<String, dynamic> listing) {
    context
        .push(
          AppRoutes.listingReview,
          extra: {'listingId': listing['id'] as String, 'readOnly': true},
        )
        .then((_) => _loadAll());
  }

  // ── Edit a live Cooperative Market listing's price ───────────────────────

  void _openEditListingPriceSheet(Map<String, dynamic> listing) {
    if (!_isOnline) {
      _showSnack(AppLocalizations.of(context).priceOfflineWarning);
      return;
    }
    final priceCtrl = TextEditingController(
      text: (listing['price_per_kg'] as num).toStringAsFixed(2),
    );
    bool isSaving = false;
    showManagementModal(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setSheet) {
          Future<void> submit() async {
            final price = double.tryParse(priceCtrl.text.trim());
            if (price == null || price <= 0) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(l10n.priceInvalidPriceError)),
              );
              return;
            }
            setSheet(() => isSaving = true);
            final ok = await _repo.updateListingPrice(
              listingId: listing['id'] as String,
              newPrice: price,
            );
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (ok) _loadAll();
              _showSnack(
                ok ? l10n.priceListingUpdated : l10n.adminInvFailedTryAgain,
              );
          }

          return ManagementModalShell(
            title: l10n.priceEditListingTitle,
            subtitle: listing['crop_name'] as String,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                  _FieldLabel(
                    label: l10n.priceFieldPricePerKg,
                    cs: Theme.of(ctx).colorScheme,
                  ),
                TextFormField(
                  controller: priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      prefixText: '₱ ',
                      hintText: '0.00',
                    ),
                ),
              ],
            ),
            footer: ManagementModalActions(
                primaryLabel: isSaving
                    ? l10n.saving
                    : l10n.priceSavePriceAction,
              isLoading: isSaving,
              onPrimary: submit,
            ),
          );
          },
        );
      },
    );
  }

  // ── Market Trends (top-bar icon) ──────────────────────────────────────────
  // Moved behind an icon instead of an inline section in the main scroll —
  // the redesigned screen already carries KPIs, search, 4 filter chips, and
  // 4 data sections, so a 5th inline analytics block (chart + history
  // table) would push everything else further down. Mirrors the existing
  // pattern of a secondary feature living behind a top-bar icon (e.g.
  // Broadcast's campaign icon on the 5 other admin root screens).
  void _openMarketTrends() {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    showManagementModal(
      context: context,
      // StatefulBuilder is required here: showManagementModal's builder
      // runs once when the modal opens, so without a local setState the
      // modal never redraws when a crop chip is tapped — the parent
      // screen's own setState (in _onChartCropSelected/_loadTrend) rebuilds
      // price_management_screen behind the modal, not the modal route
      // itself. setModalState mirrors that state into the visible sheet.
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
            bodyIsScrollable: true,
            body: _MarketTrendsCard(
              prices: _latestPrices,
              history: _history,
              trendData: _trendData,
              selectedCropId: _selectedCropIdForChart,
              loadingTrend: _loadingTrend,
              onCropSelected: (cropId) async {
                if (_selectedCropIdForChart == cropId) return;
                setState(() {
                  _selectedCropIdForChart = cropId;
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

  // ── KPI cards (dashboard.md section 12) ───────────────────────────────────
  // Counts for the same 4 categories the sections below already split the
  // data into — Public/Cooperative reference prices, Public/Cooperative
  // live listings — so these are a summary of data the screen already
  // fetches, not a new query.
  Widget _buildPriceKpiCards(AppLocalizations l10n, ColorScheme cs) {
    final publicCount = _latestPrices
        .where((p) => p.priceType == _PriceTypes.market)
        .length;
    final coopCount = _latestPrices
        .where((p) => p.priceType == _PriceTypes.sp3)
        .length;
    final livePublicCount = _liveListings
        .where((l) => l['crop_type'] != _PriceTypes.sp3)
        .length;
    final liveCoopCount = _liveListings
        .where((l) => l['crop_type'] == _PriceTypes.sp3)
        .length;

    // Grouped inside the same outer titled container the Report tab uses
    // (Executive Snapshot etc.), not just individually restyled cards.
    // Horizontal-scrolling row (matches Crop/Program Management's KPI
    // treatment) instead of a fixed 2x2 grid. Labels are the shortened
    // KPI-only wording (priceKpi*) — distinct from the fuller
    // price*/priceLiveListings* keys still used as section headers below,
    // so renaming these doesn't also rename the sections.
    final cards = <Widget>[
      ReportIconStatCard(
                  icon: Icons.storefront_rounded,
                  accent: AppConstants.buyerBlue,
        label: l10n.priceKpiPublicRef,
                  value: '$publicCount',
                ),
      ReportIconStatCard(
                  icon: Icons.groups_rounded,
                  accent: AppConstants.primaryGreen,
        label: l10n.priceKpiCoopRef,
                  value: '$coopCount',
                ),
      ReportIconStatCard(
                  icon: Icons.sensors_rounded,
                  accent: AppConstants.amber,
        label: l10n.priceKpiPublicListings,
                  value: '$livePublicCount',
                ),
      ReportIconStatCard(
                  icon: Icons.sensors_rounded,
                  accent: AppConstants.warningAmber,
        label: l10n.priceKpiCoopListings,
                  value: '$liveCoopCount',
                ),
    ];
    return ReportSectionCard(
      title: 'Price Overview',
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

  @override
  Widget build(BuildContext context) {
    final l10n   = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs     = Theme.of(context).colorScheme;

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
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppConstants.primaryGreen,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                          children: [
                            // ── Offline warning ──────────────────────────
                            if (!_isOnline) _OfflineWarningBanner(l10n: l10n),
                            if (!_isOnline) const SizedBox(height: 12),

                            // ── KPI cards (section 12) ───────────────────
                            _buildPriceKpiCards(l10n, cs),
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
                            const SizedBox(height: 10),

                            // ── Filter chips — All | Public Ref. | Coop
                            // Ref. | Public Listings | Coop Listings ───────
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.zero,
                              child: Row(
                              children: [
                                  _SectionChip(
                                    label: l10n.reportsAll,
                                    isSelected: _sectionFilter == null,
                                    onTap: () =>
                                        setState(() => _sectionFilter = null),
                                    cs: cs,
                                    sagana: sagana,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: _SectionChip(
                                      label: l10n.priceFilterPublicRef,
                                      isSelected:
                                          _sectionFilter ==
                                          _PriceSection.publicRef,
                                      onTap: () => setState(
                                        () => _sectionFilter =
                                            _PriceSection.publicRef,
                                ),
                                      cs: cs,
                                      sagana: sagana,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: _SectionChip(
                                      label: l10n.priceFilterCoopRef,
                                      isSelected:
                                          _sectionFilter ==
                                          _PriceSection.coopRef,
                                      onTap: () => setState(
                                        () => _sectionFilter =
                                            _PriceSection.coopRef,
                                      ),
                                      cs: cs,
                                      sagana: sagana,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: _SectionChip(
                                      label: l10n.priceFilterPublicListings,
                                      isSelected:
                                          _sectionFilter ==
                                          _PriceSection.publicListings,
                                      onTap: () => setState(
                                        () => _sectionFilter =
                                            _PriceSection.publicListings,
                                      ),
                                      cs: cs,
                                      sagana: sagana,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: _SectionChip(
                                      label: l10n.priceFilterCoopListings,
                                      isSelected:
                                          _sectionFilter ==
                                          _PriceSection.coopListings,
                                      onTap: () => setState(
                                        () => _sectionFilter =
                                            _PriceSection.coopListings,
                                      ),
                                      cs: cs,
                                      sagana: sagana,
                                  ),
                                ),
                              ],
                            ),
                            ),
                            const SizedBox(height: 20),

                            // ── Public Market — Reference Prices ─────────
                            if (_sectionFilter == null ||
                                _sectionFilter == _PriceSection.publicRef) ...[
                              _SectionLabel(
                                  text: l10n.pricePublicMarketReference,
                                cs: cs,
                              ),
                              const SizedBox(height: 8),
                              _PriceGrid(
                                prices: _latestPrices
                                    .where(
                                      (p) =>
                                          p.priceType == _PriceTypes.market &&
                                          (_searchQuery.isEmpty ||
                                              p.cropName.toLowerCase().contains(
                                                _searchQuery,
                                              )),
                                    )
                                    .toList(),
                                isOnline: _isOnline,
                                onTap: _openUpdateSheet,
                                cs: cs,
                                sagana: sagana,
                              ),
                              const SizedBox(height: 20),
                            ],

                            // ── Cooperative Market — Reference Prices ────
                            if (_sectionFilter == null ||
                                _sectionFilter == _PriceSection.coopRef) ...[
                              _SectionLabel(
                                  text: l10n.priceCoopMarketReference,
                                cs: cs,
                              ),
                              const SizedBox(height: 8),
                              _PriceGrid(
                                prices: _latestPrices
                                    .where(
                                      (p) =>
                                          p.priceType == _PriceTypes.sp3 &&
                                          (_searchQuery.isEmpty ||
                                              p.cropName.toLowerCase().contains(
                                                _searchQuery,
                                              )),
                                    )
                                    .toList(),
                                isOnline: _isOnline,
                                onTap: _openUpdateSheet,
                                cs: cs,
                                sagana: sagana,
                              ),
                              const SizedBox(height: 20),
                            ],

                            // ── Live Listings — Public Market ────────────
                            if (_sectionFilter == null ||
                                _sectionFilter ==
                                    _PriceSection.publicListings) ...[
                            _SectionLabel(
                                text: l10n.priceLiveListingsPublicTitle,
                                cs: cs,
                              ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.priceLiveListingsPublicNote,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                            ),
                            const SizedBox(height: 8),
                            _ListingGrid(
                              listings: _liveListings
                                    .where(
                                      (l) =>
                                          l['crop_type'] != _PriceTypes.sp3 &&
                                          (_searchQuery.isEmpty ||
                                              (l['crop_name'] as String? ?? '')
                                                  .toLowerCase()
                                                  .contains(_searchQuery)),
                                    )
                                  .toList(),
                              editable: false,
                              onEdit: null,
                                onTap: _openListingDetails,
                              cs: cs,
                              sagana: sagana,
                            ),
                            const SizedBox(height: 20),
                            ],

                            // ── Live Listings — Cooperative Market ───────
                            if (_sectionFilter == null ||
                                _sectionFilter ==
                                    _PriceSection.coopListings) ...[
                            _SectionLabel(
                                text: l10n.priceLiveListingsCoopTitle,
                                cs: cs,
                              ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.priceLiveListingsCoopNote,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                            ),
                            const SizedBox(height: 8),
                            _ListingGrid(
                              listings: _liveListings
                                    .where(
                                      (l) =>
                                          l['crop_type'] == _PriceTypes.sp3 &&
                                          (_searchQuery.isEmpty ||
                                              (l['crop_name'] as String? ?? '')
                                                  .toLowerCase()
                                                  .contains(_searchQuery)),
                                    )
                                  .toList(),
                              editable: true,
                              onEdit: _openEditListingPriceSheet,
                                onTap: _openListingDetails,
                              cs: cs,
                              sagana: sagana,
                            ),
                            ],

                            // Reserves room for the floating Add Price
                            // Entry button (Positioned bottom: 24, its own
                            // ~56px height) so scrolling to the end never
                            // leaves it sitting behind the FAB.
                            const SizedBox(height: 96),
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
// Offline Warning Banner
// ─────────────────────────────────────────────────────────────────────────────

class _OfflineWarningBanner extends StatelessWidget {
  final AppLocalizations l10n;
  const _OfflineWarningBanner({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.error.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: cs.error, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.priceSystemOfflineTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onErrorContainer,
                  ),
                ),
                Text(
                  l10n.priceSystemOfflineBody,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: cs.onErrorContainer.withValues(alpha: 0.80),
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

// ─────────────────────────────────────────────────────────────────────────────
// Price Grid
// ─────────────────────────────────────────────────────────────────────────────

class _PriceGrid extends StatelessWidget {
  final List<PriceRecordModel> prices;
  final bool isOnline;
  final ValueChanged<PriceRecordModel> onTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _PriceGrid({
    required this.prices,
    required this.isOnline,
    required this.onTap,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    if (prices.isEmpty) return _EmptyPrices(cs: cs);
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
// Section label (Phase 6b — the 4-section Price Management layout)
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
  final ColorScheme cs;

  const _SectionLabel({required this.text, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live listing cards — Phase 6b
// ─────────────────────────────────────────────────────────────────────────────

class _ListingGrid extends StatelessWidget {
  final List<Map<String, dynamic>> listings;
  final bool editable;
  final ValueChanged<Map<String, dynamic>>? onEdit;
  // Whole-card tap — opens ListingReviewScreen(readOnly: true) for either
  // market. `editable`'s small edit-price icon (Coop only) stays a
  // separate, additional affordance layered on top, unchanged.
  final ValueChanged<Map<String, dynamic>> onTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _ListingGrid({
    required this.listings,
    required this.editable,
    required this.onEdit,
    required this.onTap,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    if (listings.isEmpty) {
      final l10n = AppLocalizations.of(context);
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        ),
        alignment: Alignment.center,
        child: Text(
          l10n.priceNoLiveListings,
          style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      );
    }
    // Same 2-column, image-forward grid as the Reference Prices sections
    // (_PriceGrid/_PriceCard) — Public and Cooperative both render through
    // this one component; only `editable` (and therefore whether the edit
    // overlay appears) differs between the two call sites.
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
      itemCount: listings.length,
      itemBuilder: (_, i) {
        final l = listings[i];
        return _ListingCard(
          listing: l,
          editable: editable,
          onEdit: onEdit == null ? null : () => onEdit!(l),
          onTap: () => onTap(l),
          cs: cs,
          sagana: sagana,
        );
      },
    );
  }
}

class _ListingCard extends StatelessWidget {
  final Map<String, dynamic> listing;
  final bool editable;
  final VoidCallback? onEdit;
  final VoidCallback onTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _ListingCard({
    required this.listing,
    required this.editable,
    required this.onEdit,
    required this.onTap,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cropName = listing['crop_name'] as String;
    final price = (listing['price_per_kg'] as num).toDouble();
    final remaining =
        (listing['remaining_kg'] as num?)?.toDouble() ??
        (listing['volume_kg'] as num).toDouble();
    final marketLabel = listing['crop_type'] == _PriceTypes.sp3
        ? l10n.priceMarketBadgeCoop
        : l10n.priceMarketBadgePublic;
    // The listing's own photo — never Crop Management's image. A listing
    // with no photo shows a generic placeholder, not the crop's reference
    // image, to keep the two sources genuinely independent rather than
    // silently falling back to one another.
    final photoUrl = listing['photo_url'] as String?;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

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
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                hasPhoto
                    ? Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.4,
                            ),
                            child: Icon(
                              Icons.image_outlined,
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
                            Icons.image_outlined,
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
                      color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull,
                        ),
                    ),
                    child: Text(
                      marketLabel,
                      style: GoogleFonts.inter(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (editable)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: onEdit,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                          child: const Icon(
                            Icons.edit_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cropName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₱${price.toStringAsFixed(2)}/kg',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.priceListingKgAvailable(remaining.toStringAsFixed(1)),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: cs.onSurfaceVariant,
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
    final badgeData  = _badge(l10n, price.priceType);
    final deltaData  = _delta(price);
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
    switch (priceType) {
      case _PriceTypes.sp3:
        return _BadgeData(
          label: l10n.priceMarketBadgeCoop,
          bg: AppConstants.primaryContainer,
          fg: AppConstants.onPrimaryContainer,
        );
      default:
        return _BadgeData(
          label: l10n.priceMarketBadgePublic,
          bg: AppConstants.secondaryContainer.withValues(alpha: 0.25),
          fg: const Color(0xFF694300),
        );
    }
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
  const _EmptyPrices({required this.cs});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 100,
      alignment: Alignment.center,
      child: Text(
        l10n.priceNoRecordsYet,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Market Trends Card (chart + history table)
// ─────────────────────────────────────────────────────────────────────────────

class _MarketTrendsCard extends StatelessWidget {
  final List<PriceRecordModel> prices;
  final List<PriceRecordModel> history;
  final List<PriceRecordModel> trendData;
  final String? selectedCropId;
  final bool loadingTrend;
  final ValueChanged<String> onCropSelected;
  final ColorScheme cs;
  final SaganaColors sagana;
  final AppLocalizations l10n;

  const _MarketTrendsCard({
    required this.prices,
    required this.history,
    required this.trendData,
    required this.selectedCropId,
    required this.loadingTrend,
    required this.onCropSelected,
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

    // Both the price summary and the history table are scoped to the
    // selected crop, so tapping a chip visibly changes the entire card —
    // not just the chart underneath it.
    final cropPrices = prices.where((p) => p.cropId == selectedCropId).toList();
    final cropHistory = history
        .where((p) => p.cropId == selectedCropId)
        .toList();

    return Container(
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Crop selector chips
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SizedBox(
              height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: crops.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final crop   = crops[i];
                    final active = selectedCropId == crop.id;
                    return GestureDetector(
                      onTap: () => onCropSelected(crop.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: active ? cs.primary : sagana.cardBackground,
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull,
                        ),
                        border: Border.all(
                          color: active
                              ? cs.primary
                              : cs.outline.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Text(
                        crop.name,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: active ? Colors.white : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Price summary — one mini-card per price type the selected crop
          // currently has (Cooperative and/or Public), each with a
          // change-since-last-entry indicator.
          if (cropPrices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (int i = 0; i < cropPrices.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: _PriceSummaryMiniCard(
                        price: cropPrices[i],
                        cs: cs,
                        l10n: l10n,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 20),

          // Trend chart
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l10n.priceMarketTrendsChartLabel,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: cs.outline,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 140,
              child: loadingTrend
                  ? Center(
                      child: CircularProgressIndicator(
                        color: cs.primary,
                        strokeWidth: 2,
                      ),
                    )
                  : trendData.length < 2
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.show_chart_rounded,
                            size: 26,
                            color: cs.outline.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.priceNotEnoughTrendData,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: cs.outline,
                            ),
                          ),
                        ],
                      ),
                    )
                  : CustomPaint(
                      size: const Size(double.infinity, 140),
                      painter: _TrendChartPainter(
                        data: trendData,
                        lineColor: cs.primary,
                        gradientColor: cs.primary,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 20),

          // History table — scoped to the selected crop only.
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.08)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              l10n.priceMarketTrendsHistoryLabel,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: cs.outline,
              ),
            ),
          ),
          _HistoryTable(history: cropHistory, cs: cs),
        ],
      ),
    );
  }
}

class _PriceSummaryMiniCard extends StatelessWidget {
  final PriceRecordModel price;
  final ColorScheme cs;
  final AppLocalizations l10n;

  const _PriceSummaryMiniCard({
    required this.price,
    required this.cs,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final isCoop = price.priceType == _PriceTypes.sp3;
    final badgeLabel = isCoop
        ? l10n.priceBadgeCoopShort
        : l10n.priceBadgePublicShort;
    final badgeColor = isCoop ? cs.primary : AppConstants.buyerBlue;
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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                        ),
                        child: Text(
              badgeLabel,
                          style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: badgeColor,
                      ),
                ),
              ),
          const SizedBox(height: 8),
          Text(
            price.formattedPrice,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
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
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 10, color: deltaColor),
            ),
          ),
              ],
          ),
          ],
        ],
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
// History Table
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryTable extends StatelessWidget {
  final List<PriceRecordModel> history;
  final ColorScheme cs;

  const _HistoryTable({required this.history, required this.cs});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row — no Crop column: this table is always scoped to
          // whichever crop chip is currently selected above it.
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  l10n.priceColType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: cs.outline,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  l10n.priceColPrice,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: cs.outline,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  l10n.priceColDate,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: cs.outline,
                  ),
                ),
              ),
            ],
          ),
          Divider(height: 12, color: cs.outline.withValues(alpha: 0.10)),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                l10n.priceNoHistoryYet,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            )
          else
            ...history.take(10).map((p) => _HistoryRow(price: p, cs: cs)),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final PriceRecordModel price;
  final ColorScheme cs;

  const _HistoryRow({required this.price, required this.cs});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // A compact variant just for this narrow table column — the canonical
    // "Cooperative Market"/"Public Market" labels (Phase 6 naming
    // convention) don't fit this column's width the way the old, shorter
    // "SP3 Buying"/"Market Avg" labels did.
    final badgeLabel = price.priceType == _PriceTypes.sp3
        ? l10n.priceBadgeCoopShort
        : l10n.priceBadgePublicShort;
    final dateStr = _dateStr(price.recordedAt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              ),
              child: Text(
                badgeLabel,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '₱${price.price.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: price.priceType == _PriceTypes.sp3
                    ? cs.primary
                    : cs.onSurface,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              dateStr,
              textAlign: TextAlign.end,
              style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
            ),
          ),
        ],
      ),
    );
  }

  String _dateStr(DateTime dt) {
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
    return '${months[dt.month - 1]} ${dt.day}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Update Price Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _UpdatePriceSheet extends StatefulWidget {
  final PriceRecordModel price;
  final PriceManagementRepository repo;
  final VoidCallback onSaved;

  const _UpdatePriceSheet({
    required this.price,
    required this.repo,
    required this.onSaved,
  });

  @override
  State<_UpdatePriceSheet> createState() => _UpdatePriceSheetState();
}

class _UpdatePriceSheetState extends State<_UpdatePriceSheet> {
  late final TextEditingController _priceCtrl;
  late final TextEditingController _sourceCtrl;
  DateTime _effectiveDate = DateTime.now();
  bool _isSaving  = false;
  bool _showWarning = false;
  // Null while loading — the notify note stays hidden rather than ever
  // flashing a wrong transient number (e.g. 0) before the real count
  // arrives; the fetch itself is a single lightweight count query.
  int? _recipientCount;

  @override
  void initState() {
    super.initState();
    _priceCtrl  = TextEditingController(
      text: widget.price.price.toStringAsFixed(2),
    );
    _sourceCtrl = TextEditingController();
    _validatePrice(widget.price.price.toStringAsFixed(2));
    _loadRecipientCount();
  }

  Future<void> _loadRecipientCount() async {
    final count = await widget.repo.fetchNotificationRecipientCount();
    if (mounted) setState(() => _recipientCount = count);
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
    final newPrice = double.tryParse(_priceCtrl.text.trim());
    if (newPrice == null || newPrice <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.priceInvalidPriceError)));
      return;
    }
    setState(() => _isSaving = true);
    try {
      await widget.repo.upsertPrice(
        cropId:        widget.price.cropId,
        cropName:      widget.price.cropName,
        price:         newPrice,
        priceType:     widget.price.priceType,
        unit:          widget.price.unit,
        source:        _sourceCtrl.text.trim().isEmpty
            ? null
            : _sourceCtrl.text.trim(),
        effectiveDate: _effectiveDate,
      );
      // Broadcast notification to farmers
      await widget.repo.broadcastPriceNotification(
        cropName: widget.price.cropName,
        newPrice: newPrice,
        unit:     widget.price.unit,
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _effectiveDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return ManagementModalShell(
      title: widget.price.cropName,
      subtitle: _priceTypeFullLabel(l10n, widget.price.priceType),
      body: Column(
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

          // Price + Date row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(label: l10n.priceNewPriceLabel, cs: cs),
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
                    _FieldLabel(label: l10n.priceEffectiveDateLabel, cs: cs),
                    GestureDetector(
                      onTap: _pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: cs.outline.withValues(alpha: 0.50),
                          ),
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                          color: context.saganaColors.cardBackground,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 16,
                              color: cs.outline,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_effectiveDate.month}/${_effectiveDate.day}/${_effectiveDate.year}',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _FieldLabel(label: l10n.priceSourceRefDocLabel, cs: cs),
          TextFormField(
            controller: _sourceCtrl,
            decoration: InputDecoration(
              hintText: l10n.priceSourceRefDocHint,
              hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
            ),
          ),
          const SizedBox(height: 16),

          // Hidden until the real recipient count loads, rather than ever
          // showing a wrong placeholder — was previously a hardcoded "52".
          if (_recipientCount != null)
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
                      l10n.priceUpdateNotifyNote(_recipientCount!),
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

class _AddPriceSheet extends StatefulWidget {
  final List<Map<String, dynamic>> availableCrops;
  final PriceManagementRepository repo;
  final VoidCallback onSaved;

  const _AddPriceSheet({
    required this.availableCrops,
    required this.repo,
    required this.onSaved,
  });

  @override
  State<_AddPriceSheet> createState() => _AddPriceSheetState();
}

class _AddPriceSheetState extends State<_AddPriceSheet> {
  final _priceCtrl  = TextEditingController();
  final _sourceCtrl = TextEditingController();
  Map<String, dynamic>? _selectedCrop;
  // Market Type is now the first field the admin picks (Phase 6 reorder),
  // driving which crops the Crop Name field offers — the reverse of the
  // old crop-picks-type direction.
  String _priceType  = _PriceTypes.sp3;
  String _unit       = 'kg';
  DateTime _date     = DateTime.now();
  bool _isSaving     = false;

  @override
  void dispose() {
    _priceCtrl.dispose();
    _sourceCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _cropsForMarketType => widget.availableCrops
      .where((c) => (c['crop_type'] as String?) == _priceType)
      .toList();

  void _onMarketTypeChanged(String type) {
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

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final price = double.tryParse(_priceCtrl.text.trim());
    if (_selectedCrop == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.priceSelectCropError)));
      return;
    }
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.priceInvalidPriceError)));
      return;
    }
    final cropId   = _selectedCrop!['id'] as String;
    final cropName = _selectedCrop!['crop_name'] as String;
    setState(() => _isSaving = true);
    try {
      await widget.repo.upsertPrice(
        cropId:        cropId,
        cropName:      cropName,
        price:         price,
        priceType:     _priceType,
        unit:          _unit,
        source:        _sourceCtrl.text.trim().isEmpty
            ? null
            : _sourceCtrl.text.trim(),
        effectiveDate: _date,
      );
      await widget.repo.broadcastPriceNotification(
        cropName: cropName,
        newPrice: price,
        unit:     _unit,
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final l10n = AppLocalizations.of(context);

    return ManagementModalShell(
      title: l10n.priceAddNew,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _FieldLabel(label: l10n.priceMarketTypeLabel, cs: cs),
          AppDropdownField<String>(
            value: _priceType,
            hintText: l10n.priceSelectMarketTypeHint,
            items: const [_PriceTypes.sp3, _PriceTypes.market],
            itemLabel: (t) => _PriceTypes.label(l10n, t),
            onChanged: (v) {
              if (v != null) _onMarketTypeChanged(v);
            },
          ),
          const SizedBox(height: 14),

          _FieldLabel(label: l10n.priceCropNameLabel, cs: cs),
          // Keyed on the selected market type — Autocomplete owns its own
          // internal TextEditingController (the `ctrl` fieldViewBuilder
          // hands back), never actually bound to this class's _cropCtrl
          // despite _cropCtrl being written to elsewhere. That meant a
          // crop name typed/selected under one market could stay visibly
          // displayed (and its stale suggestion list stay cached) after
          // switching markets, since Autocomplete only recomputes options
          // on text edits, not when _cropsForMarketType's underlying data
          // changes. A fresh key forces Flutter to fully recreate the
          // widget (and its internal controller/options cache) on every
          // market switch, guaranteeing the crop field can never carry
          // over a selection from the previous market.
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
            fieldViewBuilder: (ctx, ctrl, focusNode, onSubmit) => TextFormField(
              controller: ctrl,
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: _priceType == _PriceTypes.sp3
                    ? l10n.priceCropHintSp3
                    : l10n.priceCropHintMarket,
                hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              ),
              onChanged: (v) {
                // Typing away from the selected option invalidates it —
                // a valid crop_id must come from picking a suggestion.
                if (_selectedCrop != null && _selectedCrop!['crop_name'] != v) {
                  setState(() => _selectedCrop = null);
                }
              },
            ),
          ),
          if (_cropsForMarketType.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.priceNoCropsInCatalog(_PriceTypes.label(l10n, _priceType)),
                style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
              ),
            ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(label: l10n.priceFieldPrice, cs: cs),
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
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel(label: l10n.priceUnitLabel, cs: cs),
                    AppDropdownField<String>(
                      value: _unit,
                      hintText: l10n.priceSelectUnitHint,
                      items: const ['kg', 'g', 'pc', 'sack'],
                      itemLabel: (u) => u,
                      onChanged: (v) => setState(() => _unit = v ?? 'kg'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _FieldLabel(label: l10n.priceEffectiveDateLabel, cs: cs),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(color: cs.outline.withValues(alpha: 0.50)),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                color: sagana.cardBackground,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 16,
                    color: cs.outline,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_date.month}/${_date.day}/${_date.year}',
                    style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          _FieldLabel(label: l10n.priceSourceRefLabel, cs: cs),
          TextFormField(
            controller: _sourceCtrl,
            decoration: InputDecoration(
              hintText: l10n.priceSourceRefHint,
              hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
            ),
          ),
        ],
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

  const _FieldLabel({required this.label, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: cs.onSurface,
        ),
      ),
    );
  }
}