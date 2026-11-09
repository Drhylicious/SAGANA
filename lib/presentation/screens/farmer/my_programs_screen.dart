import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/program_model.dart' show daysSinceReceived;
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/models/program_outcome_model.dart';
import '../../../data/models/program_return_model.dart';
import '../../../data/models/program_assistance_model.dart';
import '../../../data/repositories/program_assistance_repository.dart';
import '../../../core/utils/app_error_message.dart';
import '../../widgets/app_toast.dart';
import '../../../data/repositories/farmer_program_repository.dart';
import '../../../data/repositories/farmer_profile_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/labeled_text_field.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/skeleton.dart';
import '../../../core/l10n/app_localizations.dart';

class MyProgramsScreen extends StatefulWidget {
  const MyProgramsScreen({super.key});

  @override
  State<MyProgramsScreen> createState() => _MyProgramsScreenState();
}

class _MyProgramsScreenState extends State<MyProgramsScreen> {
  final _repo = FarmerProfileRepository();
  final _programRepo = FarmerProgramRepository();
  List<MyProgramEntry> _programs = [];
  // The outcome report that represents each enrollment right now.
  Map<String, MyOutcomeReport> _reportByMember = {};
  // Harvest returns received so far, and the plain status of failed outcomes.
  MyReturnsSnapshot _returns = const MyReturnsSnapshot();
  // Assistance after a failed outcome (separate from loans), by program member.
  final _assistRepo = ProgramAssistanceRepository();
  Map<String, AssistanceOption> _assistOptions = {};
  Map<String, AssistanceRequest> _assistLatest = {};
  // The Farmer's requests for another distribution, by the failed round ('pending' | 'approved').
  Map<String, String> _redistRequests = {};
  bool _isLoading = true;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchMyPrograms(),
      _programRepo.fetchMyOutcomeReports(),
      _programRepo.fetchMyReturns(),
      _assistRepo.fetchMyOptions(),
      _assistRepo.fetchMyRequests(),
      _programRepo.fetchMyRedistributionRequests(),
    ]);
    if (!mounted) return;
    final programs = results[0] as List<MyProgramEntry>;
    final reports = results[1] as List<MyOutcomeReport>; // newest first
    final byMember = <String, MyOutcomeReport>{};
    for (final p in programs) {
      final current = currentReportFor<MyOutcomeReport>(
        reports,
        p.id,
        memberOf: (r) => r.programMemberId,
        isReturned: (r) => r.isReturned,
      );
      if (current != null) byMember[p.id] = current;
    }
    setState(() {
      _programs = programs;
      _reportByMember = byMember;
      _returns = results[2] as MyReturnsSnapshot;
      _assistOptions = {
        for (final o in results[3] as List<AssistanceOption>) o.programMemberId: o,
      };
      // Newest first, so the first one seen per member is the latest.
      _assistLatest = {};
      for (final r in results[4] as List<AssistanceRequest>) {
        _assistLatest.putIfAbsent(r.programMemberId, () => r);
      }
      _redistRequests = results[5] as Map<String, String>;
      _isLoading = false;
    });
  }

  /// The Farmer's request for another distribution: what they reported, then a required note. It goes to the
  /// cooperative, which can only approve it (they were already marked eligible).
  Future<void> _openRequestRedistribution(MyProgramEntry entry) async {
    final report = _reportByMember[entry.id];
    final noteCtrl = TextEditingController();
    var saving = false;
    String? error;
    final sent = await showManagementModal<bool>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        final cs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            Future<void> submit() async {
              if (saving) return;
              if (noteCtrl.text.trim().isEmpty) {
                setModal(() => error = l10n.farmerRedistNoteRequired);
                return;
              }
              setModal(() {
                saving = true;
                error = null;
              });
              try {
                await _programRepo.requestRedistribution(memberId: entry.id, note: noteCtrl.text.trim());
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e, st) {
                if (!ctx.mounted) return;
                setModal(() => saving = false);
                AppToast.show(ctx, friendlyError(l10n, e, st), isError: true);
              }
            }

            Widget row(String label, String value) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(label,
                            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(value,
                            textAlign: TextAlign.end,
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                );

            return ManagementModalShell(
              title: l10n.farmerRedistSheetTitle,
              subtitle: entry.programName,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.farmerRedistSheetInfo,
                      style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 14),
                  Text(l10n.farmerRedistReported,
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  row(l10n.farmerRedistItemGiven,
                      '${entry.quantityGiven != null ? '${formatQuantityGrouped(entry.quantityGiven!)} ' : ''}'
                      '${entry.itemUnit ?? ''} ${entry.itemName ?? ''}'.trim()),
                  if (report != null) ...[
                    row(l10n.farmerRedistReportedOutcome,
                        report.reportedOutcome == 'successful'
                            ? l10n.outcStatusSuccessful
                            : l10n.outcStatusFailed),
                    row(l10n.farmerRedistReportedOn, _formatDate(report.submittedAt)),
                    if (report.finalizedAt != null)
                      row(l10n.farmerRedistConfirmedOn, _formatDate(report.finalizedAt!)),
                  ],
                  const SizedBox(height: 10),
                  LabeledTextField(
                    controller: noteCtrl,
                    label: l10n.farmerRedistNoteLabel,
                    hint: '',
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!, style: GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed)),
                    ),
                ],
              ),
              footer: ManagementModalActions(
                primaryLabel: l10n.farmerRedistSubmit,
                isLoading: saving,
                onPrimary: saving ? null : submit,
              ),
            );
          },
        );
      },
    );
    noteCtrl.dispose();
    if (sent == true && mounted) {
      AppToast.show(context, AppLocalizations.of(context).farmerRedistSent);
      _load();
    }
  }

  Future<void> _openAssistance(MyProgramEntry entry) async {
    final sent = await context.push<bool>(
      AppRoutes.requestAssistance,
      extra: {'programMemberId': entry.id, 'programName': entry.programName},
    );
    if (sent == true) _load();
  }

  Future<void> _cancelAssistance(AssistanceRequest r) async {
    final l10n = AppLocalizations.of(context);
    try {
      await _assistRepo.cancel(r.id);
      if (!mounted) return;
      AppToast.show(context, l10n.assistCancelled);
      _load();
    } catch (e, st) {
      if (mounted) AppToast.show(context, friendlyError(l10n, e, st), isError: true);
    }
  }

  Future<void> _openReport(MyProgramEntry entry, MyOutcomeReport? current) async {
    final filed = await context.push<bool>(
      AppRoutes.reportOutcome,
      extra: {'entry': entry, 'returnNote': current?.returnNote},
    );
    if (filed == true) _load();
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _statusLabel(AppLocalizations l10n, String status) {
    switch (status) {
      case 'withdrawn':
        return l10n.farmerProgStatusWithdrawn;
      case 'completed':
        return l10n.farmerProgStatusCompleted;
      default:
        return l10n.farmerProgStatusActive;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Stack(
        children: [
          Column(
            children: [
              TopBarSpacer(height: 64),
              CachedDataNotice(
                screen: 'my_programs',
                isOnline: _isOnline,
                offlineMessage: l10n.offlinePrograms,
              ),
              const SizedBox(height: 4),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _load,
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: SkeletonList(),
                        )
                      : _programs.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          children: [
                            const SizedBox(height: 90),
                            const Icon(
                              Icons.volunteer_activism_outlined,
                              size: 56,
                              color: AppConstants.outline,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              l10n.farmerProgEmptyTitle,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.farmerProgEmptyBody,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                height: 1.45,
                                color: AppConstants.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                          itemCount: _programs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 14),
                          itemBuilder: (_, i) => MyProgramCard(
                            entry: _programs[i],
                            report: _reportByMember[_programs[i].id],
                            harvestReturn: _returns.byMember[_programs[i].id],
                            resolution: _returns.resolutionByMember[_programs[i].id],
                            assistOption: _assistOptions[_programs[i].id],
                            assistRequest: _assistLatest[_programs[i].id],
                            redistStatus: _redistRequests[_programs[i].id],
                            onRequestRedistribution: _isOnline ? () => _openRequestRedistribution(_programs[i]) : null,
                            onAssist: () => _openAssistance(_programs[i]),
                            onCancelAssist: () => _cancelAssistance(_assistLatest[_programs[i].id]!),
                            onReport: () => _openReport(
                              _programs[i],
                              _reportByMember[_programs[i].id],
                            ),
                            formatDate: _formatDate,
                            statusLabel: (s) => _statusLabel(l10n, s),
                          ),
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
              title: 'My Programs',
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
        ],
      ),
    );
  }
}

/// One enrolled program on the Farmer's My Programs screen (public so its layout can be tested).
class MyProgramCard extends StatelessWidget {
  final MyProgramEntry entry;
  final MyOutcomeReport? report;
  final ProgramReturnSummary? harvestReturn;
  final String? resolution;
  final AssistanceOption? assistOption;
  final AssistanceRequest? assistRequest;
  // The Farmer's request for another distribution after "Eligible for Reassessment" (null = none sent).
  final String? redistStatus;
  final VoidCallback? onRequestRedistribution;
  final VoidCallback? onAssist;
  final VoidCallback? onCancelAssist;
  final VoidCallback onReport;
  final String Function(DateTime) formatDate;
  final String Function(String) statusLabel;

  const MyProgramCard({
    required this.entry,
    required this.report,
    this.harvestReturn,
    this.resolution,
    this.assistOption,
    this.assistRequest,
    this.redistStatus,
    this.onRequestRedistribution,
    this.onAssist,
    this.onCancelAssist,
    required this.onReport,
    required this.formatDate,
    required this.statusLabel,
  });

  String _qty(double v) => formatQuantityGrouped(v);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accent = entry.isSalesProgram
        ? AppConstants.successGreen
        : AppConstants.programPurple;
    final hasPhoto =
        entry.programImageUrl != null && entry.programImageUrl!.isNotEmpty;
    final fallbackIcon = entry.isSalesProgram
        ? Icons.storefront_rounded
        : Icons.volunteer_activism_rounded;

    // Every enrolled program opens Program Details.
    return GestureDetector(
      onTap: () =>
          context.push(AppRoutes.programDetails, extra: {'entry': entry}),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: AppConstants.outline.withValues(alpha: 0.10),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF455A64).withValues(alpha: 0.06),
              blurRadius: 10,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Photo header ──────────────────────────────────────────
            SizedBox(
              height: 110,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  hasPhoto
                      ? Image.network(
                          entry.programImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _headerFallback(
                            accent,
                            fallbackIcon,
                          ),
                        )
                      : _headerFallback(accent, fallbackIcon),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _Badge(
                      label: statusLabel(entry.enrollmentStatus),
                      color: AppConstants.successGreen,
                      solid: true,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.programName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: AppConstants.outline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Badge(
                        label: entry.isSalesProgram
                            ? l10n.farmerProgSalesProgram
                            : l10n.farmerProgDistributionProgram,
                        color: accent,
                      ),
                      if (entry.roundNo > 1)
                        _Badge(
                          label: entry.roundNo == 2
                              ? l10n.farmerProgRoundSecond
                              : l10n.farmerProgRound(entry.roundNo),
                          color: AppConstants.buyerBlue,
                        ),
                      Text(
                        l10n.farmerProgEnrolledOn(formatDate(entry.enrolledAt)),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppConstants.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (entry.programDescription != null &&
                      entry.programDescription!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      entry.programDescription!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.4,
                        color: AppConstants.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Divider(
                    height: 1,
                    color: AppConstants.outline.withValues(alpha: 0.12),
                  ),
                  const SizedBox(height: 14),
                  if (entry.isSalesProgram)
                    Text(
                      l10n.farmerProgSalesHint,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppConstants.onSurfaceVariant,
                      ),
                    )
                  else
                    ..._distributionBody(context, l10n),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerFallback(Color accent, IconData icon) => Container(
    color: accent.withValues(alpha: 0.12),
    alignment: Alignment.center,
    child: Icon(icon, size: 38, color: accent.withValues(alpha: 0.7)),
  );

  // Enrolled → Received → Outcome, the same three steps the cooperative
  // follows. Colours: green = done, red = recorded as failed, grey = waiting.
  List<Widget> _distributionBody(BuildContext context, AppLocalizations l10n) {
    final received = entry.isDistributed;
    final r = report;
    // A finalized report is the outcome. An outcome recorded BEFORE the
    // evidence workflow (no report) still shows as it was.
    final legacyDone =
        r == null && (entry.isOutcomeThriving || entry.isOutcomeFailed);
    final outcomeDone = (r?.isFinalized ?? false) || legacyDone;
    final failedFinal = r != null
        ? r.finalOutcome == 'failed'
        : entry.isOutcomeFailed;
    final outcomeColor = outcomeDone
        ? (failedFinal ? AppConstants.errorRed : AppConstants.successGreen)
        : (r?.isReturned ?? false)
        ? AppConstants.errorRed
        : AppConstants.amber;
    final outcomeText = r != null
        ? (r.isFinalized
              ? (r.finalOutcome == 'failed'
                    ? l10n.outcStatusFailed
                    : l10n.outcStatusSuccessful)
              : r.isReturned
              ? l10n.outcStatusReturned
              : l10n.outcStatusPending)
        : entry.isOutcomeThriving
        ? l10n.farmerProgOutcomeThriving
        : entry.isOutcomeFailed
        ? l10n.farmerProgOutcomeFailed
        : l10n.farmerProgOutcomePending;
    // Only a Harvest Return reports an outcome. A Free Distribution is complete once received.
    final canReport =
        received &&
        entry.isHarvestReturn &&
        r == null &&
        !legacyDone &&
        entry.enrollmentStatus == 'active';

    final what = received
        ? '${_qty(entry.quantityGiven ?? 0)}'
              '${entry.itemUnit != null ? ' ${entry.itemUnit}' : ''}'
              '${entry.itemName != null ? ' ${entry.itemName}' : ''}'
        : '';

    return [
      Row(
        children: [
          _Step(
            label: l10n.farmerProgStageEnrolled,
            color: AppConstants.successGreen,
            done: true,
          ),
          _StepLine(active: received),
          _Step(
            label: l10n.farmerProgStageReceived,
            color: AppConstants.successGreen,
            done: received,
          ),
          if (entry.isHarvestReturn) ...[
            _StepLine(active: outcomeDone),
            _Step(
              label: l10n.farmerProgStageOutcome,
              color: outcomeColor,
              done: outcomeDone,
            ),
          ],
        ],
      ),
      const SizedBox(height: 12),
      if (!received)
        Text(
          l10n.farmerProgAwaiting,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: AppConstants.onSurfaceVariant,
          ),
        )
      else ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // The distributed item's photo from Inventory Management (reused,
            // not a separate upload).
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: (entry.itemImageUrl != null &&
                      entry.itemImageUrl!.isNotEmpty)
                  ? Image.network(
                      entry.itemImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.inventory_2_outlined,
                        size: 18,
                        color: AppConstants.primaryGreen,
                      ),
                    )
                  : const Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: AppConstants.primaryGreen,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.farmerProgReceivedLine(
                  what,
                  formatDate(entry.distributedAt!),
                ),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppConstants.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // A Free Distribution: the item is the Farmer's. An outcome recorded earlier stays as history.
        if (!entry.isHarvestReturn && !outcomeDone)
          Text(
            l10n.farmerProgFreeOwned,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppConstants.successGreen,
            ),
          ),
        // Waiting to report: how long ago the item was received. Neutral, and with no
        // deadline implied: the cooperative has not set an official reporting date.
        if (entry.isHarvestReturn || outcomeDone)
          Text(
            canReport
                ? l10n.farmerProgReportPending(daysSinceReceived(entry.distributedAt!))
                : outcomeText,
            key: canReport ? const Key('reportPendingLine') : null,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: outcomeDone || r != null
                  ? outcomeColor
                  : AppConstants.onSurfaceVariant,
            ),
          ),
        if (entry.isHarvestReturn && r != null && r.isPending) ...[
          const SizedBox(height: 6),
          Text(
            l10n.outcPendingLine(formatDate(r.submittedAt)),
            style: GoogleFonts.inter(
              fontSize: 11,
              height: 1.4,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _check(l10n.outcCheckEvidence, r.reviewDone),
              _check(l10n.outcCheckField, r.verificationDone),
            ],
          ),
        ],
        if (entry.isHarvestReturn && r != null && r.isReturned) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppConstants.errorRed.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Text(
              (r.returnNote ?? '').trim().isEmpty
                  ? l10n.outcReturnedNoNote
                  : r.returnNote!,
              style: GoogleFonts.inter(fontSize: 12, height: 1.4),
            ),
          ),
        ],
        if ((entry.isHarvestReturn && r != null && r.isReturned) || canReport) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onReport,
              icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
              label: Text(
                r != null && r.isReturned
                    ? l10n.outcSubmitNewReport
                    : l10n.outcReportAction,
              ),
            ),
          ),
        ],
      ],
      if (harvestReturn != null) ...[
        const SizedBox(height: 10),
        _returnStatus(l10n, harvestReturn!),
      ],
      if (failedFinal && outcomeDone && resolution != null) ...[
        const SizedBox(height: 10),
        _resolutionStatus(l10n, resolution!),
      ],
      if (failedFinal && outcomeDone) ..._assistanceBlock(l10n),
      if (entry.isHarvestReturn) ...[
        const SizedBox(height: 12),
        _returnBox(l10n),
      ],
    ];
  }

  Widget _check(String label, bool done) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
        size: 15,
        color: done ? AppConstants.successGreen : AppConstants.outline,
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          color: done ? AppConstants.onSurface : AppConstants.onSurfaceVariant,
        ),
      ),
    ],
  );

  // Assistance after a failed outcome: the latest request's status, and a button
  // to ask when the database says this outcome may. Not a loan.
  List<Widget> _assistanceBlock(AppLocalizations l10n) {
    final req = assistRequest;
    final opt = assistOption;
    final widgets = <Widget>[];
    if (req != null) {
      final color = req.isApproved
          ? AppConstants.successGreen
          : req.isRejected
          ? AppConstants.errorRed
          : req.isPending
          ? AppConstants.warningAmber
          : AppConstants.onSurfaceVariant;
      final status = switch (req.status) {
        'approved' => l10n.assistStatusApproved,
        'rejected' => l10n.assistStatusRejected,
        'cancelled' => l10n.assistStatusCancelled,
        _ => l10n.assistStatusPending,
      };
      widgets.add(const SizedBox(height: 10));
      widgets.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l10n.assistStatusLine(req.requestNumber)} · $status',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: color),
              ),
              if (req.assistanceReference != null)
                Text(
                  l10n.assistFarmerRef(req.assistanceReference!),
                  style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant),
                ),
              if (req.isRejected && (req.reviewNote ?? '').isNotEmpty)
                Text(req.reviewNote!, style: GoogleFonts.inter(fontSize: 11, height: 1.4)),
              if (req.isPending && onCancelAssist != null)
                TextButton(
                  onPressed: onCancelAssist,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(l10n.assistCancel),
                ),
            ],
          ),
        ),
      );
    }
    if (opt != null && opt.canRequest && onAssist != null) {
      widgets.add(const SizedBox(height: 10));
      widgets.add(
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onAssist,
            icon: const Icon(Icons.volunteer_activism_rounded, size: 18),
            label: Text(l10n.assistRequestAction),
          ),
        ),
      );
    }
    return widgets;
  }

  // Where the Farmer's harvest return stands (received so far, no staff names).
  Widget _returnStatus(AppLocalizations l10n, ProgramReturnSummary r) {
    final done = r.status == 'received';
    final closed = r.status == 'closed_short';
    final color = done
        ? AppConstants.successGreen
        : closed
        ? AppConstants.onSurfaceVariant
        : AppConstants.buyerBlue;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.agriculture_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.retFarmerLine(
                formatReturnQuantity(r.receivedQuantity),
                formatReturnQuantity(r.dueQuantity),
                r.unit,
                r.cropName,
              ),
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }

  // The status of a Failed outcome. Only the status: never who decided or why. A referral for loan assessment
  // also explains what it is not (a loan) and offers the existing loan request. "Eligible for Reassessment"
  // tells the Farmer they may ask for another distribution, without joining again.
  Widget _resolutionStatus(AppLocalizations l10n, String resolution) {
    final text = switch (resolution) {
      FailedResolution.closedNoFurtherObligation => l10n.resFarmerClosed,
      FailedResolution.eligibleForReassessment => l10n.resFarmerReassess,
      FailedResolution.referredForLoanAssessment => l10n.resFarmerReferred,
      _ => l10n.resFarmerPending,
    };
    final referred = resolution == FailedResolution.referredForLoanAssessment;
    final eligible = resolution == FailedResolution.eligibleForReassessment &&
        entry.programStatus != 'completed';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 15, color: AppConstants.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
              ),
            ),
          ],
        ),
        if (referred) ...[
          const SizedBox(height: 6),
          Text(
            l10n.resFarmerReferredNote,
            style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: AppConstants.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (ctx) => OutlinedButton.icon(
              key: const Key('requestLoanFromReferral'),
              onPressed: () => ctx.push(AppRoutes.requestLoan),
              icon: const Icon(Icons.request_quote_outlined, size: 18),
              label: Text(l10n.resFarmerRequestLoan),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            ),
          ),
        ],
        if (eligible) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppConstants.successGreen.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: AppConstants.successGreen.withValues(alpha: 0.30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.farmerRedistEligibleTitle,
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                if (redistStatus == 'pending')
                  Text(l10n.farmerRedistPending,
                      style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: AppConstants.onSurfaceVariant))
                else if (redistStatus == 'approved')
                  Text(l10n.farmerRedistApproved,
                      style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: AppConstants.onSurfaceVariant))
                else ...[
                  Text(l10n.farmerRedistEligibleBody,
                      style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: AppConstants.onSurfaceVariant)),
                  if (onRequestRedistribution != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        key: const Key('requestRedistributionButton'),
                        onPressed: onRequestRedistribution,
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: Text(l10n.farmerRedistRequestButton),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _returnBox(AppLocalizations l10n) {
    // History only: a program that was settled in pesos under the old
    // revenue-share model keeps showing what was recorded.
    if (entry.isSettled && entry.amountReturned != null) {
      return Text(
        l10n.farmerProgReturnedMoney(
          entry.amountReturned!.toStringAsFixed(2),
          formatDate(entry.settledAt!),
        ),
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppConstants.successGreen,
        ),
      );
    }
    final qty = entry.returnQuantity;
    final what = qty == null
        ? null
        : '${_qty(qty)}'
              '${entry.returnUnitShown != null ? ' ${entry.returnUnitShown}' : ''}'
              '${entry.returnName != null ? ' ${entry.returnName}' : ''}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppConstants.warningAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: AppConstants.warningAmber.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (what != null)
            Text(
              l10n.farmerProgHarvestReturn(what.trim()),
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppConstants.onSurface,
              ),
            ),
          if (what != null) const SizedBox(height: 3),
          Text(
            l10n.farmerProgHarvestReturnNote,
            style: GoogleFonts.inter(
              fontSize: 11,
              height: 1.4,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final bool solid;
  const _Badge({required this.label, required this.color, this.solid = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: solid ? Colors.white : color,
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String label;
  final Color color;
  final bool done;
  const _Step({required this.label, required this.color, required this.done});

  @override
  Widget build(BuildContext context) {
    final c = done ? color : AppConstants.outline.withValues(alpha: 0.4);
    return Column(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: done ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: c, width: 2),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 4),
        // A 10-point caption: it follows the phone's text size, but only up to 1.3x, so
        // three of them still fit side by side on a small screen at the largest sizes.
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: done ? FontWeight.w700 : FontWeight.w500,
              color: done ? AppConstants.onSurface : AppConstants.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool active;
  const _StepLine({required this.active});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        // Lines up with the middle of the 22px circle, above the label.
        padding: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
        child: Container(
          height: 2,
          color: active
              ? AppConstants.successGreen
              : AppConstants.outline.withValues(alpha: 0.25),
        ),
      ),
    );
  }
}
