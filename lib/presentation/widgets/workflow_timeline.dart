import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/quantity_utils.dart';
import '../../data/models/workflow_event_model.dart';

/// The word shown for a history action. The database action words are shared by
/// listings, orders, Market Linking requests and enrollments.
String workflowActionLabel(AppLocalizations l, String action) {
  switch (action) {
    case 'submitted':
      return l.wfActSubmitted;
    case 'approved':
      return l.wfActApproved;
    case 'disapproved':
    case 'rejected':
      return l.wfActDisapproved;
    case 'withdrawn':
      return l.wfActWithdrawn;
    case 'edited':
      return l.wfActEdited;
    case 'edit_requested':
      return l.wfActEditRequested;
    case 'edit_approved':
      return l.wfActEditApproved;
    case 'edit_rejected':
      return l.wfActEditRejected;
    case 'edit_cancelled':
      return l.wfActEditCancelled;
    case 'sold_out':
      return l.wfActSoldOut;
    case 'reopened':
      return l.wfActReopened;
    case 'placed':
      return l.wfActPlaced;
    case 'ready_for_pickup':
      return l.wfActReadyForPickup;
    case 'out_for_delivery':
      return l.wfActOutForDelivery;
    case 'delivered':
      return l.wfActDelivered;
    case 'completed':
      return l.wfActCompleted;
    case 'cancelled':
      return l.wfActCancelled;
    case 'buyer_found':
      return l.wfActBuyerFound;
    case 'buyer_details_saved':
      return l.wfActBuyerDetails;
    case 'sale_recorded':
      return l.wfActSaleRecorded;
    case 'cancellation_requested':
      return l.wfActCancellationRequested;
    case 'cancellation_approved':
      return l.wfActCancellationApproved;
    case 'cancellation_declined':
      return l.wfActCancellationDeclined;
    case 'cancellation_withdrawn':
      return l.wfActCancellationWithdrawn;
    // Loans and loan requests (entity types 'loan' and 'loan_request').
    case 'issued':
      return l.wfActIssued;
    case 'payment_recorded':
      return l.wfActPaymentRecorded;
    case 'overdue':
      return l.wfActOverdue;
    case 'paid':
      return l.wfActPaid;
    default:
      return l.wfActStatusChanged;
  }
}

String workflowRoleLabel(AppLocalizations l, String? role) {
  switch (role) {
    case 'admin':
      return l.wfRoleAdmin;
    case 'officer':
      return l.wfRoleOfficer;
    case 'farmer':
      return l.wfRoleFarmer;
    case 'buyer':
      return l.wfRoleBuyer;
    default:
      return l.wfRoleSystem;
  }
}

/// "Manager Juan Dela Cruz" for the Manager / Officer; "You" / "SP3 Cooperative"
/// for a Farmer, who never sees a staff identity.
String workflowActorLabel(AppLocalizations l, WorkflowEvent e, {required bool staffView}) {
  if (!staffView) {
    switch (e.by) {
      case 'you':
        return l.wfByYou;
      case 'cooperative':
        return l.wfByCooperative;
      default:
        return l.wfBySystem;
    }
  }
  final role = workflowRoleLabel(l, e.actorRole);
  final name = (e.actorName ?? '').trim();
  return name.isEmpty ? role : l.wfActivityBy(role, name);
}

Color workflowActionColor(String action) {
  switch (action) {
    case 'approved':
    case 'edit_approved':
    case 'completed':
    case 'delivered':
    case 'sale_recorded':
    case 'cancellation_approved':
    case 'issued':
    case 'paid':
    case 'payment_recorded':
      return AppConstants.successGreen;
    case 'disapproved':
    case 'rejected':
    case 'edit_rejected':
    case 'cancelled':
    case 'withdrawn':
    case 'cancellation_declined':
    case 'overdue':
      return AppConstants.errorRed;
    case 'edit_requested':
    case 'cancellation_requested':
    case 'submitted':
    case 'placed':
    case 'buyer_found':
      return AppConstants.buyerBlue;
    default:
      return AppConstants.warningAmber;
  }
}

IconData workflowActionIcon(String action) {
  switch (action) {
    case 'approved':
    case 'edit_approved':
    case 'cancellation_approved':
      return Icons.check_circle_rounded;
    case 'disapproved':
    case 'rejected':
    case 'edit_rejected':
    case 'cancellation_declined':
      return Icons.cancel_rounded;
    case 'cancelled':
    case 'edit_cancelled':
    case 'withdrawn':
    case 'cancellation_withdrawn':
      return Icons.remove_circle_rounded;
    case 'edit_requested':
    case 'edited':
      return Icons.edit_rounded;
    case 'completed':
    case 'delivered':
      return Icons.task_alt_rounded;
    case 'sale_recorded':
    case 'payment_recorded':
      return Icons.payments_rounded;
    case 'issued':
    case 'paid':
      return Icons.task_alt_rounded;
    case 'overdue':
      return Icons.warning_amber_rounded;
    case 'ready_for_pickup':
    case 'out_for_delivery':
      return Icons.local_shipping_rounded;
    case 'buyer_found':
    case 'buyer_details_saved':
      return Icons.person_search_rounded;
    default:
      return Icons.fiber_manual_record_rounded;
  }
}

/// The lines under an event: what changed, from the event's details.
List<String> workflowDetailLines(AppLocalizations l, WorkflowEvent e) {
  final d = e.details;
  final unit = d['unit'] as String?;
  num? n(Object? v) => v is num ? v : null;
  final lines = <String>[];

  final changes = d['changes'];
  if (changes is Map) {
    final q = changes['quantity'];
    if (q is Map && n(q['from']) != null && n(q['to']) != null) {
      lines.add(l.wfDetailQuantity(
        formatQuantityUnit(n(q['from'])!, unit),
        formatQuantityUnit(n(q['to'])!, unit),
      ));
    }
    final p = changes['price'];
    if (p is Map && n(p['from']) != null && n(p['to']) != null) {
      lines.add(l.wfDetailPrice(
        formatPricePerUnit(n(p['from'])!, unit),
        formatPricePerUnit(n(p['to'])!, unit),
      ));
    }
    if (changes['description'] is Map) lines.add(l.wfDetailDescription);
    if (changes['photo'] == true) lines.add(l.wfDetailPhoto);
  }

  if (e.action == 'sale_recorded' && n(d['quantity']) != null) {
    lines.add(l.wfDetailSale(
      formatQuantityUnit(n(d['quantity'])!, unit),
      (d['buyer'] as String?) ?? '',
      formatPesos(n(d['total']) ?? 0),
    ));
  }
  if (e.action == 'placed' && n(d['quantity']) != null && n(d['price']) != null) {
    lines.add(l.wfDetailPlaced(
      formatQuantityUnit(n(d['quantity'])!, unit),
      formatPricePerUnit(n(d['price'])!, unit),
    ));
  }
  // Loans and loan requests.
  if (e.action == 'issued' && d['reference'] is String && n(d['total']) != null) {
    lines.add(l.wfDetailLoanIssued(d['reference'] as String, _pesoAmount(n(d['total'])!)));
  }
  if (e.action == 'payment_recorded' && n(d['amount']) != null) {
    lines.add(l.wfDetailLoanPayment(
      _pesoAmount(n(d['amount'])!),
      _pesoAmount(n(d['balance']) ?? 0),
    ));
  }
  if (e.action == 'approved' && d['loan_reference'] is String) {
    lines.add(l.wfDetailLoanFromRequest(
      d['loan_reference'] as String,
      _pesoAmount(n(d['monthly_payment']) ?? 0),
    ));
  }
  return lines;
}

String _pesoAmount(num v) => NumberFormat('#,##0.00').format(v);

/// A vertical history, newest first: what happened, who did it (a name and role
/// for staff; "You" / "SP3 Cooperative" for a Farmer), the reason when there is
/// one, and the time. [staffView] decides how the actor is shown.
class WorkflowTimeline extends StatelessWidget {
  final List<WorkflowEvent> events;
  final bool staffView;
  final String? emptyText;

  const WorkflowTimeline({
    super.key,
    required this.events,
    required this.staffView,
    this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          emptyText ?? l.wfActivityEmpty,
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }
    final sorted = [...events]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final locale = Localizations.localeOf(context).toString();
    final when = DateFormat.yMMMd(locale).add_jm();
    return Column(
      children: [
        for (var i = 0; i < sorted.length; i++)
          _Row(
            event: sorted[i],
            isLast: i == sorted.length - 1,
            actor: workflowActorLabel(l, sorted[i], staffView: staffView),
            title: workflowActionLabel(l, sorted[i].action),
            lines: workflowDetailLines(l, sorted[i]),
            time: when.format(sorted[i].createdAt),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final WorkflowEvent event;
  final bool isLast;
  final String actor;
  final String title;
  final List<String> lines;
  final String time;

  const _Row({
    required this.event,
    required this.isLast,
    required this.actor,
    required this.title,
    required this.lines,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = workflowActionColor(event.action);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(workflowActionIcon(event.action), size: 14, color: color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: cs.outline.withValues(alpha: 0.20),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '$actor · $time',
                    style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        line,
                        style: GoogleFonts.inter(fontSize: 12, color: cs.onSurface),
                      ),
                    ),
                  if ((event.reason ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        event.reason!.trim(),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
