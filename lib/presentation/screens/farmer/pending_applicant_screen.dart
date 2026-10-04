import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_address_model.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/repositories/buyer_address_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PendingApplicantScreen — Shell with 3 tabs (Home, Notifications, Profile)
// Shown to farmers whose user_roles.status = 'pending'
// ─────────────────────────────────────────────────────────────────────────────

class PendingApplicantScreen extends StatefulWidget {
  final int initialTab;
  const PendingApplicantScreen({super.key, this.initialTab = 0});

  @override
  State<PendingApplicantScreen> createState() => _PendingApplicantScreenState();
}

class _PendingApplicantScreenState extends State<PendingApplicantScreen> {
  late int _currentTab;
  final _client = Supabase.instance.client;
  RealtimeChannel? _statusChannel;

  // Applicant profile + lifecycle state
  String _fullName = '';
  String _username = '';
  bool _isOnline = true;
  bool _isLoading = true;
  bool _isBusy = false;

  // 'draft' | 'pending' | 'rejected' | 'active'
  String _status = 'draft';
  bool _pendingAcknowledgement = false;
  String? _rejectionReason;

  // The approval dialog opens once per applicant per app session. Tracked
  // here (not in storage) so a new session can show it again if the
  // acknowledgement is still pending.
  static final Set<String> _approvalDialogShownFor = {};

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadState();
    _subscribeToStatus();
  }

  @override
  void dispose() {
    _statusChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadState() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;
      final info = await _client
          .from('user_information')
          .select('full_name, username')
          .eq('user_id', userId)
          .maybeSingle();
      final role = await _client
          .from('user_roles')
          .select('status, pending_acknowledgement, rejection_reason')
          .eq('user_id', userId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _fullName = info?['full_name'] as String? ?? 'Applicant';
        _username = info?['username'] as String? ?? '';
        _status = role?['status'] as String? ?? 'draft';
        _pendingAcknowledgement =
            role?['pending_acknowledgement'] as bool? ?? false;
        _rejectionReason = role?['rejection_reason'] as String?;
        _isLoading = false;
      });
      await HiveService.saveMemberStatus(_status);
      await HiveService.savePendingAcknowledgement(_pendingAcknowledgement);
      _maybeShowApprovalDialog();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Realtime — reload state whenever the admin changes anything on the row.
  void _subscribeToStatus() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    _statusChannel = _client
        .channel('pending_status_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'user_roles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            if (mounted) _loadState();
          },
        )
        .subscribe();
  }

  Future<void> _submitApplication() async {
    setState(() => _isBusy = true);
    try {
      await AuthService.submitApplication();
      if (!mounted) return;
      _toast(AppLocalizations.of(context).pendingSubmittedToast, ok: true);
      await _loadState();
    } catch (e) {
      if (!mounted) return;
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _acknowledge() async {
    setState(() => _isBusy = true);
    try {
      await AuthService.acknowledgeMembership();
      if (!mounted) return;
      context.go(AppRoutes.farmerDashboard);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Shows the approval dialog once per applicant per session, when the
  /// application is approved and the Continue step is still pending.
  void _maybeShowApprovalDialog() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || !mounted) return;
    final approved = _status == 'active' && _pendingAcknowledgement;
    if (!approved || _approvalDialogShownFor.contains(userId)) return;
    _approvalDialogShownFor.add(userId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showApprovalDialog();
    });
  }

  Future<void> _showApprovalDialog() async {
    final l10n = AppLocalizations.of(context);
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.pendingApprovalDialogTitle,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          l10n.pendingApprovalDialogBody,
          style: GoogleFonts.inter(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.pendingLater),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.pendingContinueButton,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: AppConstants.primaryGreen,
              ),
            ),
          ),
        ],
      ),
    );
    if (proceed == true) await _acknowledge();
  }

  /// Opens the dedicated review screen. The status is reloaded afterwards in
  /// case the applicant's details changed the Home tab's content.
  Future<void> _editDetails() async {
    await context.push(AppRoutes.pendingReview);
    if (mounted) _loadState();
  }

  void _toast(String msg, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: ok ? AppConstants.successGreen : AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onTabTap(int index) {
    setState(() => _currentTab = index);
    // Update URL so back button works correctly
    switch (index) {
      case 0:
        context.go(AppRoutes.pendingHome);
      case 1:
        context.go(AppRoutes.pendingNotifications);
      case 2:
        context.go(AppRoutes.pendingProfile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;

    final screens = [
      _PendingHomeTab(
        fullName: _fullName,
        username: _username,
        isOnline: _isOnline,
        status: _status,
        pendingAcknowledgement: _pendingAcknowledgement,
        rejectionReason: _rejectionReason,
        isBusy: _isBusy,
        onSubmit: _submitApplication,
        onAcknowledge: _acknowledge,
        onEditDetails: _editDetails,
      ),
      const _PendingNotificationsTab(),
      _PendingProfileTab(fullName: _fullName, username: _username),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading && _currentTab == 0
          ? const Center(
              child: CircularProgressIndicator(
                color: AppConstants.primaryGreen,
                strokeWidth: 2,
              ),
            )
          : screens[_currentTab],
      bottomNavigationBar: _PendingBottomNav(
        currentIndex: _currentTab,
        onTap: _onTabTap,
        sagana: sagana,
        cs: cs,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Navigation — 4 tabs
// ─────────────────────────────────────────────────────────────────────────────

class _PendingBottomNav extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _PendingBottomNav({
    required this.currentIndex,
    required this.onTap,
    required this.sagana,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = [
      (Icons.home_rounded, Icons.home_outlined, l10n.pendingNavHome),
      (
        Icons.notifications_rounded,
        Icons.notifications_outlined,
        l10n.pendingNavUpdates,
      ),
      (Icons.person_rounded, Icons.person_outlined, l10n.pendingNavProfile),
    ];

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: sagana.navBarBackground,
            border: Border(
              top: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: Row(
                children: items.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  final active = i == currentIndex;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTap(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppConstants.onPrimaryContainer.withValues(
                                      alpha: 0.15,
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusFull,
                              ),
                            ),
                            child: Icon(
                              active ? item.$1 : item.$2,
                              size: 22,
                              color: active
                                  ? AppConstants.primaryGreen
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.$3,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: active
                                  ? AppConstants.primaryGreen
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 0: Home — Application status + progress tracker
// ─────────────────────────────────────────────────────────────────────────────

class _PendingHomeTab extends StatelessWidget {
  final String fullName;
  final String username;
  final bool isOnline;
  final String status; // draft | pending | rejected | active
  final bool pendingAcknowledgement;
  final String? rejectionReason;
  final bool isBusy;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onAcknowledge;
  final Future<void> Function() onEditDetails;

  const _PendingHomeTab({
    required this.fullName,
    required this.username,
    required this.isOnline,
    required this.status,
    required this.pendingAcknowledgement,
    required this.rejectionReason,
    required this.isBusy,
    required this.onSubmit,
    required this.onAcknowledge,
    required this.onEditDetails,
  });

  bool get _isApproved => status == 'active' && pendingAcknowledgement;
  bool get _isRejected => status == 'rejected';
  bool get _isDraft => status == 'draft';

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return CustomScrollView(
      slivers: [
        // Glass top bar
        SliverPersistentHeader(
          pinned: true,
          delegate: _SimpleTopBar(
            title: l10n.pendingHomeTitle,
            sagana: sagana,
            cs: cs,
            topPadding: MediaQuery.of(context).padding.top,
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Welcome banner
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppConstants.primaryGreen,
                      AppConstants.primaryContainer,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                  boxShadow: [
                    BoxShadow(
                      color: AppConstants.primaryGreen.withValues(alpha: 0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.20),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.agriculture_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.pendingWelcome(fullName.split(' ').first),
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                l10n.cooperativeName,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.80),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isApproved
                          ? l10n.pendingBannerApproved
                          : _isRejected
                          ? l10n.pendingBannerRejected
                          : _isDraft
                          ? l10n.pendingBannerDraft
                          : l10n.pendingBannerPending,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.90),
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Status-driven action card (Issue 5)
              _statusCard(context, cs, sagana),
              const SizedBox(height: 20),

              if (!isOnline) ...[
                OfflineBanner(message: l10n.pendingOfflineBanner),
                const SizedBox(height: 20),
              ],

              // Cooperative contact info
              _ContactCard(cs: cs, sagana: sagana),
            ]),
          ),
        ),
      ],
    );
  }

  // ── Status-driven action card ──────────────────────────────────────────────

  Widget _statusCard(
    BuildContext context,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final l10n = AppLocalizations.of(context);
    final Color accent;
    final String badge;
    if (_isApproved) {
      accent = AppConstants.successGreen;
      badge = l10n.pendingBadgeApproved;
    } else if (_isRejected) {
      accent = AppConstants.errorRed;
      badge = l10n.pendingBadgeRejected;
    } else if (_isDraft) {
      accent = AppConstants.buyerBlue;
      badge = l10n.pendingBadgeDraft;
    } else {
      accent = AppConstants.warningAmber;
      badge = l10n.pendingBadgePending;
    }

    return Container(
      padding: const EdgeInsets.all(18),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.pendingApplicationStatusTitle,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          if (username.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              l10n.pendingYourUsername(username.toUpperCase()),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 14),

          if (_isApproved) ...[
            Text(
              l10n.pendingApprovedMessage(fullName.split(' ').first),
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            _fullButton(
              label: l10n.pendingContinueButton,
              icon: Icons.arrow_forward_rounded,
              color: AppConstants.successGreen,
              busy: isBusy,
              onTap: onAcknowledge,
            ),
          ] else if (_isRejected) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppConstants.errorRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(
                  color: AppConstants.errorRed.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.pendingRejectedReasonTitle,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppConstants.errorRed,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rejectionReason?.trim().isNotEmpty == true
                        ? rejectionReason!.trim()
                        : l10n.pendingNoReasonProvided,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: cs.onSurface,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.pendingResubmitHint,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            _outlineButton(
              label: l10n.pendingReviewEditButton,
              icon: Icons.edit_outlined,
              onTap: onEditDetails,
            ),
            const SizedBox(height: 10),
            _fullButton(
              label: l10n.pendingResubmitButton,
              icon: Icons.send_rounded,
              color: AppConstants.primaryGreen,
              busy: isBusy,
              onTap: onSubmit,
            ),
          ] else if (_isDraft) ...[
            Text(
              l10n.pendingDraftMessage,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            _outlineButton(
              label: l10n.pendingReviewEditButton,
              icon: Icons.edit_outlined,
              onTap: onEditDetails,
            ),
            const SizedBox(height: 10),
            _fullButton(
              label: l10n.pendingSubmitButton,
              icon: Icons.send_rounded,
              color: AppConstants.primaryGreen,
              busy: isBusy,
              onTap: onSubmit,
            ),
          ] else ...[
            // pending — progress tracker
            _ProgressStep(
              icon: Icons.check_circle_rounded,
              label: l10n.pendingStepSubmitted,
              sublabel: l10n.pendingStepSubmittedSub,
              isComplete: true,
              isActive: false,
              cs: cs,
            ),
            _ProgressConnector(isComplete: true, cs: cs),
            _ProgressStep(
              icon: Icons.hourglass_top_rounded,
              label: l10n.pendingStepReview,
              sublabel: l10n.pendingStepReviewSub,
              isComplete: false,
              isActive: true,
              cs: cs,
            ),
            _ProgressConnector(isComplete: false, cs: cs),
            _ProgressStep(
              icon: Icons.verified_rounded,
              label: l10n.pendingStepDecision,
              sublabel: l10n.pendingStepDecisionSub,
              isComplete: false,
              isActive: false,
              cs: cs,
            ),
          ],
        ],
      ),
    );
  }

  Widget _fullButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool busy,
    required Future<void> Function()? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: (busy || onTap == null) ? null : () => onTap(),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
        ),
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon, size: 18),
        label: Text(
          label,
          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _outlineButton({
    required String label,
    required IconData icon,
    required Future<void> Function() onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () => onTap(),
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// Progress step widget
class _ProgressStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final bool isComplete;
  final bool isActive;
  final ColorScheme cs;

  const _ProgressStep({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.isComplete,
    required this.isActive,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final color = isComplete
        ? AppConstants.successGreen
        : isActive
        ? AppConstants.warningAmber
        : cs.outline;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.40)),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: (isComplete || isActive)
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: (isComplete || isActive)
                        ? cs.onSurface
                        : cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  sublabel,
                  style: GoogleFonts.inter(
                    fontSize: 11,
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

class _ProgressConnector extends StatelessWidget {
  final bool isComplete;
  final ColorScheme cs;
  const _ProgressConnector({required this.isComplete, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 17),
      child: Container(
        width: 2,
        height: 16,
        color: isComplete
            ? AppConstants.successGreen.withValues(alpha: 0.40)
            : cs.outline.withValues(alpha: 0.20),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final ColorScheme cs;
  final SaganaColors sagana;
  const _ContactCard({required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.cooperativeName,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          _ContactRow(
            icon: Icons.location_on_outlined,
            text: l10n.pendingContactAddress,
            cs: cs,
          ),
          const SizedBox(height: 6),
          _ContactRow(
            icon: Icons.calendar_month_outlined,
            text: l10n.pendingContactBod,
            cs: cs,
          ),
          const SizedBox(height: 6),
          _ContactRow(
            icon: Icons.people_alt_outlined,
            text: l10n.pendingContactMembers,
            cs: cs,
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final ColorScheme cs;
  const _ContactRow({required this.icon, required this.text, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1: Notifications — reuses NotificationRepository directly
// ─────────────────────────────────────────────────────────────────────────────

class _PendingNotificationsTab extends StatefulWidget {
  const _PendingNotificationsTab();

  @override
  State<_PendingNotificationsTab> createState() =>
      _PendingNotificationsTabState();
}

class _PendingNotificationsTabState extends State<_PendingNotificationsTab> {
  final _repo = NotificationRepository();
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final items = await _repo.fetchNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        // Top bar
        _SimpleTopBarWidget(
          title: l10n.pendingNotificationsTitle,
          sagana: sagana,
          cs: cs,
        ),

        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppConstants.primaryGreen,
                    strokeWidth: 2,
                  ),
                )
              : RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _load,
                  child: _notifications.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 100),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.notifications_none_rounded,
                                    size: 48,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.pendingNoNotifications,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    l10n.pendingNoNotificationsSub,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                          itemCount: _notifications.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: cs.outline.withValues(alpha: 0.08),
                          ),
                          itemBuilder: (_, i) {
                            final n = _notifications[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 4,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.10),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.notifications_rounded,
                                      color: cs.primary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          n.title,
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: n.isRead
                                                ? FontWeight.w500
                                                : FontWeight.w700,
                                            color: cs.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          n.body,
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
                          },
                        ),
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2: Profile
// ─────────────────────────────────────────────────────────────────────────────

class _PendingProfileTab extends StatefulWidget {
  final String fullName;
  final String username;

  const _PendingProfileTab({required this.fullName, required this.username});

  @override
  State<_PendingProfileTab> createState() => _PendingProfileTabState();
}

class _PendingProfileTabState extends State<_PendingProfileTab> {
  final _client = Supabase.instance.client;

  String? _profilePhotoUrl;
  String? _phone;
  String? _email;
  String? _gender; // male | female | prefer_not_to_say
  DateTime? _dateOfBirth;
  BuyerAddressModel? _address;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;
      final row = await _client
          .from('user_information')
          .select('full_name, phone_number, profile_photo_url, contact_email')
          .eq('user_id', userId)
          .maybeSingle();
      final farmer = await _client
          .from('farmer_profiles')
          .select('date_of_birth, gender')
          .eq('user_id', userId)
          .maybeSingle();
      // The registration address is the default address (saved at signup).
      final address = await BuyerAddressRepository().fetchDefaultAddress();
      if (!mounted) return;
      setState(() {
        _profilePhotoUrl = row?['profile_photo_url'] as String?;
        _phone = row?['phone_number'] as String?;
        _email = row?['contact_email'] as String?;
        _gender = farmer?['gender'] as String?;
        final dob = farmer?['date_of_birth'] as String?;
        _dateOfBirth = dob == null ? null : DateTime.tryParse(dob);
        _address = address;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _genderLabel(AppLocalizations l10n, String? key) => switch (key) {
    'male' => l10n.registerGenderMale,
    'female' => l10n.registerGenderFemale,
    'prefer_not_to_say' => l10n.registerGenderPreferNotToSay,
    _ => l10n.pendingNotSet,
  };

  Future<void> _signOut() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          l10n.pendingSignOut,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          l10n.pendingSignOutConfirm,
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.pendingCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.pendingSignOut,
              style: const TextStyle(color: AppConstants.errorRed),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AuthService.logout();
      if (!mounted) return;
      context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        _SimpleTopBarWidget(
          title: l10n.pendingProfileTitle,
          sagana: sagana,
          cs: cs,
        ),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppConstants.primaryGreen,
                    strokeWidth: 2,
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  child: Column(
                    children: [
                      // Avatar + name
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: sagana.cardBackground,
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusXl,
                          ),
                          border: Border.all(
                            color: cs.outline.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Column(
                          children: [
                            // Profile photo
                            Stack(
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: cs.surfaceContainerHighest,
                                    border: Border.all(
                                      color: AppConstants.primaryGreen
                                          .withValues(alpha: 0.30),
                                      width: 2.5,
                                    ),
                                  ),
                                  child: _profilePhotoUrl != null
                                      ? ClipOval(
                                          child: Image.network(
                                            _profilePhotoUrl!,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : Icon(
                                          Icons.person_rounded,
                                          size: 42,
                                          color: cs.onSurfaceVariant,
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              widget.fullName,
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (widget.username.isNotEmpty)
                              Text(
                                widget.username.toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppConstants.warningAmber.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppConstants.radiusFull,
                                ),
                              ),
                              child: Text(
                                l10n.pendingVerificationBadge,
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: AppConstants.warningAmber,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Personal information (read-only)
                      _InfoSection(
                        title: l10n.pendingPersonalInfoTitle,
                        rows: [
                          _InfoRow(
                            label: l10n.emailAddress,
                            value: _email ?? l10n.pendingNotSet,
                            icon: Icons.email_outlined,
                          ),
                          _InfoRow(
                            label: l10n.pendingPhoneLabel,
                            value: _phone ?? l10n.pendingNotSet,
                            icon: Icons.phone_outlined,
                          ),
                          _InfoRow(
                            label: l10n.addMemberDobLabel,
                            value: _dateOfBirth == null
                                ? l10n.pendingNotSet
                                : _formatDate(_dateOfBirth!),
                            icon: Icons.cake_outlined,
                          ),
                          _InfoRow(
                            label: l10n.registerGenderLabel,
                            value: _genderLabel(l10n, _gender),
                            icon: Icons.person_outline_rounded,
                          ),
                        ],
                        cs: cs,
                        sagana: sagana,
                      ),
                      const SizedBox(height: 16),

                      // Address (read-only, from the address saved at signup)
                      _InfoSection(
                        title: l10n.pendingAddressInfoTitle,
                        rows: _address == null
                            ? [
                                _InfoRow(
                                  label: l10n.registerAddressReviewLabel,
                                  value: l10n.pendingNoAddressYet,
                                  icon: Icons.location_on_outlined,
                                ),
                              ]
                            : [
                                _InfoRow(
                                  label: l10n.registerRegionLabel,
                                  value:
                                      _address!.regionName ??
                                      l10n.pendingNotSet,
                                  icon: Icons.map_outlined,
                                ),
                                _InfoRow(
                                  label: l10n.registerProvinceLabel,
                                  value:
                                      _address!.provinceName ??
                                      l10n.pendingNotSet,
                                  icon: Icons.map_outlined,
                                ),
                                _InfoRow(
                                  label: l10n.registerCityLabel,
                                  value:
                                      _address!.cityMunicipalityName ??
                                      l10n.pendingNotSet,
                                  icon: Icons.location_city_outlined,
                                ),
                                _InfoRow(
                                  label: l10n.registerBarangayLabel,
                                  value:
                                      _address!.barangayName ??
                                      l10n.pendingNotSet,
                                  icon: Icons.holiday_village_outlined,
                                ),
                                _InfoRow(
                                  label: l10n.registerPostalLabel,
                                  value:
                                      _address!.postalCode ??
                                      l10n.pendingNotSet,
                                  icon: Icons.markunread_mailbox_outlined,
                                ),
                                _InfoRow(
                                  label: l10n.registerStreetLabel,
                                  value: _address!.street ?? l10n.pendingNotSet,
                                  icon: Icons.signpost_outlined,
                                ),
                                _InfoRow(
                                  label: l10n.registerBuildingLabel,
                                  value:
                                      _address!.building ?? l10n.pendingNotSet,
                                  icon: Icons.apartment_outlined,
                                ),
                                _InfoRow(
                                  label: l10n.registerHouseNoLabel,
                                  value:
                                      _address!.houseNo ?? l10n.pendingNotSet,
                                  icon: Icons.home_outlined,
                                ),
                              ],
                        cs: cs,
                        sagana: sagana,
                      ),
                      const SizedBox(height: 16),

                      // Locked cooperative features notice
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.pendingLockedFeatures,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Sign out
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: _signOut,
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: Text(
                            l10n.pendingSignOut,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  final String title;
  final List<_InfoRow> rows;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _InfoSection({
    required this.title,
    required this.rows,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          ),
          child: Column(
            children: rows.asMap().entries.map((entry) {
              final i = entry.key;
              final row = entry.value;
              final isLast = i == rows.length - 1;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Icon(row.icon, size: 18, color: cs.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.label,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                row.value,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: cs.outline.withValues(alpha: 0.08),
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _InfoRow {
  final String label;
  final String value;
  final IconData icon;
  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
  });
}

// Simple reusable top bar (non-pinned, for tabs that don't scroll far)
class _SimpleTopBarWidget extends StatelessWidget {
  final String title;
  final SaganaColors sagana;
  final ColorScheme cs;
  const _SimpleTopBarWidget({
    required this.title,
    required this.sagana,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      height: 64 + topPadding,
      padding: EdgeInsets.only(top: topPadding, left: 20, right: 20),
      decoration: BoxDecoration(
        color: sagana.navBarBackground,
        border: Border(
          bottom: BorderSide(color: cs.outline.withValues(alpha: 0.20)),
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
    );
  }
}

// SliverPersistentHeader delegate for the Home tab. Same height, background,
// and bottom divider as the Notifications and Profile headers.
class _SimpleTopBar extends SliverPersistentHeaderDelegate {
  final String title;
  final SaganaColors sagana;
  final ColorScheme cs;
  final double topPadding;

  const _SimpleTopBar({
    required this.title,
    required this.sagana,
    required this.cs,
    required this.topPadding,
  });

  @override
  double get minExtent => 64 + topPadding;
  @override
  double get maxExtent => 64 + topPadding;
  @override
  bool shouldRebuild(covariant _SimpleTopBar old) =>
      old.title != title || old.topPadding != topPadding;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: 64 + topPadding,
      padding: EdgeInsets.only(top: topPadding, left: 20, right: 20),
      decoration: BoxDecoration(
        color: sagana.navBarBackground,
        border: Border(
          bottom: BorderSide(color: cs.outline.withValues(alpha: 0.20)),
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
    );
  }
}
