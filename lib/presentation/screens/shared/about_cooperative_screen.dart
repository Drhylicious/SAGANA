import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../widgets/support_info_widgets.dart';

/// About the Cooperative — shared by every role and by guests.
///
/// Facts come from the cooperative's own account of itself (the BOD
/// Chairperson interview in the project documentation). No email address or
/// contact number is shown here, on purpose.
class AboutCooperativeScreen extends StatelessWidget {
  const AboutCooperativeScreen({super.key});

  // The CDA registration number is an identifier, not translated text.
  static const _registrationNumber = '9520-1040000000036899';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const accent = AppConstants.primaryGreen;

    final sections = <SupportSection>[
      SupportSection(
        icon: Icons.flag_rounded,
        title: l10n.coopPurposeTitle,
        blocks: [SupportBlock.paragraph(l10n.coopPurposeBody)],
      ),
      SupportSection(
        icon: Icons.agriculture_rounded,
        title: l10n.coopWorkTitle,
        blocks: [
          SupportBlock.bullets([
            l10n.coopWorkBiz1,
            l10n.coopWorkBiz2,
            l10n.coopWorkBiz3,
          ]),
          SupportBlock.paragraph(l10n.coopWorkBody),
        ],
      ),
      SupportSection(
        icon: Icons.groups_rounded,
        title: l10n.coopMembershipTitle,
        blocks: [
          SupportBlock.bullets([
            l10n.coopMem1,
            l10n.coopMem2,
            l10n.coopMem3,
            l10n.coopMem4,
            l10n.coopMem5,
          ]),
          SupportBlock.note(l10n.coopMemNote),
        ],
      ),
      SupportSection(
        icon: Icons.account_balance_rounded,
        title: l10n.coopGovTitle,
        blocks: [SupportBlock.paragraph(l10n.coopGovBody)],
      ),
      SupportSection(
        icon: Icons.hub_rounded,
        title: l10n.coopSaganaTitle,
        blocks: [
          SupportBlock.paragraph(l10n.coopSaganaBody),
          SupportBlock.bullets([l10n.coopSaganaMarket1, l10n.coopSaganaMarket2]),
        ],
      ),
    ];

    return SupportScaffold(
      title: l10n.aboutCooperative,
      children: [
        SupportHero(
          icon: Icons.agriculture_rounded,
          title: 'SP3 Agriculture Cooperative',
          subtitle: l10n.coopHeroFilipino,
          detail: l10n.coopHeroPlace,
        ),
        const SizedBox(height: 16),
        SupportCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.coopAtAGlance,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 14),
              SupportFact(
                icon: Icons.verified_rounded,
                label: l10n.coopFactRegisteredLabel,
                value: l10n.coopFactRegisteredValue,
              ),
              const SupportDivider(),
              SupportFact(
                icon: Icons.tag_rounded,
                label: l10n.coopFactRegNoLabel,
                value: _registrationNumber,
              ),
              const SupportDivider(),
              SupportFact(
                icon: Icons.category_rounded,
                label: l10n.coopFactTypeLabel,
                value: l10n.coopFactTypeValue,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final s in sections) ...[
          SupportDocumentSectionCard(section: s, accent: accent),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}
