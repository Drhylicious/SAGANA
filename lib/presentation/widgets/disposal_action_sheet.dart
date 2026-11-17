import '../../core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/quantity_utils.dart';
import 'management_modal.dart';
import 'material_list_tile.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DisposalActionSheet
// Shown from Inventory when a farmer decides what to do with a batch.
// Pure selection UI — the calling screen decides what happens next for
// each choice, so this stays reusable if another screen ever needs the
// same "pick one of a few labeled actions" modal.
//
// Rebuilt on ManagementModalShell (centered dialog) instead of
// showModalBottomSheet, matching the rest of the admin management-module
// interactions.
// ─────────────────────────────────────────────────────────────────────────────

enum DisposalAction { marketplace, cooperative, informal }

Future<DisposalAction?> showDisposalActionSheet(
  BuildContext context, {
  required String cropName,
  required double availableKg,
  String unit = kDefaultUnit,
  required bool isCoopEligible,
  required String? exclusiveChannel,
}) {
  return showManagementModal<DisposalAction>(
    context: context,
    builder: (_) => _DisposalActionSheet(
      cropName: cropName,
      availableKg: availableKg,
      unit: unit,
      isCoopEligible: isCoopEligible,
      exclusiveChannel: exclusiveChannel,
    ),
  );
}

class _DisposalActionSheet extends StatelessWidget {
  final String cropName;
  final double availableKg;
  final String unit;
  final bool isCoopEligible;
  final String? exclusiveChannel;

  const _DisposalActionSheet({
    required this.cropName,
    required this.availableKg,
    required this.unit,
    required this.isCoopEligible,
    required this.exclusiveChannel,
  });

  // A crop reserved for one selling channel (Ginger → DA-AMAD Market Linking)
  // can only ever move through that channel — never the Marketplace, Offer to
  // Cooperative or an Informal Sale. Read from the batch's exclusive_channel
  // (copied from the crop's own setting in the database), not from the crop's
  // name or its market type. The database enforces the same rule
  // (enforce_selling_channel); this just avoids offering a choice that would
  // be refused.
  bool get _isDaAmadExclusive => exclusiveChannel != null;

  @override
  Widget build(BuildContext context) {
    if (_isDaAmadExclusive) {
      return ManagementModalShell(
        title: AppLocalizations.of(context).enhAvailable494(
          (cropName).toString(),
          (formatQuantityUnit(availableKg, unit)).toString(),
        ),
        subtitle: AppLocalizations.of(
          context,
        ).enhWhatWouldYouLikeToDoWithThis495,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(
                context,
              ).enhGingerIsSoldExclusivelyThroughTheDAAMAD,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ManagementModalShell(
      title: AppLocalizations.of(context).enhAvailable494(
        (cropName).toString(),
        (formatQuantityUnit(availableKg, unit)).toString(),
      ),
      subtitle: AppLocalizations.of(context).enhWhatWouldYouLikeToDoWithThis495,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DisposalOptionTile(
            icon: Icons.storefront_outlined,
            iconColor: AppConstants.buyerBlue,
            title: AppLocalizations.of(context).enhSellThroughMarketplace,
            subtitle: AppLocalizations.of(
              context,
            ).enhListForPublicBuyersToPurchase,
            onTap: () => Navigator.pop(context, DisposalAction.marketplace),
          ),
          if (isCoopEligible)
            _DisposalOptionTile(
              icon: Icons.groups_outlined,
              iconColor: Theme.of(context).colorScheme.primary,
              title: AppLocalizations.of(context).sellingTypeOfferToCooperative,
              subtitle: AppLocalizations.of(
                context,
              ).enhSPConfirmsTheExactQuantityAndPriceAt,
              onTap: () => Navigator.pop(context, DisposalAction.cooperative),
            ),
          _DisposalOptionTile(
            icon: Icons.handshake_outlined,
            iconColor: AppConstants.amber,
            title: AppLocalizations.of(context).enhRecordInformalSale,
            subtitle: AppLocalizations.of(
              context,
            ).enhForCashSalesOrOffAppBuyers,
            onTap: () => Navigator.pop(context, DisposalAction.informal),
          ),
        ],
      ),
    );
  }
}

class _DisposalOptionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DisposalOptionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}
