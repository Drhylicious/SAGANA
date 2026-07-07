import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/price_record_model.dart';
import '../../../data/repositories/price_management_repository.dart';
import '../../../data/services/connectivity_service.dart';

// ─── Price type constants ─────────────────────────────────────────────────────

class _PriceTypes {
  static const sp3      = 'sp3_cooperative';
  static const daAmad   = 'da_amad_market';
  static const market   = 'open_market';

  static const all = [sp3, daAmad, market];

  static String label(String type) {
    switch (type) {
      case sp3:    return 'SP3 Buying';
      case daAmad: return 'DA-AMAD';
      case market: return 'Market Avg';
      default:     return type;
    }
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class PriceManagementScreen extends StatefulWidget {
  const PriceManagementScreen({super.key});

  @override
  State<PriceManagementScreen> createState() =>
      _PriceManagementScreenState();
}

class _PriceManagementScreenState extends State<PriceManagementScreen> {
  final _repo = PriceManagementRepository();

  List<PriceRecordModel> _latestPrices = [];
  List<PriceRecordModel> _history      = [];
  List<String> _knownCrops             = [];
  bool _isLoading  = true;
  bool _isOnline   = true;
  DateTime? _lastRefreshed;

  // ── Selected crop for trend chart ────────────────────────────────────────
  String? _selectedCropForChart;
  List<PriceRecordModel> _trendData = [];
  bool _loadingTrend = false;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadAll();
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
      _repo.fetchKnownCropNames(),
    ]);
    if (!mounted) return;
    final prices  = results[0] as List<PriceRecordModel>;
    final history = results[1] as List<PriceRecordModel>;
    final crops   = results[2] as List<String>;
    setState(() {
      _latestPrices    = prices;
      _history         = history;
      _knownCrops      = crops;
      _lastRefreshed   = DateTime.now();
      _isLoading       = false;
      // Auto-select first crop for chart
      if (_selectedCropForChart == null && prices.isNotEmpty) {
        _selectedCropForChart = prices.first.cropName;
        _loadTrend(prices.first.cropName);
      }
    });
  }

  Future<void> _loadTrend(String cropName) async {
    setState(() => _loadingTrend = true);
    final data = await _repo.fetchTrendForCrop(cropName);
    if (!mounted) return;
    setState(() {
      _trendData    = data;
      _loadingTrend = false;
    });
  }

  void _onChartCropSelected(String cropName) {
    if (_selectedCropForChart == cropName) return;
    setState(() => _selectedCropForChart = cropName);
    _loadTrend(cropName);
  }

  // ── Open update sheet ─────────────────────────────────────────────────────

  void _openUpdateSheet(PriceRecordModel price) {
    if (!_isOnline) {
      _showSnack(AppLocalizations.of(context).priceOfflineWarning);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UpdatePriceSheet(
        price: price,
        repo: _repo,
        onSaved: _loadAll,
      ),
    );
  }

  // ── Open add sheet ────────────────────────────────────────────────────────

  void _openAddSheet() {
    if (!_isOnline) {
      _showSnack(AppLocalizations.of(context).priceOfflineWarning);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddPriceSheet(
        knownCrops: _knownCrops,
        repo: _repo,
        onSaved: _loadAll,
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

  String _refreshLabel() {
    if (_lastRefreshed == null) return '';
    final diff = DateTime.now().difference(_lastRefreshed!);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
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
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                          children: [

                            // ── Offline warning ──────────────────────────
                            if (!_isOnline)
                              _OfflineWarningBanner(l10n: l10n),
                            if (!_isOnline) const SizedBox(height: 12),

                            // ── Info banner ──────────────────────────────
                            _InfoBanner(
                              memberCount: 52,
                              sagana: sagana,
                              cs: cs,
                            ),
                            const SizedBox(height: 20),

                            // ── Live Market Rates ─────────────────────────
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  l10n.priceLiveRates,
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface,
                                  ),
                                ),
                                Text(
                                  _refreshLabel(),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: cs.outline,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_latestPrices.isEmpty)
                              _EmptyPrices(cs: cs)
                            else
                              _PriceGrid(
                                prices: _latestPrices,
                                isOnline: _isOnline,
                                onTap: _openUpdateSheet,
                                cs: cs,
                                sagana: sagana,
                              ),
                            const SizedBox(height: 24),

                            // ── Market Trends ─────────────────────────────
                            Text(
                              l10n.priceMarketTrends,
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _MarketTrendsCard(
                              prices: _latestPrices,
                              history: _history,
                              trendData: _trendData,
                              selectedCrop: _selectedCropForChart,
                              loadingTrend: _loadingTrend,
                              onCropSelected: _onChartCropSelected,
                              cs: cs,
                              sagana: sagana,
                              l10n: l10n,
                            ),
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
  final ColorScheme cs;
  final SaganaColors sagana;

  const _TopAppBar({
    required this.title,
    required this.onBack,
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
            border: Border(
              bottom: BorderSide(color: sagana.glassBorder),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: onBack,
              ),
              const SizedBox(width: 4),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
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
        border: Border.all(
          color: cs.error.withValues(alpha: 0.20),
        ),
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
                  'System Offline',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onErrorContainer,
                  ),
                ),
                Text(
                  'Price updates are disabled until connection is restored.',
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
// Info Banner
// ─────────────────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final int memberCount;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _InfoBanner({
    required this.memberCount,
    required this.sagana,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppConstants.radiusLg),
                bottomLeft: Radius.circular(AppConstants.radiusLg),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: cs.primary, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pricing Impact',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                            height: 1.4,
                          ),
                          children: [
                            const TextSpan(
                                text:
                                    'Updates here directly affect buying rates for '),
                            TextSpan(
                              text: '$memberCount cooperative members',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
                              ),
                            ),
                            const TextSpan(
                                text:
                                    '. SP3 Buying Prices are premium rates exclusive to member-only transactions.'),
                          ],
                        ),
                      ),
                    ],
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
    return Column(
      children: prices
          .map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PriceCard(
                  price: p,
                  isOnline: isOnline,
                  onTap: () => onTap(p),
                  cs: cs,
                  sagana: sagana,
                ),
              ))
          .toList(),
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
    final badgeData  = _badge(price.priceType);
    final deltaData  = _delta(price);
    final updatedStr = _updatedLabel(price.recordedAt);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge + edit icon row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeData.bg,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(
                    badgeData.label,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: badgeData.fg,
                    ),
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: isOnline ? cs.primary : cs.outline,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Crop name + price + delta
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      price.cropName,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: cs.outline,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '₱${price.price.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          '/${price.unit}',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: cs.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (deltaData != null)
                  Row(
                    children: [
                      Icon(deltaData.icon, size: 16, color: deltaData.color),
                      const SizedBox(width: 2),
                      Text(
                        deltaData.label,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: deltaData.color,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Footer
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: cs.outline.withValues(alpha: 0.10),
                  ),
                ),
              ),
              child: Text(
                'Updated $updatedStr',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _BadgeData _badge(String priceType) {
    switch (priceType) {
      case _PriceTypes.sp3:
        return _BadgeData(
          label: 'SP3 BUYING',
          bg: AppConstants.primaryContainer,
          fg: AppConstants.onPrimaryContainer,
        );
      case _PriceTypes.daAmad:
        return _BadgeData(
          label: 'DA-AMAD REFERENCE',
          bg: const Color(0xFFE3F2FD),
          fg: AppConstants.buyerBlue,
        );
      default:
        return _BadgeData(
          label: 'MARKET AVERAGE',
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
      return _DeltaData(
        icon: Icons.horizontal_rule_rounded,
        label: '0%',
        color: AppConstants.outline,
      );
    }
    return _DeltaData(
      icon: pct > 0
          ? Icons.arrow_upward_rounded
          : Icons.arrow_downward_rounded,
      label: '${pct.abs().toStringAsFixed(1)}%',
      color: pct > 0 ? AppConstants.successGreen : AppConstants.errorRed,
    );
  }

  String _updatedLabel(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
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
  const _DeltaData(
      {required this.icon, required this.label, required this.color});
}

class _EmptyPrices extends StatelessWidget {
  final ColorScheme cs;
  const _EmptyPrices({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      alignment: Alignment.center,
      child: Text(
        'No price records yet. Tap + to add the first entry.',
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
  final String? selectedCrop;
  final bool loadingTrend;
  final ValueChanged<String> onCropSelected;
  final ColorScheme cs;
  final SaganaColors sagana;
  final AppLocalizations l10n;

  const _MarketTrendsCard({
    required this.prices,
    required this.history,
    required this.trendData,
    required this.selectedCrop,
    required this.loadingTrend,
    required this.onCropSelected,
    required this.cs,
    required this.sagana,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final cropNames = prices.map((p) => p.cropName).toSet().toList();

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Crop selector chips
          if (cropNames.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: cropNames.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final name   = cropNames[i];
                    final active = selectedCrop == name;
                    return GestureDetector(
                      onTap: () => onCropSelected(name),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: active
                              ? cs.primary
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull),
                        ),
                        child: Text(
                          name,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: active
                                ? Colors.white
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 12),

          // Trend chart
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
                          child: Text(
                            'Not enough data for trend.\nAdd more price entries.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: cs.outline,
                            ),
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
          const SizedBox(height: 16),

          // History table
          Divider(
            height: 1,
            color: cs.outline.withValues(alpha: 0.08),
          ),
          _HistoryTable(history: history, cs: cs),
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'CROP',
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
                  'TYPE',
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
                  'PRICE',
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
                  'DATE',
                  textAlign: TextAlign.end,
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
          Divider(
            height: 12,
            color: cs.outline.withValues(alpha: 0.10),
          ),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No price history yet.',
                style: GoogleFonts.inter(
                    fontSize: 12, color: cs.onSurfaceVariant),
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
    final badgeLabel = _PriceTypes.label(price.priceType);
    final dateStr = _dateStr(price.recordedAt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              price.cropName,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusSm),
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
              style: GoogleFonts.inter(
                fontSize: 11,
                color: cs.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _dateStr(DateTime dt) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
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

  @override
  void initState() {
    super.initState();
    _priceCtrl  = TextEditingController(
        text: widget.price.price.toStringAsFixed(2));
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
    final newPrice = double.tryParse(_priceCtrl.text.trim());
    if (newPrice == null || newPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid price.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      await widget.repo.upsertPrice(
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update price. Try again.')),
        );
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
    final cs     = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline.withValues(alpha: 0.30),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.price.cropName,
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      widget.price.priceTypeLabel,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.outline,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                  style: IconButton.styleFrom(
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // >20% warning
            if (_showWarning)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(
                    color: cs.error.withValues(alpha: 0.20),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: cs.error, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Significant change detected! This price is >20% different '
                        'from the current rate. Please verify before updating.',
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
                      _FieldLabel(label: 'New Price (₱/kg)', cs: cs),
                      TextFormField(
                        controller: _priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
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
                      _FieldLabel(label: 'Effective Date', cs: cs),
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
                                AppConstants.radiusMd),
                            color: sagana.cardBackground,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_rounded,
                                  size: 16, color: cs.outline),
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

            // Source field
            _FieldLabel(label: 'Source / Reference Document', cs: cs),
            TextFormField(
              controller: _sourceCtrl,
              decoration: InputDecoration(
                hintText:
                    'e.g. Board Resolution #102, DA Bulletin',
                hintStyle: GoogleFonts.inter(
                    fontSize: 13, color: cs.outline),
              ),
            ),
            const SizedBox(height: 16),

            // Notification info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.06),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notifications_active_outlined,
                      color: cs.primary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Updating this price will send a push notification '
                      'to all 52 registered members via the Member App.',
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
            const SizedBox(height: 20),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.primary),
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusMd),
                      ),
                      child: Text(
                        'Cancel',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Update Price',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add New Price Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AddPriceSheet extends StatefulWidget {
  final List<String> knownCrops;
  final PriceManagementRepository repo;
  final VoidCallback onSaved;

  const _AddPriceSheet({
    required this.knownCrops,
    required this.repo,
    required this.onSaved,
  });

  @override
  State<_AddPriceSheet> createState() => _AddPriceSheetState();
}

class _AddPriceSheetState extends State<_AddPriceSheet> {
  final _cropCtrl   = TextEditingController();
  final _priceCtrl  = TextEditingController();
  final _sourceCtrl = TextEditingController();
  String _priceType  = _PriceTypes.sp3;
  String _unit       = 'kg';
  DateTime _date     = DateTime.now();
  bool _isSaving     = false;

  @override
  void dispose() {
    _cropCtrl.dispose();
    _priceCtrl.dispose();
    _sourceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final crop  = _cropCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());
    if (crop.isEmpty || price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill in crop name and a valid price.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      await widget.repo.upsertPrice(
        cropName:      crop,
        price:         price,
        priceType:     _priceType,
        unit:          _unit,
        source:        _sourceCtrl.text.trim().isEmpty
            ? null
            : _sourceCtrl.text.trim(),
        effectiveDate: _date,
      );
      await widget.repo.broadcastPriceNotification(
        cropName: crop,
        newPrice: price,
        unit:     _unit,
      );
      if (mounted) Navigator.pop(context);
      widget.onSaved();
    } catch (_) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to add price entry. Try again.')),
        );
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
    final cs     = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline.withValues(alpha: 0.30),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Add Price Entry',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 20),

            // Crop name with autocomplete suggestion
            _FieldLabel(label: 'Crop Name', cs: cs),
            Autocomplete<String>(
              optionsBuilder: (v) => widget.knownCrops.where(
                (c) => c.toLowerCase().contains(v.text.toLowerCase()),
              ),
              onSelected: (v) => _cropCtrl.text = v,
              fieldViewBuilder:
                  (ctx, ctrl, focusNode, onSubmit) => TextFormField(
                controller: ctrl,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: 'e.g. Peanut, Palay, Ginger',
                  hintStyle: GoogleFonts.inter(
                      fontSize: 13, color: cs.outline),
                ),
                onChanged: (v) => _cropCtrl.text = v,
              ),
            ),
            const SizedBox(height: 14),

            // Price type
            _FieldLabel(label: 'Price Type', cs: cs),
            Row(
              children: _PriceTypes.all.map((type) {
                final active = _priceType == type;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _priceType = type),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: active
                              ? cs.primary
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusMd),
                        ),
                        child: Text(
                          _PriceTypes.label(type),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: active
                                ? Colors.white
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Price + unit row
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel(label: 'Price (₱)', cs: cs),
                      TextFormField(
                        controller: _priceCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(
                                decimal: true),
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
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
                      _FieldLabel(label: 'Unit', cs: cs),
                      DropdownButtonFormField<String>(
                        value: _unit,
                        items: ['kg', 'g', 'pc', 'sack']
                            .map((u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(u,
                                      style: GoogleFonts.inter(
                                          fontSize: 14)),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _unit = v ?? 'kg'),
                        decoration: const InputDecoration(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Effective date
            _FieldLabel(label: 'Effective Date', cs: cs),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: cs.outline.withValues(alpha: 0.50)),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMd),
                  color: sagana.cardBackground,
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 16, color: cs.outline),
                    const SizedBox(width: 8),
                    Text(
                      '${_date.month}/${_date.day}/${_date.year}',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: cs.onSurface),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Source
            _FieldLabel(label: 'Source / Reference', cs: cs),
            TextFormField(
              controller: _sourceCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. Board Resolution, DA Bulletin',
                hintStyle: GoogleFonts.inter(
                    fontSize: 13, color: cs.outline),
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Add Price Entry',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600),
                    ),
            ),
          ],
        ),
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

