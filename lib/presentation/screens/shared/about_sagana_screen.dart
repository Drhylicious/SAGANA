import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/services/guest_mode_service.dart';
import '../../../data/services/hive_service.dart';
import '../../widgets/support_info_widgets.dart';

/// About SAGANA — shared by every role and by guests.
///
/// The "what SAGANA does for you" line follows the viewer: a signed-in role, or
/// the Buyer / Farmer preview a guest is exploring. The team section is a single
/// column of individual cards (picture, full name, role, description).
class AboutSaganaScreen extends StatelessWidget {
  const AboutSaganaScreen({super.key});

  String _roleSummary(AppLocalizations l10n) {
    final guest = GuestModeService.instance;
    if (guest.isGuest) {
      return guest.role == GuestRole.farmer
          ? l10n.farmerAboutSaganaBody
          : l10n.aboutSaganaBody;
    }
    switch (HiveService.getUserRole()) {
      case 'farmer':
        return l10n.farmerAboutSaganaBody;
      case 'buyer':
        return l10n.aboutSaganaBody;
      default:
        return l10n.adminAboutSaganaBody;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    final features = <(IconData, Color, String, String)>[
      (
        Icons.eco_rounded,
        AppConstants.primaryGreen,
        l10n.aboutFeat1Title,
        l10n.aboutFeat1Desc,
      ),
      (
        Icons.storefront_rounded,
        AppConstants.buyerBlue,
        l10n.aboutFeat2Title,
        l10n.aboutFeat2Desc,
      ),
      (
        Icons.handshake_rounded,
        AppConstants.programPurple,
        l10n.aboutFeat3Title,
        l10n.aboutFeat3Desc,
      ),
      (
        Icons.show_chart_rounded,
        AppConstants.amber,
        l10n.aboutFeat4Title,
        l10n.aboutFeat4Desc,
      ),
      (
        Icons.cloud_off_rounded,
        AppConstants.successGreen,
        l10n.aboutFeat5Title,
        l10n.aboutFeat5Desc,
      ),
      (
        Icons.translate_rounded,
        AppConstants.buyerBlue,
        l10n.aboutFeat6Title,
        l10n.aboutFeat6Desc,
      ),
    ];

    final team = _team(l10n);

    return SupportScaffold(
      title: l10n.aboutSagana,
      children: [
        SupportHero(
          leading: Container(
            width: 84,
            height: 84,
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/images/sagana_icon.png',
              fit: BoxFit.contain,
            ),
          ),
          title: AppConstants.appName,
          subtitle: l10n.aboutSaganaTagline,
          detail: l10n.aboutSaganaHeroSubtitle,
        ),
        const SizedBox(height: 10),
        const _VersionLine(),
        const SizedBox(height: 16),
        SupportCard(
          accent: AppConstants.primaryGreen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.aboutSaganaForYou,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _roleSummary(l10n),
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  height: 1.55,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
        SupportGroupTitle(title: l10n.aboutSaganaWhatsInside),
        SupportCard(
          child: Column(
            children: [
              for (var i = 0; i < features.length; i++) ...[
                if (i > 0) const SupportDivider(),
                SupportFeatureRow(
                  icon: features[i].$1,
                  color: features[i].$2,
                  title: features[i].$3,
                  description: features[i].$4,
                ),
              ],
            ],
          ),
        ),
        SupportGroupTitle(title: l10n.aboutSaganaBuiltForTitle),
        SupportCard(
          child: Text(
            l10n.aboutSaganaBuiltForBody,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              height: 1.6,
              color: cs.onSurface,
            ),
          ),
        ),
        SupportGroupTitle(
          title: l10n.aboutTeamTitle,
          subtitle: l10n.aboutTeamSubtitle,
        ),
        for (var i = 0; i < team.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _TeamCard(member: team[i]),
        ],
      ],
    );
  }

  // The team. Names are people, not translated text.
  static List<_TeamMember> _team(AppLocalizations l10n) => [
    _TeamMember(
      name: 'Jhon Drhy M. Salangsang',
      role: l10n.aboutRoleLeadDeveloper,
      description: l10n.aboutRoleLeadDeveloperDesc,
      icon: Icons.code_rounded,
      color: AppConstants.primaryGreen,
      photo: const AssetImage('assets/images/jhon-drhy.jpg'),
    ),
    _TeamMember(
      name: 'Marc Louie M. Yañez',
      role: l10n.aboutRoleUiUxDesigner,
      description: l10n.aboutRoleUiUxDesignerDesc,
      icon: Icons.palette_rounded,
      color: AppConstants.programPurple,
      photo: const AssetImage('assets/images/marc-louie.jpg'),
    ),
    _TeamMember(
      name: 'John Harvey Revilloza',
      role: l10n.aboutRoleSystemAnalyst,
      description: l10n.aboutRoleSystemAnalystDesc,
      icon: Icons.account_tree_rounded,
      color: AppConstants.buyerBlue,
      photo: const AssetImage('assets/images/john-harvey.jpg'),
    ),
    _TeamMember(
      name: 'John Harold Revilloza',
      role: l10n.aboutRoleQaTester,
      description: l10n.aboutRoleQaTesterDesc,
      icon: Icons.fact_check_rounded,
      color: AppConstants.amber,
      photo: const AssetImage('assets/images/john-harold.jpg'),
    ),
  ];
}

class _TeamMember {
  final String name;
  final String role;
  final String description;
  final IconData icon;
  final Color color;

  /// The member's picture. Null shows the placeholder avatar.
  final ImageProvider? photo;

  const _TeamMember({
    required this.name,
    required this.role,
    required this.description,
    required this.icon,
    required this.color,
    this.photo,
  });
}

/// One team member in their own centered card: a picture, the full name, the
/// role, and a short description. Each card carries its role colour (banner,
/// ring and role pill) so the four read as one team while staying distinct.
class _TeamCard extends StatelessWidget {
  final _TeamMember member;

  const _TeamCard({required this.member});

  static const double _bannerHeight = 88;
  static const double _avatarSize = 104;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = member.color;

    return SupportCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: Column(
          children: [
            SizedBox(
              height: _bannerHeight + _avatarSize / 2,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    height: _bannerHeight,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [c, c.withValues(alpha: 0.65)],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: -24,
                          top: -34,
                          child: _bannerCircle(90),
                        ),
                        Positioned(
                          right: -18,
                          bottom: -42,
                          child: _bannerCircle(110),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: _bannerHeight - _avatarSize / 2,
                    child: Container(
                      width: _avatarSize,
                      height: _avatarSize,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: context.saganaColors.cardBackground,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: c.withValues(alpha: 0.30),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: c, width: 3),
                          color: c.withValues(alpha: 0.12),
                        ),
                        child: ClipOval(
                          child: member.photo == null
                              ? Icon(
                                  Icons.person_rounded,
                                  size: 54,
                                  color: c.withValues(alpha: 0.7),
                                )
                              : Transform.scale(
                                  scale: 1.45,
                                  alignment: const Alignment(0, 0.35),
                                  child: Image(
                                    image: member.photo!,
                                    fit: BoxFit.cover,
                                    alignment: const Alignment(0, 0.25),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: Column(
                children: [
                  Text(
                    member.name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                      border: Border.all(color: c.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(member.icon, size: 15, color: c),
                        const SizedBox(width: 7),
                        Text(
                          member.role,
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: c,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    member.description,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.55,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _bannerCircle(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: 0.12),
    ),
  );
}

/// "Version 1.0.0 (build 2)": the installed app, so it can be compared with the
/// version shown on the SAGANA download page. Nothing is shown until it is read.
class _VersionLine extends StatelessWidget {
  const _VersionLine();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) return const SizedBox.shrink();
        return Center(
          child: Text(
            l10n.aboutVersion(info.version, info.buildNumber),
            style: GoogleFonts.inter(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        );
      },
    );
  }
}
