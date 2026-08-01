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
import '../../../routes/app_routes.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/web_safe_blur_container.dart';

/// Admin Profile — the logged-in administrator's own account, read-only
/// display of identity + organizational info. Route: /admin/profile
///
/// Editing (name/phone/sitio/photo) lives in AdminEditProfileScreen;
/// preferences, data & storage, and sign out live in AdminSettingsScreen —
/// this screen no longer owns any of that, mirroring how BuyerAccountScreen
/// is purely a display surface and defers editing/settings elsewhere.
class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  final _repo = AdminProfileRepository();

  AdminProfileModel? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final profile = await _repo.fetchProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
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
      body: Stack(
        children: [
          Column(
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
                                _buildIdentityCard(context, l10n, cs),
                                const SizedBox(height: AppConstants.spacingSectionV),
                                _sectionLabel(l10n.adminProfileOrganizationalInfo, cs),
                                _buildOrgInfoCard(context, l10n, cs, sagana),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Secondary header: back button, title beside it, settings icon on
  // the right — same pattern as Buyer/Farmer's pushed-screen headers, now
  // extended with the settings entry point Admin was missing. ───────────

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

  Widget _buildIdentityCard(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    final profile = _profile!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        gradient: AppConstants.primaryButtonGradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        children: [
          ProfileAvatar(
            photoUrl: profile.profilePhotoUrl,
            displayName: profile.fullName,
            radius: 40,
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Text(profile.fullName,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white)),
          Text(profile.position ?? l10n.adminProfileDefaultRole,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
          const SizedBox(height: 4),
          Text(profile.email, style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.70))),
        ],
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _orgInfoRow(l10n.adminProfileEmployeeId, profile.employeeId ?? '—', cs),
          const SizedBox(height: AppConstants.spacingSm),
          _orgInfoRow(l10n.adminProfilePosition, profile.position ?? '—', cs),
          const SizedBox(height: AppConstants.spacingSm),
          _orgInfoRow(l10n.adminProfileDepartment, profile.department ?? '—', cs),
          if (profile.adminSince != null) ...[
            const SizedBox(height: AppConstants.spacingSm),
            _orgInfoRow(l10n.adminProfileAdminSince, DateFormat('MMMM yyyy').format(profile.adminSince!), cs),
          ],
          const SizedBox(height: AppConstants.spacingSm),
          Text(l10n.adminProfileOrgInfoHint, style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _orgInfoRow(String label, String value, ColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
        Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface)),
      ],
    );
  }

  Widget _sectionLabel(String label, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(label.toUpperCase(),
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: cs.outline, letterSpacing: 0.8)),
    );
  }
}
