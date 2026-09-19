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

/// Admin Profile — identity in a plain-card hero (no gradient — matches
/// the Reports module's own "Phase 16" fix for the identical "oversized
/// gradient block" complaint), a 7-stat Activity Summary (server-backed,
/// per-admin), and a 2x2 Quick Access grid. Route: /admin/profile
///
/// Employee ID and the Organizational Information card were both removed
/// (Admin Profile & Settings review): Employee ID is confirmed unused
/// anywhere else in the codebase, and Organizational Information was
/// redundant with the hero card's own Position/Department display.
///
/// Editing lives in AdminEditProfileScreen; preferences/sign-out/support
/// now live in the shared Navigation Drawer, reachable from every
/// primary screen — not just from here. This screen intentionally never
/// surfaces cooperative-wide KPIs — those stay owned by
/// AdminDashboardScreen.
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
  int _offersConfirmedCount = 0;
  int _loanPaymentsRecordedCount = 0;
  int _inventoryAdjustmentsCount = 0;
  int _salesRecordedCount = 0;
  int _cropRequestsReviewedCount = 0;
  int _listingsReviewedCount = 0;
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
      _repo.fetchOffersConfirmedCount(),
      _repo.fetchLoanPaymentsRecordedCount(),
      _repo.fetchInventoryAdjustmentsCount(),
      _repo.fetchSalesRecordedCount(),
      _repo.fetchCropRequestsReviewedCount(),
      _repo.fetchListingsReviewedCount(),
    ]);
    if (!mounted) return;
    final profile = results[0] as AdminProfileModel?;
    setState(() {
      _profile = profile;
      _pricesUpdatedCount = results[1] as int;
      _broadcastsSentCount = results[2] as int;
      _offersConfirmedCount = results[3] as int;
      _loanPaymentsRecordedCount = results[4] as int;
      _inventoryAdjustmentsCount = results[5] as int;
      _salesRecordedCount = results[6] as int;
      _cropRequestsReviewedCount = results[7] as int;
      _listingsReviewedCount = results[8] as int;
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
                            _buildHeroCard(context, l10n, cs, sagana),
                            const SizedBox(height: AppConstants.spacingSectionV),
                            _sectionHeader(l10n.adminProfileActivitySummary, l10n.adminProfileActivitySummaryCaption, cs),
                            _buildActivitySummary(context, l10n, cs, sagana),
                            const SizedBox(height: AppConstants.spacingSectionV),
                            _sectionHeader(l10n.adminProfileQuickAccess, l10n.adminProfileQuickAccessCaption, cs),
                            _buildQuickAccessGrid(context, l10n, cs, sagana),
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
              // Settings gear removed (Admin Profile & Settings review) —
              // Account/Preferences/Support/Sign-Out now live in the
              // Navigation Drawer, reachable from every primary screen's
              // SAGANA icon, not just from this one profile screen.
            ],
          ),
        ),
      ),
    );
  }

  /// Identity + Email / Administrator Since. Redesigned per review
  /// feedback (matching the Reports module's own "Phase 16" fix for the
  /// identical complaint — a single solid gradient block felt oversized
  /// and cut off values that weren't fully visible): a plain card
  /// background instead of a gradient, and Email/Admin Since as
  /// full-width labeled rows instead of cramped equal-width columns, so a
  /// long email address is never truncated. Employee ID is deliberately
  /// no longer shown — confirmed unused anywhere else in the codebase,
  /// and not meaningful for the Admin viewing their own profile.
  /// Organizational Information (Position/Department card) was removed
  /// entirely as redundant with what's already shown here.
  Widget _buildHeroCard(BuildContext context, AppLocalizations l10n, ColorScheme cs, SaganaColors sagana) {
    final profile = _profile!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Green ring behind the avatar — the one deliberate brand
              // touch on an otherwise plain-card hero (per review
              // feedback that the redesigned card read as too flat/plain
              // once the gradient was removed), without reintroducing a
              // full gradient block.
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppConstants.primaryGreen.withValues(alpha: 0.35), width: 2),
                ),
                child: ProfileAvatar(
                  photoUrl: profile.profilePhotoUrl,
                  displayName: profile.fullName,
                  radius: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.fullName,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: cs.onSurface)),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                      ),
                      child: Text(
                          profile.position ??
                              (HiveService.isOfficer
                                  ? 'Cooperative Officer'
                                  : l10n.adminProfileDefaultRole),
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                    ),
                    if (profile.department != null) ...[
                      const SizedBox(height: 4),
                      Text(profile.department!,
                          style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: cs.outline.withValues(alpha: 0.24), height: 1),
          const SizedBox(height: 14),
          _heroRow(l10n.adminProfileEmail, profile.email, cs),
          const SizedBox(height: 12),
          _heroRow(
            l10n.adminProfileAdminSince,
            profile.adminSince != null ? DateFormat('MMMM yyyy').format(profile.adminSince!) : '—',
            cs,
          ),
        ],
      ),
    );
  }

  /// Full-width label + value row — value gets all remaining width and
  /// wraps rather than truncating, so a long email address is always
  /// fully visible instead of being cut off with an ellipsis.
  Widget _heroRow(String label, String value, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ),
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

  /// Eight confirmed, server-backed, per-admin stats — an even count for
  /// a clean 2-column grid (an odd 7th tile left a dangling half-row,
  /// flagged in review). "Offers Confirmed" was the 8th genuinely
  /// confirmed-attributable activity from the same investigation (Issue
  /// A6) that hadn't been added yet, so it fills the gap rather than
  /// inventing a new metric. "Loans Issued" is still deliberately NOT
  /// included: farmer_loans has no attribution column at all, confirmed
  /// during that review, so there's nothing to count without a schema
  /// change out of scope here.
  ///
  /// Each tile gets its own accent color + icon badge (cycling through a
  /// small palette, same visual language as ReportHeroCard's stat tiles)
  /// instead of a flat black-on-white number — addresses the "too plain"
  /// feedback without a redesign of the whole screen.
  ///
  /// Laid out as manual paired rows (mirroring _buildQuickAccessGrid
  /// below) rather than GridView's fixed childAspectRatio — a fixed
  /// aspect ratio gave every tile the same height regardless of how many
  /// lines its caption actually wrapped to, which is what caused the
  /// reported overflow on the longer captions.
  Widget _buildActivitySummary(BuildContext context, AppLocalizations l10n, ColorScheme cs, SaganaColors sagana) {
    final accents = [
      AppConstants.primaryGreen,
      AppConstants.buyerBlue,
      AppConstants.amber,
      AppConstants.programPurple,
    ];
    final icons = [
      Icons.sell_outlined,
      Icons.campaign_outlined,
      Icons.handshake_outlined,
      Icons.payments_outlined,
      Icons.inventory_2_outlined,
      Icons.point_of_sale_outlined,
      Icons.fact_check_outlined,
      Icons.storefront_outlined,
    ];
    final stats = [
      (
        label: l10n.adminProfilePricesUpdated,
        value: _pricesUpdatedCount,
        caption: l10n.adminProfilePricesUpdatedCaption,
        onTap: () => context.push(AppRoutes.priceManagement),
      ),
      (
        label: l10n.adminProfileBroadcastsSent,
        value: _broadcastsSentCount,
        caption: l10n.adminProfileBroadcastsSentCaption,
        onTap: () => context.push(AppRoutes.broadcastHistory),
      ),
      (
        label: l10n.adminProfileOffersConfirmed,
        value: _offersConfirmedCount,
        caption: l10n.adminProfileOffersConfirmedCaption,
        onTap: () => context.push(AppRoutes.offerToCooperative),
      ),
      (
        label: l10n.adminProfileLoanPaymentsRecorded,
        value: _loanPaymentsRecordedCount,
        caption: l10n.adminProfileLoanPaymentsRecordedCaption,
        onTap: () => context.push(AppRoutes.loanHistory),
      ),
      (
        label: l10n.adminProfileInventoryAdjustments,
        value: _inventoryAdjustmentsCount,
        caption: l10n.adminProfileInventoryAdjustmentsCaption,
        onTap: () => context.push(AppRoutes.adminInventory),
      ),
      (
        label: l10n.adminProfileSalesRecorded,
        value: _salesRecordedCount,
        caption: l10n.adminProfileSalesRecordedCaption,
        onTap: () => context.push(AppRoutes.salesReport),
      ),
      (
        label: l10n.adminProfileCropRequestsReviewed,
        value: _cropRequestsReviewedCount,
        caption: l10n.adminProfileCropRequestsReviewedCaption,
        onTap: () => context.push(AppRoutes.cropRequestApproval),
      ),
      (
        label: l10n.adminProfileListingsReviewed,
        value: _listingsReviewedCount,
        caption: l10n.adminProfileListingsReviewedCaption,
        onTap: () => context.push(AppRoutes.listingReview),
      ),
    ];

    return Column(
      children: [
        for (int row = 0; row < stats.length ~/ 2; row++) ...[
          if (row > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _statCard(
                    context,
                    label: stats[row * 2].label,
                    value: '${stats[row * 2].value}',
                    caption: stats[row * 2].caption,
                    icon: icons[row * 2],
                    accent: accents[row % accents.length],
                    onTap: stats[row * 2].onTap,
                    cs: cs,
                    sagana: sagana,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    context,
                    label: stats[row * 2 + 1].label,
                    value: '${stats[row * 2 + 1].value}',
                    caption: stats[row * 2 + 1].caption,
                    icon: icons[row * 2 + 1],
                    accent: accents[(row + 1) % accents.length],
                    onTap: stats[row * 2 + 1].onTap,
                    cs: cs,
                    sagana: sagana,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _statCard(
    BuildContext context, {
    required String label,
    required String value,
    required String caption,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
    required ColorScheme cs,
    required SaganaColors sagana,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), shape: BoxShape.circle),
                  child: Icon(icon, color: accent, size: 15),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w800, color: accent)),
            const SizedBox(height: 4),
            Text(caption, style: GoogleFonts.inter(fontSize: 9, color: cs.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
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
          border: Border.all(color: cs.outline.withValues(alpha: 0.24)),
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

}