import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
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
import '../../widgets/shared_widgets.dart';
import '../../widgets/top_harvested_crops_chart.dart';
import '../../widgets/trend_chart_painter.dart';

class FarmerAnalyticsScreen extends StatefulWidget {
  const FarmerAnalyticsScreen({super.key});

  @override
  State<FarmerAnalyticsScreen> createState() => _FarmerAnalyticsScreenState();
}

class _FarmerAnalyticsScreenState extends State<FarmerAnalyticsScreen> {
  final _repo = AnalyticsRepository();
  final _notifRepo = NotificationRepository();

  AnalyticsPeriod _period = AnalyticsPeriod.thisSeason;
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
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _loadAll();
  }

  @override
  void dispose() {
    AppEventService.instance.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchFarmPerformance(_period),
      _repo.fetchRecentTransactions(),
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
      if (_selectedPriceCard != null) {
        _priceHistory = results[1] as List<PriceHistoryPoint>;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
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
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    children: [
                      // Period selector
                      _PeriodSelector(
                        active: _period,
                        onChanged: _onPeriodChanged,
                      ),
                      const SizedBox(height: 24),

                      // ── Section 1: Farm Performance ──────────────────────
                      const _SectionTitle('My Farm Performance'),
                      const SizedBox(height: 12),
                      _isLoading
                          ? _PerformanceShimmer()
                          : _PerformanceGrid(summary: _performance),
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
                      const _SectionTitle('Price Monitoring'),
                      const SizedBox(height: 12),
                      _isLoading
                          ? const SizedBox(
                              height: 130,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppConstants.primaryGreen,
                                ),
                              ),
                            )
                          : _priceCards.isEmpty
                          ? const _NoDataNotice(
                              message: 'No market prices available yet.',
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
                          periodLabel: _period.label,
                        ),
                      const SizedBox(height: 28),

                      // ── Section 3: Planting Forecast ─────────────────────
                      const PlantingForecastSectionHeader(),
                      const SizedBox(height: 12),
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
                          ? const _NoDataNotice(
                              message:
                                  'Forecasts will appear once enough cooperative-wide harvest history is recorded.',
                            )
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
                      const SizedBox(height: 20),
                      if (!_isLoading && _topSelling.isNotEmpty)
                        TopHarvestedCropsChart(crops: _topSelling),
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
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFDBF1FE),
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          ),
          child: Row(
            children: AnalyticsPeriod.values.map((p) {
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
                      p.label,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isActive
                            ? Colors.white
                            : AppConstants.onSurfaceVariant,
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
          'Applies to Farm Performance and Price History only.',
          style: GoogleFonts.inter(fontSize: 9, color: AppConstants.outline),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Title
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppConstants.charcoal,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Performance Grid (4 cards)
// ─────────────────────────────────────────────────────────────────────────────

class _PerformanceGrid extends StatelessWidget {
  final FarmPerformanceSummary summary;
  const _PerformanceGrid({required this.summary});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.0,
      children: [
        _MetricCard(
          label: 'Total Yield',
          value: '${_fmt(summary.totalYieldKg)} kg',
          valueColor: AppConstants.successGreen,
        ),
        _MetricCard(
          label: 'Total Revenue',
          value: '₱${_fmt(summary.totalRevenue)}',
          valueColor: AppConstants.charcoal,
        ),
        _MetricCard(
          label: 'Total Expenses',
          value: '₱${_fmt(summary.totalExpenses)}',
          valueColor: AppConstants.errorRed,
        ),
        _MetricCard(
          label: 'Net Profit',
          value: '₱${_fmt(summary.netProfit)}',
          valueColor: AppConstants.successGreen,
          accentBorder: true,
        ),
      ],
    );
  }

  String _fmt(double v) {
    if (v >= 1000) {
      return NumberFormat('#,##0').format(v);
    }
    return v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool accentBorder;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.valueColor,
    this.accentBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            children: [
              if (accentBorder)
                Container(width: 4, color: AppConstants.successGreen),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.outline,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: valueColor,
                        ),
                        overflow: TextOverflow.ellipsis,
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
// Harvest Breakdown Card
// ─────────────────────────────────────────────────────────────────────────────

class _HarvestBreakdownCard extends StatelessWidget {
  final List<CropYieldBreakdown> breakdown;
  const _HarvestBreakdownCard({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
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
                'HARVEST BY CROP',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.outline.withValues(alpha: 0.70),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 14),
              if (breakdown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      'No harvest data for this period.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppConstants.outline,
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
                                color: AppConstants.onSurface,
                              ),
                            ),
                            Text(
                              '${b.quantityKg.toStringAsFixed(0)} kg',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppConstants.onSurface,
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
                            backgroundColor: const Color(0xFFD5ECF8),
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

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
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
                'Recent Transactions',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.charcoal,
                ),
              ),
              const SizedBox(height: 10),
              if (transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      'No transactions yet.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppConstants.outline,
                      ),
                    ),
                  ),
                )
              else
                ...transactions.asMap().entries.map((entry) {
                  final t = entry.value;
                  final isLast = entry.key == transactions.length - 1;
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: isLast
                          ? null
                          : Border(
                              bottom: BorderSide(
                                color: Colors.white.withValues(alpha: 0.40),
                              ),
                            ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.cropName,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppConstants.onSurface,
                                ),
                              ),
                              Text(
                                '${DateFormat('MMM d, yyyy').format(t.date)} • ${t.quantityKg.toStringAsFixed(0)} kg • REF: #${t.reference}',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: AppConstants.outline,
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
                            color: AppConstants.onSurface,
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
    return SizedBox(
      height: 138,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final c = cards[i];
          final isActive = c.cropName == selected?.cropName && c.priceType == selected?.priceType;
          return GestureDetector(
            onTap: () => onSelected(c),
            child: Container(
              width: 170,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.70),
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                border: Border(
                  bottom: BorderSide(
                    color: isActive
                        ? AppConstants.primaryGreen
                        : Colors.transparent,
                    width: 4,
                  ),
                ),
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
                          c.cropName,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isActive
                                ? AppConstants.primaryGreen
                                : AppConstants.charcoal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (c.priceDiff != null)
                        Text(
                          '${c.isUp ? '↑' : '↓'} ₱${c.priceDiff!.abs().toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: c.isUp
                                ? AppConstants.successGreen
                                : AppConstants.errorRed,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '₱${c.currentPrice.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.onSurface,
                        ),
                      ),
                      Text(
                        '/kg',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: AppConstants.outline,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (c.marginPerKg != null) ...[
                    Container(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.50),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Margin/kg:',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppConstants.outline,
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
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
                      'Price History: $cropName',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.charcoal,
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
                          'Not enough price history yet.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppConstants.outline,
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
                                  lineColor: AppConstants.primaryGreen,
                                  gradientColor: AppConstants.primaryGreen,
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
                                    decoration: const BoxDecoration(
                                      color: AppConstants.primaryGreen,
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
                        color: AppConstants.outline,
                      ),
                    ),
                    Text(
                      'Today',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        color: AppConstants.outline,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Market prices are updated by SP3 Cooperative admin.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontStyle: FontStyle.italic,
                  color: AppConstants.outline,
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
// Shared
// ─────────────────────────────────────────────────────────────────────────────

class _NoDataNotice extends StatelessWidget {
  final String message;
  const _NoDataNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.outline.withValues(alpha: 0.20)),
      ),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 12, color: AppConstants.outline),
        ),
      ),
    );
  }
}

class _PerformanceShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.0,
      children: List.generate(
        4,
        (_) => Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.50),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          ),
        ),
      ),
    );
  }
}