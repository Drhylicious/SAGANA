import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Unique farmers enrolled in the program — a farmer starting a second
  // round (Start New Round) must not inflate this, since they're still
  // just one enrolled farmer with two records. _totalRoundsCount below is
  // the separate, row-count metric for that.
  int get _enrolledFarmersCount =>
      _allEntries.map((e) => e.farmerId).toSet().length;
  int get _totalRoundsCount => _allEntries.length;
  int get _submittedCount =>
      _allEntries.where((e) => e.status == MarketLinkingStatus.submitted).length;
  int get _buyerFoundCount =>
      _allEntries.where((e) => e.status == MarketLinkingStatus.buyerFound).length;
  int get _completedCount =>
      _allEntries.where((e) => e.status == MarketLinkingStatus.completed).length;
  int get _cancelledCount =>
      _allEntries.where((e) => e.status == MarketLinkingStatus.cancelled).length;

  void _showStatusSheet(MarketLinkingModel entry, MarketLinkingStatus targetStatus) {
    showManagementModal(
      context: context,
      builder: (_) => _UpdateStatusSheet(
        entry: entry,
        targetStatus: targetStatus,
        repo: _repo,
        onSaved: _load,
      ),
    );
  }

  void _confirmStartNewRound(MarketLinkingModel entry) {
    showManagementModal(
      context: context,
      builder: (ctx) => ManagementModalShell(
        title: 'Start New Round',
        subtitle: entry.farmerName,
        body: const Text(
          'Enrolls this farmer in a fresh Ginger Market Linking round, '
          'starting again from Submitted. The previous round stays on '
          'record as history.',
        ),
        footer: ManagementModalActions(
          primaryLabel: 'Start New Round',
          onPrimary: () async {
            Navigator.pop(ctx);
            await _repo.startNewRound(farmerId: entry.farmerId);
            _load();
          },
        ),
      ),
    );
  }

  void _confirmDelete(MarketLinkingModel entry) {
    showManagementModal(
      context: context,
      builder: (ctx) => ManagementModalShell(
        title: 'Delete Record',
        subtitle: entry.farmerName,
        body: const Text(
          'Permanently deletes this cancelled Market Linking record. This '
          'cannot be undone.',
        ),
        footer: ManagementModalActions(
          primaryLabel: 'Delete',
          isDestructive: true,
          onPrimary: () async {
            Navigator.pop(ctx);
            await _repo.deleteEntry(entry.id);
            _load();
          },
        ),
      ),
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
                              enrolledFarmers: _enrolledFarmersCount,
                              totalRounds: _totalRoundsCount,
                              submitted: _submittedCount,
                              buyerFound: _buyerFoundCount,
                              completed: _completedCount,
                              cancelled: _cancelledCount,
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
                                    onEnterBuyerDetails: _isOnline
                                        ? () => _showStatusSheet(e, MarketLinkingStatus.buyerFound)
                                        : null,
                                    onComplete: _isOnline
                                        ? () => _showStatusSheet(e, MarketLinkingStatus.completed)
                                        : null,
                                    onCancel: _isOnline
                                        ? () => _showStatusSheet(e, MarketLinkingStatus.cancelled)
                                        : null,
                                    onStartNewRound: _isOnline
                                        ? () => _confirmStartNewRound(e)
                                        : null,
                                    onDelete: _isOnline
                                        ? () => _confirmDelete(e)
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

// ─── KPI Strip ────────────────────────────────────────────────────────────────
// Same card language as MarketplaceDashboardScreen's KPI strip (icon + label
// + value, horizontal scroll). Counts come from the full unfiltered season,
// not the currently-selected chip, so they stay accurate no matter what's
// filtered below.
class _KpiStrip extends StatelessWidget {
  final int enrolledFarmers, totalRounds, submitted, buyerFound, completed, cancelled;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _KpiStrip({
    required this.enrolledFarmers,
    required this.totalRounds,
    required this.submitted,
    required this.buyerFound,
    required this.completed,
    required this.cancelled,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = [
      // Unique farmers in the program — NOT a count of rounds/records
      // (see "Total Rounds" below for that). Starting a new round for an
      // already-enrolled farmer must not move this number.
      _KpiTile('Enrolled', '$enrolledFarmers', cs.primary, Icons.eco_rounded),
      _KpiTile('Total Rounds', '$totalRounds', AppConstants.programPurple, Icons.repeat_rounded),
      _KpiTile('Submitted', '$submitted', AppConstants.warningAmber, Icons.upload_file_rounded),
      _KpiTile('Buyer Found', '$buyerFound', AppConstants.buyerBlue, Icons.handshake_outlined),
      _KpiTile('Completed', '$completed', AppConstants.successGreen, Icons.check_circle_outline_rounded),
      _KpiTile('Cancelled', '$cancelled', AppConstants.errorRed, Icons.cancel_outlined),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🌿', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'DA-AMAD Ginger Program — institutional export pricing, bypasses the open marketplace.',
                style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
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
  // One callback per stage-appropriate action — replaces the single
  // onUpdateStatus that used to open one combined sheet with a status
  // picker offering Buyer Found/Completed/Cancelled all at once. Only the
  // action(s) valid for entry.status are ever wired (see build() below),
  // so the card renders exactly one of these small groups:
  //   submitted            -> onEnterBuyerDetails only
  //   buyer_found          -> onCancel + onComplete
  //   completed/cancelled  -> onStartNewRound only
  final VoidCallback? onEnterBuyerDetails;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final VoidCallback? onStartNewRound;
  final VoidCallback? onDelete;
  const _EntryCard({
    required this.entry,
    required this.cs,
    required this.sagana,
    this.onEnterBuyerDetails,
    this.onComplete,
    this.onCancel,
    this.onStartNewRound,
    this.onDelete,
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
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.10),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 4, color: statusColor),
          ),
          Column(
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
                            color: AppConstants.tertiaryContainer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.farmerName,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          if (entry.purok != null)
                            Text(
                              entry.purok!,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
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
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: statusColor,
                        ),
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
                        Text(
                          '${entry.volumeKg!.toStringAsFixed(0)} kg',
                          style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (entry.pricePerKg != null) ...[
                        Icon(Icons.payments_outlined, size: 13, color: cs.outline),
                        const SizedBox(width: 4),
                        Text(
                          '₱${entry.pricePerKg!.toStringAsFixed(2)}/kg',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (entry.buyerName != null) ...[
                        Icon(Icons.handshake_outlined, size: 13, color: cs.outline),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            entry.buyerName!,
                            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              if (entry.batchNumber != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 13, color: cs.outline),
                      const SizedBox(width: 4),
                      Text(
                        'Linked to Batch #${entry.batchNumber}',
                        style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                      if (entry.confirmedVolumeKg != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '· ${entry.confirmedVolumeKg!.toStringAsFixed(0)} kg confirmed',
                          style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
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
                    child: Text(
                      entry.notes!,
                      style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),

              if (entry.status == MarketLinkingStatus.submitted)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: _ActionButton(
                    onTap: onEnterBuyerDetails,
                    icon: Icons.person_add_alt_1_rounded,
                    label: 'Enter Buyer Details',
                    style: onEnterBuyerDetails != null ? _ActionStyle.tertiary : _ActionStyle.disabled,
                    cs: cs,
                  ),
                ),
              if (entry.status == MarketLinkingStatus.buyerFound)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          onTap: onCancel,
                          icon: Icons.close_rounded,
                          label: 'Cancel',
                          style: onCancel != null ? _ActionStyle.outlineDestructive : _ActionStyle.disabled,
                          cs: cs,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionButton(
                          onTap: onComplete,
                          icon: Icons.handshake_rounded,
                          label: 'Complete',
                          style: onComplete != null ? _ActionStyle.gradient : _ActionStyle.disabled,
                          cs: cs,
                        ),
                      ),
                    ],
                  ),
                ),
              if (entry.status == MarketLinkingStatus.completed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: _ActionButton(
                    onTap: onStartNewRound,
                    icon: Icons.refresh_rounded,
                    label: 'Start New Round',
                    style: onStartNewRound != null ? _ActionStyle.tertiary : _ActionStyle.disabled,
                    cs: cs,
                  ),
                ),
              // Cancelled entries additionally offer Delete — cancelled
              // records carry no sale/history value the way Completed ones
              // do, so they shouldn't just accumulate forever.
              if (entry.status == MarketLinkingStatus.cancelled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          onTap: onDelete,
                          icon: Icons.delete_outline_rounded,
                          label: 'Delete',
                          style: onDelete != null ? _ActionStyle.outlineDestructive : _ActionStyle.disabled,
                          cs: cs,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionButton(
                          onTap: onStartNewRound,
                          icon: Icons.refresh_rounded,
                          label: 'Start New Round',
                          style: onStartNewRound != null ? _ActionStyle.tertiary : _ActionStyle.disabled,
                          cs: cs,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
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

enum _ActionStyle { tertiary, gradient, outlineDestructive, disabled }

/// One reusable card-action button covering the three visual styles that
/// used to be hand-rolled separately ("Update Status"'s amber-tertiary
/// look, "Confirm Sale"'s green gradient) plus a new destructive-outline
/// style for "Cancel" — introduced when the single combined status-picker
/// sheet was split into distinct per-stage actions (Enter Buyer Details /
/// Cancel + Complete / Start New Round).
class _ActionButton extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final String label;
  final _ActionStyle style;
  final ColorScheme cs;
  const _ActionButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.style,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    Color background = cs.outline.withValues(alpha: 0.20);
    Color foreground = cs.outline;
    Gradient? gradient;
    Border? border;

    switch (style) {
      case _ActionStyle.tertiary:
        background = AppConstants.tertiaryContainer;
        foreground = AppConstants.onTertiaryContainer;
        break;
      case _ActionStyle.gradient:
        gradient = const LinearGradient(
          colors: [AppConstants.primaryGreen, AppConstants.successGreen],
        );
        foreground = Colors.white;
        break;
      case _ActionStyle.outlineDestructive:
        background = Colors.transparent;
        foreground = cs.error;
        border = Border.all(color: cs.error);
        break;
      case _ActionStyle.disabled:
        break;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: gradient == null ? background : null,
          gradient: gradient,
          border: border,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: foreground),
            ),
          ],
        ),
      ),
    );
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
// Single-purpose per invocation now — targetStatus is fixed by which
// button on the card opened it (Enter Buyer Details / Cancel / Complete),
// not picked from a Completed/Cancelled/Buyer-Found selector inside the
// sheet itself. That selector was removed: a Submitted entry could only
// ever meaningfully move to Buyer Found next, and once Buyer Found, the
// card's own Cancel/Complete buttons already say which outcome this save
// is for — a picker was one extra, redundant step. See M-marketplace-5.
class _UpdateStatusSheet extends StatefulWidget {
  final MarketLinkingModel entry;
  final MarketLinkingStatus targetStatus;
  final MarketLinkingRepository repo;
  final VoidCallback onSaved;
  const _UpdateStatusSheet({
    required this.entry,
    required this.targetStatus,
    required this.repo,
    required this.onSaved,
  });

  @override
  State<_UpdateStatusSheet> createState() => _UpdateStatusSheetState();
}

class _UpdateStatusSheetState extends State<_UpdateStatusSheet> {
  final _buyerNameCtrl = TextEditingController();
  final _buyerContactCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _requestedVolumeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _confirmedVolumeCtrl = TextEditingController();
  bool _isSaving = false;

  bool get _isCancelling => widget.targetStatus == MarketLinkingStatus.cancelled;
  bool get _isCompleting => widget.targetStatus == MarketLinkingStatus.completed;

  List<Map<String, dynamic>> _eligibleBatches = [];
  String? _selectedBatchId;
  bool _loadingBatches = true;

  @override
  void initState() {
    super.initState();
    _buyerNameCtrl.text = widget.entry.buyerName ?? '';
    _buyerContactCtrl.text = widget.entry.buyerContact ?? '';
    _priceCtrl.text = widget.entry.pricePerKg?.toStringAsFixed(2) ?? '';
    _requestedVolumeCtrl.text = widget.entry.requestedVolumeKg?.toStringAsFixed(2) ?? '';
    _notesCtrl.text = widget.entry.notes ?? '';
    _confirmedVolumeCtrl.text = widget.entry.confirmedVolumeKg?.toStringAsFixed(2) ?? '';
    _selectedBatchId = widget.entry.inventoryBatchId;
    if (_isCancelling) {
      _loadingBatches = false;
    } else {
      _loadBatches();
    }
  }

  // Ginger Market Linking is handled one farmer, one harvest at a time —
  // there is no scenario where an admin picks between several of a
  // farmer's Ginger batches. So this auto-links the batch instead of
  // presenting a picker: prefer whatever batch is already on this entry
  // (as long as it still has stock), otherwise the farmer's most recent
  // eligible Ginger batch. See M-marketplace-6.
  Future<void> _loadBatches() async {
    final batches = await widget.repo.fetchEligibleBatches(widget.entry.farmerId);
    if (!mounted) return;
    setState(() {
      _eligibleBatches = batches;
      final existing = widget.entry.inventoryBatchId;
      if (existing != null && batches.any((b) => b['id'] == existing)) {
        _selectedBatchId = existing;
      } else if (batches.isNotEmpty) {
        _selectedBatchId = batches.first['id'] as String;
      } else {
        _selectedBatchId = null;
      }
      _loadingBatches = false;
    });
  }

  @override
  void dispose() {
    _buyerNameCtrl.dispose();
    _buyerContactCtrl.dispose();
    _priceCtrl.dispose();
    _requestedVolumeCtrl.dispose();
    _notesCtrl.dispose();
    _confirmedVolumeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      // Attach/clear the batch independently of status, unless we're
      // completing right now — the RPC itself sets inventory_batch_id
      // in that case, so there's no need to do it twice. Cancelling never
      // touches the batch link at all.
      if (!_isCancelling &&
          !_isCompleting &&
          _selectedBatchId != widget.entry.inventoryBatchId) {
        await widget.repo.attachBatch(id: widget.entry.id, batchId: _selectedBatchId);
      }

      await widget.repo.updateStatus(
        id: widget.entry.id,
        newStatus: widget.targetStatus,
        buyerName: _isCancelling || _buyerNameCtrl.text.trim().isEmpty ? null : _buyerNameCtrl.text.trim(),
        buyerContact: _isCancelling || _buyerContactCtrl.text.trim().isEmpty ? null : _buyerContactCtrl.text.trim(),
        pricePerKg: _isCancelling ? null : double.tryParse(_priceCtrl.text.trim()),
        requestedVolumeKg: widget.targetStatus == MarketLinkingStatus.buyerFound
            ? double.tryParse(_requestedVolumeCtrl.text.trim())
            : null,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        inventoryBatchId: _isCompleting ? _selectedBatchId : null,
        confirmedVolumeKg: _isCompleting
            ? double.tryParse(_confirmedVolumeCtrl.text.trim())
            : null,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          e.toString().contains('exceeds')
              ? 'Confirmed volume exceeds what\'s left in that batch.'
              : 'Failed to update. Please try again.',
        )),
      );
    }
  }

  String get _title {
    switch (widget.targetStatus) {
      case MarketLinkingStatus.buyerFound: return 'Enter Buyer Details';
      case MarketLinkingStatus.completed: return 'Complete Sale';
      case MarketLinkingStatus.cancelled: return 'Cancel Enrollment';
      case MarketLinkingStatus.submitted: return 'Update';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ManagementModalShell(
      title: _title,
      subtitle: widget.entry.farmerName,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cancelling needs nothing but an optional reason — no buyer,
          // price, quantity, or batch fields at all.
          if (!_isCancelling) ...[
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
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              decoration: InputDecoration(
                prefixText: '₱ ',
                hintText: '0.00',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              ),
            ),
            const SizedBox(height: 12),

            // Only asked for at Buyer Found time — the buyer's stated
            // intent, distinct from Confirmed Volume below (which only
            // applies once completing against an actual batch).
            if (widget.targetStatus == MarketLinkingStatus.buyerFound) ...[
              _FieldLabel(label: 'Quantity Buyer Wants to Purchase (kg)', cs: cs),
              TextFormField(
                controller: _requestedVolumeCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                decoration: InputDecoration(
                  hintText: '0.00',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Ginger Harvest Batch — always this farmer's own batch,
            // automatically, never a manual choice among several (this
            // program is one farmer, one harvest, one buyer at a time).
            _FieldLabel(label: 'Ginger Harvest Batch', cs: cs),
            if (_loadingBatches)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_selectedBatchId == null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppConstants.warningAmber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: AppConstants.warningAmber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No available Ginger harvest batch found for this farmer.',
                        style: GoogleFonts.inter(fontSize: 12, color: cs.onSurface),
                      ),
                    ),
                  ],
                ),
              )
            else
              Builder(builder: (context) {
                final batch = _eligibleBatches.firstWhere((b) => b['id'] == _selectedBatchId);
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Batch #${batch['batch_number']} — ${(batch['available_kg'] as num).toStringAsFixed(0)} kg available',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }),

            if (_isCompleting && _selectedBatchId != null) ...[
              const SizedBox(height: 12),
              _FieldLabel(label: 'Confirmed Volume (kg)', cs: cs),
              TextFormField(
                controller: _confirmedVolumeCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                decoration: InputDecoration(
                  hintText: '0.00',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
                  helperText: () {
                    final batch = _eligibleBatches.firstWhere(
                      (b) => b['id'] == _selectedBatchId,
                      orElse: () => const {},
                    );
                    final avail = batch['available_kg'];
                    return avail != null
                        ? 'Up to ${(avail as num).toStringAsFixed(0)} kg available in this batch'
                        : null;
                  }(),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],

          _FieldLabel(label: _isCancelling ? 'Reason (optional)' : 'Notes (optional)', cs: cs),
          TextFormField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: _isCancelling ? 'Why this enrollment is being cancelled...' : 'Additional notes...',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
            ),
          ),
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: _isCancelling ? 'Confirm Cancellation' : 'Save Changes',
        isDestructive: _isCancelling,
        isLoading: _isSaving,
        // The harvest batch link is no longer optional (see M-marketplace-6)
        // — if this farmer genuinely has no eligible Ginger batch, there's
        // nothing real to link this record to, so saving is blocked rather
        // than silently proceeding without one. Cancelling never needs a
        // batch at all.
        onPrimary: (!_isCancelling && !_loadingBatches && _selectedBatchId == null) ? null : _save,
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
                            '${f['name']}${f['purok'] != null ? ' — ${f['purok']}' : ''}',
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