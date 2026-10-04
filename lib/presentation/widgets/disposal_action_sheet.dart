import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
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
  required bool isCoopEligible,
  required String? cropType,
}) {
  return showManagementModal<DisposalAction>(
    context: context,
    builder: (_) => _DisposalActionSheet(
      cropName: cropName,
      availableKg: availableKg,
      isCoopEligible: isCoopEligible,
      cropType: cropType,
    ),
  );
}

class _DisposalActionSheet extends StatelessWidget {
  final String cropName;
  final double availableKg;
  final bool isCoopEligible;
  final String? cropType;

  const _DisposalActionSheet({
    required this.cropName,
    required this.availableKg,
    required this.isCoopEligible,
    required this.cropType,
  });

  // Ginger is DA-AMAD-exclusive — it can only ever move through Market
  // Linking, never the open Marketplace, Offer to Cooperative, or an
  // informal sale. Keyed off the batch's denormalized crop_type (set at
  // harvest time from crop_master.crop_type — see
  // supabase_schema_harvest_market_type_persistence.sql), matching the
  // same crop_type-based check market_linking_repository.dart already
  // uses. Previously a crop-name substring match ('ginger'.contains) —
  // fragile in both directions: it would misclassify any future crop
  // whose name happens to contain "ginger", and would miss a DA-AMAD
  // crop that doesn't literally have that name.
  bool get _isDaAmadExclusive => cropType == 'da_amad_market';

  @override
  Widget build(BuildContext context) {
    if (_isDaAmadExclusive) {
      return ManagementModalShell(
        title: '$cropName • ${availableKg.toStringAsFixed(0)} kg available',
        subtitle: 'What would you like to do with this batch?',
        body: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ginger is sold exclusively through the DA-AMAD Market Linking '
              'program, not the open Marketplace, Offer to Cooperative, or an '
              'informal sale. Check My Market Linking for this batch\'s status.',
              style: TextStyle(fontSize: 13, color: AppConstants.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ManagementModalShell(
      title: '$cropName • ${availableKg.toStringAsFixed(0)} kg available',
      subtitle: 'What would you like to do with this batch?',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DisposalOptionTile(
            icon: Icons.storefront_outlined,
            iconColor: AppConstants.buyerBlue,
            title: 'Sell through Marketplace',
            subtitle: 'List for public buyers to purchase',
            onTap: () => Navigator.pop(context, DisposalAction.marketplace),
          ),
          if (isCoopEligible)
            _DisposalOptionTile(
              icon: Icons.groups_outlined,
              iconColor: AppConstants.primaryGreen,
              title: 'Offer to Cooperative',
              subtitle: 'SP3 confirms the exact quantity and price at pickup',
              onTap: () => Navigator.pop(context, DisposalAction.cooperative),
            ),
          _DisposalOptionTile(
            icon: Icons.handshake_outlined,
            iconColor: AppConstants.amber,
            title: 'Record Informal Sale',
            subtitle: 'For cash sales or off-app buyers',
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
      title: Text(title,
          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppConstants.outline),
    );
  }
}