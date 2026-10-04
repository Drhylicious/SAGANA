import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/repositories/market_linking_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';

/// Farmer's own DA-AMAD Market Linking screen. Gated on Enrollment (see
/// DaAmadEnrollmentModel in market_linking_repository.dart) — a farmer
/// only ever sees the real Market Linking content (their harvest
/// submissions) once approved. Everyone else sees whichever state
/// applies: no Ginger crop yet, a form to enroll, a pending-review state,
/// or a rejected state with a way to resubmit.
///
/// Once approved: buyer name/contact and any inventory-batch tie are
/// still deliberately never shown here — that's admin-side bookkeeping.
class MyMarketLinkingScreen extends StatefulWidget {
  const MyMarketLinkingScreen({super.key});

  @override
  State<MyMarketLinkingScreen> createState() => _MyMarketLinkingScreenState();
}

class _MyMarketLinkingScreenState extends State<MyMarketLinkingScreen> {
  final _repo = MarketLinkingRepository();

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
    final showCelebration =
        enrollment != null &&
        enrollment.status == DaAmadEnrollmentStatus.approved &&
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
      await HiveService.setDaAmadApprovalSeen(enrollment.id, userId: _userId);
    }
    if (mounted) setState(() => _showApprovalCelebration = false);
  }

  Future<void> _loadEntries() async {
    setState(() => _isLoadingEntries = true);
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
              const SizedBox(height: 64),
              if (!_isOnline)
                const OfflineBanner(
                  message:
                      "You're offline — your enrollment status may not be up to date.",
                ),
              Expanded(
                child: _isLoadingGate
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppConstants.primaryGreen,
                        ),
                      )
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
    if (_isLoadingEntries) {
      return const Center(
        child: CircularProgressIndicator(color: AppConstants.primaryGreen),
      );
    }
    if (_entries.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [_ApprovedNextStepCard(cs: cs, sagana: sagana)],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) {
        final entry = _entries[i];
        return _EnrollmentCard(entry: entry, cs: cs, sagana: sagana);
      },
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

class _EnrollmentCard extends StatelessWidget {
  final MarketLinkingModel entry;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _EnrollmentCard({
    required this.entry,
    required this.cs,
    required this.sagana,
  });

  static const _stages = ['Submitted', 'Buyer Found', 'Completed'];

  int get _stageIndex {
    switch (entry.status) {
      case MarketLinkingStatus.buyerFound:
        return 1;
      case MarketLinkingStatus.completed:
        return 2;
      default:
        return 0;
    }
  }

  Color get _statusColor {
    switch (entry.status) {
      case MarketLinkingStatus.requested:
        return AppConstants.outline;
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

  @override
  Widget build(BuildContext context) {
    final isCancelled = entry.status == MarketLinkingStatus.cancelled;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${entry.cropName} Program — DA-AMAD',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  entry.status.label.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: _statusColor,
                  ),
                ),
              ),
            ],
          ),
          Text(
            '${entry.seasonYear} Season',
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),

          if (!isCancelled)
            Row(
              children: List.generate(_stages.length * 2 - 1, (i) {
                if (i.isOdd) {
                  final passed = (i ~/ 2) < _stageIndex;
                  return Expanded(
                    child: Container(
                      height: 2,
                      color: passed
                          ? _statusColor.withValues(alpha: 0.4)
                          : cs.outline.withValues(alpha: 0.15),
                    ),
                  );
                }
                final dotIndex = i ~/ 2;
                final reached = dotIndex <= _stageIndex;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: reached
                            ? _statusColor
                            : cs.outline.withValues(alpha: 0.25),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _stages[dotIndex],
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

          const SizedBox(height: 14),
          Row(
            children: [
              if (entry.volumeKg != null) ...[
                Icon(Icons.scale_outlined, size: 13, color: cs.outline),
                const SizedBox(width: 4),
                Text(
                  '${entry.volumeKg!.toStringAsFixed(0)} kg committed',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              // Price shown only once there's a real match — never before,
              // since there's nothing real to show pre-match. Buyer name
              // and contact are deliberately never shown to the farmer.
              if (entry.pricePerKg != null &&
                  (entry.status == MarketLinkingStatus.buyerFound ||
                      entry.status == MarketLinkingStatus.completed)) ...[
                const SizedBox(width: 12),
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
              ],
            ],
          ),

          // Buyer's requested quantity — distinct from "kg committed"
          // above (the farmer's own volume at submission) and only
          // meaningful once a buyer has actually been matched.
          if (entry.requestedVolumeKg != null &&
              (entry.status == MarketLinkingStatus.buyerFound ||
                  entry.status == MarketLinkingStatus.completed)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.shopping_bag_outlined, size: 13, color: cs.outline),
                const SizedBox(width: 4),
                Text(
                  'Buyer wants ${entry.requestedVolumeKg!.toStringAsFixed(0)} kg',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],

          if (isCancelled) ...[
            const SizedBox(height: 10),
            Text(
              entry.notes != null && entry.notes!.isNotEmpty
                  ? 'Cancelled: ${entry.notes}'
                  : 'This sale was cancelled.',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
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
                'Congratulations!',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your enrollment in the DA-AMAD Ginger Market Linking program has been approved. '
                'You may now submit your Ginger harvest for sale through Market Linking.',
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
                    'Continue',
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
