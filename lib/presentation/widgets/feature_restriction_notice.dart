import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/utils/app_utils.dart';
import '../../data/models/member_restriction.dart';
import '../../data/models/suspension_reasons.dart';
import '../../data/services/feature_restriction_service.dart';
import '../../routes/app_routes.dart';
import 'app_dialog.dart';
import 'shared_widgets.dart';

/// The one question every "start something new" button asks first: is this feature
/// restricted for the signed-in Farmer?
///
/// Returns true when the action may go ahead. When it is restricted it shows the
/// short notice (what, why, until when) and returns false. The list is refreshed
/// first, so a restriction applied a moment ago is respected; offline it uses what
/// it last knew. The database refuses a restricted action either way, so this is
/// only the friendly part.
Future<bool> ensureFeatureAvailable(
  BuildContext context,
  RestrictableFeature feature,
) async {
  final service = FeatureRestrictionService.instance;
  await service.refresh();
  if (!context.mounted) return false;
  final restriction = service.of(feature);
  if (restriction == null) return true;
  await showFeatureRestrictedNotice(context, restriction);
  return false;
}

/// "Requesting a loan is restricted" with the reason and the end date, and a way
/// to the Farmer's full list.
Future<void> showFeatureRestrictedNotice(
  BuildContext context,
  MyRestriction restriction,
) async {
  final l10n = AppLocalizations.of(context);
  final router = GoRouter.of(context);
  final goToDetails = await AppDialog.show<bool>(
    context: context,
    child: ConfirmDialog(
      title: l10n.restrictedNoticeTitle(restriction.feature.label(l10n)),
      message: '${restrictionReasonText(l10n, restriction.reason)}\n'
          '${restrictionUntilText(l10n, restriction.endsAt)}',
      confirmLabel: l10n.restrictedNoticeView,
      cancelLabel: l10n.restrictedNoticeOk,
    ),
  );
  if (goToDetails == true) router.push(AppRoutes.myRestrictions);
}

/// The reason in the Farmer's language (the stored text is the canonical English
/// wording of an approved reason, or the staff member's own words for "Other").
String restrictionReasonText(AppLocalizations l10n, String stored) =>
    localizedSuspensionReason(l10n, stored.trim());

/// "Until Dec 5, 2026" or "Until lifted by the cooperative".
String restrictionUntilText(AppLocalizations l10n, DateTime? endsAt) =>
    endsAt == null
    ? l10n.restrictUntilLifted
    : l10n.restrictedNoticeUntil(AppUtils.formatDate(endsAt, l10n.localeName));
