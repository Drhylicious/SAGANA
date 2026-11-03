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
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/repositories/buyer_address_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/pending_applicant_views.dart';
import '../../widgets/skeleton.dart';

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
  String _firstName = '';
  String _username = '';
  bool _isOnline = true;
  bool _isLoading = true;
  bool _isBusy = false;

  // 'pending' | 'rejected' (shown as Disapproved) | 'active' (Approved);
  // 'draft' only for an account registered under the old flow.
  String _status = 'pending';
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
          .select('full_name, first_name, username')
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
        _firstName = (info?['first_name'] as String?)?.trim() ?? '';
        _username = info?['username'] as String? ?? '';
        _status = role?['status'] as String? ?? 'pending';
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

  // Realtime — reload state whenever the Manager changes anything on the row.
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
        backgroundColor: ok ? AppConstants.midGreen : AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// What the greeting calls the applicant: the first name as entered, or the
  /// first word of the full name for an account that has no separate first name.
  String get _greetingName {
    if (_firstName.isNotEmpty) return _firstName;
    return _fullName.split(' ').first;
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
      PendingHomeView(
        firstName: _greetingName,
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
      _PendingProfileTab(
        fullName: _fullName,
        status: _status,
        pendingAcknowledgement: _pendingAcknowledgement,
      ),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading && _currentTab == 0
          ? CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: PendingTopBarDelegate(
                    title: AppLocalizations.of(context).pendingHomeTitle,
                    topPadding: MediaQuery.of(context).padding.top,
                  ),
                ),
                // No hasScrollBody:false here: that mode measures the child's
                // intrinsic height, and SkeletonList contains a LayoutBuilder,
                // which cannot answer that (assertion in debug builds).
                const SliverFillRemaining(
                  child: Padding(padding: EdgeInsets.all(16), child: SkeletonList()),
                ),
              ],
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
// Tab 1: Notifications — the same repository and actions as the other roles
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

  void _replace(String id, bool isRead) {
    setState(() {
      _notifications = _notifications
          .map((n) => n.id == id ? n.copyWith(isRead: isRead) : n)
          .toList();
    });
    AppEventService.instance.notify();
  }

  // A pending applicant cannot open the cooperative screens a notification
  // would link to, so a tap only marks it read.
  Future<void> _onTap(NotificationModel n) async {
    if (n.isRead) return;
    _replace(n.id, true);
    await _repo.markAsRead(n.id);
  }

  Future<void> _toggleRead(NotificationModel n) async {
    final nowRead = !n.isRead;
    _replace(n.id, nowRead);
    if (nowRead) {
      await _repo.markAsRead(n.id);
    } else {
      await _repo.markAsUnread(n.id);
    }
  }

  Future<void> _markAllRead() async {
    setState(() {
      _notifications = _notifications
          .map((n) => n.copyWith(isRead: true))
          .toList();
    });
    AppEventService.instance.notify();
    await _repo.markAllAsRead();
  }

  Future<void> _markAllUnread() async {
    setState(() {
      _notifications = _notifications
          .map((n) => n.copyWith(isRead: false))
          .toList();
    });
    AppEventService.instance.notify();
    await _repo.markAllAsUnread();
  }

  Future<void> _delete(NotificationModel n) async {
    setState(() => _notifications.removeWhere((x) => x.id == n.id));
    AppEventService.instance.notify();
    await _repo.deleteNotification(n.id);
  }

  @override
  Widget build(BuildContext context) {
    return PendingNotificationsView(
      notifications: _notifications,
      isLoading: _isLoading,
      onRefresh: _load,
      onTap: _onTap,
      onToggleRead: _toggleRead,
      onDelete: _delete,
      onMarkAllRead: _markAllRead,
      onMarkAllUnread: _markAllUnread,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2: Profile
// ─────────────────────────────────────────────────────────────────────────────

class _PendingProfileTab extends StatefulWidget {
  final String fullName;

  /// draft | pending | rejected | active (approved, waiting for Continue)
  final String status;
  final bool pendingAcknowledgement;

  const _PendingProfileTab({
    required this.fullName,
    required this.status,
    required this.pendingAcknowledgement,
  });

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

  bool get _isApproved =>
      widget.status == 'active' && widget.pendingAcknowledgement;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = widget.status == 'rejected'
        ? l10n.pendingBadgeRejected
        : widget.status == 'draft'
        ? l10n.pendingBadgeDraft
        : _isApproved
        ? l10n.pendingBadgeApproved
        : l10n.farmerDetailsPendingApplicantBadge.toUpperCase();
    final color = widget.status == 'rejected'
        ? AppConstants.errorRed
        : _isApproved
        ? AppConstants.successGreen
        : AppConstants.warningAmber;

    return PendingProfileView(
      profile: FarmerProfileModel(
        userId: _client.auth.currentUser?.id ?? '',
        fullName: widget.fullName,
        contactEmail: _email,
        phoneNumber: _phone,
        profilePhotoUrl: _profilePhotoUrl,
        dateOfBirth: _dateOfBirth,
        gender: _gender,
        capitalShares: 0,
        isVerified: false,
        primaryCrops: const [],
      ),
      address: _address,
      statusLabel: label,
      statusColor: color,
      isLoading: _isLoading,
      onSignOut: _signOut,
    );
  }
}
