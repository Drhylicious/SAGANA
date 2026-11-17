import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../core/utils/quantity_utils.dart';
import '../../data/models/program_assistance_model.dart';

/// An approved assistance request as it reads in Loan History, laid out like a loan record (reference, items,
/// figures) so the two sit together. It is NOT a loan: there is no value, no payment, no due date and no balance,
/// and the card says so ("Repayment: None"). Display only: nothing on it can be tapped.
///
/// [showFarmer] adds the avatar and name (the Manager's lists across all Farmers); inside one Farmer's own history
/// the name is left out, like the loan cards there.
class AssistanceRecordCard extends StatelessWidget {
  final AssistanceRequest request;
  final bool showFarmer;

  const AssistanceRecordCard({
    super.key,
    required this.request,
    this.showFarmer = false,
  });

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final r = request;
    final approvedOn = DateFormat('MMM d, yyyy').format(r.reviewedAt ?? r.createdAt);
    // The approval reference is the record's number; the request number is shown only if there is no reference yet.
    final reference = (r.assistanceReference ?? '').isNotEmpty ? r.assistanceReference! : r.requestNumber;
    final name = (r.farmerName ?? '').trim();
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppConstants.programPurple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        l10n.loanHistoryFilterAssistance.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: AppConstants.programPurple,
        ),
      ),
    );

    Widget figure(String label, String value, {bool alignEnd = false}) => Expanded(
      child: Column(
        crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
        ],
      ),
    );

    return Container(
      key: Key('assistanceRecord_${r.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.programPurple.withValues(alpha: 0.30)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showFarmer && name.isNotEmpty) ...[
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppConstants.primaryGreen,
                  child: Text(
                    _initials(name),
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showFarmer && name.isNotEmpty ? name : reference,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface),
                    ),
                    Text(
                      showFarmer && name.isNotEmpty ? reference : l10n.assistRecordApprovedOn(approvedOn),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              pill,
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final i in r.items)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: context
                        .adaptiveSurface(const Color(0xFFE6F2F8))
                        .withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull,
                    ),
                  ),
                  child: Text(
                    '${formatQuantity(i.quantity)} ${i.unit} ${i.itemName}',
                    style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              figure(l10n.assistRecordItems, '${r.items.length}'),
              figure(l10n.assistRecordApproved, approvedOn),
              figure(l10n.assistRecordRepayment, l10n.assistRecordNone, alignEnd: true),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.volunteer_activism_rounded, size: 14, color: AppConstants.programPurple),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  (r.programName ?? '').isEmpty
                      ? l10n.assistFromProgram
                      : l10n.assistFromProgramNamed(r.programName!),
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.programPurple,
                  ),
                ),
              ),
            ],
          ),
          if ((r.message ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.message!,
              style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
