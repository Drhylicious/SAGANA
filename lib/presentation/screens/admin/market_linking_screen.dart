import '../../widgets/view_only_banner.dart';
import '../../../data/services/staff_permission_service.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/db_error_utils.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/market_linking_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/table_change_watcher.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/listing_filter_modal.dart'
    show MarketplaceFilterBar, MarketplaceFilterOption;
import '../../widgets/management_modal.dart';
import '../../widgets/market_linking_sale_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/workflow_history_sheet.dart';

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

/// What the Manager/Officer list can be narrowed to. Each chip shows how many
/// requests it holds.
enum _MlFilter { all, cancellationRequests, waiting, buyerFound, completed, cancelled }

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
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _isLoading = true;
  bool _isOnline = true;
  _MlFilter _filter = _MlFilter.all;
  TableChangeWatcher? _watcher;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _load();
    // A Farmer submitting a request, or another Manager moving one along,
    // updates the list and the chip counts without a pull-down.
    _watcher = TableChangeWatcher(
      tables: const ['market_linking_programs'],
      onChange: () {
        if (mounted) _load(silent: true);
      },
    )..start();
  }

  @override
  void dispose() {
    _watcher?.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final entries = await _repo.fetchAll();
    if (!mounted) return;
    setState(() {
      _allEntries = entries;
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

  bool _matches(MarketLinkingModel e, _MlFilter f) {
    switch (f) {
      case _MlFilter.all:
        return true;
      case _MlFilter.cancellationRequests:
        return e.isCancellationRequested;
      case _MlFilter.waiting:
        return e.status == MarketLinkingStatus.submitted;
      case _MlFilter.buyerFound:
        return e.status == MarketLinkingStatus.buyerFound;
      case _MlFilter.completed:
        return e.status == MarketLinkingStatus.completed;
      case _MlFilter.cancelled:
        return e.status == MarketLinkingStatus.cancelled;
    }
  }

  // Cancellation requests come first (they are waiting on the Manager), then
  // the other open requests, then completed, then cancelled (each group keeps
  // the newest-first order the list arrives in).
  List<MarketLinkingModel> get _visibleEntries {
    final matching = _actionableEntries
        .where((e) => e.matchesSearch(_query))
        .where((e) => _matches(e, _filter))
        .toList();
    int rank(MarketLinkingModel e) => e.isCancellationRequested
        ? 0
        : e.isActive
        ? 1
        : e.status == MarketLinkingStatus.completed
        ? 2
        : 3;
    final indexed = matching.asMap().entries.toList()
      ..sort((a, b) {
        final byRank = rank(a.value).compareTo(rank(b.value));
        return byRank != 0 ? byRank : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  // Counts come from every request, not only the ones the search shows, so a
  // chip always says how many requests of its kind exist.
  Map<_MlFilter, int> get _counts => {
    for (final f in _MlFilter.values)
      f: _actionableEntries.where((e) => _matches(e, f)).length,
  };

  void _afterSave(String message) {
    _load();
    if (mounted) AppToast.show(context, message);
  }

  // Stage 2 — Buyer Details (buyer information only; sells nothing).
  void _showBuyerDetails(MarketLinkingModel entry) {
    showManagementModal(
      context: context,
      builder: (_) => _BuyerDetailsSheet(entry: entry, repo: _repo, onSaved: _afterSave),
    );
  }

  // Stage 3 — Complete Sale: quantity purchased, agreed price, notes. A
  // part-purchase leaves the unsold quantity with the Farmer.
  void _showCompleteSale(MarketLinkingModel entry) {
    if (!requireManage(context, StaffModule.marketplace)) return;
    showManagementModal(
      context: context,
      builder: (_) => _CompleteSaleSheet(entry: entry, repo: _repo, onSaved: _afterSave),
    );
  }

  // Review a Farmer's cancellation request: approve, or decline with a reason.
  void _reviewCancellation(MarketLinkingModel entry, {required bool approve}) {
    if (!requireManage(context, StaffModule.marketplace)) return;
    showManagementModal(
      context: context,
      builder: (_) => _ReviewCancellationSheet(
        entry: entry,
        approve: approve,
        repo: _repo,
        onDone: _afterSave,
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
    if (!requireManage(context, StaffModule.marketplace)) return;
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
              TopBarSpacer(height: 64),
              // ── Fixed header: Search bar -> Filter chips -> the list ─────
              // Type to find a request by farmer, crop, batch or buyer; the
              // chips (with their counts) narrow it further.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      onChanged: (v) => setState(() => _query = v.trim()),
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).mlkSearchHint,
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: AppLocalizations.of(context).mlkSearchClear,
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _query = '');
                                },
                              ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    MarketplaceFilterBar<_MlFilter>(
                      selected: _filter,
                      onSelected: (f) => setState(() => _filter = f),
                      options: [
                        for (final f in _MlFilter.values)
                          MarketplaceFilterOption(
                            value: f,
                            label: _filterLabel(AppLocalizations.of(context), f),
                            count: _counts[f] ?? 0,
                            color: _filterColor(context, f),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _load,
                  child: _isLoading
                      ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                          children: [
                            // Pending farmer requests are gone — that gate
                            // is now Enrollment (Manage Enrollments, top
                            // bar), reviewed once per farmer rather than
                            // once per harvest submission. Every entry
                            // reaching this list is already actionable.
                            if (visible.isEmpty && _query.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 40),
                                child: Column(
                                  children: [
                                    Icon(Icons.search_off_rounded, size: 40, color: cs.outline),
                                    const SizedBox(height: 10),
                                    Text(
                                      AppLocalizations.of(context).mlkNoSearchResults,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              )
                            else if (visible.isEmpty)
                              _EmptyState(

                                hasFilter: _filter != _MlFilter.all,
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
                                    onBuyerDetails: _isOnline
                                        ? () => _showBuyerDetails(e)
                                        : null,
                                    onComplete: _isOnline
                                        ? () => _showCompleteSale(e)
                                        : null,
                                    onApproveCancellation: _isOnline
                                        ? () => _reviewCancellation(e, approve: true)
                                        : null,
                                    onDeclineCancellation: _isOnline
                                        ? () => _reviewCancellation(e, approve: false)
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
    return SubPageTopBar(title: l10n.marketLinkTitle, onBack: onBack, trailing: IconButton( tooltip: l10n.mlkManageEnrollments,
 icon: Icon(Icons.how_to_reg_rounded, color: cs.primary), onPressed: onManageEnrollments, ));
  }
}

// ─── Filter chips ─────────────────────────────────────────────────────────────
// One row: All, Cancellation requests, Waiting for a buyer, Buyer found,
// Completed, Cancelled, each with how many requests it holds (the shared
// MarketplaceFilterBar). Colours match the status pill on the cards.
String _filterLabel(AppLocalizations l10n, _MlFilter f) {
  switch (f) {
    case _MlFilter.all:
      return l10n.mlkFilterAll;
    case _MlFilter.waiting:
      return l10n.mlkStatusWaiting;
    case _MlFilter.buyerFound:
      return l10n.mlkStatusBuyerFound;
    case _MlFilter.completed:
      return l10n.statCompleted;
    case _MlFilter.cancellationRequests:
      return l10n.mlkFilterCancellationRequests;
    case _MlFilter.cancelled:
      return l10n.mlkStatusCancelled;
  }
}

Color _filterColor(BuildContext context, _MlFilter f) {
  switch (f) {
    case _MlFilter.all:
      return Theme.of(context).colorScheme.primary;
    case _MlFilter.cancellationRequests:
      return AppConstants.errorRed;
    case _MlFilter.waiting:
      return AppConstants.warningAmber;
    case _MlFilter.buyerFound:
      return AppConstants.buyerBlue;
    case _MlFilter.completed:
      return AppConstants.successGreen;
    case _MlFilter.cancelled:
      return AppConstants.outline;
  }
}

// _PendingRequestCard removed along with the per-harvest 'requested' ->
// Approve/Decline gate — see the note above _approveRequest's removal.

// ─── Entry Card ───────────────────────────────────────────────────────────────
// One request, worked through four clearly separate stages (shown as a bar):
//   Request -> Buyer Details -> Complete Sale -> Completed
// Built from the same shared pieces as the Farmer's card. The one main action is
// always the next stage:
//   waiting for a buyer -> Add Buyer Details
//   buyer found         -> Complete Sale (and Edit buyer details)
//   completed           -> nothing (final, read-only)
// There is no Cancel here: a cancellation starts with the Farmer, and arrives
// as a banner on the request with Approve / Decline.
class _EntryCard extends StatelessWidget {
  final MarketLinkingModel entry;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback? onBuyerDetails;
  final VoidCallback? onComplete;
  final VoidCallback? onApproveCancellation;
  final VoidCallback? onDeclineCancellation;
  final VoidCallback? onDelete;
  const _EntryCard({
    required this.entry,
    required this.cs,
    required this.sagana,
    this.onBuyerDetails,
    this.onComplete,
    this.onApproveCancellation,
    this.onDeclineCancellation,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isCancelled = entry.status == MarketLinkingStatus.cancelled;
    final isWaiting = entry.status == MarketLinkingStatus.submitted;
    final isBuyerFound = entry.status == MarketLinkingStatus.buyerFound;
    final subtitle = entry.batchNumber != null
        ? '${entry.cropName} · ${formatBatchNumber(entry.batchNumber)}'
        : entry.cropName;
    final notes = (entry.notes ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: entry.isCancellationRequested
              ? AppConstants.errorRed.withValues(alpha: 0.35)
              : cs.outline.withValues(alpha: 0.10),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Opacity(
        opacity: isCancelled ? 0.75 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MarketLinkingEntryPhoto(entry: entry, size: 52),
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
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: MarketLinkingStatusChip(entry: entry)),
              ],
            ),

            // The farmer's cancellation request: review it right here.
            if (entry.isCancellationRequested) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppConstants.errorRed.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.mlkCancelBanner(entry.cancellationReason ?? ''),
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.4,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            onTap: onDeclineCancellation,
                            icon: Icons.close_rounded,
                            label: l10n.mlkDeclineCancellation,
                            style: onDeclineCancellation != null
                                ? _ActionStyle.outlineDestructive
                                : _ActionStyle.disabled,
                          cs: cs,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ActionButton(
                            onTap: onApproveCancellation,
                            icon: Icons.check_rounded,
                            label: l10n.mlkApproveCancellation,
                            style: onApproveCancellation != null
                                ? _ActionStyle.tertiary
                                : _ActionStyle.disabled,
                          cs: cs,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            if (!isCancelled) ...[
              const SizedBox(height: 16),
              MarketLinkingStageBar(entry: entry),
              if (entry.volumeKg != null) ...[
                const SizedBox(height: 16),
                MarketLinkingSaleProgress(entry: entry),
              ],
            ],

            // Stage 2 on show: who the buyer is.
            if (entry.hasBuyer && !isCancelled) ...[
              const SizedBox(height: 14),
              MarketLinkingBuyerBlock(entry: entry),
            ],

            // What to do next, in one line.
            if (isWaiting || (isBuyerFound && !entry.hasSales)) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isWaiting ? l10n.mlkHintAddBuyer : l10n.mlkHintCompleteSale,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.4,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            if (entry.sales.isNotEmpty) ...[
              const SizedBox(height: 14),
              MarketLinkingSalesList(entry: entry),
            ],

            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                notes,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],

            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 12, color: cs.outline),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _timelineLabel(entry, l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 10.5, color: cs.outline),
                  ),
                ),
              ],
            ),

            // Who did each step (buyer details, sales, cancellations), with name and
            // time. Staff only.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showWorkflowHistorySheet(
                  context,
                  entityType: 'market_linking',
                  entityId: entry.id,
                  title: '${entry.cropName} · ${entry.farmerName}',
                ),
                icon: const Icon(Icons.history_rounded, size: 16),
                label: Text(l10n.wfHistoryAction),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
              ),
            ),

            // The next stage is the one main action.
            if (isWaiting) ...[
              const SizedBox(height: 14),
              _ActionButton(
                onTap: onBuyerDetails,
                icon: Icons.person_add_alt_1_rounded,
                label: l10n.mlkActionAddBuyer,
                style: onBuyerDetails != null ? _ActionStyle.gradient : _ActionStyle.disabled,
              cs: cs,
              ),
            ],
            if (isBuyerFound) ...[
              const SizedBox(height: 14),
              _ActionButton(
                onTap: onComplete,
                icon: Icons.handshake_rounded,
                label: l10n.mlkActionCompleteSale,
                style: onComplete != null ? _ActionStyle.gradient : _ActionStyle.disabled,
              cs: cs,
              ),
              const SizedBox(height: 10),
              _ActionButton(
                onTap: onBuyerDetails,
                icon: Icons.edit_outlined,
                label: l10n.mlkActionEditBuyer,
                style: onBuyerDetails != null ? _ActionStyle.tertiary : _ActionStyle.disabled,
              cs: cs,
              ),
            ],

            // Cancelled entries offer Delete only — they carry no sale history.
            if (isCancelled) ...[
              const SizedBox(height: 14),
              _ActionButton(
                onTap: onDelete,
                icon: Icons.delete_outline_rounded,
                label: l10n.commonDelete,
                style: onDelete != null
                    ? _ActionStyle.outlineDestructive
                    : _ActionStyle.disabled,
              cs: cs,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _timelineLabel(MarketLinkingModel e, AppLocalizations l10n) {
    if (e.completedAt != null) {
      return l10n.marketLinkTimelineCompleted(_fmt(e.completedAt!));
    }
    if (e.buyerFoundAt != null) {
      return l10n.marketLinkTimelineBuyerFound(_fmt(e.buyerFoundAt!));
    }
    return l10n.marketLinkTimelineSubmitted(_fmt(e.submittedAt));
  }

  String _fmt(DateTime dt) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
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

// ─── Stage 2: Buyer Details ───────────────────────────────────────────────────
// Who the buyer is, and nothing else: full name and contact number (required),
// email (optional). Saving only records the buyer (the request
// becomes Buyer Found). It never sells, completes or deducts anything — the
// quantity and price are entered later, in Complete Sale.
class _BuyerDetailsSheet extends StatefulWidget {
  final MarketLinkingModel entry;
  final MarketLinkingRepository repo;
  final void Function(String message) onSaved;
  const _BuyerDetailsSheet({
    required this.entry,
    required this.repo,
    required this.onSaved,
  });

  @override
  State<_BuyerDetailsSheet> createState() => _BuyerDetailsSheetState();
}

class _BuyerDetailsSheetState extends State<_BuyerDetailsSheet> {
  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String? _nameError;
  String? _contactError;
  String? _emailError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _nameCtrl.text = e.buyerName ?? '';
    _contactCtrl.text = e.buyerContact ?? '';
    _emailCtrl.text = e.buyerEmail ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final email = _emailCtrl.text.trim();
    setState(() {
      _nameError = _nameCtrl.text.trim().isEmpty ? l10n.mlkBuyerNameRequired : null;
      _contactError = _contactCtrl.text.trim().isEmpty ? l10n.mlkBuyerContactRequired : null;
      _emailError = email.isNotEmpty && !_emailShape.hasMatch(email)
          ? l10n.mlkBuyerEmailInvalid
          : null;
    });
    if (_nameError != null || _contactError != null || _emailError != null) return;

    setState(() => _isSaving = true);
    try {
      await widget.repo.saveBuyerDetails(
        programId: widget.entry.id,
        fullName: _nameCtrl.text,
        contactNumber: _contactCtrl.text,
        email: email,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved(l10n.mlkBuyerSaved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppToast.show(
        context,
        readableDatabaseMessage(e) ?? l10n.mlkBuyerSaveFailed,
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return ManagementModalShell(
      title: l10n.mlkBuyerTitle,
      subtitle: widget.entry.farmerName,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.mlkBuyerNote,
                  style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _FieldLabel(label: l10n.mlkBuyerFullName, cs: cs),
          TextFormField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() => _nameError = null),
            decoration: InputDecoration(hintText: l10n.mlkBuyerFullNameHint, errorText: _nameError),
          ),
          const SizedBox(height: 12),
          _FieldLabel(label: l10n.mlkBuyerContact, cs: cs),
          TextFormField(
            controller: _contactCtrl,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() => _contactError = null),
            decoration: InputDecoration(hintText: l10n.mlkBuyerContactHint, errorText: _contactError),
          ),
          const SizedBox(height: 12),
          _FieldLabel(label: l10n.mlkBuyerEmail, cs: cs),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() => _emailError = null),
            decoration: InputDecoration(hintText: l10n.mlkBuyerEmailHint, errorText: _emailError),
          ),
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: l10n.mlkBuyerSave,
        isLoading: _isSaving,
        onPrimary: _save,
      ),
    );
  }
}

// ─── Review a Farmer's cancellation request ───────────────────────────────────
// Approve: the unsold reserved quantity goes back to the Farmer's stock and any
// sale already recorded stays. Decline: a reason is required, and the Farmer is
// told. The Manager/Officer never starts a cancellation themselves.
class _ReviewCancellationSheet extends StatefulWidget {
  final MarketLinkingModel entry;
  final bool approve;
  final MarketLinkingRepository repo;
  final void Function(String message) onDone;
  const _ReviewCancellationSheet({
    required this.entry,
    required this.approve,
    required this.repo,
    required this.onDone,
  });

  @override
  State<_ReviewCancellationSheet> createState() => _ReviewCancellationSheetState();
}

class _ReviewCancellationSheetState extends State<_ReviewCancellationSheet> {
  final _reasonCtrl = TextEditingController();
  String? _reasonError;
  bool _isSaving = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!widget.approve && _reasonCtrl.text.trim().isEmpty) {
      setState(() => _reasonError = l10n.mlkDeclineReasonRequired);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await widget.repo.respondToCancellation(
        programId: widget.entry.id,
        approve: widget.approve,
        notes: _reasonCtrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onDone(widget.approve ? l10n.mlkCancelApproved : l10n.mlkCancelDeclinedToast);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppToast.show(
        context,
        readableDatabaseMessage(e) ?? l10n.mlkCancelReviewFailed,
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final e = widget.entry;
    return ManagementModalShell(
      title: widget.approve ? l10n.mlkApproveTitle : l10n.mlkDeclineTitle,
      subtitle: e.farmerName,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppConstants.errorRed.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Text(
              l10n.mlkCancelBanner(e.cancellationReason ?? ''),
              style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: cs.onSurface),
            ),
          ),
          const SizedBox(height: 14),
          if (widget.approve)
            Text(
              l10n.mlkApproveBody,
              style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: cs.onSurfaceVariant),
            )
          else ...[
            _FieldLabel(label: l10n.mlkDeclineReasonLabel, cs: cs),
            TextFormField(
              controller: _reasonCtrl,
              maxLines: 3,
              onChanged: (_) => setState(() => _reasonError = null),
              decoration: InputDecoration(
                hintText: l10n.mlkDeclineReasonHint,
                errorText: _reasonError,
              ),
            ),
          ],
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: widget.approve ? l10n.mlkApproveConfirm : l10n.mlkDeclineConfirm,
        isDestructive: !widget.approve,
        isLoading: _isSaving,
        onPrimary: _submit,
      ),
    );
  }
}

// ─── Stage 3: Complete Sale ───────────────────────────────────────────────────
// The transaction itself: the harvest batch (read-only: the request's own),
// quantity purchased, agreed price per kg, the total (worked out as you type)
// and optional notes. The buyer is the one saved in Buyer Details and is shown
// here read-only. The Manager/Officer reviews it all, then taps Complete Sale:
// only then does the sold quantity and the Farmer's remaining stock change. A
// part-purchase leaves the unsold quantity with the Farmer (80 submitted, 50
// sold -> 30 still in the request); buying the last of it completes the request.
// The Farmer owns the Ginger and receives the payment: this is the Farmer's
// sale, not Cooperative stock or revenue.
class _CompleteSaleSheet extends StatefulWidget {
  final MarketLinkingModel entry;
  final MarketLinkingRepository repo;
  final void Function(String message) onSaved;
  const _CompleteSaleSheet({
    required this.entry,
    required this.repo,
    required this.onSaved,
  });

  @override
  State<_CompleteSaleSheet> createState() => _CompleteSaleSheetState();
}

class _CompleteSaleSheetState extends State<_CompleteSaleSheet> {
  final _qtyCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _qtyError;
  String? _priceError;
  bool _isSaving = false;

  double get _remaining => widget.entry.remainingKg;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    // The last agreed price is a sensible starting point; the quantity starts
    // as what is left (the Manager lowers it for a part-purchase).
    _priceCtrl.text = e.pricePerKg != null ? e.pricePerKg!.toStringAsFixed(2) : '';
    _qtyCtrl.text = _remaining > 0 ? formatQuantity(_remaining) : '';
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double? get _qty => parseDecimal(_qtyCtrl.text, max: _remaining);
  double? get _price => parseDecimal(_priceCtrl.text);
  double? get _total =>
      (_qty != null && _price != null) ? moneyOf(_qty!, _price!) : null;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _qtyError = quantityErrorText(
        _qtyCtrl.text,
        max: _remaining,
        unit: widget.entry.unit,
        label: l10n.mlkSaleQtyLabel,
      );
      _priceError = priceErrorText(_priceCtrl.text, label: l10n.mlkSalePriceLabel);
    });
    if (_qtyError != null || _priceError != null) return;

    final qty = _qty!;
    final price = _price!;
    setState(() => _isSaving = true);
    try {
      await widget.repo.recordSale(
        programId: widget.entry.id,
        quantityKg: qty,
        pricePerKg: price,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      final left = roundQuantity(_remaining - qty);
      final message = left > 0
          ? l10n.mlkSaleDoneMore(
              formatQuantityUnit(qty, widget.entry.unit),
              formatQuantityUnit(left, widget.entry.unit),
            )
          : l10n.mlkSaleDoneAll(
              formatQuantityUnit(qty, widget.entry.unit),
              formatPesos(moneyOf(qty, price)),
            );
      Navigator.pop(context);
      widget.onSaved(message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppToast.show(
        context,
        readableDatabaseMessage(e) ?? l10n.mlkSaleFailed,
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final e = widget.entry;
    final total = _total;
    final qty = _qty;
    final leftAfter = qty != null ? roundQuantity(_remaining - qty) : null;

    Widget readOnlyRow(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );

    return ManagementModalShell(
      title: l10n.mlkActionCompleteSale,
      subtitle: e.farmerName,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // What is being sold, to whom: both already decided, shown read-only.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    MarketLinkingEntryPhoto(entry: e, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        e.cropName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                readOnlyRow(
                  l10n.mlkSaleBatchLabel,
                  e.batchNumber != null ? formatBatchNumber(e.batchNumber) : '—',
                ),
                readOnlyRow(
                  l10n.mlkSaleBuyerLabel,
                  [
                    (e.buyerName ?? '').trim(),
                    if ((e.buyerContact ?? '').trim().isNotEmpty) e.buyerContact!.trim(),
                  ].join(' · '),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.mlkSaleLeftOf(
                    formatQuantityUnit(_remaining, e.unit),
                    formatQuantityUnit(e.volumeKg ?? 0, e.unit),
                  ),
                  style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Side by side when there is room, stacked on a very narrow screen.
          // Both labels get the same height (they may wrap to two lines, in
          // Tagalog especially), so the two input boxes always line up.
          LayoutBuilder(
            builder: (context, constraints) {
              final qtyField = AlignedLabeledField(
                label: l10n.mlkSaleQty(unitOrDefault(e.unit)),
                child: TextFormField(
                  controller: _qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [DecimalInputFormatter()],
                  onChanged: (_) => setState(() => _qtyError = null),
                  decoration: InputDecoration(
                    suffixText: unitOrDefault(e.unit),
                    hintText: '0.00',
                    errorText: _qtyError,
                    errorMaxLines: 2,
                  ),
                ),
              );
              final priceField = AlignedLabeledField(
                label: l10n.mlkSalePrice(unitOrDefault(e.unit)),
                child: TextFormField(
                  controller: _priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [DecimalInputFormatter()],
                  onChanged: (_) => setState(() => _priceError = null),
                  decoration: InputDecoration(
                    prefixText: '₱ ',
                    hintText: '0.00',
                    errorText: _priceError,
                    errorMaxLines: 2,
                  ),
                ),
              );
              if (constraints.maxWidth < 300) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [qtyField, const SizedBox(height: 12), priceField],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: qtyField),
                  const SizedBox(width: 12),
                  Expanded(child: priceField),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          // The total is worked out as you type.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppConstants.successGreen.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: AppConstants.successGreen.withValues(alpha: 0.30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.mlkSaleTotal,
                  style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  total != null ? formatPesos(total) : '₱0.00',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.successGreen,
                  ),
                ),
                if (leftAfter != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    leftAfter > 0
                        ? l10n.mlkSaleAfter(formatQuantityUnit(leftAfter, e.unit))
                        : l10n.mlkSaleCompletesRequest,
                    style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _FieldLabel(label: l10n.mlkSaleNotes, cs: cs),
          TextFormField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: InputDecoration(hintText: l10n.mlkSaleNotesHint),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${l10n.mlkSaleReviewNote} ${l10n.mlkSaleOwnerNote}',
                  style: GoogleFonts.inter(fontSize: 11.5, height: 1.4, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: l10n.mlkActionCompleteSale,
        isLoading: _isSaving,
        onPrimary: _remaining > 0 ? _save : null,
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

