import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/analytics_model.dart';
import '../../../data/repositories/analytics_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/profile_state_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_navigation_drawer.dart';
import '../../widgets/planting_forecast_card.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/top_harvested_crops_chart.dart';
import '../../widgets/trend_chart_painter.dart';

// Period labels live on AnalyticsPeriod as plain English
// (analytics_model.dart) since the model has no AppLocalizations access —
// same reasoning PlantingForecast's own trend label/explanation were moved
// out to their widget for (see planting_forecast_card.dart). Shared by the
// period selector pills and the Price History chart's period badge, so
// both sections can never show a differently-worded period label.
String _periodLabel(AppLocalizations l10n, AnalyticsPeriod p) {
  switch (p) {
    case AnalyticsPeriod.thisMonth:
      return l10n.farmerAnalyticsPeriodThisMonth;
    case AnalyticsPeriod.thisSeason:
      return l10n.farmerAnalyticsPeriodThisSeason;
    case AnalyticsPeriod.thisYear:
      return l10n.farmerAnalyticsPeriodThisYear;
    case AnalyticsPeriod.allTime:
      return l10n.farmerAnalyticsPeriodAllTime;
  }
}

class FarmerAnalyticsScreen extends StatefulWidget {
  const FarmerAnalyticsScreen({super.key});

  @override
  State<FarmerAnalyticsScreen> createState() => _FarmerAnalyticsScreenState();
}

class _FarmerAnalyticsScreenState extends State<FarmerAnalyticsScreen> {
  final _repo = AnalyticsRepository();
  final _notifRepo = NotificationRepository();

  AnalyticsPeriod _period = AnalyticsPeriod.thisMonth;
  FarmPerformanceSummary _performance = FarmPerformanceSummary.empty;
  List<TransactionRecord> _transactions = [];
  List<CropPriceCard> _priceCards = [];
  List<PriceHistoryPoint> _priceHistory = [];
  List<PlantingForecast> _forecasts = [];
  List<TopSellingCrop> _topSelling = [];
  int _unreadCount = 0;

  CropPriceCard? _selectedPriceCard;
  bool _isLoading = true;
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    AppEventService.instance.addListener(_onDataChanged);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _isOnline = ConnectivityService.instance.isOnline;
    _connectivitySubscription = ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _loadAll();
  }

  @override
  void dispose() {
    AppEventService.instance.removeListener(_onDataChanged);
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchFarmPerformance(_period),
      _repo.fetchRecentTransactions(startDate: _period.startDate),
      _repo.fetchPriceCards(),
      _repo.fetchPlantingForecasts(),
      _repo.fetchTopSellingCrops(),
      _notifRepo.fetchUnreadCount(),
    ]);
    if (!mounted) return;

    final priceCards = results[2] as List<CropPriceCard>;
    final initialCard = priceCards.isNotEmpty ? priceCards.first : null;

    setState(() {
      _performance = results[0] as FarmPerformanceSummary;
      _transactions = results[1] as List<TransactionRecord>;
      _priceCards = priceCards;
      _forecasts = results[3] as List<PlantingForecast>;
      _topSelling = results[4] as List<TopSellingCrop>;
      _unreadCount = results[5] as int;
      _selectedPriceCard = initialCard;
      _isLoading = false;
    });

    if (initialCard != null) _loadPriceHistory(initialCard);
  }

  Future<void> _loadPriceHistory(CropPriceCard card) async {
    final history = await _repo.fetchPriceHistory(
      card.cropName,
      priceType: card.priceType,
      startDate: _period.startDate,
    );
    if (!mounted) return;
    setState(() {
      _selectedPriceCard = card;
      _priceHistory = history;
    });
  }

  Future<void> _onPeriodChanged(AnalyticsPeriod p) async {
    setState(() => _period = p);
    final results = await Future.wait([
      _repo.fetchFarmPerformance(p),
      // Recent Transactions previously ignored the period filter entirely
      // — found during live-testing verification, since a farmer could
      // see a transaction from outside the selected period sitting right
      // under a Total Revenue figure that correctly excluded it.
      _repo.fetchRecentTransactions(startDate: p.startDate),
      // Re-fetch history for whichever crop is currently selected too —
      // previously this chart never responded to the period selector at
      // all, contradicting the screen's own "Applies to Farm Performance
      // and Price History" caption.
      if (_selectedPriceCard != null)
        _repo.fetchPriceHistory(
          _selectedPriceCard!.cropName,
          priceType: _selectedPriceCard!.priceType,
          startDate: p.startDate,
        ),
    ]);
    if (!mounted) return;
    setState(() {
      _performance = results[0] as FarmPerformanceSummary;
      _transactions = results[1] as List<TransactionRecord>;
      if (_selectedPriceCard != null) {
        _priceHistory = results[2] as List<PriceHistoryPoint>;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: AnimatedBuilder(
        animation: FarmerProfileStateService.instance,
        builder: (context, _) {
          final profile = FarmerProfileStateService.instance.profile;
          return AppNavigationDrawer(
            photoUrl: profile?.profilePhotoUrl,
            displayName: profile?.fullName ?? 'Farmer',
            contactEmail: profile?.contactEmail,
            phoneNumber: profile?.phoneNumber,
            onEditProfile: () {
              Navigator.pop(context);
              context.pushRoute(AppRoutes.farmerEditProfile);
            },
            onEditFarmDetails: () {
              Navigator.pop(context);
              context.pushRoute(AppRoutes.editFarmDetails);
            },
            onMyAddresses: () {
              Navigator.pop(context);
              context.pushRoute(AppRoutes.myAddresses);
            },
            onSignOut: () => confirmFarmerSignOut(context),
            onAboutSagana: () => context.pushRoute(AppRoutes.aboutSagana),
            onAboutOrganization: () => context.pushRoute(AppRoutes.aboutCooperative),
            onPrivacyPolicy: () => context.pushRoute(AppRoutes.privacyPolicy),
            onTermsOfUse: () => context.pushRoute(AppRoutes.termsOfUse),
          );
        },
      ),
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(message: "You're offline — price and performance data may not be up to date."),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 72),
                    Expanded(
                child: RefreshIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  onRefresh: _loadAll,
                  child: ListView(
                    // 72 clears the floating bottom nav bar (64px tall,
                    // farmer_bottom_nav.dart) with a small margin. Found
                    // during Phase 9 verification at 10, which is less than
                    // the nav bar's own height — the last visible card
                    // would sit partially behind it. 72 was the last known
                    // value confirmed safe before this regressed; if it was
                    // changed again to fight the "gap below the last
                    // forecast card" complaint, that gap needs a different
                    // fix than shrinking clearance below the nav bar.
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    children: [
                      // Period selector
                      _PeriodSelector(
                        active: _period,
                        onChanged: _onPeriodChanged,
                      ),
                      const SizedBox(height: AppConstants.spacingSectionV),

                      // ── Section 1: Farm Performance ──────────────────────
                      ReportSectionHeader(
                        icon: Icons.agriculture_rounded,
                        title: l10n.farmerAnalyticsFarmPerformanceTitle,
                      ),
                      const SizedBox(height: AppConstants.spacingMd),
                      _isLoading
                          ? _PerformanceShimmer()
                          : _PerformanceKpiStrip(summary: _performance),
                      const SizedBox(height: 14),
                      if (!_isLoading)
                        _HarvestBreakdownCard(
                          breakdown: _performance.cropBreakdown,
                        ),
                      const SizedBox(height: 14),
                      if (!_isLoading)
                        _TransactionsCard(transactions: _transactions),
                      const SizedBox(height: 28),

                      // ── Section 2: Price Monitoring ──────────────────────
                      ReportSectionHeader(
                        icon: Icons.payments_rounded,
                        title: l10n.farmerAnalyticsPriceMonitoringTitle,
                      ),
                      const SizedBox(height: AppConstants.spacingMd),
                      _isLoading
                          ? SizedBox(
                              height: 130,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            )
                          : _priceCards.isEmpty
                          ? ReportEmptyState(
                              message: l10n.farmerAnalyticsNoPricesAvailable,
                            )
                          : _PriceCardsRow(
                              cards: _priceCards,
                              selected: _selectedPriceCard,
                              onSelected: _loadPriceHistory,
                            ),
                      const SizedBox(height: 14),
                      if (!_isLoading && _selectedPriceCard != null)
                        _PriceHistoryChart(
                          cropName: _selectedPriceCard!.cropName,
                          points: _priceHistory,
                          periodLabel: _periodLabel(l10n, _period),
                        ),
                      const SizedBox(height: AppConstants.spacingSectionV),

                      // ── Top Harvested Crops ──────────────────────────────
                      // Positioned here, between Price History and Planting
                      // Forecast, to match Admin Analytics Dashboard's own
                      // section order exactly (Price Snapshot -> Top
                      // Harvested Crops -> Planting Forecast) — previously
                      // this sat after the forecast cards instead. Shared
                      // with Admin, already theme-aware; only its `title` is
                      // overridden here for localization (a plain default
                      // parameter, not touched in the shared widget file).
                      if (!_isLoading && _topSelling.isNotEmpty) ...[
                        TopHarvestedCropsChart(
                          crops: _topSelling,
                          title: l10n.farmerAnalyticsTopHarvestedCropsTitle,
                        ),
                        const SizedBox(height: AppConstants.spacingSectionV),
                      ],

                      // ── Section 3: Planting Forecast ─────────────────────
                      // PlantingForecastSectionHeader and PlantingForecastCard
                      // are shared with Admin's Analytics Dashboard and were
                      // already fully theme-aware and localized — verified by
                      // direct read, not restyled here, per the reviewed
                      // finding that neither needed a change.
                      const PlantingForecastSectionHeader(),
                      const SizedBox(height: AppConstants.spacingMd),
                      _isLoading
                          ? Column(
                              children: List.generate(
                                2,
                                (_) => const Padding(
                                  padding: EdgeInsets.only(bottom: 10),
                                  child: SizedBox(height: 90),
                                ),
                              ),
                            )
                          : _forecasts.isEmpty
                          // Reuses Admin's existing analyticsNoForecastsYet
                          // key — identical English text, same feature,
                          // same ReportEmptyState widget Admin's own
                          // dashboard uses for this exact empty state.
                          ? ReportEmptyState(message: l10n.analyticsNoForecastsYet)
                          : Column(
                              children: _forecasts
                                  .map(
                                    (f) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: PlantingForecastCard(forecast: f),
                                    ),
                                  )
                                  .toList(),
                            ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: 'Analytics',
              unreadCount: _unreadCount,
              hideProfileAvatar: true,
              onProfileTap: () => context.goTab(AppRoutes.farmerProfile),
              onNotificationTap: () =>
                  context.pushRoute(AppRoutes.farmerNotifications),
              enableMenu: true,
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
// Period Selector
// ─────────────────────────────────────────────────────────────────────────────

class _PeriodSelector extends StatelessWidget {
  final AnalyticsPeriod active;
  final ValueChanged<AnalyticsPeriod> onChanged;

  const _PeriodSelector({required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppConstants.primaryGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          ),
          child: Row(
            children: analyticsPeriodChipOrder.map((p) {
              final isActive = p == active;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppConstants.primaryGreen
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                    child: Text(
                      _periodLabel(l10n, p),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isActive ? Colors.white : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.farmerAnalyticsPeriodCaption,
          style: GoogleFonts.inter(fontSize: 9, color: cs.outline),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Performance Grid (4 cards)
// ─────────────────────────────────────────────────────────────────────────────

// Tile styling (color-tinted background/border, icon badge, typography)
// mirrors Admin Marketplace tab's _KpiStrip/_KpiTile exactly
// (marketplace_dashboard_screen.dart), per explicit request. Layout is a
// 2x2 grid rather than Marketplace's horizontal-scrolling strip — with
// exactly 4 tiles (an even number, all visible without scrolling), a
// fixed grid reads better than a scrollable row per follow-up request.
// Only the icon badge/border/label-adjacent tint carries each tile's
// semantic color; the value text itself is uniformly `cs.onSurface`,
// matching Marketplace's own convention exactly (color signals category,
// not magnitude — Marketplace doesn't color-code a value green/red
// either).
class _PerformanceKpiStrip extends StatelessWidget {
  final FarmPerformanceSummary summary;
  const _PerformanceKpiStrip({required this.summary});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tiles = [
      _KpiTile(l10n.farmerAnalyticsTotalYield, '${_fmt(summary.totalYieldKg)} kg', AppConstants.successGreen, Icons.grass_rounded),
      _KpiTile(l10n.farmerAnalyticsTotalRevenue, '₱${_fmt(summary.totalRevenue)}', cs.primary, Icons.payments_rounded),
      _KpiTile(l10n.farmerAnalyticsTotalExpenses, '₱${_fmt(summary.totalExpenses)}', AppConstants.errorRed, Icons.receipt_long_rounded),
      _KpiTile(l10n.farmerAnalyticsNetProfit, '₱${_fmt(summary.netProfit)}', AppConstants.midGreen, Icons.trending_up_rounded),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      // 1.7 overflowed by ~7px when a label wrapped to its full 2 lines
      // (confirmed live) — 1.4 gives enough vertical room for icon badge +
      // 2-line label + value with margin, matching the same "generous
      // fixed height beats width-derived height" lesson Admin Reports'
      // own KPI-card overflow fix already documented (report_tab.md 4.15).
      childAspectRatio: 1.4,
      children: tiles.map((t) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: t.color.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: t.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Icon(t.icon, size: 14, color: t.color),
              ),
              const SizedBox(height: 6),
              Text(
                t.label,
                style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant, height: 1.2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                t.value,
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _fmt(double v) {
    if (v >= 1000) {
      return NumberFormat('#,##0').format(v);
    }
    return v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }
}

class _KpiTile {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _KpiTile(this.label, this.value, this.color, this.icon);
}

// ─────────────────────────────────────────────────────────────────────────────
// Harvest Breakdown Card
// ─────────────────────────────────────────────────────────────────────────────

class _HarvestBreakdownCard extends StatelessWidget {
  final List<CropYieldBreakdown> breakdown;
  const _HarvestBreakdownCard({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: sagana.glassBorder),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.farmerAnalyticsHarvestByCropTitle.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.70),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 14),
              if (breakdown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      l10n.farmerAnalyticsNoHarvestData,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                ...breakdown.map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              b.cropName,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                            Text(
                              '${b.quantityKg.toStringAsFixed(0)} kg',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: b.percentOfMax,
                            minHeight: 7,
                            backgroundColor: cs.outline.withValues(alpha: 0.2),
                            valueColor: const AlwaysStoppedAnimation(
                              AppConstants.successGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transactions Card
// ─────────────────────────────────────────────────────────────────────────────

class _TransactionsCard extends StatelessWidget {
  final List<TransactionRecord> transactions;
  const _TransactionsCard({required this.transactions});

  // Visual distinction between the three revenue channels a transaction
  // can come from — previously only distinguishable by reading the
  // ORD-/COOP-/INF- text prefix in the reference. Colors reuse tokens
  // already meaningful elsewhere in this app rather than inventing new
  // ones: buyerBlue for a Buyer marketplace order, primaryGreen for a
  // cooperative purchase (the cooperative's own brand color), gold for
  // an informal farm-gate sale (a distinct, warm "outside the system"
  // tone matching AppConstants.gold's existing use elsewhere).
  static (IconData, Color) _sourceMeta(String reference) {
    if (reference.startsWith('ORD-')) {
      return (Icons.storefront_rounded, AppConstants.buyerBlue);
    } else if (reference.startsWith('COOP-')) {
      return (Icons.groups_rounded, AppConstants.primaryGreen);
    }
    return (Icons.handshake_rounded, AppConstants.gold);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: sagana.glassBorder),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.farmerAnalyticsRecentTransactionsTitle,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              if (transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      l10n.farmerAnalyticsNoTransactions,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                ...transactions.asMap().entries.map((entry) {
                  final t = entry.value;
                  final isLast = entry.key == transactions.length - 1;
                  final (sourceIcon, sourceColor) = _sourceMeta(t.reference);
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: isLast
                          ? null
                          : Border(
                              bottom: BorderSide(color: sagana.glassBorder),
                            ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: sourceColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(sourceIcon, size: 14, color: sourceColor),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.cropName,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                l10n.farmerAnalyticsTransactionMeta(
                                  DateFormat('MMM d, yyyy').format(t.date),
                                  t.quantityKg.toStringAsFixed(0),
                                  t.reference,
                                ),
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '₱${NumberFormat('#,##0').format(t.totalAmount)}',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Price Cards Row
// ─────────────────────────────────────────────────────────────────────────────

class _PriceCardsRow extends StatelessWidget {
  final List<CropPriceCard> cards;
  final CropPriceCard? selected;
  final ValueChanged<CropPriceCard> onSelected;

  const _PriceCardsRow({
    required this.cards,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    // 170 fits the image (90) + name + price. Also has to clear
    // Container's own automatic border-width inset — BoxDecoration.border
    // adds implicit padding equal to its own width (so the active card's
    // 2px border quietly ate 4px of the Column's available height, and
    // even the inactive 1px border ate 2px), which is exactly why 160
    // overflowed by 2-4px depending on active state. The Margin/kg row
    // below adds its own height only when it renders — and today it never
    // does, since fetchPriceCards() never populates CropPriceCard.costPerKg
    // anywhere in the codebase, so marginPerKg is always null. If a future
    // cost-basis feature wires that field up, this fixed height will need
    // to grow back to fit that row too (was 216 before the first fix,
    // sized for exactly that case).
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final c = cards[i];
          final isActive = c.cropName == selected?.cropName && c.priceType == selected?.priceType;
          final marketColor = MarketTypeDisplay.color(context, c.priceType);
          final hasImage = c.imageUrl != null && c.imageUrl!.isNotEmpty;
          // Same larger horizontal card layout as Home's Market Rates
          // carousel (_MarketRateCard, farmer_dashboard_screen.dart) —
          // image filling the card's upper portion with the market-type
          // badge overlaid top-left, crop identity and price below.
          // Structure/proportions mirrored exactly; colors kept
          // theme-aware (sagana.glassBackground/glassBorder) rather than
          // Market Rate's own fixed white, consistent with the rest of
          // this screen's Dark Mode support.
          return GestureDetector(
            onTap: () => onSelected(c),
            child: Container(
              width: 180,
              decoration: BoxDecoration(
                color: sagana.glassBackground,
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                border: Border.all(
                  color: isActive ? AppConstants.primaryGreen : sagana.glassBorder,
                  width: isActive ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF455A64).withValues(alpha: 0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 90,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        hasImage
                            ? Image.network(
                                c.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: marketColor.withValues(alpha: 0.12),
                                  child: Icon(Icons.eco_rounded, size: 32, color: marketColor),
                                ),
                              )
                            : Container(
                                color: marketColor.withValues(alpha: 0.12),
                                child: Icon(Icons.eco_rounded, size: 32, color: marketColor),
                              ),
                        // price_type badge — previously the only thing
                        // telling two cards apart when the same crop has
                        // both a cooperative and an open-market price was
                        // the crop name text alone (see
                        // analytics_repository.dart's (crop_name,
                        // price_type) dedup key comment). Reuses
                        // MarketTypeDisplay, the same shared color+label
                        // lookup Home/Market Rate Details/View Market
                        // already use for this exact field.
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: marketColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              MarketTypeDisplay.label(l10n, c.priceType),
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        if (c.priceDiff != null)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: (c.isUp ? AppConstants.successGreen : AppConstants.errorRed)
                                    .withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${c.isUp ? '↑' : '↓'} ₱${c.priceDiff!.abs().toStringAsFixed(2)}',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.cropName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isActive ? AppConstants.primaryGreen : cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '₱${c.currentPrice.toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '/kg',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        if (c.marginPerKg != null) ...[
                          const SizedBox(height: 8),
                          Container(height: 1, color: sagana.glassBorder),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                l10n.farmerAnalyticsMarginPerKg,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '${c.hasPositiveMargin ? '+' : ''}₱${c.marginPerKg!.toStringAsFixed(2)}',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: c.hasPositiveMargin
                                      ? AppConstants.successGreen
                                      : AppConstants.errorRed,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Price History Chart
// ─────────────────────────────────────────────────────────────────────────────

class _PriceHistoryChart extends StatelessWidget {
  final String cropName;
  final List<PriceHistoryPoint> points;
  final String periodLabel;

  const _PriceHistoryChart({
    required this.cropName,
    required this.points,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: sagana.glassBorder),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      l10n.farmerAnalyticsPriceHistoryTitle(cropName),
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                    child: Text(
                      periodLabel,
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.primaryGreen,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 130,
                width: double.infinity,
                child: points.length < 2
                    ? Center(
                        child: Text(
                          l10n.farmerAnalyticsNoPriceHistory,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final values = points.map((p) => p.price).toList();
                          return Stack(
                            children: [
                              CustomPaint(
                                size: Size(constraints.maxWidth, 130),
                                painter: TrendChartPainter(
                                  values: values,
                                  lineColor: cs.primary,
                                  gradientColor: cs.primary,
                                ),
                              ),
                              // Endpoint dot — TrendChartPainter (shared,
                              // generalized) doesn't draw one itself,
                              // unlike the private painter this replaces.
                              // Position computed with the same padding
                              // math TrendChartPainter uses internally, so
                              // it lands exactly on the curve's last point.
                              Builder(builder: (context) {
                                final minV = values.reduce((a, b) => a < b ? a : b);
                                final maxV = values.reduce((a, b) => a > b ? a : b);
                                final rawRange = (maxV - minV).abs();
                                final effRange = rawRange < 1 ? 1.0 : rawRange;
                                final padding = effRange * 0.15;
                                final lo = minV - padding;
                                final range = (maxV + padding) - lo;
                                final lastY = 130 * (1 - (values.last - lo) / range);
                                return Positioned(
                                  left: constraints.maxWidth - 4,
                                  top: lastY - 4,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          );
                        },
                      ),
              ),
              if (points.length >= 2) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('MMM d').format(points.first.date),
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      l10n.farmerAnalyticsToday,
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Text(
                l10n.farmerAnalyticsPriceFooterNote,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _PerformanceShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    // Matches _PerformanceKpiStrip's own 2x2 grid dimensions (10px gaps,
    // 1.7 aspect ratio) so the loading state doesn't jump when real data
    // replaces it.
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      // 1.7 overflowed by ~7px when a label wrapped to its full 2 lines
      // (confirmed live) — 1.4 gives enough vertical room for icon badge +
      // 2-line label + value with margin, matching the same "generous
      // fixed height beats width-derived height" lesson Admin Reports'
      // own KPI-card overflow fix already documented (report_tab.md 4.15).
      childAspectRatio: 1.4,
      children: List.generate(
        4,
        (_) => Container(
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
        ),
      ),
    );
  }
}