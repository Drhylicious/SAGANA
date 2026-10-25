import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level checks that every place a name is entered or edited uses the
/// separated fields (Surname, First Name, M.I., Suffix) and saves the parts, and
/// that the complete name is only built for display. Mutation-tested: each
/// expectation fails if the matching line is reverted.
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  const editScreens = {
    'Farmer Edit Profile': 'lib/presentation/screens/farmer/farmer_edit_profile_screen.dart',
    'Buyer Edit Profile': 'lib/presentation/screens/buyer/buyer_edit_profile_screen.dart',
    'Manager / Officer Edit Profile': 'lib/presentation/screens/admin/admin_edit_profile_screen.dart',
  };

  group('Edit Profile screens', () {
    for (final e in editScreens.entries) {
      test('${e.key}: separated fields, parts saved, no single Full Name input', () {
        final src = _read(e.value);
        expect(src, contains('PersonNameFields('));
        expect(src, contains('PersonNameFieldsStyle.profile'));
        expect(src, contains('name: _name.parts'));
        // Surname and first name are validated on the fields.
        expect(src, contains('_nameFormKey.currentState?.validate()'));
        // An account with no parts yet can still save its other fields.
        expect(src, contains('allowAllBlank: _name.legacyFullName != null'));
        // No single name controller or Full Name field is left.
        expect(src, isNot(contains('_nameController')));
        expect(src, isNot(contains('l10n.fullName')));
        expect(src, isNot(contains('adminProfileFullName')));
        // The old full-name argument is gone.
        expect(src, isNot(contains('fullName: _')));
      });
    }
  });

  test('Pending Applicant "Review & Edit Details": the same fields, and it saves the parts', () {
    final src = _read('lib/presentation/screens/farmer/pending_review_details_screen.dart');
    expect(src, contains('PersonNameFields('));
    expect(src, contains('name: _name.parts'));
    expect(src, isNot(contains('_nameCtrl')));
    // The read-only view still shows the complete name (display only).
    expect(src, contains('l10n.pendingFullNameLabel, p?.fullName'));
  });

  group('Repositories save the parts, never a typed full name', () {
    test('Farmer: Edit Profile and Pending Applicant', () {
      final src = _read('lib/data/repositories/farmer_profile_repository.dart');
      expect(src, contains('if (name != null) ...name.toColumns()'));
      expect(src, contains("'name': name?.toColumns()"));
      // updateApplicantDetails no longer takes or writes a full name.
      final applicant = src.substring(
        src.indexOf('Future<void> updateApplicantDetails'),
        src.indexOf('// ─── Update basic info'),
      );
      expect(applicant, isNot(contains("'full_name':")));
      expect(applicant, contains('...name.toColumns()'));
    });

    test('Buyer', () {
      final src = _read('lib/data/repositories/buyer_profile_repository.dart');
      expect(src, contains('if (name != null) ...name.toColumns()'));
      expect(src, contains("'name': name?.toColumns()"));
      expect(src, contains("surname: info?['surname'] as String?"));
    });

    test('Manager / Officer', () {
      final src = _read('lib/data/repositories/admin_profile_repository.dart');
      expect(src, contains('if (name != null) ...name.toColumns()'));
      expect(src, contains("'name': name?.toColumns()"));
      expect(src, contains("surname: infoRow['surname'] as String?"));
    });

    test('a queued save replays with the parts (and an old queued full name still works)', () {
      final src = _read('lib/data/services/offline_action_replay.dart');
      expect(
        RegExp(r"name: NameParts\.fromRow\(p\['name'\] as Map\?\)").allMatches(src).length,
        3,
        reason: 'farmer, buyer and admin replays',
      );
      expect(
        RegExp(r"fullName: p\['fullName'\] as String\?").allMatches(src).length,
        3,
      );
    });

    test('the profile reads load every column, so an older database still opens the screen', () {
      expect(_read('lib/data/repositories/buyer_profile_repository.dart'), contains('.select()'));
      expect(_read('lib/data/repositories/admin_profile_repository.dart'), contains('.select()'));
    });
  });

  group('Every entry point uses the same fields', () {
    const entry = {
      'Register': 'lib/presentation/screens/auth/register_screen.dart',
      'Create Farmer Member': 'lib/presentation/screens/admin/add_new_member_screen.dart',
      'Create Officer': 'lib/presentation/screens/admin/create_officer_account_screen.dart',
      'Pending Applicant details': 'lib/presentation/screens/farmer/pending_review_details_screen.dart',
      ...editScreens,
    };
    for (final e in entry.entries) {
      test(e.key, () => expect(_read(e.value), contains('PersonNameFields(')));
    }
  });

  group('The database rebuilds the complete name from the parts on UPDATE', () {
    final sql = _read('supabase_schema/supabase_schema_registration_12_name_components.sql');
    test('parts changed -> validated and full_name recomposed', () {
      expect(sql, contains('-- Parts given or changed.'));
      expect(sql, contains('NEW.full_name := public.compose_full_name('));
    });
    test('trigger fires on UPDATE, not only INSERT', () {
      expect(sql, contains('BEFORE INSERT OR UPDATE ON public.user_information'));
    });
    test('a lone full_name edit clears the parts so the two can never disagree', () {
      expect(sql, contains('NEW.surname        := NULL;'));
    });
  });
}
