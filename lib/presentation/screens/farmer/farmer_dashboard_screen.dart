import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/animations/staggered_entrance.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/dashboard_summary_model.dart';
import '../../../data/models/price_record_model.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/profile_state_service.dart';
import '../../../data/services/sync_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';

class FarmerDashboardScreen extends StatefulWidget {
  const FarmerDashboardScreen({super.key});

  @override
  State<FarmerDashboardScreen> createState() => _FarmerDashboardScreenState();
}

class _FarmerDashboardScreenState extends State<FarmerDashboardScreen> {
  final _dashRepo = DashboardRepository();
  final _profileState = FarmerProfileStateService.instance;

  DashboardSummaryModel _summary = DashboardSummaryModel.empty;
  List<PriceRecordModel> _prices = [];
  List<ActivityItem> _activity = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    AppEventService.instance.addListener(_onHarvestRecorded);
    _profileState.addListener(_onProfileStateChanged);
    _loadData();
    _listenConnectivity();
  }

  @override
  void dispose() {
    AppEventService.instance.removeListener(_onHarvestRecorded);
    _profileState.removeListener(_onProfileStateChanged);
    super.dispose();
  }

  void _onHarvestRecorded() {
    if (mounted) _loadData();
  }

  void _onProfileStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppTheme.applySystemOverlay(context);
  }

  void _listenConnectivity() {
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _isOnline = ConnectivityService.instance.isOnline;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _dashRepo.fetchSummary(),
        _dashRepo.fetchLatestPrices(),
        _dashRepo.fetchRecentActivity(),
      ]);
      await _profileState.refresh();
      if (!mounted) return;
      setState(() {
        _summary = results[0] as DashboardSummaryModel;
        _prices = results[1] as List<PriceRecordModel>;
        _activity = results[2] as List<ActivityItem>;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSync() async {
    setState(() => _isSyncing = true);
    await SyncService.syncPending();
    await _loadData();
    if (mounted) setState(() => _isSyncing = false);
  }

  String _greeting(AppLocalizations l10n) {
    final hour = DateTime.now().hour;
    if (hour < 12) return l10n.greetingMorning;
    if (hour < 18) return l10n.greetingAfternoon;
    return l10n.greetingEvening;
  }

  String _firstName(AppLocalizations l10n) {
    final name = _profileState.fullName ?? l10n.defaultFarmerName;
    return name.split(' ').first;
  }

  String get _formattedDate {
    return DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Stack(
        children: [
          // ── Offline Banner + Scrollable Content ────────────────────────────
          Column(
            children: [
              if (!_isOnline) const _OfflineBanner(),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadData,
                  child: CustomScrollView(
                    slivers: [
                      // Top app bar space
                      const SliverToBoxAdapter(child: SizedBox(height: 72)),
                      // Welcome
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: StaggeredEntrance(
                            index: 0,
                            child: _WelcomeSection(
                              greeting: _greeting(l10n),
                              firstName: _firstName(l10n),
                              date: _formattedDate,
                              isLoading: _isLoading,
                            ),
                          ),
                        ),
                      ),
                      // KPI cards
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: _KpiSection(
                            summary: _summary,
                            isLoading: _isLoading,
                            isSyncing: _isSyncing,
                            onSync: _handleSync,
                          ),
                        ),
                      ),
                      // Ticker
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: _PriceTicker(
                            prices: _prices,
                            isLoading: _isLoading,
                          ),
                        ),
                      ),
                      // Recent activity
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
                          child: _RecentActivitySection(
                            items: _activity,
                            isLoading: _isLoading,
                            onViewAll: () => context
                                .pushRoute(AppRoutes.farmerRecentActivity),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Top App Bar (overlaid) ─────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              onProfileTap: () => context.goTab(AppRoutes.farmerProfile),
              onNotificationTap: () =>
                  context.pushRoute(AppRoutes.farmerNotifications),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offline Banner
// ─────────────────────────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppConstants.warningAmber,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'You\'re offline — data shown from cache',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
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
// Welcome Section
// ─────────────────────────────────────────────────────────────────────────────

class _WelcomeSection extends StatelessWidget {
  final String greeting;
  final String firstName;
  final String date;
  final bool isLoading;

  const _WelcomeSection({
    required this.greeting,
    required this.firstName,
    required this.date,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        isLoading
            ? _Shimmer(width: 200, height: 28)
            : Text(
                '$greeting, $firstName!',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.charcoal,
                  letterSpacing: -0.3,
                ),
              ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 14,
              color: AppConstants.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              date,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI Section
// ─────────────────────────────────────────────────────────────────────────────

class _KpiSection extends StatelessWidget {
  final DashboardSummaryModel summary;
  final bool isLoading;
  final bool isSyncing;
  final VoidCallback onSync;

  const _KpiSection({
    required this.summary,
    required this.isLoading,
    required this.isSyncing,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _YieldCard(summary: summary, isLoading: isLoading),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _EarningsCard(summary: summary, isLoading: isLoading),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SyncCard(
          summary: summary,
          isLoading: isLoading,
          isSyncing: isSyncing,
          onSync: onSync,
        ),
      ],
    );
  }
}

class _YieldCard extends StatelessWidget {
  final DashboardSummaryModel summary;
  final bool isLoading;

  const _YieldCard({required this.summary, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total Yield',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          isLoading
              ? _Shimmer(width: 80, height: 24)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _formatNumber(summary.totalYieldKg),
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.charcoal,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'kg',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppConstants.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                summary.yieldTrendUp
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                size: 16,
                color: summary.yieldTrendUp
                    ? AppConstants.successGreen
                    : AppConstants.errorRed,
              ),
              const SizedBox(width: 4),
              Text(
                '${summary.yieldChangePercent.abs().toStringAsFixed(0)}% vs last month',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: summary.yieldTrendUp
                      ? AppConstants.successGreen
                      : AppConstants.errorRed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatNumber(double n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1)}k';
    }
    return n.toStringAsFixed(0);
  }
}

class _EarningsCard extends StatelessWidget {
  final DashboardSummaryModel summary;
  final bool isLoading;

  const _EarningsCard({required this.summary, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  'Total Earnings',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppConstants.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppConstants.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Goal ${summary.earningsGoalPercent}%',
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.amber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          isLoading
              ? _Shimmer(width: 90, height: 24)
              : Text(
                  '₱${_formatCurrency(summary.totalEarnings)}',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.secondaryContainer,
                  ),
                ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: summary.earningsProgressPercent,
              minHeight: 6,
              backgroundColor: AppConstants.amber.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppConstants.secondaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '₱${_formatCurrency(summary.totalEarnings)} / ₱${_formatCurrency(summary.earningsGoal)}',
            style: GoogleFonts.inter(
              fontSize: 9,
              color: AppConstants.onSurfaceVariant,
            ),
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }

  String _formatCurrency(double v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(1)}k';
    }
    return v.toStringAsFixed(0);
  }
}

class _SyncCard extends StatelessWidget {
  final DashboardSummaryModel summary;
  final bool isLoading;
  final bool isSyncing;
  final VoidCallback onSync;

  const _SyncCard({
    required this.summary,
    required this.isLoading,
    required this.isSyncing,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnsynced = summary.unsyncedCount > 0;
    return _GlassCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unsynced Records',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppConstants.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    isLoading
                        ? _Shimmer(width: 60, height: 20)
                        : Flexible(
                            child: Text(
                              '${summary.unsyncedCount} Item${summary.unsyncedCount != 1 ? 's' : ''}',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppConstants.charcoal,
                              ),
                            ),
                          ),
                    const SizedBox(width: 8),
                    if (hasUnsynced)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFDAD6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Requires Sync',
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF93000A),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: isSyncing ? null : onSync,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppConstants.primaryContainer,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Row(
                children: [
                  isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppConstants.onPrimaryContainer,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.sync_rounded,
                          size: 16,
                          color: AppConstants.onPrimaryContainer,
                        ),
                  const SizedBox(width: 6),
                  Text(
                    'Sync Now',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppConstants.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Price Ticker
// ─────────────────────────────────────────────────────────────────────────────

class _PriceTicker extends StatefulWidget {
  final List<PriceRecordModel> prices;
  final bool isLoading;

  const _PriceTicker({required this.prices, required this.isLoading});

  @override
  State<_PriceTicker> createState() => _PriceTickerState();
}

class _PriceTickerState extends State<_PriceTicker>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startTicker());
  }

  void _startTicker() {
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      final current = _scrollController.offset;
      if (current >= max) {
        _scrollController.jumpTo(0);
      } else {
        _scrollController.jumpTo(current + 1);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.prices.isEmpty ? _fallbackPrices() : widget.prices;

    return _GlassCard(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          // Label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.40),
              border: Border(
                right: BorderSide(
                  color: AppConstants.outline.withValues(alpha: 0.15),
                ),
              ),
            ),
            child: Text(
              'MARKET\nRATES',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppConstants.primaryGreen,
                letterSpacing: 1.5,
                height: 1.4,
              ),
            ),
          ),
          // Scrolling ticker
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  ...items.map((p) => _TickerItem(price: p)),
                  // Duplicate for seamless loop
                  ...items.map((p) => _TickerItem(price: p)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<PriceRecordModel> _fallbackPrices() => [
    PriceRecordModel(
      id: '1',
      cropName: 'Peanut',
      price: 65,
      unit: 'kg',
      priceType: 'sp3_cooperative',
      recordedAt: DateTime.now(),
    ),
    PriceRecordModel(
      id: '2',
      cropName: 'Ginger',
      price: 55,
      unit: 'kg',
      priceType: 'da_amad_market',
      previousPrice: 60,
      recordedAt: DateTime.now(),
    ),
    PriceRecordModel(
      id: '3',
      cropName: 'Banana',
      price: 18.5,
      unit: 'kg',
      priceType: 'open_market',
      recordedAt: DateTime.now(),
    ),
  ];
}

class _TickerItem extends StatelessWidget {
  final PriceRecordModel price;
  const _TickerItem({required this.price});

  @override
  Widget build(BuildContext context) {
    final isUp = price.isUp;
    final isDown = price.isDown;
    final trendColor = isUp
        ? AppConstants.successGreen
        : isDown
        ? AppConstants.errorRed
        : AppConstants.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            price.cropName,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppConstants.onSurface,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '₱${price.price}/${price.unit}',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppConstants.onSurface,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isUp
                ? '▲'
                : isDown
                ? '▼'
                : '—',
            style: TextStyle(fontSize: 10, color: trendColor),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent Activity
// ─────────────────────────────────────────────────────────────────────────────

class _RecentActivitySection extends StatelessWidget {
  final List<ActivityItem> items;
  final bool isLoading;
  final VoidCallback onViewAll;

  const _RecentActivitySection({
    required this.items,
    required this.isLoading,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Activity',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppConstants.charcoal,
              ),
            ),
            GestureDetector(
              onTap: onViewAll,
              child: Text(
                'View All',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.primaryContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (isLoading)
          _GlassCard(
            child: Column(
              children: List.generate(
                3,
                (_) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _Shimmer(width: double.infinity, height: 48),
                ),
              ),
            ),
          )
        else if (items.isEmpty)
          _GlassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 40,
                    color: AppConstants.outline,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No recent activity',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppConstants.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.30),
                  ),
                ),
                child: Column(
                  children: items
                      .asMap()
                      .entries
                      .map(
                        (e) => Column(
                          children: [
                            _ActivityTile(item: e.value),
                            if (e.key < items.length - 1)
                              Divider(
                                height: 1,
                                color: AppConstants.outline.withValues(
                                  alpha: 0.08,
                                ),
                              ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final ActivityItem item;
  const _ActivityTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _ActivityIcon(type: item.type, isAlert: item.isAlert),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppConstants.charcoal,
                  ),
                ),
                Text(
                  item.subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: item.isAlert
                        ? AppConstants.errorRed
                        : AppConstants.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (item.valueLabel != null)
                Text(
                  item.valueLabel!,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: item.isAlert
                        ? AppConstants.errorRed
                        : item.type == ActivityType.order
                        ? AppConstants.primaryGreen
                        : AppConstants.charcoal,
                  ),
                ),
              if (item.statusLabel != null)
                Text(
                  item.statusLabel!,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: item.isAlert
                        ? AppConstants.errorRed.withValues(alpha: 0.70)
                        : AppConstants.successGreen,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityIcon extends StatelessWidget {
  final ActivityType type;
  final bool isAlert;

  const _ActivityIcon({required this.type, required this.isAlert});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color bg;
    Color fg;

    if (isAlert) {
      icon = Icons.event_repeat_rounded;
      bg = AppConstants.errorRed.withValues(alpha: 0.12);
      fg = AppConstants.errorRed;
    } else {
      switch (type) {
        case ActivityType.harvest:
          icon = Icons.eco_rounded;
          bg = AppConstants.primaryGreen.withValues(alpha: 0.10);
          fg = AppConstants.primaryGreen;
          break;
        case ActivityType.order:
          icon = Icons.shopping_cart_outlined;
          bg = AppConstants.primaryGreen.withValues(alpha: 0.10);
          fg = AppConstants.primaryGreen;
          break;
        case ActivityType.listing:
          icon = Icons.storefront_outlined;
          bg = AppConstants.successGreen.withValues(alpha: 0.10);
          fg = AppConstants.successGreen;
          break;
        case ActivityType.loan:
          icon = Icons.account_balance_wallet_outlined;
          bg = AppConstants.warningAmber.withValues(alpha: 0.10);
          fg = AppConstants.warningAmber;
          break;
      }
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 22, color: fg),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const _GlassCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding ?? const EdgeInsets.all(AppConstants.spacingGutter),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
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
    _animation = Tween<double>(
      begin: -1,
      end: 2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
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
            colors: const [
              Color(0xFFE8E8E8),
              Color(0xFFF5F5F5),
              Color(0xFFE8E8E8),
            ],
          ),
        ),
      ),
    );
  }
}
