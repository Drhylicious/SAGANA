import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';

// Small pieces shared by the Farmer's Edit Listing screen, the Manager's Pending
// Approvals list and the edit-request review screen.

String editRequestStatusLabel(AppLocalizations l, String status) {
  switch (status) {
    case 'approved':
      return l.listingStateApproved;
    case 'rejected':
      return l.listingStateDisapproved;
    case 'cancelled':
      return l.leStatusCancelled;
    default:
      return l.listingFilterPending;
  }
}

Color editRequestStatusColor(String status) {
  switch (status) {
    case 'approved':
      return AppConstants.successGreen;
    case 'rejected':
      return AppConstants.errorRed;
    case 'cancelled':
      return AppConstants.mutedSlate;
    default:
      return AppConstants.warningAmber;
  }
}

class EditRequestStatusChip extends StatelessWidget {
  final String status;
  const EditRequestStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = editRequestStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        editRequestStatusLabel(AppLocalizations.of(context), status),
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class EditRequestNotice extends StatelessWidget {
  final String text;
  const EditRequestNotice({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.buyerBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppConstants.buyerBlue.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppConstants.buyerBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
