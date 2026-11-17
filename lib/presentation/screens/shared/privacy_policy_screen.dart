import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../widgets/support_info_widgets.dart';

/// Privacy Policy — shared by every role and by guests.
///
/// Each statement here describes something SAGANA actually does today (what the
/// registration and profile screens collect, the services the app calls, what is
/// stored on the device). When a feature changes, update the matching section and
/// the strings in app_en.arb / app_tl.arb together.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const accent = AppConstants.amber;

    final sections = <SupportSection>[
      SupportSection(
        icon: Icons.people_alt_rounded,
        title: l10n.privS1Title,
        blocks: [SupportBlock.paragraph(l10n.privS1Body)],
      ),
      SupportSection(
        icon: Icons.assignment_ind_rounded,
        title: l10n.privS2Title,
        blocks: [
          SupportBlock.labeled([
            (l10n.supportLblAllAccounts, l10n.privS2All),
            (l10n.supportLblBuyers, l10n.privS2Buyers),
            (l10n.supportLblFarmers, l10n.privS2Farmers),
            (l10n.supportLblStaff, l10n.privS2Staff),
          ]),
          SupportBlock.note(l10n.privS2Note),
        ],
      ),
      SupportSection(
        icon: Icons.photo_camera_rounded,
        title: l10n.privS3Title,
        blocks: [SupportBlock.bullets([l10n.privS3B1, l10n.privS3B2])],
      ),
      SupportSection(
        icon: Icons.history_rounded,
        title: l10n.privS4Title,
        blocks: [
          SupportBlock.bullets([
            l10n.privS4B1,
            l10n.privS4B2,
            l10n.privS4B3,
            l10n.privS4B4,
          ]),
        ],
      ),
      SupportSection(
        icon: Icons.tune_rounded,
        title: l10n.privS5Title,
        blocks: [
          SupportBlock.bullets([
            l10n.privS5B1,
            l10n.privS5B2,
            l10n.privS5B3,
            l10n.privS5B4,
            l10n.privS5B5,
            l10n.privS5B6,
          ]),
        ],
      ),
      SupportSection(
        icon: Icons.visibility_rounded,
        title: l10n.privS6Title,
        blocks: [
          SupportBlock.paragraph(l10n.privS6Body),
          SupportBlock.labeled([
            (l10n.supportLblYou, l10n.privS6You),
            (l10n.supportLblManager, l10n.privS6Manager),
            (l10n.supportLblOfficers, l10n.privS6Officers),
            (l10n.supportLblOthers, l10n.privS6Others),
            (l10n.supportLblGuests, l10n.privS6Guests),
          ]),
        ],
      ),
      SupportSection(
        icon: Icons.cloud_rounded,
        title: l10n.privS7Title,
        blocks: [
          SupportBlock.bullets([
            l10n.privS7B1,
            l10n.privS7B2,
            l10n.privS7B3,
            l10n.privS7B4,
          ]),
          SupportBlock.note(l10n.privS7Note),
        ],
      ),
      SupportSection(
        icon: Icons.smartphone_rounded,
        title: l10n.privS8Title,
        blocks: [SupportBlock.bullets([l10n.privS8B1, l10n.privS8B2])],
      ),
      SupportSection(
        icon: Icons.lock_rounded,
        title: l10n.privS9Title,
        blocks: [
          SupportBlock.bullets([
            l10n.privS9B1,
            l10n.privS9B2,
            l10n.privS9B3,
            l10n.privS9B4,
          ]),
        ],
      ),
      SupportSection(
        icon: Icons.settings_rounded,
        title: l10n.privS10Title,
        blocks: [
          SupportBlock.bullets([
            l10n.privS10B1,
            l10n.privS10B2,
            l10n.privS10B3,
            l10n.privS10B4,
          ]),
        ],
      ),
      SupportSection(
        icon: Icons.explore_rounded,
        title: l10n.privS11Title,
        blocks: [SupportBlock.paragraph(l10n.privS11Body)],
      ),
      SupportSection(
        icon: Icons.update_rounded,
        title: l10n.privS12Title,
        blocks: [SupportBlock.paragraph(l10n.privS12Body)],
      ),
    ];

    return SupportScaffold(
      title: l10n.privacyPolicy,
      children: [
        SupportHero(
          icon: Icons.privacy_tip_rounded,
          title: l10n.privacyPolicy,
          subtitle: l10n.privHeroSubtitle,
          meta: l10n.supportLastUpdated,
        ),
        SupportDocumentBody(
          accent: accent,
          inShort: [
            l10n.privInShort1,
            l10n.privInShort2,
            l10n.privInShort3,
            l10n.privInShort4,
          ],
          sections: sections,
        ),
      ],
    );
  }
}
