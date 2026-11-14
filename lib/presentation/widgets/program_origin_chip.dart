import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';

/// A small pill that says a record came from a Cooperative Program ("From Cooperative Program"). It marks
/// only that one record (a harvest entry or a batch of produce), never the Farmer's whole crop.
class ProgramOriginChip extends StatelessWidget {
  const ProgramOriginChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppConstants.buyerBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.volunteer_activism_rounded, size: 11, color: AppConstants.buyerBlue),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppConstants.buyerBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
