import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/models/buyer_profile_model.dart';

/// What a Buyer's account is, for the Manager.
///
/// A Buyer is Active or Inactive, nothing else. Inactive is derived: an
/// Active account with no activity for more than 30 days
/// ([BuyerProfileModel.inactiveAfter]). Never stored, never blocks login.
enum BuyerStatus { active, inactive }

BuyerStatus buyerStatusOf(BuyerProfileModel buyer, {DateTime? now}) {
  if (buyer.isInactiveAt(now ?? DateTime.now())) return BuyerStatus.inactive;
  return BuyerStatus.active;
}

String buyerStatusLabel(AppLocalizations l10n, BuyerStatus status) {
  switch (status) {
    case BuyerStatus.active:
      return l10n.farmerMgmtStatusActiveLabel;
    case BuyerStatus.inactive:
      return l10n.analyticsInactive;
  }
}

/// Same colours as Members (farmer_management_screen.dart): Active green,
/// Inactive grey.
Color buyerStatusColor(BuildContext context, BuyerStatus status) {
  switch (status) {
    case BuyerStatus.active:
      return AppConstants.successGreen;
    case BuyerStatus.inactive:
      return Theme.of(context).colorScheme.outline;
  }
}

/// Status pill: a dot and the word, in the status colour.
class BuyerStatusBadge extends StatelessWidget {
  final BuyerStatus status;
  final bool large;

  const BuyerStatusBadge({super.key, required this.status, this.large = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = buyerStatusColor(context, status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 8,
        vertical: large ? 5 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: large ? 8 : 6,
            height: large ? 8 : 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: large ? 7 : 5),
          Flexible(
            child: Text(
              buyerStatusLabel(l10n, status),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: large ? 12 : 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
