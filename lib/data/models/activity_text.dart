import 'package:flutter/widgets.dart' show Locale;

import '../../core/l10n/app_localizations.dart';
import '../services/app_settings_service.dart';
import 'activity_keys_generated.dart';
import 'admin_legacy_generated.dart';
import 'admin_log_message.dart';

/// Bilingual text for Recent Activity. Writers store a stable key plus
/// parameters (message_key / message_params) next to an English copy in
/// `description`. Readers render the key in the current language. Rows written
/// before keys existed are matched back to a key from their English text.

/// Renders any stored activity message in [l].
String renderActivityMessage(AppLocalizations l, AdminLogMessage m) {
  final p = m.params;
  switch (m.key) {
    case 'activityProfileUpdated':
      final labels = (p['fields'] ?? '')
          .split(',')
          .where((code) => code.isNotEmpty)
          .map((code) => activityFieldLabel(l, code) ?? code);
      return l.activityProfileUpdated(labels.join(', '));
    case 'activitySyncedOfflineRecords':
      return l.activitySyncedOfflineRecords;
  }
  return renderGeneratedActivity(l, m.key, p) ??
      renderAdminLogMessage(l, m);
}

/// English copy stored in the legacy `description` column.
String activityEnglish(AdminLogMessage m) =>
    renderActivityMessage(lookupAppLocalizations(const Locale('en')), m);

const _fieldCodeForEnglish = {
  'name': 'name',
  'phone number': 'phone',
  'profile photo': 'photo',
  'email': 'email',
  'date of birth': 'dob',
  'gender': 'gender',
  'farm name': 'farmName',
  'farm address': 'farmAddress',
  'farm location': 'farmLocation',
  'farm details': 'farmDetails',
  'land area': 'landArea',
  'ownership type': 'ownership',
  'soil type': 'soil',
  'water source': 'water',
  'years farming': 'years',
};

/// Recovers a key from a profile/crop/address/home activity description written
/// before keys existed. Null when the text isn't one of the known sentences.
AdminLogMessage? parseLegacyActivity(String text) {
  var m = RegExp(r'^Updated photo for (.+)$').firstMatch(text);
  if (m != null) {
    return AdminLogMessage('activityCropPhotoUpdated', {'crop': m.group(1)!});
  }
  if (text == 'Updated profile photo') {
    return const AdminLogMessage('activityProfilePhotoUpdated');
  }
  m = RegExp(r'^Updated address \((.+)\)$').firstMatch(text);
  if (m != null) {
    return AdminLogMessage('activityAddressUpdated', {'label': m.group(1)!});
  }
  m = RegExp(r'^Added address \((.+)\)$').firstMatch(text);
  if (m != null) {
    return AdminLogMessage('activityAddressAdded', {'label': m.group(1)!});
  }
  m = RegExp(r'^Deleted address \((.+)\)$').firstMatch(text);
  if (m != null) {
    return AdminLogMessage('activityAddressDeleted', {'label': m.group(1)!});
  }
  m = RegExp(r'^Set "(.+)" as default address$').firstMatch(text);
  if (m != null) {
    return AdminLogMessage('activityAddressDefault', {'label': m.group(1)!});
  }
  if (text == 'Changed password') {
    return const AdminLogMessage('activityPasswordChanged');
  }
  if (text == 'Cancelled program purchase request') {
    return const AdminLogMessage('activityProgramPurchaseCancelled');
  }
  if (text == 'Synced offline records') {
    return const AdminLogMessage('activitySyncedOfflineRecords');
  }
  m = RegExp(r'^Updated (.+)$').firstMatch(text);
  if (m != null) {
    final codes = <String>[];
    for (final label in m.group(1)!.split(', ')) {
      final code = _fieldCodeForEnglish[label];
      if (code == null) return null;
      codes.add(code);
    }
    return AdminLogMessage('activityProfileUpdated', {'fields': codes.join(',')});
  }
  return null;
}

/// Columns every activity writer inserts. Only the English copy is stored;
/// readers recover the key from it (see parseLegacyActivity), so no extra
/// columns are needed.
Map<String, Object?> activityRowFields(AdminLogMessage m) => {
      'description': activityEnglish(m),
    };

Map<String, String> _paramsOf(Object? raw) {
  if (raw is! Map) return const {};
  return raw.map((k, v) => MapEntry('$k', '$v'));
}

/// The key and parameters for a row, from its stored key or, for legacy rows,
/// from its English description. Null when neither identifies a message.
AdminLogMessage? activityMessageForRow(
  Map row, {
  required AdminLogMessage? Function(String) legacy,
}) {
  final key = row['message_key'] as String?;
  if (key != null) return AdminLogMessage(key, _paramsOf(row['message_params']));
  return legacy(row['description'] as String? ?? '');
}

/// Text for a profile/crop/address/home activity row in the current language.
String localizeActivityRow(Map row) {
  final l = lookupAppLocalizations(AppSettingsService.instance.locale);
  final message = activityMessageForRow(row, legacy: parseLegacyActivity);
  if (message != null) return renderActivityMessage(l, message);
  return row['description'] as String? ?? '';
}

/// Text for an admin_activity_log row in the current language.
String localizeAdminLogRow(Map row) {
  final l = lookupAppLocalizations(AppSettingsService.instance.locale);
  final message = activityMessageForRow(row, legacy: parseLegacyAdminLog);
  if (message != null) return renderActivityMessage(l, message);
  return row['description'] as String? ?? '';
}

/// Key for a row (or null for legacy rows that don't match a key). Used where
/// the UI branches on the kind of entry rather than its text.
String? activityKeyForRow(Map row, {required bool admin}) {
  final message = activityMessageForRow(
    row,
    legacy: admin ? parseLegacyAdminLog : parseLegacyActivity,
  );
  return message?.key;
}
