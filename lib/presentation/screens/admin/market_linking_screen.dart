import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/market_linking_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/management_modal.dart';

class MarketLinkingScreen extends StatefulWidget {
  const MarketLinkingScreen({super.key});

  @override
  State<MarketLinkingScreen> createState() => _MarketLinkingScreenState();
}

class _MarketLinkingScreenState extends State<MarketLinkingScreen> {
  final _repo = MarketLinkingRepository();

  // Fetched once, unfiltered — status filtering happens client-side below.
  // Previously each filter tap re-hit the repo with statusFilter, which
  // meant the KPI counts (computed from that same filtered list) silently
  // went to 0 for every status except the one currently selected. Loading
  // the full season once and filtering in memory fixes that and also cuts
  // a network round-trip per filter tap.
  List<MarketLinkingModel> _allEntries = [];
  bool _isLoading = true;
  bool _isOnline = true;
  MarketLinkingStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await _repo.fetchAll();
    if (!mounted) return;
    setState(() {
      _allEntries = data;
      _isLoading = false;
    });
  }

  List<MarketLinkingModel> get _visibleEntries {
    if (_statusFilter == null) return _allEntries;
    return _allEntries.where((e) => e.status == _statusFilter).toList();
  }

  int get _totalCount => _allEntries.length;
  int get _submittedCount =>
      _allEntries.where((e) => e.status == MarketLinkingStatus.submitted).length;
  int get _buyerFoundCount =>
      _allEntries.where((e) => e.status == MarketLinkingStatus.buyerFound).length;
  int get _completedCount =>
      _allEntries.where((e) => e.status == MarketLinkingStatus.completed).length;
  int get _cancelledCount =>
      _allEntries.where((e) => e.status == MarketLinkingStatus.cancelled).length;

  void _showStatusSheet(MarketLinkingModel entry) {
    showManagementModal(
      context: context,
      builder: (_) => _UpdateStatusSheet(entry: entry, repo: _repo, onSaved: _load),
    );
  }

  void _showEnrollSheet() async {
    final data = await _repo.fetchEnrollmentCandidates();
    if (!mounted) return;
    showManagementModal(
      context: context,
      builder: (_) => _EnrollFarmerSheet(
        totalGingerFarmers: data['totalGingerFarmers'] as int,
        farmers: data['unenrolled'] as List<Map<String, dynamic>>,
        repo: _repo,
        onSaved: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final visible = _visibleEntries;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: _isOnline
          ? FloatingActionButton(
              onPressed: _showEnrollSheet,
              backgroundColor: AppConstants.tertiaryContainer,
              child: const Icon(Icons.add_rounded, color: AppConstants.onTertiaryContainer),
            )
          : null,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              _FilterBar(
                selected: _statusFilter,
                submittedCount: _submittedCount,
                buyerFoundCount: _buyerFoundCount,
                completedCount: _completedCount,
                cancelledCount: _cancelledCount,
                totalCount: _totalCount,
                onChanged: (s) => setState(() => _statusFilter = s),
                cs: cs,
                sagana: sagana,
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _load,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppConstants.primaryGreen,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
                          children: [
                            // ── KPI strip ─────────────────────────────────
                            _KpiStrip(
                              total: _totalCount,
                              submitted: _submittedCount,
                              buyerFound: _buyerFoundCount,
                              completed: _completedCount,
                              cs: cs,
                              sagana: sagana,
                            ),
                            const SizedBox(height: 16),

                            // ── DA-AMAD explainer ─────────────────────────
                            // Full explainer when the program is empty (it's
                            // the only content on the page and needs to earn
                            // its keep); collapses to a slim strip once
                            // there's real data so it doesn't compete with
                            // the KPI cards and entries below.
                            _DaAmadInfoCard(
                              cs: cs,
                              compact: _allEntries.isNotEmpty,
                            ),
                            const SizedBox(height: 16),

                            if (visible.isEmpty)
                              _EmptyState(
                                hasFilter: _statusFilter != null,
                                cs: cs,
                                sagana: sagana,
                              )
                            else ...[
                              ...visible.map(
                                (e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _EntryCard(
                                    entry: e,
                                    cs: cs,
                                    sagana: sagana,
                                    onUpdateStatus: _isOnline
                                        ? () => _showStatusSheet(e)
                                        : null,
                                  ),
                                ),
                              ),
                            ],
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
            child: _TopAppBar(
              onBack: () => context.pop(),
              sagana: sagana,
              cs: cs,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Top App Bar ──────────────────────────────────────────────────────────────
// "Buyers" quick-link removed — it routed to BuyerManagementScreen (the
// app's marketplace buyer directory), but DA-AMAD is an external
// institutional buyer, not one of those accounts. The button promised a
// connection that didn't exist; removing it rather than repointing it
// since there's no in-app "DA-AMAD contacts" destination to send it to.
class _TopAppBar extends StatelessWidget {
  final VoidCallback onBack;
  final SaganaColors sagana;
  final ColorScheme cs;
  const _TopAppBar({required this.onBack, required this.sagana, required this.cs});

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
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Market Linking',
                        style: GoogleFonts.poppins(fontSize: 17,
                            fontWeight: FontWeight.w700, color: cs.primary)),
                    Text('Ginger Program — DA-AMAD',
                        style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Filter Bar ───────────────────────────────────────────────────────────────
// Chips now carry live counts (same data the KPI strip uses), so the row
// doubles as a compact status legend even before you tap anything.
class _FilterBar extends StatelessWidget {
  final MarketLinkingStatus? selected;
  final int submittedCount, buyerFoundCount, completedCount, cancelledCount, totalCount;
  final ValueChanged<MarketLinkingStatus?> onChanged;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _FilterBar({
    required this.selected,
    required this.submittedCount,
    required this.buyerFoundCount,
    required this.completedCount,
    required this.cancelledCount,
    required this.totalCount,
    required this.onChanged,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: sagana.cardBackground,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _Chip(label: 'All', count: totalCount, active: selected == null,
                color: cs.primary, onTap: () => onChanged(null), cs: cs),
            const SizedBox(width: 8),
            _Chip(label: 'Submitted', count: submittedCount,
                active: selected == MarketLinkingStatus.submitted,
                color: AppConstants.warningAmber,
                onTap: () => onChanged(MarketLinkingStatus.submitted), cs: cs),
            const SizedBox(width: 8),
            _Chip(label: 'Buyer Found', count: buyerFoundCount,
                active: selected == MarketLinkingStatus.buyerFound,
                color: AppConstants.buyerBlue,
                onTap: () => onChanged(MarketLinkingStatus.buyerFound), cs: cs),
            const SizedBox(width: 8),
            _Chip(label: 'Completed', count: completedCount,
                active: selected == MarketLinkingStatus.completed,
                color: AppConstants.successGreen,
                onTap: () => onChanged(MarketLinkingStatus.completed), cs: cs),
            const SizedBox(width: 8),
            _Chip(label: 'Cancelled', count: cancelledCount,
                active: selected == MarketLinkingStatus.cancelled,
                color: cs.outline,
                onTap: () => onChanged(MarketLinkingStatus.cancelled), cs: cs),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final ColorScheme cs;
  const _Chip({
    required this.label,
    required this.count,
    required this.active,
    required this.color,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? Colors.white : cs.onSurface,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withValues(alpha: 0.25)
                    : cs.onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── KPI Strip ────────────────────────────────────────────────────────────────
// Same card language as MarketplaceDashboardScreen's KPI strip (icon + label
// + value, horizontal scroll). Counts come from the full unfiltered season,
// not the currently-selected chip, so they stay accurate no matter what's
// filtered below.
class _KpiStrip extends StatelessWidget {
  final int total, submitted, buyerFound, completed;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _KpiStrip({
    required this.total,
    required this.submitted,
    required this.buyerFound,
    required this.completed,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _KpiTile('Enrolled', '$total', cs.primary, Icons.eco_rounded),
      _KpiTile('Submitted', '$submitted', AppConstants.warningAmber, Icons.upload_file_rounded),
      _KpiTile('Buyer Found', '$buyerFound', AppConstants.buyerBlue, Icons.handshake_outlined),
      _KpiTile('Completed', '$completed', AppConstants.successGreen, Icons.check_circle_outline_rounded),
    ];

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final t = tiles[i];
          return Container(
            width: 108,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: sagana.cardBackground,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Icon(t.icon, size: 13, color: t.color),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(t.label,
                        style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
                Text(t.value,
                    style: GoogleFonts.poppins(
                        fontSize: 22, fontWeight: FontWeight.w800, color: t.color)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _KpiTile {
  final String label, value;
  final Color color;
  final IconData icon;
  const _KpiTile(this.label, this.value, this.color, this.icon);
}

// ─── DA-AMAD Info Card ────────────────────────────────────────────────────────
class _DaAmadInfoCard extends StatelessWidget {
  final ColorScheme cs;
  final bool compact;
  const _DaAmadInfoCard({required this.cs, required this.compact});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppConstants.tertiaryContainer.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(
            color: AppConstants.onTertiaryContainer.withValues(alpha: 0.20),
          ),
        ),
        child: Row(
          children: [
            const Text('🌿', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'DA-AMAD Ginger Program — institutional export pricing, bypasses the open marketplace.',
                style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.tertiaryContainer.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: AppConstants.onTertiaryContainer.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🌿', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DA-AMAD Ginger Market Linking',
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
                const SizedBox(height: 3),
                Text(
                  'Links SP3 Ginger farmers directly to DA-AMAD institutional '
                  'buyers for premium export pricing. Farmers enrolled here '
                  'bypass the open marketplace for their Ginger harvest.',
                  style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Entry Card ───────────────────────────────────────────────────────────────
class _EntryCard extends StatelessWidget {
  final MarketLinkingModel entry;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback? onUpdateStatus;
  const _EntryCard({
    required this.entry,
    required this.cs,
    required this.sagana,
    this.onUpdateStatus,
  });

  static const _stages = [
    MarketLinkingStatus.submitted,
    MarketLinkingStatus.buyerFound,
    MarketLinkingStatus.completed,
  ];

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(entry.status, cs);
    final isCancelled = entry.status == MarketLinkingStatus.cancelled;
    final stageIndex = _stages.indexOf(entry.status); // -1 if cancelled

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border(
          left: BorderSide(color: statusColor, width: 4),
          top: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
          right: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
          bottom: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppConstants.tertiaryContainer.withValues(alpha: 0.15),
                  ),
                  child: Center(
                    child: Text(
                      entry.initials,
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.tertiaryContainer),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.farmerName,
                          style: GoogleFonts.poppins(
                              fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
                      if (entry.sitio != null)
                        Text(entry.sitio!,
                            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(
                    entry.status.label.toUpperCase(),
                    style: GoogleFonts.inter(
                        fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: statusColor),
                  ),
                ),
              ],
            ),
          ),

          // Pipeline progress — Submitted → Buyer Found → Completed.
          // Purely visual, reads directly off entry.status; cancelled
          // entries skip this since they're outside the normal pipeline.
          if (!isCancelled)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: List.generate(_stages.length * 2 - 1, (i) {
                  if (i.isOdd) {
                    final passed = (i ~/ 2) < stageIndex;
                    return Expanded(
                      child: Container(
                        height: 2,
                        color: passed
                            ? statusColor.withValues(alpha: 0.4)
                            : cs.outline.withValues(alpha: 0.15),
                      ),
                    );
                  }
                  final dotIndex = i ~/ 2;
                  final reached = dotIndex <= stageIndex;
                  return Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: reached ? statusColor : cs.outline.withValues(alpha: 0.25),
                    ),
                  );
                }),
              ),
            ),

          if (entry.volumeKg != null || entry.buyerName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: [
                  if (entry.volumeKg != null) ...[
                    Icon(Icons.scale_outlined, size: 13, color: cs.outline),
                    const SizedBox(width: 4),
                    Text('${entry.volumeKg!.toStringAsFixed(0)} kg',
                        style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
                    const SizedBox(width: 12),
                  ],
                  if (entry.pricePerKg != null) ...[
                    Icon(Icons.payments_outlined, size: 13, color: cs.outline),
                    const SizedBox(width: 4),
                    Text('₱${entry.pricePerKg!.toStringAsFixed(2)}/kg',
                        style: GoogleFonts.poppins(
                            fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
                    const SizedBox(width: 12),
                  ],
                  if (entry.buyerName != null) ...[
                    Icon(Icons.handshake_outlined, size: 13, color: cs.outline),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(entry.buyerName!,
                          style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ],
              ),
            ),

          // Timestamp trail — data already on the model, never surfaced
          // before.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 12, color: cs.outline),
                const SizedBox(width: 4),
                Text(
                  _timelineLabel(entry),
                  style: GoogleFonts.inter(fontSize: 10, color: cs.outline),
                ),
              ],
            ),
          ),

          if (entry.notes != null && entry.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Text(entry.notes!,
                    style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
              ),
            ),

          if (entry.isActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onUpdateStatus,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: onUpdateStatus != null
                              ? AppConstants.tertiaryContainer
                              : cs.outline.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.update_rounded, size: 15,
                                color: onUpdateStatus != null
                                    ? AppConstants.onTertiaryContainer
                                    : cs.outline),
                            const SizedBox(width: 6),
                            Text('Update Status',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: onUpdateStatus != null
                                        ? AppConstants.onTertiaryContainer
                                        : cs.outline)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (entry.status == MarketLinkingStatus.buyerFound) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: onUpdateStatus,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppConstants.primaryGreen, AppConstants.successGreen],
                            ),
                            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.handshake_rounded, size: 15, color: Colors.white),
                              const SizedBox(width: 6),
                              Text('Confirm Sale',
                                  style: GoogleFonts.poppins(
                                      fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                            ],
                          ),
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

  String _timelineLabel(MarketLinkingModel e) {
    if (e.completedAt != null) return 'Completed ${_fmt(e.completedAt!)}';
    if (e.buyerFoundAt != null) return 'Buyer found ${_fmt(e.buyerFoundAt!)}';
    return 'Submitted ${_fmt(e.submittedAt)}';
  }

  String _fmt(DateTime dt) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Color _statusColor(MarketLinkingStatus s, ColorScheme cs) {
    switch (s) {
      case MarketLinkingStatus.submitted: return AppConstants.warningAmber;
      case MarketLinkingStatus.buyerFound: return AppConstants.buyerBlue;
      case MarketLinkingStatus.completed: return AppConstants.successGreen;
      case MarketLinkingStatus.cancelled: return cs.outline;
    }
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool hasFilter;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _EmptyState({required this.hasFilter, required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          const Text('🌿', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 14),
          Text(
            hasFilter ? 'No farmers match this status' : 'No Ginger farmers enrolled yet',
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            hasFilter ? 'Try a different filter' : 'Tap the + button to enroll a Ginger farmer',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ─── Update Status Modal ──────────────────────────────────────────────────────
class _UpdateStatusSheet extends StatefulWidget {
  final MarketLinkingModel entry;
  final MarketLinkingRepository repo;
  final VoidCallback onSaved;
  const _UpdateStatusSheet({required this.entry, required this.repo, required this.onSaved});

  @override
  State<_UpdateStatusSheet> createState() => _UpdateStatusSheetState();
}

class _UpdateStatusSheetState extends State<_UpdateStatusSheet> {
  late MarketLinkingStatus _selectedStatus;
  final _buyerNameCtrl = TextEditingController();
  final _buyerContactCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.entry.status;
    _buyerNameCtrl.text = widget.entry.buyerName ?? '';
    _buyerContactCtrl.text = widget.entry.buyerContact ?? '';
    _priceCtrl.text = widget.entry.pricePerKg?.toStringAsFixed(2) ?? '';
    _notesCtrl.text = widget.entry.notes ?? '';
  }

  @override
  void dispose() {
    _buyerNameCtrl.dispose();
    _buyerContactCtrl.dispose();
    _priceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await widget.repo.updateStatus(
        id: widget.entry.id,
        newStatus: _selectedStatus,
        buyerName: _buyerNameCtrl.text.trim().isEmpty ? null : _buyerNameCtrl.text.trim(),
        buyerContact: _buyerContactCtrl.text.trim().isEmpty ? null : _buyerContactCtrl.text.trim(),
        pricePerKg: double.tryParse(_priceCtrl.text.trim()),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (_) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update. Please try again.')),
      );
    }
  }

  Color _statusColor(MarketLinkingStatus s, ColorScheme cs) {
    switch (s) {
      case MarketLinkingStatus.buyerFound: return AppConstants.buyerBlue;
      case MarketLinkingStatus.completed: return AppConstants.successGreen;
      case MarketLinkingStatus.cancelled: return cs.outline;
      default: return AppConstants.warningAmber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ManagementModalShell(
      title: 'Update Status',
      subtitle: widget.entry.farmerName,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label: 'New Status', cs: cs),
          Row(
            children: MarketLinkingStatus.values
                .where((s) => s != MarketLinkingStatus.submitted)
                .map((s) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedStatus = s),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _selectedStatus == s
                                  ? _statusColor(s, cs)
                                  : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                            ),
                            child: Text(
                              s.label,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _selectedStatus == s ? Colors.white : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          if (_selectedStatus == MarketLinkingStatus.buyerFound ||
              _selectedStatus == MarketLinkingStatus.completed) ...[
            _FieldLabel(label: 'Buyer Name', cs: cs),
            TextFormField(
              controller: _buyerNameCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. DA-AMAD Collector, Marinduque',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              ),
            ),
            const SizedBox(height: 12),
            _FieldLabel(label: 'Agreed Price (₱/kg)', cs: cs),
            TextFormField(
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '₱ ',
                hintText: '0.00',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _FieldLabel(label: 'Notes (optional)', cs: cs),
          TextFormField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Additional notes or cancellation reason...',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
            ),
          ),
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: 'Save Changes',
        isLoading: _isSaving,
        onPrimary: _save,
      ),
    );
  }
}

// ─── Enroll Farmer Modal ──────────────────────────────────────────────────────
class _EnrollFarmerSheet extends StatefulWidget {
  final int totalGingerFarmers;
  final List<Map<String, dynamic>> farmers;
  final MarketLinkingRepository repo;
  final VoidCallback onSaved;
  const _EnrollFarmerSheet({
    required this.totalGingerFarmers,
    required this.farmers,
    required this.repo,
    required this.onSaved,
  });

  @override
  State<_EnrollFarmerSheet> createState() => _EnrollFarmerSheetState();
}

class _EnrollFarmerSheetState extends State<_EnrollFarmerSheet> {
  String? _selectedFarmerId;
  final _volumeCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _volumeCtrl.dispose();
    super.dispose();
  }

  Future<void> _enroll() async {
    if (_selectedFarmerId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please select a farmer.')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      await widget.repo.enrollFarmer(
        farmerId: _selectedFarmerId!,
        volumeKg: double.tryParse(_volumeCtrl.text.trim()),
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (_) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to enroll. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ManagementModalShell(
      title: 'Enroll Ginger Farmer',
      subtitle: 'Add a farmer to the DA-AMAD program',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label: 'Select Farmer', cs: cs),
          widget.farmers.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.totalGingerFarmers == 0
                            ? Icons.info_outline_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 16,
                        color: cs.outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.totalGingerFarmers == 0
                              ? 'No farmers are registered as growing Ginger yet. '
                                'Ginger must be added to a farmer\'s profile before '
                                'they can be enrolled here.'
                              : 'All ${widget.totalGingerFarmers} Ginger farmers are '
                                'already enrolled this season.',
                          style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                )
              : DropdownButtonFormField<String>(
                  initialValue: _selectedFarmerId,
                  isExpanded: true,
                  hint: Text(
                    'Select a Ginger farmer',
                    style: GoogleFonts.inter(fontSize: 14, color: cs.outline),
                    overflow: TextOverflow.ellipsis,
                  ),
                  items: widget.farmers
                      .map(
                        (f) => DropdownMenuItem(
                          value: f['id'] as String,
                          child: Text(
                            '${f['name']}${f['sitio'] != null ? ' — ${f['sitio']}' : ''}',
                            style: GoogleFonts.inter(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedFarmerId = v),
                ),
          const SizedBox(height: 14),
          _FieldLabel(label: 'Committed Volume (kg) — optional', cs: cs),
          TextFormField(
            controller: _volumeCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: 'e.g. 500',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              suffixText: 'kg',
            ),
          ),
        ],
      ),
      footer: widget.farmers.isEmpty
          ? null
          : ManagementModalActions(
              primaryLabel: 'Enroll in DA-AMAD Program',
              isLoading: _isSaving,
              onPrimary: _enroll,
            ),
    );
  }
}

// ─── Field Label ──────────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String label;
  final ColorScheme cs;
  const _FieldLabel({required this.label, required this.cs});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label,
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
        ),
      );
}