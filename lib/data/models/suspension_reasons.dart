import '../../core/l10n/app_localizations.dart';

/// One approved suspension reason. [text] is the canonical English wording
/// that gets stored in user_roles.suspension_reason; [label] is the localized
/// wording shown in the dropdown and on the red notice.
class SuspensionReason {
  final String text;
  final String Function(AppLocalizations l10n) label;

  const SuspensionReason({required this.text, required this.label});
}

/// Approved reason lists, exactly as agreed. "Other" is not in these lists:
/// it is offered separately, last, and opens a text field.
final List<SuspensionReason> farmerSuspensionReasons = [
  SuspensionReason(
    text: 'Unpaid or repeatedly missed loan payments',
    label: (l) => l.suspendReasonFarmerLoan,
  ),
  SuspensionReason(
    text: 'Breach of cooperative bylaws or policies',
    label: (l) => l.suspendReasonFarmerBylaws,
  ),
  SuspensionReason(
    text: 'False or misleading membership information',
    label: (l) => l.suspendReasonFarmerFalseInfo,
  ),
  SuspensionReason(
    text: 'Misuse of cooperative programmes or distributed inputs',
    label: (l) => l.suspendReasonFarmerPrograms,
  ),
  SuspensionReason(
    text: 'Diverting cooperative stock or produce outside agreed channels',
    label: (l) => l.suspendReasonFarmerDiversion,
  ),
  SuspensionReason(
    text: 'Unresolved capital or payout obligations',
    label: (l) => l.suspendReasonFarmerCapital,
  ),
  SuspensionReason(
    text: 'Fraudulent use of the account or identity',
    label: (l) => l.suspendReasonFarmerFraud,
  ),
  SuspensionReason(
    text: 'Abusive conduct toward staff or members',
    label: (l) => l.suspendReasonFarmerAbuse,
  ),
];

final List<SuspensionReason> buyerSuspensionReasons = [
  SuspensionReason(
    text: 'Repeated failure to pick up or pay for orders',
    label: (l) => l.suspendReasonBuyerPickup,
  ),
  SuspensionReason(
    text: 'Fraudulent or false orders',
    label: (l) => l.suspendReasonBuyerFakeOrders,
  ),
  SuspensionReason(
    text: 'Abusive conduct toward farmers or staff',
    label: (l) => l.suspendReasonBuyerAbuse,
  ),
  SuspensionReason(
    text: 'Misuse of the buyer account or identity',
    label: (l) => l.suspendReasonBuyerIdentity,
  ),
  SuspensionReason(
    text: 'Breach of marketplace terms',
    label: (l) => l.suspendReasonBuyerTerms,
  ),
  SuspensionReason(
    text: 'Unresolved payment disputes',
    label: (l) => l.suspendReasonBuyerDisputes,
  ),
];

/// Reason list for a role: 'buyer' gets buyer reasons, everything else
/// (farmer) gets farmer reasons.
List<SuspensionReason> suspensionReasonsFor(String role) =>
    role == 'buyer' ? buyerSuspensionReasons : farmerSuspensionReasons;

/// Shows a stored reason in the admin's language when it is one of the
/// approved reasons, and as typed when it is a custom "Other" reason.
String localizedSuspensionReason(AppLocalizations l10n, String stored) {
  for (final r in [...farmerSuspensionReasons, ...buyerSuspensionReasons]) {
    if (r.text == stored) return r.label(l10n);
  }
  return stored;
}
