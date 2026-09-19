import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/services/app_settings_service.dart';
import 'profile_avatar.dart';
import 'shared_widgets.dart';

/// Shared Navigation Drawer for Admin, Farmer, and Buyer (Officer reuses
/// Admin's) — opened via the SAGANA icon on each role's primary/root
/// screens. Deliberately a "dumb" display widget: photo/name/contact and
/// every action are passed in by the caller.
///
/// Rendered as a rounded floating card that fills the full available
/// height (not a fixed fraction of screen height — an earlier version
/// pinned it to a percentage, which left a gap on some screens and cut
/// content on others). Still reads as a distinct card rather than a flat
/// edge-to-edge panel via the right-side margin, rounded corners, and
/// shadow.
///
/// Content does not scroll: the full header + Account + App Preferences
/// + Support & Info + Sign Out stack is wrapped in a LayoutBuilder +
/// FittedBox(fit: BoxFit.scaleDown) — on a tall-enough device it renders
/// at its natural 1:1 size, and on a shorter one it scales the whole
/// stack down uniformly to fit the available height rather than clipping
/// or requiring a scroll. This is what makes "no scrolling" and "adapts
/// to any screen size" both actually true at once, rather than a fixed
/// padding tweak that only happens to fit one tested device.
/// Flutter's built-in DrawerController drives the actual open/close
/// slide+scrim and its timing isn't publicly overridable without
/// replacing Scaffold's drawer mechanism entirely (which all 14 root
/// screens are wired against).
class AppNavigationDrawer extends StatelessWidget {
  final String? photoUrl;
  final String displayName;
  final String? contactEmail;
  final String? phoneNumber;
  final VoidCallback onEditProfile;
  // Farmer-only Account-section item, directly below Edit Profile — the
  // one role-specific addition to an otherwise identical Drawer across
  // Admin/Farmer/Buyer/Officer. Null (Admin/Buyer/Officer) simply omits
  // the row rather than needing a second drawer variant.
  final VoidCallback? onEditFarmDetails;
  final VoidCallback onSignOut;
  final VoidCallback onAboutSagana;
  final VoidCallback onAboutOrganization;
  final VoidCallback onPrivacyPolicy;
  final VoidCallback onTermsOfUse;

  const AppNavigationDrawer({
    super.key,
    required this.photoUrl,
    required this.displayName,
    required this.contactEmail,
    required this.phoneNumber,
    required this.onEditProfile,
    this.onEditFarmDetails,
    required this.onSignOut,
    required this.onAboutSagana,
    required this.onAboutOrganization,
    required this.onPrivacyPolicy,
    required this.onTermsOfUse,
  });

  // Contact lines: shown as separate rows (not joined on one line) since
  // a real email address plus a phone number rarely both fit legibly on
  // a single row at this width. Both shown when both exist; either one
  // alone when only one exists; nothing when neither does.
  List<String> get _contactLines {
    final email = contactEmail?.trim();
    final phone = phoneNumber?.trim();
    return [
      if (email != null && email.isNotEmpty) email,
      if (phone != null && phone.isNotEmpty) phone,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final contactLines = _contactLines;

    // Fills the full available height (no fixed fraction of screen size)
    // so it adapts naturally to any device/aspect ratio with no dead gap
    // above or below — a percentage-based height left a gap on some
    // screens and cut content on others. Still reads as a distinct
    // floating card, not the old flat edge-to-edge panel, via the
    // right-side margin, rounded corners, and shadow below.
    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Container(
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: sagana.scaffoldBackground,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(AppConstants.radiusLg),
                    bottomRight: Radius.circular(AppConstants.radiusLg),
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(6, 0)),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // ─── Branded profile header ─────────────────────────
                    // Deliberately OUTSIDE the FittedBox below: this always
                    // renders at natural 1:1 size, full width — it must
                    // never be subject to scale-down, since any scaling
                    // here (even slight) shrinks its width along with its
                    // height (BoxFit.scaleDown preserves aspect ratio),
                    // which is exactly what caused the stray white gap
                    // next to the green background in earlier passes. Only
                    // the body below (which is what can actually overflow)
                    // gets scaled if it doesn't fit.
                    //
                    // Top padding includes the status bar inset (SafeArea's
                    // top is disabled for this Container specifically) so
                    // the green background extends to the true top edge
                    // instead of leaving a gap above it, while the avatar/
                    // name stay clear of the status bar via this padding.
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(20, 22 + MediaQuery.of(context).padding.top, 20, 20),
                      decoration: const BoxDecoration(
                        gradient: AppConstants.primaryButtonGradient,
                        borderRadius: BorderRadius.only(topRight: Radius.circular(AppConstants.radiusLg)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.5),
                            ),
                            child: ProfileAvatar(photoUrl: photoUrl, displayName: displayName, radius: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                for (final line in contactLines) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    line,
                                    style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.85)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ─── Body (non-scrolling, scales down only if needed) ─
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                  SectionLabel(label: l10n.sectionAccount),
                                  SettingsCard(children: [
                                    SettingsRow(
                                      icon: Icons.person_outline_rounded,
                                      iconColor: AppConstants.primaryGreen,
                                      title: l10n.editProfile,
                                      onTap: onEditProfile,
                                    ),
                                    if (onEditFarmDetails != null) ...[
                                      const SettingsDivider(),
                                      SettingsRow(
                                        icon: Icons.agriculture_rounded,
                                        iconColor: AppConstants.tertiaryContainer,
                                        title: l10n.editFarmDetails,
                                        onTap: onEditFarmDetails!,
                                      ),
                                    ],
                                  ]),
                                  const SizedBox(height: 16),

                                  SectionLabel(label: l10n.sectionAppPreferences),
                                  AnimatedBuilder(
                                    animation: AppSettingsService.instance,
                                    builder: (context, _) {
                                      final isDark = AppSettingsService.instance.themeMode == ThemeMode.dark;
                                      final isTagalog = AppSettingsService.instance.locale.languageCode == AppConstants.localeTagalog;
                                      return SettingsCard(children: [
                                        SettingsRow(
                                          icon: Icons.dark_mode_outlined,
                                          iconColor: AppConstants.charcoal,
                                          title: l10n.appearance,
                                          subtitle: isDark ? l10n.themeDark : l10n.themeLight,
                                          showChevron: false,
                                          trailing: Switch(
                                            value: isDark,
                                            onChanged: (v) => AppSettingsService.instance
                                                .setThemeMode(v ? ThemeMode.dark : ThemeMode.light),
                                          ),
                                        ),
                                        const SettingsDivider(),
                                        SettingsRow(
                                          icon: Icons.language_rounded,
                                          iconColor: AppConstants.buyerBlue,
                                          title: l10n.language,
                                          subtitle: isTagalog ? l10n.languageTagalog : l10n.languageEnglish,
                                          showChevron: false,
                                          trailing: Switch(
                                            value: isTagalog,
                                            onChanged: (v) => AppSettingsService.instance.setLocale(
                                              Locale(v ? AppConstants.localeTagalog : AppConstants.localeEnglish),
                                            ),
                                          ),
                                        ),
                                      ]);
                                    },
                                  ),
                                  const SizedBox(height: 16),

                                  SectionLabel(label: l10n.sectionSupportInfo),
                                  SettingsCard(children: [
                                    SettingsRow(
                                      icon: Icons.info_outline_rounded,
                                      iconColor: AppConstants.primaryGreen,
                                      title: l10n.aboutSagana,
                                      onTap: onAboutSagana,
                                    ),
                                    const SettingsDivider(),
                                    SettingsRow(
                                      icon: Icons.support_agent_rounded,
                                      iconColor: AppConstants.buyerBlue,
                                      title: l10n.aboutCooperative,
                                      onTap: onAboutOrganization,
                                    ),
                                    const SettingsDivider(),
                                    SettingsRow(
                                      icon: Icons.privacy_tip_outlined,
                                      iconColor: AppConstants.amber,
                                      title: l10n.privacyPolicy,
                                      onTap: onPrivacyPolicy,
                                    ),
                                    const SettingsDivider(),
                                    SettingsRow(
                                      icon: Icons.gavel_rounded,
                                      iconColor: AppConstants.onSurfaceVariant,
                                      title: l10n.termsOfUse,
                                      onTap: onTermsOfUse,
                                    ),
                                  ]),
                                  const SizedBox(height: 16),

                                  SettingsCard(children: [
                                    SettingsRow(
                                      icon: Icons.logout_rounded,
                                      iconColor: AppConstants.errorRed,
                                      title: l10n.adminProfileSignOut,
                                      titleColor: AppConstants.errorRed,
                                      showChevron: false,
                                      onTap: onSignOut,
                                    ),
                                  ]),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
