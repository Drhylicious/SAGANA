import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../widgets/support_info_widgets.dart';

/// Terms of Use — shared by every role and by guests.
///
/// The rules here mirror how SAGANA works today (roles, registration and
/// approval, listing review, order and payment steps, loans and programs,
/// offline Sync, suspension and feature restrictions). When a workflow changes,
/// update the matching section and the strings in app_en.arb / app_tl.arb
/// together.
class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const accent = AppConstants.buyerBlue;

    final sections = <SupportSection>[
      SupportSection(
        icon: Icons.handshake_rounded,
        title: l10n.termsS1Title,
        blocks: [SupportBlock.paragraph(l10n.termsS1Body)],
      ),
      SupportSection(
        icon: Icons.badge_rounded,
        title: l10n.termsS2Title,
        blocks: [
          SupportBlock.labeled([
            (l10n.supportLblBuyer, l10n.termsS2Buyer),
            (l10n.supportLblFarmer, l10n.termsS2Farmer),
            (l10n.supportLblOfficer, l10n.termsS2Officer),
            (l10n.supportLblManager, l10n.termsS2Manager),
            (l10n.supportLblGuests, l10n.termsS2Guest),
          ]),
        ],
      ),
      SupportSection(
        icon: Icons.manage_accounts_rounded,
        title: l10n.termsS3Title,
        blocks: [
          SupportBlock.bullets([
            l10n.termsS3B1,
            l10n.termsS3B2,
            l10n.termsS3B3,
            l10n.termsS3B4,
          ]),
        ],
      ),
      SupportSection(
        icon: Icons.eco_rounded,
        title: l10n.termsS4Title,
        blocks: [
          SupportBlock.bullets([
            l10n.termsS4B1,
            l10n.termsS4B2,
            l10n.termsS4B3,
            l10n.termsS4B4,
          ]),
        ],
      ),
      SupportSection(
        icon: Icons.storefront_rounded,
        title: l10n.termsS5Title,
        blocks: [
          SupportBlock.bullets([l10n.termsS5B1, l10n.termsS5B2, l10n.termsS5B3]),
        ],
      ),
      SupportSection(
        icon: Icons.receipt_long_rounded,
        title: l10n.termsS6Title,
        blocks: [
          SupportBlock.bullets([
            l10n.termsS6B1,
            l10n.termsS6B2,
            l10n.termsS6B3,
            l10n.termsS6B4,
          ]),
        ],
      ),
      SupportSection(
        icon: Icons.volunteer_activism_rounded,
        title: l10n.termsS7Title,
        blocks: [
          SupportBlock.bullets([
            l10n.termsS7B1,
            l10n.termsS7B2,
            l10n.termsS7B3,
            l10n.termsS7B4,
          ]),
          SupportBlock.note(l10n.termsS7Note),
        ],
      ),
      SupportSection(
        icon: Icons.gavel_rounded,
        title: l10n.termsS8Title,
        blocks: [
          SupportBlock.bullets([l10n.termsS8B1, l10n.termsS8B2, l10n.termsS8B3]),
        ],
      ),
      SupportSection(
        icon: Icons.sync_rounded,
        title: l10n.termsS9Title,
        blocks: [
          SupportBlock.bullets([
            l10n.termsS9B1,
            l10n.termsS9B2,
            l10n.termsS9B3,
            l10n.termsS9B4,
          ]),
        ],
      ),
      SupportSection(
        icon: Icons.show_chart_rounded,
        title: l10n.termsS10Title,
        blocks: [SupportBlock.paragraph(l10n.termsS10Body)],
      ),
      SupportSection(
        icon: Icons.account_balance_rounded,
        title: l10n.termsS11Title,
        blocks: [SupportBlock.paragraph(l10n.termsS11Body)],
      ),
      SupportSection(
        icon: Icons.update_rounded,
        title: l10n.termsS12Title,
        blocks: [SupportBlock.paragraph(l10n.termsS12Body)],
      ),
    ];

    return SupportScaffold(
      title: l10n.termsOfUse,
      children: [
        SupportHero(
          icon: Icons.gavel_rounded,
          title: l10n.termsOfUse,
          subtitle: l10n.termsHeroSubtitle,
          meta: l10n.supportLastUpdated,
        ),
        SupportDocumentBody(
          accent: accent,
          inShort: [
            l10n.termsInShort1,
            l10n.termsInShort2,
            l10n.termsInShort3,
            l10n.termsInShort4,
          ],
          sections: sections,
        ),
      ],
    );
  }
}
