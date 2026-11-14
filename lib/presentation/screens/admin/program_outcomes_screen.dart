import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/program_outcome_model.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/request_card.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

/// Every outcome report across the programs, for the Manager and Officers to
/// work through. Pending reports come first; Finalized and Returned are one tap
/// away. Opening a card shows the essentials; "Open" goes to the full review
/// page. Route: /admin/programs/outcomes
class ProgramOutcomesScreen extends StatefulWidget {
  const ProgramOutcomesScreen({super.key});

  @override
  State<ProgramOutcomesScreen> createState() => _ProgramOutcomesScreenState();
}

class _ProgramOutcomesScreenState extends State<ProgramOutcomesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _repo = ProgramRepository();
  bool _loading = true;
  bool _failed = false;
  List<OutcomeReport> _all = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await _repo.fetchOutcomeReports();
      if (!mounted) return;
      setState(() {
        _all = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  String _fmt(DateTime d) {
    final m = [
      AppLocalizations.of(context).enhJan,
      AppLocalizations.of(context).enhFeb,
      AppLocalizations.of(context).enhMar,
      AppLocalizations.of(context).enhApr,
      AppLocalizations.of(context).adminCalMonthMay,
      AppLocalizations.of(context).enhJun,
      AppLocalizations.of(context).enhJul,
      AppLocalizations.of(context).enhAug,
      AppLocalizations.of(context).enhSep,
      AppLocalizations.of(context).enhOct,
      AppLocalizations.of(context).enhNov,
      AppLocalizations.of(context).enhDec,
    ];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  (String, Color) _stage(OutcomeReport r, AppLocalizations l10n) {
    switch (r.stage) {
      case OutcomeStage.awaitingBoth:
        return (l10n.outcStatusPending, AppConstants.amber);
      case OutcomeStage.awaitingVerification:
        return (l10n.outcStageAwaitingVerificationShort, AppConstants.amber);
      case OutcomeStage.awaitingReview:
        return (l10n.outcStageAwaitingReviewShort, AppConstants.amber);
      case OutcomeStage.readyToFinalize:
        return (l10n.outcStageReadyShort, AppConstants.buyerBlue);
      case OutcomeStage.returned:
        return (l10n.outcStatusReturned, AppConstants.errorRed);
      case OutcomeStage.closed:
        return (l10n.outcStageClosed, Theme.of(context).colorScheme.outline);
      case OutcomeStage.finalized:
        final failed = r.finalOutcome == 'failed';
        return (
          failed ? l10n.outcStatusFailed : l10n.outcStatusSuccessful,
          failed ? AppConstants.errorRed : AppConstants.successGreen,
        );
    }
  }

  Widget _card(OutcomeReport r, AppLocalizations l10n) {
    final (label, color) = _stage(r, l10n);
    return RequestCard(
      leading: RequestAvatar(name: r.farmerName, color: color),
      title: r.farmerName,
      subtitle: r.programName,
      summary:
          '${r.isSuccessfulReport ? l10n.outcReportedSuccessful : l10n.outcReportedFailed} · ${_fmt(r.submittedAt)}',
      statusLabel: label,
      statusColor: color,
      details: [
        if (r.itemName != null)
          RequestDetailRow(label: l10n.reqReceived, value: r.itemName!),
        RequestDetailRow(
          label: l10n.outcStepReview,
          value: r.reviewDecision == null
              ? l10n.outcPendingShort
              : (r.isReviewed
                    ? l10n.outcDecisionValidated
                    : l10n.outcDecisionReturned),
        ),
        RequestDetailRow(
          label: l10n.outcStepVerify,
          value: r.isVerified
              ? (r.disputed
                    ? l10n.outcFindingDisputes
                    : l10n.outcFindingConfirms)
              : l10n.outcPendingShort,
        ),
        if (r.isSuccessfulReport && r.quantityHarvested != null)
          RequestDetailRow(
            label: _plain(l10n.outcQtyHarvested),
            value:
                '${r.quantityHarvested!.toStringAsFixed(2)} ${r.quantityUnit ?? ''}'
                    .trim(),
          ),
        if (!r.isSuccessfulReport && r.failureCause != null)
          RequestDetailRow(
            label: _plain(l10n.outcFailureCause),
            value: r.failureCause!,
          ),
        RequestDetailRow(
          label: _plain(l10n.outcEvidence),
          value: l10n.outcPhotoCountShort(r.farmerPhotos.length),
        ),
        // The photos staff took during the field visit are kept apart from the Farmer's own evidence.
        if (r.isVerified)
          RequestDetailRow(
            label: _plain(l10n.outcFieldPhotos),
            value: l10n.outcPhotoCountShort(r.fieldPhotos.length),
          ),
      ],
      actions: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => context
              .push(AppRoutes.programOutcomeDetail, extra: {'report': r})
              .then((_) => _load()),
          child: Text(
            r.isFinalized ? l10n.outcViewAction : l10n.outcOpenReview,
          ),
        ),
      ),
    );
  }

  Widget _tabList(
    List<OutcomeReport> shown,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    return RefreshIndicator(
      onRefresh: _load,
      child: shown.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 80),
                Icon(
                  Icons.fact_check_outlined,
                  size: 44,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    l10n.outcEmpty,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              itemCount: shown.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _card(shown[i], l10n),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final l10n = AppLocalizations.of(context);
    final pending = _all.where((r) => r.isPending).toList();
    final finalized = _all.where((r) => r.isFinalized).toList();
    final returned = _all.where((r) => r.isReturned).toList();
    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            SubPageTopBar(
              title: l10n.outcReviewsTitle,
              onBack: () => context.pop(),
            ),
            TabBar(
              controller: _tabs,
              labelColor: AppConstants.primaryGreen,
              unselectedLabelColor: cs.onSurfaceVariant,
              indicatorColor: AppConstants.primaryGreen,
              tabs: [
                Tab(text: l10n.outcFilterPending(pending.length)),
                Tab(text: l10n.outcFilterFinalized(finalized.length)),
                Tab(text: l10n.outcFilterReturned(returned.length)),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SkeletonList(),
                    )
                  : _failed
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 40,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.outcLoadFailed,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: Text(l10n.programHistoryRetry),
                          ),
                        ],
                      ),
                    )
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _tabList(pending, l10n, cs),
                        _tabList(finalized, l10n, cs),
                        _tabList(returned, l10n, cs),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The form labels carry a required-field star ("Photos (evidence) *"); a detail row is not a form field.
String _plain(String s) => s.replaceAll(RegExp(r'\s*\*$'), '');
