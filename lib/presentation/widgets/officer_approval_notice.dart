import 'package:flutter/material.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/services/hive_service.dart';
import 'app_dialog.dart';
import 'shared_widgets.dart';

/// Step before an account is created. When an OFFICER creates a Farmer account,
/// they must confirm that it goes to the Manager as a pending applicant and
/// cannot use Farmer features until the Manager approves it. The Manager's own
/// accounts are active at once, so no question is asked. (An Officer cannot
/// create an Officer account at all.)
///
/// Returns true to go ahead. (The pending status is applied by the database, not
/// by this dialog.)
Future<bool> confirmOfficerSubmission(BuildContext context) async {
  if (!HiveService.isOfficer) return true;
  final l10n = AppLocalizations.of(context);
  final confirmed = await AppDialog.show<bool>(
    context: context,
    child: ConfirmDialog(
      title: l10n.createAccountSubmitTitle,
      message: l10n.createAccountSubmitBody,
      confirmLabel: l10n.createAccountSubmitConfirm,
      cancelLabel: l10n.cancel,
    ),
  );
  return confirmed == true;
}

/// The message shown after the account was created: the Manager's account is
/// ready; an Officer's is waiting for approval.
String accountCreatedMessage(AppLocalizations l10n, String readyMessage) =>
    HiveService.isOfficer ? l10n.createAccountSubmitted : readyMessage;
