import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/services/hive_service.dart';

/// About SAGANA — dedicated screen (Admin Profile & Settings Phase 7),
/// shared by every role. Unlike the other three Support & Info items
/// (About the Cooperative, Privacy Policy, Terms of Use — all built on
/// the generic SupportInfoScreen since their content is role-agnostic),
/// this one needs its own screen: the summary line at the top is
/// role-specific (matches the existing per-role ARB pattern — Admin,
/// Farmer, and Buyer already had distinct one-line bodies to avoid
/// showing another role's description), and it also displays the
/// developer grid, which no other Support & Info screen needs.
///
/// Developer names/photos are placeholders (Developer 1-4, generic
/// avatar icon) — real names/photos to be supplied later; swapping them
/// in only touches the _developerNames list below, not this screen's
/// structure.
class AboutSaganaScreen extends StatelessWidget {
  const AboutSaganaScreen({super.key});

  String _roleSummary(AppLocalizations l10n) {
    switch (HiveService.getUserRole()) {
      case 'farmer':
        return l10n.farmerAboutSaganaBody;
      case 'buyer':
        return l10n.aboutSaganaBody;
      case 'admin':
      case 'officer':
      default:
        return l10n.adminAboutSaganaBody;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: sagana.scaffoldBackground,
        elevation: 0,
        leading: BackButton(onPressed: () => context.pop(), color: AppConstants.primaryGreen),
        title: Text(l10n.aboutSagana,
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 8, AppConstants.spacingSafeH, 40),
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppConstants.primaryGreen.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.info_outline_rounded, color: AppConstants.primaryGreen, size: 28),
          ),
          const SizedBox(height: 16),
          Text(_roleSummary(l10n),
              textAlign: TextAlign.justify,
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, height: 1.5, color: cs.onSurface)),
          const SizedBox(height: 14),
          Text(l10n.aboutSaganaFullDescription,
              textAlign: TextAlign.justify,
              style: GoogleFonts.inter(fontSize: 13, height: 1.6, color: cs.onSurfaceVariant)),
          const SizedBox(height: 28),
          Text(l10n.aboutSaganaBuiltBy,
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.92,
            children: [
              for (int i = 1; i <= 4; i++) _developerCard(l10n, i, cs, sagana),
            ],
          ),
        ],
      ),
    );
  }

  Widget _developerCard(AppLocalizations l10n, int number, ColorScheme cs, SaganaColors sagana) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: cs.primary.withValues(alpha: 0.12),
            child: Icon(Icons.person_rounded, color: cs.primary, size: 30),
          ),
          const SizedBox(height: 10),
          Text('${l10n.aboutSaganaDeveloperLabel} $number',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 3),
          Text(l10n.aboutSaganaDeveloperRole,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
