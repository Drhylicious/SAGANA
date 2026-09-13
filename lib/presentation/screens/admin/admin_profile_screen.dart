import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_profile_model.dart';
import '../../../data/repositories/admin_profile_repository.dart';
import '../../../data/services/admin_profile_state_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/web_safe_blur_container.dart';

/// Admin Profile — identity + org snapshot in one hero card, a two-stat
/// Activity Summary (server-backed, per-admin), a 2x2 Quick Access grid,
/// and the full Organizational Information card. Route: /admin/profile
///
/// Editing lives in AdminEditProfileScreen; preferences/sign-out live in
/// AdminSettingsScreen. This screen intentionally never surfaces
/// cooperative-wide KPIs — those stay owned by AdminDashboardScreen.
class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  final _repo = AdminProfileRepository();

  AdminProfileModel? _profile;
  int _pricesUpdatedCount = 0;
  int _broadcastsSentCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchProfile(),
      _repo.fetchPricesUpdatedCount(),
      _repo.fetchBroadcastsSentCount(),
    ]);
    if (!mounted) return;
    final profile = results[0] as AdminProfileModel?;
    setState(() {
      _profile = profile;
      _pricesUpdatedCount = results[1] as int;
      _broadcastsSentCount = results[2] as int;
      _isLoading = false;
    });
    if (profile != null) {
      AdminProfileStateService.instance.updateProfile(profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Column(
        children: [
          _buildHeader(context, l10n, cs, sagana),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _profile == null
                    ? Center(
                        child: Text(l10n.adminProfileLoadError,
                            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                          children: [
                            _buildHeroCard(context, l10n, cs),
                            const SizedBox(height: AppConstants.spacingSectionV),
                            _sectionHeader(l10n.adminProfileActivitySummary, l10n.adminProfileActivitySummaryCaption, cs),
                            _buildActivitySummary(context, l10n, cs, sagana),
                            const SizedBox(height: AppConstants.spacingSectionV),
                            _sectionHeader(l10n.adminProfileQuickAccess, l10n.adminProfileQuickAccessCaption, cs),
                            _buildQuickAccessGrid(context, l10n, cs, sagana),
                            const SizedBox(height: AppConstants.spacingSectionV),
                            _sectionHeader(l10n.adminProfileOrganizationalInfo, l10n.adminProfileOrganizationalInfoCaption, cs),
                            _buildOrgInfoCard(context, l10n, cs, sagana),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n, ColorScheme cs, SaganaColors sagana) {
    return WebSafeBlurContainer(
      decoration: BoxDecoration(
        color: sagana.glassBackground,
        border: Border(bottom: BorderSide(color: sagana.glassBorder)),
      ),
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSm),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(
                  l10n.adminProfileTitle,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: cs.primary),
                ),
              ),
              IconButton(
                icon: Icon(Icons.settings_outlined, color: cs.primary, size: 26),
                onPressed: () => context.push(AppRoutes.adminSettings),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Identity + a 3-field at-a-glance strip (Email / Employee ID /
  /// Administrator Since). Position and Department also shown here for
  /// quick context; the full organizational record still lives in its own
  /// card below — this hero is a summary, not a replacement for it.
  Widget _buildHeroCard(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    final profile = _profile!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        gradient: AppConstants.primaryButtonGradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileAvatar(
                photoUrl: profile.profilePhotoUrl,
                displayName: profile.fullName,
                radius: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.fullName,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(
                        profile.position ??
                            (HiveService.isOfficer
                                ? 'Cooperative Officer'
                                : l10n.adminProfileDefaultRole),
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.92))),
                    if (profile.department != null)
                      Text(profile.department!,
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.72))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.18), height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(flex: 2, child: _heroField(l10n.adminProfileEmail, profile.email)),
              const SizedBox(width: 8),
              Expanded(child: _heroField(l10n.adminProfileEmployeeId, profile.employeeId ?? '—')),
              const SizedBox(width: 8),
              Expanded(
                child: _heroField(
                  l10n.adminProfileAdminSince,
                  profile.adminSince != null ? DateFormat('MMMM yyyy').format(profile.adminSince!) : '—',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: Colors.white.withValues(alpha: 0.65))),
        const SizedBox(height: 3),
        Text(value,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
      ],
    );
  }

  /// Header stacked (title above caption) rather than side-by-side, since
  /// the reference design's single-row header assumes desktop width —
  /// on a real phone viewport the caption sentence won't fit next to the
  /// title without truncating.
  Widget _sectionHeader(String title, String caption, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(caption, style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// Two confirmed, server-backed, per-admin stats — text-only cards,
  /// matching the reference (no icons here, unlike Quick Access below).
  Widget _buildActivitySummary(BuildContext context, AppLocalizations l10n, ColorScheme cs, SaganaColors sagana) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: _statCard(
              context,
              label: l10n.adminProfilePricesUpdated,
              value: '$_pricesUpdatedCount',
              caption: l10n.adminProfilePricesUpdatedCaption,
              onTap: () => context.push(AppRoutes.priceManagement),
              cs: cs,
              sagana: sagana,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _statCard(
              context,
              label: l10n.adminProfileBroadcastsSent,
              value: '$_broadcastsSentCount',
              caption: l10n.adminProfileBroadcastsSentCaption,
              onTap: () => context.push(AppRoutes.broadcastHistory),
              cs: cs,
              sagana: sagana,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(
    BuildContext context, {
    required String label,
    required String value,
    required String caption,
    required VoidCallback onTap,
    required ColorScheme cs,
    required SaganaColors sagana,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(value, style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w800, color: cs.onSurface)),
            const SizedBox(height: 6),
            Text(caption, style: GoogleFonts.inter(fontSize: 9, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  /// Pure navigation shortcuts — 2x2 grid. manageAdminAccounts is
  /// deliberately never referenced: no admin tab exists in
  /// ManageAccountsScreen.
  ///
  /// Cosmetic fix (verification pass): Farmer Accounts / Officer Accounts
  /// route into Member Management, which the router already blocks for
  /// an Officer (Decision D19) — they were previously shown anyway and
  /// just bounced back to the dashboard on tap. Hidden here instead.
  Widget _buildQuickAccessGrid(BuildContext context, AppLocalizations l10n, ColorScheme cs, SaganaColors sagana) {
    final isOfficer = HiveService.isOfficer;
    final items = [
      if (!isOfficer) ...[
        (
          icon: Icons.groups_outlined,
          color: AppConstants.primaryGreen,
          title: l10n.adminProfileFarmerAccounts,
          subtitle: l10n.adminProfileFarmerAccountsSubtitle,
          onTap: () => context.push(AppRoutes.manageFarmerAccounts),
        ),
        (
          icon: Icons.badge_outlined,
          color: AppConstants.buyerBlue,
          title: l10n.adminProfileOfficerAccounts,
          subtitle: l10n.adminProfileOfficerAccountsSubtitle,
          onTap: () => context.push(AppRoutes.manageOfficerAccounts),
        ),
      ],
      (
        icon: Icons.history_rounded,
        color: AppConstants.amber,
        title: l10n.adminProfileRecentActivity,
        subtitle: l10n.adminProfileRecentActivitySubtitle,
        onTap: () => context.push(AppRoutes.adminActivityLog),
      ),
      (
        icon: Icons.dashboard_outlined,
        color: cs.primary,
        title: l10n.adminProfileSystemOverview,
        subtitle: l10n.adminProfileSystemOverviewSubtitle,
        onTap: () => context.go(AppRoutes.adminDashboard),
      ),
    ];

    return Column(
      children: [
        for (int row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(child: _quickAccessCard(items[row * 2], cs, sagana)),
                const SizedBox(width: 12),
                Expanded(child: _quickAccessCard(items[row * 2 + 1], cs, sagana)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _quickAccessCard(
    ({IconData icon, Color color, String title, String subtitle, VoidCallback onTap}) item,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      onTap: item.onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: item.color.withValues(alpha: 0.10), shape: BoxShape.circle),
                  child: Icon(item.icon, color: item.color, size: 18),
                ),
                Icon(Icons.arrow_forward_rounded, size: 14, color: cs.outline.withValues(alpha: 0.6)),
              ],
            ),
            const SizedBox(height: 10),
            Text(item.title, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 3),
            Text(item.subtitle,
                style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildOrgInfoCard(BuildContext context, AppLocalizations l10n, ColorScheme cs, SaganaColors sagana) {
    final profile = _profile!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _orgField(l10n.adminProfileEmployeeId, profile.employeeId ?? '—', cs)),
              Expanded(child: _orgField(l10n.adminProfilePosition, profile.position ?? '—', cs)),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: cs.outline.withValues(alpha: 0.10), height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _orgField(l10n.adminProfileDepartment, profile.department ?? '—', cs)),
              Expanded(
                child: _orgField(
                  l10n.adminProfileAdminSince,
                  profile.adminSince != null ? DateFormat('MMMM yyyy').format(profile.adminSince!) : '—',
                  cs,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(l10n.adminProfileOrgInfoHint,
              textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _orgField(String label, String value, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(height: 3),
        Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
      ],
    );
  }
}