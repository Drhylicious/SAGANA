import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/data/models/activity_text.dart';
import 'package:sagana/data/models/admin_legacy_generated.dart';
import 'package:sagana/data/models/admin_log_message.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final tl = lookupAppLocalizations(const Locale('tl'));

  group('legacy English rows map back to keys', () {
    test('profile update lists field names', () {
      final m = parseLegacyActivity('Updated name, phone number');
      expect(m?.key, 'activityProfileUpdated');
      expect(m?.params['fields'], 'name,phone');
    });

    test('address and password sentences', () {
      expect(parseLegacyActivity('Added address (Home)')?.key, 'activityAddressAdded');
      expect(parseLegacyActivity('Added address (Home)')?.params['label'], 'Home');
      expect(parseLegacyActivity('Changed password')?.key, 'activityPasswordChanged');
      expect(parseLegacyActivity('Set "Farm" as default address')?.params['label'], 'Farm');
    });

    test('crop photo is not mistaken for a profile photo', () {
      expect(parseLegacyActivity('Updated photo for Rice')?.key, 'activityCropPhotoUpdated');
      expect(parseLegacyActivity('Updated profile photo')?.key, 'activityProfilePhotoUpdated');
    });

    test('unknown sentences are not matched', () {
      expect(parseLegacyActivity('Something else entirely'), isNull);
      expect(parseLegacyAdminLog('Something else entirely'), isNull);
    });

    test('admin log templates with parameters', () {
      final m = parseLegacyAdminLog('Added "Juan Dela Cruz" as a new member.');
      expect(m?.key, 'adminLogMemberAdded');
      expect(m?.params['fullName'], 'Juan Dela Cruz');
    });

    test('admin log plural templates', () {
      final m = parseLegacyAdminLog('Broadcast "Pulong" sent to 1 recipient.');
      expect(m?.key, 'adminLogBroadcastSent');
      expect(m?.params['count'], '1');
      expect(parseLegacyAdminLog('Generated a PDF export (3 reports).')?.params['count'], '3');
    });
  });

  group('rendering follows the language', () {
    test('a keyed admin entry renders in Tagalog and English', () {
      const m = AdminLogMessage('adminLogMemberAdded', {'fullName': 'Juan'});
      expect(renderActivityMessage(en, m), 'Added "Juan" as a new member.');
      expect(renderActivityMessage(tl, m), isNot(equals(renderActivityMessage(en, m))));
    });

    test('profile field names are translated inside the sentence', () {
      const m = AdminLogMessage('activityProfileUpdated', {'fields': 'name,phone'});
      expect(renderActivityMessage(en, m), 'Updated name, phone number');
      final inTagalog = renderActivityMessage(tl, m);
      expect(inTagalog, isNot(contains('phone number')));
      expect(inTagalog, contains('numero ng telepono'));
    });

    test('legacy rows still display their English text in English', () {
      final m = parseLegacyActivity('Changed password')!;
      expect(activityEnglish(m), 'Changed password');
    });
  });
}
