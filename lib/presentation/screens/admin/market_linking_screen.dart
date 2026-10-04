import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/market_linking_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/report_summary_widgets.dart' show ReportSectionCard;

String marketLinkingStatusLabel(AppLocalizations l10n, MarketLinkingStatus s) {
  switch (s) {
    case MarketLinkingStatus.requested:
      return 'Requested';
    case MarketLinkingStatus.submitted:
      return l10n.marketLinkKpiSubmitted;
    case MarketLinkingStatus.buyerFound:
      return l10n.marketLinkKpiBuyerFound;
    case MarketLinkingStatus.completed:
      return l10n.statCompleted;
    case MarketLinkingStatus.cancelled:
      return l10n.buyerActivityStatusCancelled;
  }
}

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
  // Approved DA-AMAD Enrollments — "Enrolled" now counts this, not
  // distinct farmers in market_linking_programs. A farmer is enrolled
  // (or not) independent of whether they currently have a harvest
  // submission in flight; see da_amad_enrollments / DaAmadEnrollmentModel.
  int _enrolledCount = 0;
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
    final results = await Future.wait([
      _repo.fetchAll(),
      _repo.fetchReviewedEnrollments(),
    ]);
    if (!mounted) return;
    final reviewed = results[1] as List<DaAmadEnrollmentModel>;
    setState(() {
      _allEntries = results[0] as List<MarketLinkingModel>;
      _enrolledCount = reviewed
          .where((e) => e.status == DaAmadEnrollmentStatus.approved)
          .length;
      _isLoading = false;
    });
  }

  // The 'requested' status is no longer created by anything (Enrollment
  // is now the one gate a farmer passes through, not a per-harvest
  // approval) — every entry here is already a real, actionable
  // submission. Kept as a no-op filter rather than assuming the list can
  // never contain a 'requested' row, in case one exists from before this
  // change.
  List<MarketLinkingModel> get _actionableEntries => _allEntries
      .where((e) => e.status != MarketLinkingStatus.requested)
      .toList();

  List<MarketLinkingModel> get _visibleEntries {
    final base = _actionableEntries;
    if (_statusFilter == null) return base;
    return base.where((e) => e.status == _statusFilter).toList();
  }

  int get _submittedCount => _actionableEntries
      .where((e) => e.status == MarketLinkingStatus.submitted)
      .length;
  int get _buyerFoundCount => _actionableEntries
      .where((e) => e.status == MarketLinkingStatus.buyerFound)
      .length;
  int get _completedCount => _actionableEntries
      .where((e) => e.status == MarketLinkingStatus.completed)
      .length;
  int get _cancelledCount => _actionableEntries
      .where((e) => e.status == MarketLinkingStatus.cancelled)
      .length;

  void _showStatusSheet(
    MarketLinkingModel entry,
    MarketLinkingStatus targetStatus,
  ) {
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

  // _confirmStartNewRound removed along with the old admin-direct
  // enrollment flow (Enroll Farmer + Start New Round both inserted a
  // market_linking_programs row directly at status='submitted', bypassing
  // the farmer's own Submit to Sell -> 'requested' -> Approve/Decline
  // path entirely). A new round is now only ever possible through that
  // farmer-initiated flow — see manage_inventory_screen.dart's Submit to
  // Sell action.

  void _confirmDelete(MarketLinkingModel entry) {
    final l10n = AppLocalizations.of(context);
    showManagementModal(
      context: context,
      builder: (ctx) => ManagementModalShell(
        title: l10n.marketLinkDeleteRecordTitle,
        subtitle: entry.farmerName,
        body: Text(l10n.marketLinkDeleteRecordBody),
        footer: ManagementModalActions(
          primaryLabel: l10n.commonDelete,
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

  // _approveRequest / _rejectRequest removed along with the per-harvest
  // 'requested' -> Approve/Decline gate (respondToRequest(), now unused).
  // Reviewing a farmer happens once, at Enrollment (Manage Enrollments,
  // top bar) — see DaAmadEnrollmentScreen. _showEnrollSheet removed along
  // with the old "+" FAB for the same reason — see the note above
  // _confirmStartNewRound's removal.

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final visible = _visibleEntries;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              // ── Fixed header — KPI strip + DA-AMAD explainer ────────────
              // Deliberately outside the scroll view: these are context an
              // admin should always see, not content that scrolls away
              // with the entry list below.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Column(
                  children: [
                    // Grouped inside the same outer titled container the
                    // Report tab uses (Executive Snapshot etc.), not just
                    // individually restyled cards.
                    ReportSectionCard(
                      title: 'Market Linking Overview',
                      icon: Icons.hub_rounded,
                      accent: AppConstants.buyerBlue,
                      child: _KpiStrip(
                        enrolledFarmers: _enrolledCount,
                        submitted: _submittedCount,
                        buyerFound: _buyerFoundCount,
                        completed: _completedCount,
                        cancelled: _cancelledCount,
                        cs: cs,
                        sagana: sagana,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Full explainer when the program is empty (it's the
                    // only content on the page and needs to earn its
                    // keep); collapses to a slim strip once there's real
                    // data so it doesn't compete with the KPI cards and
                    // entries below.
                    _DaAmadInfoCard(cs: cs, compact: _allEntries.isNotEmpty),
                    const SizedBox(height: 16),
                  ],
                ),
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
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                          children: [
                            // Pending farmer requests are gone — that gate
                            // is now Enrollment (Manage Enrollments, top
                            // bar), reviewed once per farmer rather than
                            // once per harvest submission. Every entry
                            // reaching this list is already actionable.
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
                                        ? () => _showStatusSheet(
                                            e,
                                            MarketLinkingStatus.buyerFound,
                                          )
                                        : null,
                                    onComplete: _isOnline
                                        ? () => _showStatusSheet(
                                            e,
                                            MarketLinkingStatus.completed,
                                          )
                                        : null,
                                    onCancel: _isOnline
                                        ? () => _showStatusSheet(
                                            e,
                                            MarketLinkingStatus.cancelled,
                                          )
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
              onManageEnrollments: () =>
                  context.push(AppRoutes.daAmadEnrollment).then((_) => _load()),
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
  final VoidCallback onManageEnrollments;
  final SaganaColors sagana;
  final ColorScheme cs;
  const _TopAppBar({
    required this.onBack,
    required this.onManageEnrollments,
    required this.sagana,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                    Text(
                      l10n.marketLinkTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                    Text(
                      l10n.marketLinkSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Manage Enrollments',
                icon: Icon(Icons.how_to_reg_rounded, color: cs.primary),
                onPressed: onManageEnrollments,
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
  final int enrolledFarmers, submitted, buyerFound, completed, cancelled;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _KpiStrip({
    required this.enrolledFarmers,
    required this.submitted,
    required this.buyerFound,
    required this.completed,
    required this.cancelled,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // "Total Rounds" (a raw row count, separate from unique farmers below)
    // removed — it was a leftover from when Admin could directly create
    // new rounds via "Enroll"/"Start New Round"; every remaining card here
    // maps to a real pipeline stage a farmer-initiated request actually
    // moves through.
    final tiles = [
      _KpiTile(
        l10n.marketLinkKpiEnrolled,
        '$enrolledFarmers',
        cs.primary,
        Icons.eco_rounded,
      ),
      _KpiTile(
        l10n.marketLinkKpiSubmitted,
        '$submitted',
        AppConstants.warningAmber,
        Icons.upload_file_rounded,
      ),
      _KpiTile(
        l10n.marketLinkKpiBuyerFound,
        '$buyerFound',
        AppConstants.buyerBlue,
        Icons.handshake_outlined,
      ),
      _KpiTile(
        l10n.statCompleted,
        '$completed',
        AppConstants.successGreen,
        Icons.check_circle_outline_rounded,
      ),
      _KpiTile(
        l10n.buyerActivityStatusCancelled,
        '$cancelled',
        AppConstants.errorRed,
        Icons.cancel_outlined,
      ),
    ];

    return SizedBox(
      // Was 88 — too tight for icon-badge + label + value once this strip
      // got the Report-tab-style reskin (previously just icon+label+value,
      // no badge row), which is what caused the reported RenderFlex
      // overflow. Matches Dashboard's own _KpiStrip height for the same
      // content shape.
      height: 104,
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
                  maxLines: 1,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  t.value,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
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
    final l10n = AppLocalizations.of(context);
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
                l10n.marketLinkDaAmadCompact,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
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
                  l10n.marketLinkDaAmadTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.marketLinkDaAmadBody,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
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

// _PendingRequestCard removed along with the per-harvest 'requested' ->
// Approve/Decline gate — see the note above _approveRequest's removal.

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
  //   submitted   -> onEnterBuyerDetails only
  //   buyer_found -> onCancel + onComplete
  //   completed   -> nothing (final, read-only — see build() below)
  //   cancelled   -> onDelete only
  final VoidCallback? onEnterBuyerDetails;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;
  const _EntryCard({
    required this.entry,
    required this.cs,
    required this.sagana,
    this.onEnterBuyerDetails,
    this.onComplete,
    this.onCancel,
    this.onDelete,
  });

  static const _stages = [
    MarketLinkingStatus.submitted,
    MarketLinkingStatus.buyerFound,
    MarketLinkingStatus.completed,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final statusColor = _statusColor(entry.status, cs);
    final isCancelled = entry.status == MarketLinkingStatus.cancelled;
    final stageIndex = _stages.indexOf(entry.status); // -1 if cancelled
    final statusLabel = marketLinkingStatusLabel(l10n, entry.status);

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10), width: 1),
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
                        color: AppConstants.tertiaryContainer.withValues(
                          alpha: 0.15,
                        ),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Flexible + ellipsis: Tagalog status labels (e.g.
                    // "Nakahanap ng Mamimili" for buyer_found) run
                    // noticeably longer than the English source and this
                    // pill previously assumed a short all-caps word would
                    // always fit next to the name column above.
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusFull,
                          ),
                        ),
                        child: Text(
                          statusLabel.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: statusColor,
                          ),
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
                          color: reached
                              ? statusColor
                              : cs.outline.withValues(alpha: 0.25),
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
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (entry.pricePerKg != null) ...[
                        Icon(
                          Icons.payments_outlined,
                          size: 13,
                          color: cs.outline,
                        ),
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
                        Icon(
                          Icons.handshake_outlined,
                          size: 13,
                          color: cs.outline,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            entry.buyerName!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
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
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 13,
                        color: cs.outline,
                      ),
                      const SizedBox(width: 4),
                      // Flexible + ellipsis: "Naka-link sa Batch #..." plus
                      // the confirmed-volume suffix can run past the card
                      // width once both segments are Tagalog on a narrow
                      // screen.
                      Flexible(
                        child: Text(
                          l10n.marketLinkLinkedToBatch(entry.batchNumber!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (entry.confirmedVolumeKg != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            l10n.marketLinkConfirmedVolumeSuffix(
                              entry.confirmedVolumeKg!.toStringAsFixed(0),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
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
                    Flexible(
                      child: Text(
                        _timelineLabel(entry, l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: cs.outline,
                        ),
                      ),
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
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusSm,
                      ),
                    ),
                    child: Text(
                      entry.notes!,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),

              if (entry.status == MarketLinkingStatus.submitted)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: _ActionButton(
                    onTap: onEnterBuyerDetails,
                    icon: Icons.person_add_alt_1_rounded,
                    label: l10n.marketLinkEnterBuyerDetails,
                    style: onEnterBuyerDetails != null
                        ? _ActionStyle.tertiary
                        : _ActionStyle.disabled,
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
                          label: l10n.cancel,
                          style: onCancel != null
                              ? _ActionStyle.outlineDestructive
                              : _ActionStyle.disabled,
                          cs: cs,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionButton(
                          onTap: onComplete,
                          icon: Icons.handshake_rounded,
                          label: l10n.marketLinkCompleteAction,
                          style: onComplete != null
                              ? _ActionStyle.gradient
                              : _ActionStyle.disabled,
                          cs: cs,
                        ),
                      ),
                    ],
                  ),
                ),
              // Completed is a final, read-only state — no action button.
              // A new round only ever happens through the farmer's own
              // Submit to Sell request, never from an admin-side control
              // here (see the note above _confirmStartNewRound's removal).
              //
              // Cancelled entries offer Delete only — cancelled records
              // carry no sale/history value the way Completed ones do, so
              // they shouldn't just accumulate forever.
              if (entry.status == MarketLinkingStatus.cancelled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: _ActionButton(
                    onTap: onDelete,
                    icon: Icons.delete_outline_rounded,
                    label: l10n.commonDelete,
                    style: onDelete != null
                        ? _ActionStyle.outlineDestructive
                        : _ActionStyle.disabled,
                    cs: cs,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _timelineLabel(MarketLinkingModel e, AppLocalizations l10n) {
    if (e.completedAt != null)
      return l10n.marketLinkTimelineCompleted(_fmt(e.completedAt!));
    if (e.buyerFoundAt != null)
      return l10n.marketLinkTimelineBuyerFound(_fmt(e.buyerFoundAt!));
    return l10n.marketLinkTimelineSubmitted(_fmt(e.submittedAt));
  }

  String _fmt(DateTime dt) {
    const m = [
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
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Color _statusColor(MarketLinkingStatus s, ColorScheme cs) {
    switch (s) {
      case MarketLinkingStatus.requested:
        return cs.outline;
      case MarketLinkingStatus.submitted:
        return AppConstants.warningAmber;
      case MarketLinkingStatus.buyerFound:
        return AppConstants.buyerBlue;
      case MarketLinkingStatus.completed:
        return AppConstants.successGreen;
      case MarketLinkingStatus.cancelled:
        return cs.outline;
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
            // Flexible + ellipsis: this button sits inside an Expanded
            // half-width slot (Cancel/Complete, Delete/Start New Round) and
            // Tagalog labels like "Simulan ang Bagong Round" are much
            // longer than their English source, so an unguarded Text here
            // can overflow the button's own Row before Flutter even gets
            // to the parent Row's width budget.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
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
  const _EmptyState({
    required this.hasFilter,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
            hasFilter
                ? l10n.marketLinkNoFarmersFiltered
                : l10n.marketLinkNoFarmersYet,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasFilter
                ? l10n.marketLinkTryDifferentFilter
                : l10n.marketLinkTapToEnroll,
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
  bool _isSaving = false;

  bool get _isCancelling =>
      widget.targetStatus == MarketLinkingStatus.cancelled;
  bool get _isCompleting =>
      widget.targetStatus == MarketLinkingStatus.completed;

  List<Map<String, dynamic>> _eligibleBatches = [];
  String? _selectedBatchId;
  bool _loadingBatches = true;

  @override
  void initState() {
    super.initState();
    _buyerNameCtrl.text = widget.entry.buyerName ?? '';
    _buyerContactCtrl.text = widget.entry.buyerContact ?? '';
    _priceCtrl.text = widget.entry.pricePerKg?.toStringAsFixed(2) ?? '';
    _requestedVolumeCtrl.text =
        widget.entry.requestedVolumeKg?.toStringAsFixed(2) ?? '';
    _notesCtrl.text = widget.entry.notes ?? '';
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
    final batches = await widget.repo.fetchEligibleBatches(
      widget.entry.farmerId,
    );
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
    super.dispose();
  }

  // Complete is a confirmation step, not a data-entry one — everything it
  // records was already captured when Buyer Details were entered at Buyer
  // Found time. The final confirmed quantity is derived, never typed:
  // whatever the buyer originally wanted, capped at whatever's actually
  // still available on the linked batch (it can only ever go down from
  // real-world stock changes since then, never up).
  double? get _computedConfirmedVolumeKg {
    final requested = widget.entry.requestedVolumeKg ?? widget.entry.volumeKg;
    if (requested == null) return null;
    final batch = _eligibleBatches.firstWhere(
      (b) => b['id'] == _selectedBatchId,
      orElse: () => const {},
    );
    final available = (batch['available_kg'] as num?)?.toDouble();
    if (available == null) return requested;
    return requested < available ? requested : available;
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
        await widget.repo.attachBatch(
          id: widget.entry.id,
          batchId: _selectedBatchId,
        );
      }

      await widget.repo.updateStatus(
        id: widget.entry.id,
        newStatus: widget.targetStatus,
        buyerName: _isCancelling || _buyerNameCtrl.text.trim().isEmpty
            ? null
            : _buyerNameCtrl.text.trim(),
        buyerContact: _isCancelling || _buyerContactCtrl.text.trim().isEmpty
            ? null
            : _buyerContactCtrl.text.trim(),
        pricePerKg: _isCancelling
            ? null
            : double.tryParse(_priceCtrl.text.trim()),
        requestedVolumeKg: widget.targetStatus == MarketLinkingStatus.buyerFound
            ? double.tryParse(_requestedVolumeCtrl.text.trim())
            : null,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        inventoryBatchId: _isCompleting ? _selectedBatchId : null,
        confirmedVolumeKg: _isCompleting ? _computedConfirmedVolumeKg : null,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().contains('exceeds')
                ? l10n.marketLinkVolumeExceedsError
                : l10n.marketLinkUpdateFailed,
          ),
        ),
      );
    }
  }

  String _title(AppLocalizations l10n) {
    switch (widget.targetStatus) {
      case MarketLinkingStatus.buyerFound:
        return l10n.marketLinkEnterBuyerDetails;
      case MarketLinkingStatus.completed:
        return l10n.marketLinkTitleCompleteSale;
      case MarketLinkingStatus.cancelled:
        return l10n.marketLinkTitleCancelEnrollment;
      case MarketLinkingStatus.submitted:
        return l10n.marketLinkTitleUpdate;
      // Not a real target of this sheet — 'requested' rows are reviewed
      // via the dedicated Pending Requests approve/reject flow, not this
      // generic status-update sheet. Exhaustiveness-only fallback.
      case MarketLinkingStatus.requested:
        return l10n.marketLinkTitleUpdate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return ManagementModalShell(
      title: _title(l10n),
      subtitle: widget.entry.farmerName,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cancelling needs nothing but an optional reason — no buyer,
          // price, quantity, or batch fields at all.
          if (!_isCancelling) ...[
            // Completing is a review-and-confirm step, not data entry —
            // everything here was already recorded at Buyer Found time.
            // Read-only, matching how Order Management's own Complete
            // step works: confirm what's already there, don't re-collect
            // it.
            if (_isCompleting) ...[
              _ReadOnlyRow(
                label: l10n.marketLinkBuyerNameLabel,
                value: widget.entry.buyerName ?? '—',
                cs: cs,
              ),
              const SizedBox(height: 10),
              _ReadOnlyRow(
                label: l10n.marketLinkAgreedPriceLabel,
                value: widget.entry.pricePerKg != null
                    ? '₱${widget.entry.pricePerKg!.toStringAsFixed(2)}/kg'
                    : '—',
                cs: cs,
              ),
              const SizedBox(height: 10),
              _ReadOnlyRow(
                label: l10n.marketLinkQuantityBuyerWantsLabel,
                value: widget.entry.requestedVolumeKg != null
                    ? '${widget.entry.requestedVolumeKg!.toStringAsFixed(0)} kg'
                    : '—',
                cs: cs,
              ),
              const SizedBox(height: 12),
            ] else ...[
              _FieldLabel(label: l10n.marketLinkBuyerNameLabel, cs: cs),
              TextFormField(
                controller: _buyerNameCtrl,
                decoration: InputDecoration(
                  hintText: l10n.marketLinkBuyerNameHint,
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
                ),
              ),
              const SizedBox(height: 12),
              _FieldLabel(label: l10n.marketLinkAgreedPriceLabel, cs: cs),
              TextFormField(
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
            ],

            // Only asked for at Buyer Found time — the buyer's stated
            // intent, shown read-only above once completing instead.
            if (widget.targetStatus == MarketLinkingStatus.buyerFound) ...[
              _FieldLabel(
                label: l10n.marketLinkQuantityBuyerWantsLabel,
                cs: cs,
              ),
              TextFormField(
                controller: _requestedVolumeCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
            _FieldLabel(label: l10n.marketLinkGingerBatchLabel, cs: cs),
            if (_loadingBatches)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
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
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: AppConstants.warningAmber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.marketLinkNoBatchFound,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Builder(
                builder: (context) {
                  final batch = _eligibleBatches.firstWhere(
                    (b) => b['id'] == _selectedBatchId,
                  );
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 14,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.marketLinkBatchAvailableLine(
                              '${batch['batch_number']}',
                              (batch['available_kg'] as num).toStringAsFixed(0),
                            ),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

            if (_isCompleting && _selectedBatchId != null) ...[
              const SizedBox(height: 10),
              _ReadOnlyRow(
                label: l10n.marketLinkConfirmedVolumeLabel,
                value: _computedConfirmedVolumeKg != null
                    ? '${_computedConfirmedVolumeKg!.toStringAsFixed(0)} kg'
                    : '—',
                cs: cs,
              ),
            ],
            const SizedBox(height: 12),
          ],

          if (_isCompleting) ...[
            if (widget.entry.notes != null && widget.entry.notes!.isNotEmpty)
              _ReadOnlyRow(
                label: l10n.paymentNotes,
                value: widget.entry.notes!,
                cs: cs,
              ),
          ] else ...[
            _FieldLabel(
              label: _isCancelling
                  ? l10n.marketLinkReasonOptional
                  : l10n.paymentNotes,
              cs: cs,
            ),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: _isCancelling
                    ? l10n.marketLinkWhyCancelled
                    : l10n.marketLinkAdditionalNotes,
                hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              ),
            ),
          ],
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: _isCancelling
            ? l10n.marketLinkConfirmCancellation
            : _isCompleting
            ? l10n.marketLinkCompleteAction
            : l10n.saveChanges,
        isDestructive: _isCancelling,
        isLoading: _isSaving,
        // The harvest batch link is no longer optional (see M-marketplace-6)
        // — if this farmer genuinely has no eligible Ginger batch, there's
        // nothing real to link this record to, so saving is blocked rather
        // than silently proceeding without one. Cancelling never needs a
        // batch at all.
        onPrimary:
            (!_isCancelling && !_loadingBatches && _selectedBatchId == null)
            ? null
            : _save,
      ),
    );
  }
}

// _EnrollFarmerSheet removed along with the "+" FAB and the rest of the
// old admin-direct enrollment flow — see the note above
// _confirmStartNewRound's removal.

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
      style: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: cs.onSurfaceVariant,
      ),
    ),
  );
}

/// Label + already-recorded value, locked — same pattern as the Ginger
/// Harvest Batch display just above it. Used by Complete Sale's
/// confirmation-only body: nothing there is still editable by the time an
/// admin taps Complete, it's reviewing what Buyer Found already recorded.
class _ReadOnlyRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  const _ReadOnlyRow({
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label, cs: cs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
