import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/repositories/market_linking_repository.dart';
import '../../../data/services/table_change_watcher.dart';

import '../../../data/services/connectivity_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/shared_widgets.dart';
import '../../../core/utils/db_error_utils.dart';

import '../../widgets/cached_data_notice.dart';
import '../../widgets/market_linking_sale_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/quantity_utils.dart';

/// Farmer's own DA-AMAD Market Linking screen. Gated on Enrollment (see
/// DaAmadEnrollmentModel in market_linking_repository.dart) — a farmer
/// only ever sees the real Market Linking content (their harvest
/// submissions) once approved. Everyone else sees whichever state
/// applies: no Ginger crop yet, a form to enroll, a pending-review state,
/// or a rejected state with a way to resubmit.
///
/// Once approved: the Farmer sees their requests in two tabs (In Progress and
/// Completed), the buyer the Manager/Officer saved for each request (read-only),
/// and every sale recorded for them.
class MyMarketLinkingScreen extends StatefulWidget {
  const MyMarketLinkingScreen({super.key});

  @override
  State<MyMarketLinkingScreen> createState() => _MyMarketLinkingScreenState();
}

class _MyMarketLinkingScreenState extends State<MyMarketLinkingScreen>
    with SingleTickerProviderStateMixin {
  final _repo = MarketLinkingRepository();
  late final TabController _tabs = TabController(length: 2, vsync: this);

  // Hears about a change the Manager/Officer saves (a buyer, a sale, a
  // cancellation review) and reloads quietly, so the Farmer never has to
  // resubmit or even pull to refresh. Realtime is a convenience: pull-to-refresh
  // and reopening the screen always work too.
  TableChangeWatcher? _watcher;

  bool get _isApproved => _enrollment?.status == DaAmadEnrollmentStatus.approved;

  DaAmadEnrollmentModel? _enrollment;
  bool _hasGinger = false;
  bool _hasPendingGingerRequest = false;
  List<MarketLinkingModel> _entries = [];
  bool _isLoadingGate = true;
  bool _isLoadingEntries = false;
  bool _isSubmittingEnrollment = false;
  bool _isOnline = true;
  // One-time full-screen celebration, gated on the real enrollment status
  // (never hardcoded) and shown at most once per approval event — see
  // HiveService.getDaAmadApprovalSeen()'s doc comment.
  bool _showApprovalCelebration = false;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _loadGate();
    _watcher = TableChangeWatcher(
      tables: const ['market_linking_programs', 'market_linking_sales'],
      onChange: () {
        if (mounted && _isApproved) _loadEntries(quiet: true);
      },
    )..start();
  }

  @override
  void dispose() {
    _watcher?.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadGate() async {
    setState(() => _isLoadingGate = true);
    final results = await Future.wait([
      _repo.fetchMyEnrollment(),
      _repo.fetchHasGingerCrop(),
      _repo.fetchHasPendingGingerRequest(),
    ]);
    if (!mounted) return;
    final enrollment = results[0] as DaAmadEnrollmentModel?;
    // Based on the actual enrollment status fetched above, never
    // hardcoded — a farmer only ever sees this once per approval event
    // (HiveService.getDaAmadApprovalSeen() is keyed by this exact
    // enrollment row's id).
    // Shown once, when the enrollment is newly approved: not if the server says
    // it was already acknowledged (any device, any login) nor if this device
    // remembers it (covers a Farmer who is offline when they tap Continue).
    final showCelebration =
        enrollment != null &&
        enrollment.status == DaAmadEnrollmentStatus.approved &&
        enrollment.acknowledgedAt == null &&
        !HiveService.getDaAmadApprovalSeen(enrollment.id, userId: _userId);
    setState(() {
      _enrollment = enrollment;
      _hasGinger = results[1] as bool;
      _hasPendingGingerRequest = results[2] as bool;
      _isLoadingGate = false;
      _showApprovalCelebration = showCelebration;
    });
    if (enrollment?.status == DaAmadEnrollmentStatus.approved) {
      _loadEntries();
    }
  }

  Future<void> _dismissApprovalCelebration() async {
    final enrollment = _enrollment;
    if (enrollment != null) {
      // Remember it on this device first (works offline), then on the server so
      // it stays acknowledged everywhere.
      await HiveService.setDaAmadApprovalSeen(enrollment.id, userId: _userId);
      await _repo.acknowledgeEnrollment(enrollment.id);
    }
    if (mounted) setState(() => _showApprovalCelebration = false);
  }

  Future<void> _loadEntries({bool quiet = false}) async {
    if (!quiet) setState(() => _isLoadingEntries = true);
    // fetchAll() is RLS-scoped to the caller's own rows for a farmer
    // account — no farmerId filter needed or possible from this side.
    final entries = await _repo.fetchAll();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _isLoadingEntries = false;
    });
  }

  Future<void> _submitEnrollment() async {
    setState(() => _isSubmittingEnrollment = true);
    try {
      await _repo.submitEnrollment();
      if (mounted) await _loadGate();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not submit enrollment. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingEnrollment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    if (_showApprovalCelebration) {
      return _ApprovalCelebrationScreen(
        onContinue: _dismissApprovalCelebration,
        cs: cs,
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              TopBarSpacer(height: 64),
              CachedDataNotice(
                screen: 'market_linking_all',
                isOnline: _isOnline,
                offlineMessage: AppLocalizations.of(context).offlineEnrollment,
              ),
              Expanded(
                child: _isLoadingGate
                    ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                    : _isApproved
                    // Approved: the tabs hold their own scrolling lists, each
                    // with its own pull-to-refresh.
                    ? _buildGatedBody(cs, sagana)
                    : RefreshIndicator(
                        color: AppConstants.primaryGreen,
                        onRefresh: _loadGate,
                        child: _buildGatedBody(cs, sagana),
                      ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: 'Market Linking',
              // Moved out of the body (was a full-width banner dominating
              // the landing page) and into the header itself — visible,
              // but no longer competing with the actual page content.
              titleTrailing:
                  _enrollment?.status == DaAmadEnrollmentStatus.approved
                  ? const _EnrolledPill()
                  : null,
              onBack: () => context.pop(),
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

  // The Farmer asks to cancel an active request. Nothing is released until the
  // Manager/Officer approves; the request shows "Cancellation Requested" meanwhile.
  Future<void> _requestCancellation(MarketLinkingModel entry) async {
    final l10n = AppLocalizations.of(context);
    if (!_isOnline) {
      AppToast.show(context, l10n.mlkCancelOffline, isError: true);
      return;
    }
    final sent = await showManagementModal<bool>(
      context: context,
      builder: (_) => _CancellationRequestSheet(entry: entry, repo: _repo),
    );
    if (sent == true && mounted) {
      AppToast.show(context, l10n.mlkCancelSent);
      _loadEntries();
    }
  }

  Widget _buildGatedBody(ColorScheme cs, SaganaColors sagana) {
    final enrollment = _enrollment;

    if (enrollment == null ||
        enrollment.status == DaAmadEnrollmentStatus.rejected) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          if (enrollment?.status == DaAmadEnrollmentStatus.rejected)
            _RejectedBanner(
              reason: enrollment!.adminNotes,
              cs: cs,
              sagana: sagana,
            ),
          if (!_hasGinger && _hasPendingGingerRequest)
            // Distinct from "no Ginger at all" — the farmer already
            // requested it, it's just still awaiting Admin's crop
            // approval (a separate review from Enrollment itself).
            // Telling them to "add Ginger" here would be wrong: they
            // already did.
            _GingerPendingApprovalCard(cs: cs, sagana: sagana)
          else if (!_hasGinger)
            _NoGingerCard(cs: cs, sagana: sagana)
          else
            _EnrollmentIntroCard(
              isResubmit: enrollment?.status == DaAmadEnrollmentStatus.rejected,
              isSubmitting: _isSubmittingEnrollment,
              isOnline: _isOnline,
              onEnroll: _submitEnrollment,
              cs: cs,
              sagana: sagana,
            ),
        ],
      );
    }

    if (enrollment.status == DaAmadEnrollmentStatus.pending) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _PendingEnrollmentCard(
            submittedAt: enrollment.submittedAt,
            cs: cs,
            sagana: sagana,
          ),
        ],
      );
    }

    // Approved.
    if (_isLoadingEntries && _entries.isEmpty) {
      return const Padding(padding: EdgeInsets.all(16), child: SkeletonList());
    }
    if (_entries.isEmpty) {
      return RefreshIndicator(
        color: AppConstants.primaryGreen,
        onRefresh: _loadEntries,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [_ApprovedNextStepCard(cs: cs, sagana: sagana)],
        ),
      );
    }

    final l10n = AppLocalizations.of(context);
    final inProgress = _entries.where((e) => e.isActive).toList();
    final completed = _entries
        .where((e) => e.status == MarketLinkingStatus.completed)
        .toList();
    final cancelled = _entries
        .where((e) => e.status == MarketLinkingStatus.cancelled)
        .toList();

    Widget card(MarketLinkingModel e) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _RequestCard(
        entry: e,
        cs: cs,
        sagana: sagana,
        onRequestCancellation: () => _requestCancellation(e),
      ),
    );

    // Summary card stays put above the tabs; swipe or tap to switch.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: _SummaryCard(entries: _entries),
        ),
        _RequestTabBar(
          controller: _tabs,
          inProgressCount: inProgress.length,
          completedCount: completed.length,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _RequestList(
                onRefresh: _loadEntries,
                emptyTitle: l10n.mlkEmptyInProgress,
                emptyBody: l10n.mlkEmptyInProgressBody,
                emptyIcon: Icons.hourglass_empty_rounded,
                children: inProgress.map(card).toList(),
              ),
              _RequestList(
                onRefresh: _loadEntries,
                emptyTitle: l10n.mlkEmptyCompleted,
                emptyBody: l10n.mlkEmptyCompletedBody,
                emptyIcon: Icons.check_circle_outline_rounded,
                // Completed first; a cancelled request is kept below, labelled,
                // so nothing disappears from the history.
                children: [
                  ...completed.map(card),
                  if (cancelled.isNotEmpty) ...[
                    _SectionLabel(l10n.mlkStatusCancelled),
                    ...cancelled.map(card),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Gate states — No Ginger / Enrollment Form / Pending / Rejected
// ─────────────────────────────────────────────────────────────────────────────

class _NoGingerCard extends StatelessWidget {
  final ColorScheme cs;
  final SaganaColors sagana;
  const _NoGingerCard({required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: AppConstants.warningAmber.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppConstants.warningAmber,
            size: 28,
          ),
          const SizedBox(height: 12),
          Text(
            'A Ginger Crop Is Required',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'DA-AMAD Market Linking is exclusive to Ginger. Add Ginger to your Crop Roster before you can enroll.',
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.pushRoute(AppRoutes.cropListing),
              child: const Text('Go to Crop Roster'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Distinct from _NoGingerCard — the farmer already requested Ginger, it's
/// just still awaiting Admin's crop approval (a separate review from
/// Market Linking Enrollment itself, which can't start until the crop
/// request clears first).
class _GingerPendingApprovalCard extends StatelessWidget {
  final ColorScheme cs;
  final SaganaColors sagana;
  const _GingerPendingApprovalCard({required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
        children: [
          const Icon(
            Icons.hourglass_top_rounded,
            color: AppConstants.warningAmber,
            size: 28,
          ),
          const SizedBox(height: 12),
          Text(
            'Ginger Crop Awaiting Approval',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'ve already requested Ginger for your Crop Roster — SP3 is still reviewing it. '
            'You\'ll be able to enroll in Market Linking once that\'s approved.',
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.pushRoute(AppRoutes.cropListing),
              child: const Text('View Crop Roster'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnrollmentIntroCard extends StatelessWidget {
  final bool isResubmit;
  final bool isSubmitting;
  final bool isOnline;
  final VoidCallback onEnroll;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _EnrollmentIntroCard({
    required this.isResubmit,
    required this.isSubmitting,
    required this.isOnline,
    required this.onEnroll,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
        children: [
          const Text('🌿', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 12),
          Text(
            'DA-AMAD Ginger Market Linking',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'SP3 connects enrolled Ginger growers directly with DA-AMAD — an institutional buyer offering export '
            'pricing, outside the open marketplace. Enroll once to participate; SP3 will review your request.',
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (isOnline && !isSubmitting) ? onEnroll : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      isResubmit ? 'Submit New Enrollment' : 'Enroll Now',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RejectedBanner extends StatelessWidget {
  final String? reason;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _RejectedBanner({
    required this.reason,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: AppConstants.errorRed.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.cancel_outlined,
            size: 18,
            color: AppConstants.errorRed,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Previous Enrollment Was Declined',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.errorRed,
                  ),
                ),
                if (reason != null && reason!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    reason!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'You can submit a new enrollment below.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
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

class _PendingEnrollmentCard extends StatelessWidget {
  final DateTime submittedAt;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _PendingEnrollmentCard({
    required this.submittedAt,
    required this.cs,
    required this.sagana,
  });

  static const _stages = ['Submitted', 'Under Review', 'Decision'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppConstants.warningAmber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  'PENDING',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: AppConstants.warningAmber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Enrollment Under Review',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'SP3 is reviewing your DA-AMAD Ginger Market Linking enrollment. You\'ll be notified once a decision is made.',
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Row(
            children: List.generate(_stages.length * 2 - 1, (i) {
              if (i.isOdd) {
                return Expanded(
                  child: Container(
                    height: 2,
                    color: AppConstants.outline.withValues(alpha: 0.15),
                  ),
                );
              }
              final reached = (i ~/ 2) == 0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: reached
                          ? AppConstants.warningAmber
                          : cs.outline.withValues(alpha: 0.25),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _stages[i ~/ 2],
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: reached
                          ? cs.onSurface
                          : cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Approved state
// ─────────────────────────────────────────────────────────────────────────────

// Moved out of the body and into the top bar (FarmerTopBar's
// titleTrailing) in a later engagement — this used to be a full-width
// bordered banner that dominated the landing page on every visit, and the
// approval moment itself is now separately communicated once via
// _ApprovalCelebrationScreen. Rendered directly in the header now, so this
// pill no longer needs cs/sagana passed in — it's a small, fixed style,
// consistent regardless of theme the same way the header itself is.
class _EnrolledPill extends StatelessWidget {
  const _EnrolledPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppConstants.successGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 12,
            color: AppConstants.successGreen,
          ),
          const SizedBox(width: 5),
          Text(
            'Enrolled',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: AppConstants.successGreen,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown once approved but before the farmer has submitted any Ginger
/// harvest yet — tells them exactly what to do next instead of a bare
/// "nothing here" message.
class _ApprovedNextStepCard extends StatelessWidget {
  final ColorScheme cs;
  final SaganaColors sagana;
  const _ApprovedNextStepCard({required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
        children: [
          const Icon(
            Icons.eco_rounded,
            color: AppConstants.primaryGreen,
            size: 28,
          ),
          const SizedBox(height: 12),
          Text(
            'Next Step: Submit a Ginger Harvest',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'re enrolled — you have nothing submitted for sale yet. Go to Manage Inventory, open a Ginger '
            'batch, and tap "Submit to Sell" to start the process.',
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.pushRoute(AppRoutes.manageInventory),
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: const Text('Go to Manage Inventory'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Request list ────────────────────────────────────────────────────────────
// Simple on purpose: how much you have received, what is still being sold, and
// what is finished. Each request says in plain words where it stands, how much
// has sold, and what is left — no stages, seasons or program jargon.

class _SummaryCard extends StatelessWidget {
  final List<MarketLinkingModel> entries;
  const _SummaryCard({required this.entries});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Every figure is worked out from the Farmer's real requests and sales.
    final s = MarketLinkingSummary.of(entries);
    final inProgress = s.inProgress;
    final completed = s.completed;


    Widget tile(IconData icon, String value, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.9)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // A 2 x 2 grid: equal tiles, equal gaps.
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppConstants.primaryGreen, AppConstants.successGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        children: [
          Row(
            children: [
              tile(Icons.hourglass_top_rounded, '$inProgress', l10n.mlkStatInProgress),
              const SizedBox(width: 10),
              tile(Icons.scale_rounded, s.soldText, l10n.mlkStatKgSold),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              tile(Icons.inventory_2_outlined, s.remainingText, l10n.mlkStatKgRemaining),
              const SizedBox(width: 10),
              tile(Icons.check_circle_outline_rounded, '$completed', l10n.statCompleted),
            ],
          ),
        ],
      ),
    );
  }
}

/// In Progress | Completed. Tap a tab, or swipe the list left and right.
class _RequestTabBar extends StatelessWidget {
  final TabController controller;
  final int inProgressCount;
  final int completedCount;
  const _RequestTabBar({
    required this.controller,
    required this.inProgressCount,
    required this.completedCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: TabBar(
        controller: controller,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: AppConstants.primaryGreen,
          borderRadius: BorderRadius.circular(AppConstants.radiusSm + 2),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: cs.onSurfaceVariant,
        labelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
        tabs: [
          Tab(height: 38, text: '${l10n.mlkInProgress} · $inProgressCount'),
          Tab(height: 38, text: '${l10n.statCompleted} · $completedCount'),
        ],
      ),
    );
  }
}

/// One tab's list: its own pull-to-refresh, and a friendly empty state.
class _RequestList extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final String emptyTitle;
  final String emptyBody;
  final IconData emptyIcon;
  final List<Widget> children;
  const _RequestList({
    required this.onRefresh,
    required this.emptyTitle,
    required this.emptyBody,
    required this.emptyIcon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      color: AppConstants.primaryGreen,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: children.isNotEmpty
            ? children
            : [
                const SizedBox(height: 40),
                Icon(emptyIcon, size: 44, color: cs.outline.withValues(alpha: 0.6)),
                const SizedBox(height: 14),
                Text(
                  emptyTitle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  emptyBody,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.4,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
      ),
    );
  }
}

/// Buyer Details on the Farmer's request: read-only, the same details the
/// Manager/Officer saved. Until a buyer is found it says so.
class _FarmerBuyerSection extends StatelessWidget {
  final MarketLinkingModel entry;
  const _FarmerBuyerSection({required this.entry});

  @override
  Widget build(BuildContext context) {
    if (entry.hasBuyer) return MarketLinkingBuyerBlock(entry: entry);
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.warningAmber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppConstants.warningAmber.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top_rounded, size: 16, color: AppConstants.warningAmber),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.mlkAwaitingBuyer,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.mlkAwaitingBuyerBody,
                  style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final MarketLinkingModel entry;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onRequestCancellation;
  const _RequestCard({
    required this.entry,
    required this.cs,
    required this.sagana,
    required this.onRequestCancellation,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isCancelled = entry.status == MarketLinkingStatus.cancelled;
    // The Buyer Details section says whether a buyer is known; the hint adds
    // what happens next once one is.
    final hint = entry.status == MarketLinkingStatus.buyerFound
        ? l10n.mlkHintBuyerFound
        : null;
    final reason = (entry.notes ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
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
                // The Farmer's own photo of this crop (what the Manager sees too).
                MarketLinkingEntryPhoto(entry: entry, size: 48, useInitials: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.cropName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      if (entry.batchNumber != null)
                        Text(
                          formatBatchNumber(entry.batchNumber),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: MarketLinkingStatusChip(entry: entry)),
              ],
            ),

            if (isCancelled) ...[
              const SizedBox(height: 12),
              Text(
                reason.isNotEmpty
                    ? l10n.mlkCancelledWithReason(reason)
                    : l10n.mlkCancelledBackInStock,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.4,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ] else if (entry.volumeKg != null) ...[
              const SizedBox(height: 16),
              MarketLinkingSaleProgress(entry: entry),
            ],

            // Buyer Details (read-only): shown as soon as the Manager/Officer
            // saves them and kept through Completed; until then, "Awaiting".
            if (!isCancelled) ...[
              const SizedBox(height: 14),
              _FarmerBuyerSection(entry: entry),
            ],

            if (hint != null) ...[
              const SizedBox(height: 12),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      hint,
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

            // Each sale recorded for the Farmer, with what they received.
            if (entry.sales.isNotEmpty) ...[
              const SizedBox(height: 14),
              MarketLinkingSalesList(entry: entry),
            ],

            // Cancellation: only the Farmer starts it, and the cooperative reviews it.
            if (entry.isCancellationRequested) ...[
              const SizedBox(height: 14),
              _CancellationNote(
                icon: Icons.pending_actions_rounded,
                color: AppConstants.errorRed,
                text: l10n.mlkCancelUnderReview(entry.cancellationReason ?? ''),
              ),
            ] else if (entry.wasCancellationDeclined) ...[
              const SizedBox(height: 14),
              _CancellationNote(
                icon: Icons.info_outline_rounded,
                color: AppConstants.warningAmber,
                text: l10n.mlkCancelDeclinedNote(entry.cancellationReviewNotes ?? ''),
              ),
            ],
            if (entry.canRequestCancellation) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onRequestCancellation,
                icon: const Icon(Icons.close_rounded, size: 16),
                label: Text(l10n.mlkRequestCancellation),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.error,
                  side: BorderSide(color: cs.error.withValues(alpha: 0.6)),
                  minimumSize: const Size.fromHeight(44),
                  textStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CancellationNote extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _CancellationNote({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Request Cancellation ─────────────────────────────────────────────────────
// A reason is required. Sending it releases nothing: the Manager/Officer reviews
// it, and the Farmer is notified when it is approved or declined.
class _CancellationRequestSheet extends StatefulWidget {
  final MarketLinkingModel entry;
  final MarketLinkingRepository repo;
  const _CancellationRequestSheet({required this.entry, required this.repo});

  @override
  State<_CancellationRequestSheet> createState() => _CancellationRequestSheetState();
}

class _CancellationRequestSheetState extends State<_CancellationRequestSheet> {
  final _reasonCtrl = TextEditingController();
  String? _error;
  bool _isSending = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    if (_reasonCtrl.text.trim().isEmpty) {
      setState(() => _error = l10n.mlkCancelReasonRequired);
      return;
    }
    setState(() => _isSending = true);
    try {
      await widget.repo.requestCancellation(
        programId: widget.entry.id,
        reason: _reasonCtrl.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      AppToast.show(
        context,
        readableDatabaseMessage(e) ?? l10n.mlkCancelFailed,
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return ManagementModalShell(
      title: l10n.mlkCancelDialogTitle,
      subtitle: widget.entry.cropName,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.mlkCancelDialogBody,
            style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.mlkCancelReasonLabel,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _reasonCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              hintText: l10n.mlkCancelReasonHint,
              errorText: _error,
            ),
          ),
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: l10n.mlkCancelSend,
        isDestructive: true,
        isLoading: _isSending,
        onPrimary: _send,
      ),
    );
  }
}

// ─── Approval Celebration ──────────────────────────────────────────────────
// One-time, full-screen — no back button or top bar, deliberately, so it
// reads as a distinct moment rather than another page of the normal flow.
// Mirrors the established "success screen" convention already used by
// listing_success_screen.dart (icon-in-a-colored-circle, headline, subtext,
// one primary button) rather than inventing a new visual language.

class _ApprovalCelebrationScreen extends StatelessWidget {
  final VoidCallback onContinue;
  final ColorScheme cs;
  const _ApprovalCelebrationScreen({
    required this.onContinue,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: AppConstants.primaryGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.celebration_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context).marketLinkCelebrationTitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context).marketLinkCelebrationBody,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusLg,
                      ),
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context).marketLinkCelebrationContinue,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
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
