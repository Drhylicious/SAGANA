import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The four screens that used to ask for a single Full Name, and the functions
// they call. The app sends the parts; the database builds the full name.
String _read(String path) => File(path).readAsStringSync();

void main() {
  final sql = _read(
    'supabase_schema/supabase_schema_registration_12_name_components.sql',
  );

  group('every account-creation call sends the name parts, not a full name', () {
    final callers = {
      'Farmer / Buyer registration': 'lib/data/services/auth_service.dart',
      'Manager > Create Farmer Member':
          'lib/data/repositories/add_member_repository.dart',
      'Manager > Create Officer':
          'lib/data/repositories/account_management_repository.dart',
    };
    callers.forEach((label, path) {
      test(label, () {
        final src = _read(path);
        for (final key in [
          "'p_surname'",
          "'p_first_name'",
          "'p_middle_initial'",
          "'p_suffix'",
        ]) {
          expect(src, contains(key), reason: '$path sends $key');
        }
        expect(src, isNot(contains("'p_full_name'")), reason: path);
      });
    });
  });

  group('the screens use the shared name fields', () {
    final screens = {
      'Register': 'lib/presentation/screens/auth/register_screen.dart',
      'Create Farmer Member':
          'lib/presentation/screens/admin/add_new_member_screen.dart',
      'Create Officer':
          'lib/presentation/screens/admin/create_officer_account_screen.dart',
    };
    screens.forEach((label, path) {
      test(label, () {
        final src = _read(path);
        expect(src, contains('PersonNameFields('));
        expect(src, contains('surname:'));
        expect(src, contains('firstName:'));
        expect(src, contains('middleInitial:'));
        expect(src, contains('suffix:'));
        expect(src, isNot(contains('_fullNameCtrl')));
      });
    });

    test('the two Manager forms use the Manager look, sign-up uses its own', () {
      expect(
        _read('lib/presentation/screens/admin/add_new_member_screen.dart'),
        contains('PersonNameFieldsStyle.form'),
      );
      expect(
        _read('lib/presentation/screens/admin/create_officer_account_screen.dart'),
        contains('PersonNameFieldsStyle.form'),
      );
      expect(
        _read('lib/presentation/screens/auth/register_screen.dart'),
        isNot(contains('PersonNameFieldsStyle.form')),
      );
    });
  });

  group('the migration (script 12)', () {
    test('adds the four columns, as separate nullable columns', () {
      for (final col in ['surname', 'first_name', 'middle_initial', 'suffix']) {
        expect(sql, contains('ADD COLUMN IF NOT EXISTS $col'), reason: col);
      }
      // Nullable: no NOT NULL on the new columns, so existing rows stay valid.
      expect(sql, isNot(contains('ADD COLUMN IF NOT EXISTS surname        text NOT NULL')));
    });

    test('does not split or rewrite any existing name', () {
      // The only statements that write the parts are the guarded, commented
      // review steps. Nothing outside comments updates user_information.
      final live = sql
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n');
      expect(live, isNot(contains('UPDATE public.user_information')));
      expect(live, isNot(contains('string_to_array')));
      expect(live, isNot(contains('split_part')));
    });

    test('keeps full_name, built from the parts in one place', () {
      expect(sql, contains('FUNCTION public.compose_full_name('));
      expect(sql, contains('NEW.full_name := public.compose_full_name('));
      // The three functions build v_name through it, never from the client.
      expect('v_name := public.compose_full_name('.allMatches(sql).length, 3);
    });

    test('each function has exactly the new name parameters and no p_full_name', () {
      expect(sql, isNot(contains('p_full_name ')));
      for (final fn in [
        'register_account',
        'create_farmer_account',
        'create_officer_account',
      ]) {
        final start = sql.indexOf('CREATE FUNCTION public.$fn(');
        expect(start, greaterThan(0), reason: fn);
        final header = sql.substring(start, start + 700);
        expect(header, contains('p_surname'), reason: fn);
        expect(header, contains('p_first_name'), reason: fn);
        expect(header, contains('p_middle_initial'), reason: fn);
        expect(header, contains('p_suffix'), reason: fn);
      }
    });

    test('old signatures are dropped and rights are re-granted to signed-in users only', () {
      for (final fn in [
        'register_account',
        'create_farmer_account',
        'create_officer_account',
      ]) {
        expect(sql, contains('DROP FUNCTION IF EXISTS public.$fn('));
        expect(sql, contains('REVOKE ALL ON FUNCTION public.$fn('));
        expect(sql, contains('GRANT EXECUTE ON FUNCTION public.$fn('));
      }
      expect(sql, isNot(contains('TO anon')));
    });

    test('is idempotent on a re-run (new signatures are dropped before created)', () {
      expect(sql, contains('re-run safety'));
      expect('DROP FUNCTION IF EXISTS public.'.allMatches(sql).length, 6);
    });

    test('keeps everything else each function does', () {
      // Spot checks on text carried over unchanged from the earlier scripts.
      expect(sql, contains("'pending'")); // Farmer applications start pending
      expect(sql, contains('issue_member_identifier'));
      expect(sql, contains('must_change_password'));
      expect(sql, contains("'Payanas', 'Torrijos', 'Marinduque', 'MIMAROPA Region', '4903'"));
      expect(sql, contains("v_auth_email IS DISTINCT FROM v_username || '@sagana.local'"));
    });
  });
}
