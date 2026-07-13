import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../routes/app_routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PendingApplicantScreen — Shell with 4 tabs
// Shown to farmers whose user_roles.status = 'pending'
// ─────────────────────────────────────────────────────────────────────────────

class PendingApplicantScreen extends StatefulWidget {
  final int initialTab;
  const PendingApplicantScreen({super.key, this.initialTab = 0});

  @override
  State<PendingApplicantScreen> createState() =>
      _PendingApplicantScreenState();
}

class _PendingApplicantScreenState extends State<PendingApplicantScreen> {
  late int _currentTab;
  final _client = Supabase.instance.client;
  RealtimeChannel? _statusChannel;

  // Basic profile data loaded once
  String  _fullName  = '';
  String  _username  = '';
  bool    _isOnline  = true;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadBasicProfile();
    _subscribeToApproval();
  }

  @override
  void dispose() {
    _statusChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadBasicProfile() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;
      final row = await _client
          .from('user_information')
          .select('full_name, username')
          .eq('user_id', userId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _fullName = row?['full_name'] as String? ?? 'Applicant';
        _username = row?['username'] as String? ?? '';
      });
    } catch (_) {}
  }

  // Realtime subscription — fires the moment admin approves the account
  void _subscribeToApproval() {
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
          callback: (payload) async {
            final newStatus = payload.newRecord['status'] as String?;
            if (newStatus == 'active' && mounted) {
              // Update Hive cache so the router guard lifts
              await HiveService.saveMemberStatus('active');
              if (!mounted) return;
              _showApprovalCelebration();
            }
          },
        )
        .subscribe();
  }

  Future<void> _showApprovalCelebration() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusXl)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppConstants.successGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.celebration_rounded,
                  size: 44,
                  color: AppConstants.successGreen,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'You\'re In! 🌾',
                style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Congratulations, $_fullName!\n\n'
                'Your membership with the SP3 Agriculture '
                'Cooperative has been officially approved. '
                'You now have full access to all farmer features.',
                style: GoogleFonts.inter(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Navigate directly to farmer dashboard — no re-login needed
                    context.go(AppRoutes.farmerDashboard);
                  },
                  child: Text('Go to My Dashboard',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onTabTap(int index) {
    setState(() => _currentTab = index);
    // Update URL so back button works correctly
    switch (index) {
      case 0: context.go(AppRoutes.pendingHome);
      case 1: context.go(AppRoutes.pendingNotifications);
      case 2: context.go(AppRoutes.pendingHelp);
      case 3: context.go(AppRoutes.pendingProfile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs     = Theme.of(context).colorScheme;

    final screens = [
      _PendingHomeTab(
          fullName: _fullName, username: _username,
          isOnline: _isOnline),
      const _PendingNotificationsTab(),
      const _PendingHelpTab(),
      _PendingProfileTab(fullName: _fullName, username: _username),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: screens[_currentTab],
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
    required this.currentIndex, required this.onTap,
    required this.sagana, required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_rounded,         Icons.home_outlined,           'Home'),
      (Icons.notifications_rounded,Icons.notifications_outlined,  'Updates'),
      (Icons.help_rounded,         Icons.help_outline_rounded,    'Help'),
      (Icons.person_rounded,       Icons.person_outlined,         'Profile'),
    ];

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: sagana.navBarBackground,
            border: Border(top: BorderSide(
                color: cs.outline.withValues(alpha: 0.10))),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: Row(
                children: items.asMap().entries.map((entry) {
                  final i       = entry.key;
                  final item    = entry.value;
                  final active  = i == currentIndex;
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
                                horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppConstants.onPrimaryContainer
                                      .withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusFull),
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

  const _PendingHomeTab({
    required this.fullName,
    required this.username,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs     = Theme.of(context).colorScheme;

    return CustomScrollView(
      slivers: [
        // Glass top bar
        SliverPersistentHeader(
          pinned: true,
          delegate: _SimpleTopBar(
            title: 'SP3 Cooperative',
            sagana: sagana,
            cs: cs,
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
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusXl),
                  boxShadow: [
                    BoxShadow(
                      color: AppConstants.primaryGreen
                          .withValues(alpha: 0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.agriculture_rounded,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Welcome, ${fullName.split(' ').first}!',
                                style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                            Text('SP3 Agriculture Cooperative',
                                style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Colors.white
                                        .withValues(alpha: 0.80))),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Text(
                      'Your application has been received and is '
                      'currently being reviewed by the cooperative '
                      'administration. You\'ll be notified here '
                      'once a decision has been made.',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.90),
                          height: 1.6),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Application status card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: sagana.cardBackground,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusLg),
                  border: Border.all(
                      color: cs.outline.withValues(alpha: 0.10)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Application Status',
                            style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppConstants.warningAmber
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusFull),
                          ),
                          child: Text(
                            'PENDING REVIEW',
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
                    const SizedBox(height: 6),
                    if (username.isNotEmpty) ...[
                      Text(
                        'Your username: ${username.toUpperCase()}',
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 14),
                    ],
                    // Progress steps
                    _ProgressStep(
                      icon: Icons.check_circle_rounded,
                      label: 'Account Created',
                      sublabel: 'Your account is set up',
                      isComplete: true,
                      isActive: false,
                      cs: cs,
                    ),
                    _ProgressConnector(isComplete: true, cs: cs),
                    _ProgressStep(
                      icon: Icons.hourglass_top_rounded,
                      label: 'Under Review',
                      sublabel: 'SP3 Admin is reviewing your application',
                      isComplete: false,
                      isActive: true,
                      cs: cs,
                    ),
                    _ProgressConnector(isComplete: false, cs: cs),
                    _ProgressStep(
                      icon: Icons.verified_rounded,
                      label: 'Membership Approved',
                      sublabel: 'You become an official SP3 member',
                      isComplete: false,
                      isActive: false,
                      cs: cs,
                    ),
                    _ProgressConnector(isComplete: false, cs: cs),
                    _ProgressStep(
                      icon: Icons.agriculture_rounded,
                      label: 'Farmer Access Activated',
                      sublabel: 'Full access to cooperative features',
                      isComplete: false,
                      isActive: false,
                      cs: cs,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Online/realtime notice
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.06),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(
                      color: cs.primary.withValues(alpha: 0.15)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isOnline
                          ? Icons.wifi_rounded
                          : Icons.wifi_off_rounded,
                      size: 18,
                      color: isOnline
                          ? AppConstants.successGreen
                          : AppConstants.warningAmber,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isOnline
                            ? 'You\'re connected. This screen will '
                              'automatically update the moment your '
                              'membership is approved — no need to '
                              'refresh or re-login.'
                            : 'You\'re offline. Connect to the internet '
                              'to receive your approval notification '
                              'in real time.',
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: cs.onSurface,
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Cooperative contact info
              _ContactCard(cs: cs, sagana: sagana),
            ]),
          ),
        ),
      ],
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
    required this.icon, required this.label, required this.sublabel,
    required this.isComplete, required this.isActive, required this.cs,
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
            width: 36, height: 36,
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
                Text(label,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: (isComplete || isActive)
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: (isComplete || isActive)
                          ? cs.onSurface
                          : cs.onSurfaceVariant,
                    )),
                Text(sublabel,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: cs.onSurfaceVariant)),
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
          Text('SP3 Agriculture Cooperative',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          const SizedBox(height: 10),
          _ContactRow(
              icon: Icons.location_on_outlined,
              text: 'Barangay Payanas, Torrijos, Marinduque',
              cs: cs),
          const SizedBox(height: 6),
          _ContactRow(
              icon: Icons.calendar_month_outlined,
              text: 'BOD Meetings: Every 1st Saturday of the month',
              cs: cs),
          const SizedBox(height: 6),
          _ContactRow(
              icon: Icons.people_alt_outlined,
              text: '52 registered cooperative members',
              cs: cs),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final ColorScheme cs;
  const _ContactRow(
      {required this.icon, required this.text, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  height: 1.4)),
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

class _PendingNotificationsTabState
    extends State<_PendingNotificationsTab> {
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
      setState(() { _notifications = items; _isLoading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs     = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Top bar
        _SimpleTopBarWidget(title: 'Notifications', sagana: sagana, cs: cs),

        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppConstants.primaryGreen, strokeWidth: 2))
              : RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _load,
                  child: _notifications.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 100),
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.notifications_none_rounded,
                                    size: 48, color: cs.onSurfaceVariant),
                                const SizedBox(height: 12),
                                Text('No notifications yet',
                                    style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: cs.onSurfaceVariant)),
                                const SizedBox(height: 6),
                                Text(
                                  'You\'ll be notified here when your\n'
                                  'membership application is updated.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
                                      height: 1.5),
                                ),
                              ],
                            ),
                          ),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                          itemCount: _notifications.length,
                          separatorBuilder: (_, __) =>
                              Divider(
                                  height: 1,
                                  color: cs.outline.withValues(alpha: 0.08)),
                          itemBuilder: (_, i) {
                            final n = _notifications[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.10),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.notifications_rounded,
                                      color: cs.primary, size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(n.title,
                                            style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              fontWeight: n.isRead
                                                  ? FontWeight.w500
                                                  : FontWeight.w700,
                                              color: cs.onSurface,
                                            )),
                                        const SizedBox(height: 3),
                                        Text(n.body,
                                            style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: cs.onSurfaceVariant)),
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
// Tab 2: Help — FAQ for pending applicants
// ─────────────────────────────────────────────────────────────────────────────

class _PendingHelpTab extends StatelessWidget {
  const _PendingHelpTab();

  static const _faqs = [
    (
      'Why can\'t I access Harvest, Loans, or Marketplace?',
      'These features are exclusive to official SP3 cooperative members. '
      'They will become available automatically once an Administrator '
      'approves your membership application.',
    ),
    (
      'How long does the approval process take?',
      'The cooperative administrator reviews applications at their '
      'earliest convenience, usually during or after BOD meetings '
      'held on the first Saturday of every month. If your application '
      'has been pending for more than one month, please contact the '
      'cooperative office directly.',
    ),
    (
      'Will I be notified when my application is approved?',
      'Yes. You will receive an in-app notification the moment your '
      'application is approved. This screen will also automatically '
      'transition you to the full Farmer Dashboard — no need to log '
      'out and log back in.',
    ),
    (
      'What is the SP3 Agriculture Cooperative?',
      'SP3 (Samahan ng mga Produktibong Pamilyang Pilipino sa Payanas) '
      'is a CDA-registered agricultural cooperative located in Barangay '
      'Payanas, Torrijos, Marinduque. It was established on February 1, '
      '2017 and currently serves 52 member-farmers.',
    ),
    (
      'What is my SAGANA username for?',
      'Your SAGANA username is your permanent login identifier for this '
      'application. Keep it safe and do not share it. If you were '
      'recognized as an official SP3 member during registration, your '
      'username follows the format SP3-XXXX.',
    ),
    (
      'How do I contact the cooperative?',
      'Visit the SP3 Cooperative office at Barangay Payanas, Torrijos, '
      'Marinduque. BOD meetings are held every first Saturday of the month '
      'and are open to applicants.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs     = Theme.of(context).colorScheme;

    return Column(
      children: [
        _SimpleTopBarWidget(title: 'Help & FAQ', sagana: sagana, cs: cs),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.06),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(
                      color: cs.primary.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: cs.primary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your application is under review. '
                        'Here are answers to common questions '
                        'while you wait.',
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: cs.onSurface,
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ..._faqs.map((faq) => _FaqItem(
                    question: faq.$1,
                    answer: faq.$2,
                    cs: cs,
                    sagana: sagana,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

class _FaqItem extends StatefulWidget {
  final String question;
  final String answer;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _FaqItem({
    required this.question, required this.answer,
    required this.cs, required this.sagana,
  });

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.sagana.cardBackground,
            borderRadius:
                BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(
                color: widget.cs.outline.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(widget.question,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: widget.cs.onSurface,
                        )),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: widget.cs.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                Divider(
                    height: 1,
                    color: widget.cs.outline.withValues(alpha: 0.10)),
                const SizedBox(height: 10),
                Text(widget.answer,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: widget.cs.onSurfaceVariant,
                      height: 1.6,
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 3: Profile — basic account management only, no cooperative features
// ─────────────────────────────────────────────────────────────────────────────

class _PendingProfileTab extends StatefulWidget {
  final String fullName;
  final String username;

  const _PendingProfileTab(
      {required this.fullName, required this.username});

  @override
  State<_PendingProfileTab> createState() => _PendingProfileTabState();
}

class _PendingProfileTabState extends State<_PendingProfileTab> {
  final _client = Supabase.instance.client;

  String? _profilePhotoUrl;
  String? _phone;
  String? _sitio;
  bool    _isLoading = true;

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
          .select('full_name, phone_number, sitio, profile_photo_url')
          .eq('user_id', userId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _profilePhotoUrl = row?['profile_photo_url'] as String?;
        _phone           = row?['phone_number'] as String?;
        _sitio           = row?['sitio'] as String?;
        _isLoading       = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Sign Out',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to sign out?',
            style: GoogleFonts.inter(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign Out',
                  style: TextStyle(color: AppConstants.errorRed))),
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
    final cs     = Theme.of(context).colorScheme;

    return Column(
      children: [
        _SimpleTopBarWidget(title: 'My Profile', sagana: sagana, cs: cs),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppConstants.primaryGreen, strokeWidth: 2))
              : SingleChildScrollView(
                  padding:
                      const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  child: Column(
                    children: [
                      // Avatar + name
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: sagana.cardBackground,
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusXl),
                          border: Border.all(
                              color: cs.outline.withValues(alpha: 0.10)),
                        ),
                        child: Column(
                          children: [
                            // Profile photo
                            Stack(
                              children: [
                                Container(
                                  width: 80, height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: cs.surfaceContainerHighest,
                                    border: Border.all(
                                        color: AppConstants.primaryGreen
                                            .withValues(alpha: 0.30),
                                        width: 2.5),
                                  ),
                                  child: _profilePhotoUrl != null
                                      ? ClipOval(
                                          child: Image.network(
                                              _profilePhotoUrl!,
                                              fit: BoxFit.cover),
                                        )
                                      : Icon(Icons.person_rounded,
                                          size: 42,
                                          color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(widget.fullName,
                                style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface),
                                textAlign: TextAlign.center),
                            if (widget.username.isNotEmpty)
                              Text(
                                widget.username.toUpperCase(),
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: cs.primary,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5),
                              ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppConstants.warningAmber
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusFull),
                              ),
                              child: Text(
                                'PENDING VERIFICATION',
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

                      // Basic info (read-only)
                      _InfoSection(
                        title: 'Account Information',
                        rows: [
                          _InfoRow(
                              label: 'Phone',
                              value: _phone ?? 'Not set',
                              icon: Icons.phone_outlined),
                          _InfoRow(
                              label: 'Sitio',
                              value: _sitio ?? 'Not set',
                              icon: Icons.location_on_outlined),
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
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusMd),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.lock_outline_rounded,
                                size: 16,
                                color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Farm Details, Input Loans, Harvest Summary, '
                                'Expenses, and Cooperative Contributions '
                                'will be available after your membership '
                                'is approved.',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                    height: 1.5),
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
                          label: Text('Sign Out',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600)),
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
    required this.title, required this.rows,
    required this.cs, required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(title.toUpperCase(),
              style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: cs.onSurfaceVariant)),
        ),
        Container(
          decoration: BoxDecoration(
            color: sagana.cardBackground,
            borderRadius:
                BorderRadius.circular(AppConstants.radiusLg),
            border:
                Border.all(color: cs.outline.withValues(alpha: 0.10)),
          ),
          child: Column(
            children: rows.asMap().entries.map((entry) {
              final i   = entry.key;
              final row = entry.value;
              final isLast = i == rows.length - 1;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Icon(row.icon, size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(row.label,
                              style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600)),
                          Text(row.value,
                              style: GoogleFonts.inter(
                                  fontSize: 13, color: cs.onSurface)),
                        ],
                      ),
                    ),
                  ]),
                ),
                if (!isLast)
                  Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: cs.outline.withValues(alpha: 0.08)),
              ]);
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
  const _InfoRow(
      {required this.label, required this.value, required this.icon});
}

// Simple reusable top bar (non-pinned, for tabs that don't scroll far)
class _SimpleTopBarWidget extends StatelessWidget {
  final String title;
  final SaganaColors sagana;
  final ColorScheme cs;
  const _SimpleTopBarWidget(
      {required this.title, required this.sagana, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64 + MediaQuery.of(context).padding.top,
      padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top, left: 20, right: 20),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title,
            style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
      ),
    );
  }
}

// SliverPersistentHeader delegate for the home tab
class _SimpleTopBar extends SliverPersistentHeaderDelegate {
  final String title;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _SimpleTopBar(
      {required this.title, required this.sagana, required this.cs});

  @override double get minExtent => 64;
  @override double get maxExtent => 64;
  @override bool shouldRebuild(covariant _SimpleTopBar old) =>
      old.title != title;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(
                bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.agriculture_rounded,
                    color: AppConstants.primaryGreen, size: 20),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
            ]),
          ),
        ),
      ),
    );
  }
}