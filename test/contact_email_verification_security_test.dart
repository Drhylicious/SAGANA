import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level checks of the verification design: who may call what, that the
/// code never reaches the app, and that sign-in is left alone. (The behaviour of
/// the SQL itself was run against an in-memory Postgres; these keep it from
/// being quietly weakened later.)
String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _fn(String sql, String name) {
  final a = sql.indexOf('FUNCTION public.$name');
  expect(a, isNonNegative, reason: name);
  // A function body ends at the closing dollar-quote line.
  return sql.substring(a, sql.indexOf(r'$$;', a) + 3);
}

void main() {
  final sql = _read('supabase_schema/supabase_schema_registration_18_contact_email_verification.sql');
  final edge = _read('supabase/functions/send-email-verification/index.ts');

  group('database', () {
    test('only the Edge Function (service role) can issue or release a code', () {
      for (final f in ['issue_contact_email_code(uuid)', 'release_contact_email_code(uuid)', 'effective_contact_email(uuid)']) {
        expect(sql, contains('REVOKE ALL ON FUNCTION public.$f FROM PUBLIC, anon, authenticated;'), reason: f);
        expect(sql, contains('GRANT EXECUTE ON FUNCTION public.$f TO service_role;'), reason: f);
      }
    });

    test('verify is for signed-in users only', () {
      expect(sql, contains('REVOKE ALL ON FUNCTION public.verify_contact_email(text) FROM PUBLIC, anon;'));
      expect(sql, contains('GRANT EXECUTE ON FUNCTION public.verify_contact_email(text) TO authenticated;'));
      // It acts on the caller only: no user id parameter.
      expect(sql, contains('v_uid     uuid := auth.uid();'));
      expect(sql, isNot(contains('verify_contact_email(p_user_id')));
    });

    test('the code table is closed: row level security, no policies, no grants', () {
      expect(sql, contains('ALTER TABLE public.contact_email_codes ENABLE ROW LEVEL SECURITY;'));
      expect(sql, isNot(contains('CREATE POLICY')));
      expect(sql, contains('REVOKE ALL ON public.contact_email_codes FROM PUBLIC, anon, authenticated;'));
    });

    test('the code is stored hashed, tied to the account and the address', () {
      expect(sql, contains('sha256(convert_to(v_code'));
      expect(sql, contains("p_user_id::text || ':' || v_email"));
      expect(sql, contains('code_hash'));
      expect(RegExp(r'\bcode\s+text\b').hasMatch(sql.substring(sql.indexOf('CREATE TABLE IF NOT EXISTS public.contact_email_codes'), sql.indexOf('ENABLE ROW LEVEL'))), isFalse,
          reason: 'there is no column holding the plain code');
    });

    test('limits: 10 minutes, 5 tries, one a minute, 5 an hour, 10 a day', () {
      final issue = _fn(sql, 'issue_contact_email_code');
      expect(issue, contains("interval '10 minutes'"));
      expect(issue, contains("interval '60 seconds'"));
      expect(issue, contains('sends_in_hour >= 5'));
      expect(issue, contains('sends_in_day >= 10'));
      final verify = _fn(sql, 'verify_contact_email');
      expect(verify, contains('attempts >= 5'));
    });

    test('wrong guesses are counted: verify answers normally instead of raising (which would roll the count back)', () {
      final verify = _fn(sql, 'verify_contact_email');
      expect(verify, isNot(contains('RAISE EXCEPTION')));
      expect(verify, contains('attempts = attempts + 1'));
    });

    test('the proof can be written only by verify (and a deliberate admin fix); never by an app user', () {
      expect(sql, contains("current_setting('sagana.contact_email_verify', true)"));
      expect(sql, contains('Email verification can only be recorded by the verification process.'));
      // The only automatic writer of the verified columns is verify_contact_email.
      final writers = RegExp(r'SET verified_contact_email').allMatches(_fn(sql, 'verify_contact_email')).length;
      expect(writers, 1);
      expect(_fn(sql, 'issue_contact_email_code'), isNot(contains('verified_contact_email    =')));
    });

    test('the code is bound to the address it was sent to: a changed address invalidates it', () {
      expect(_fn(sql, 'verify_contact_email'), contains("'email_changed'"));
    });

    test('sign-in, auth.users and password recovery are not touched', () {
      // Statements only: the header comments explain WHY and name these things.
      final live = sql
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n');
      expect(live, isNot(contains('UPDATE auth.users')));
      expect(live, isNot(contains('INSERT INTO auth.users')));
      expect(live, isNot(contains('email_confirmed_at =')));
      expect(live, isNot(contains('promote_contact_email')));
      expect(live, isNot(contains('can_use_otp_reset')));
      // And nothing else in the schema folder writes the verified columns.
      for (final f in Directory('supabase_schema').listSync().whereType<File>()) {
        // Script 19 only READS the proof (to decide who may recover by email).
        // Script 20 replaces script 18's functions (same writer, plus the pending
        // address); it is checked on its own in the "change email" tests.
        if (!f.path.endsWith('.sql') ||
            f.path.contains('registration_18_') ||
            f.path.contains('registration_19_') ||
            f.path.contains('registration_20_')) {
          continue;
        }
        final other = f.readAsStringSync();
        expect(other.contains('verified_contact_email'), isFalse, reason: f.path);
      }
    });

    test('existing accounts are never marked verified automatically', () {
      // The only statement that writes the proof outside verify is a commented template.
      final live = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
      expect('contact_email_verified_at = now()'.allMatches(live).length, 1, reason: 'only in verify_contact_email');
    });
  });

  group('Edge Function', () {
    test('it identifies the caller from the JWT and takes no user id from the request', () {
      expect(edge, contains('auth.getUser()'));
      expect(edge, contains('return json(401'));
      // The only thing read from the request body is the password a Manager gives
      // to change their sign-in email: never a user id, never an address.
      expect('req.json()'.allMatches(edge).length, 1);
      expect(edge, contains('body?.current_password'));
      expect(edge.contains('body?.user'), isFalse);
      expect(edge.contains('body?.email'), isFalse);
      expect(edge, isNot(contains('req.text()')));
    });

    test('the code never leaves in a response or a log', () {
      // Every json(...) answer is built without the code.
      final answers = RegExp(r'json\(\d+,\s*\{[^}]*\}', dotAll: true).allMatches(edge).map((m) => m.group(0)!);
      for (final a in answers) {
        expect(a.contains('code'), isFalse, reason: a);
        expect(a.contains('issued.code'), isFalse, reason: a);
      }
      // issued.code is used in exactly one place: handed to the mailer.
      expect('issued.code'.allMatches(edge).length, 1);
      expect(edge, contains('sendCode(issued.email as string, issued.code as string)'));
      for (final line in edge.split('\n').where((l) => l.contains('console.'))) {
        // (the function's own name appears in an error log; the VALUE must not)
        expect(line.contains('issued.code'), isFalse, reason: line);
        expect(line.contains('.code'), isFalse, reason: line);
      }
    });

    test('a failed send gives the send back, and says so without exposing details', () {
      expect(edge, contains('release_contact_email_code'));
      expect(edge, contains('"send_failed"'));
    });

    test('it uses the service role only for the two database calls', () {
      expect(RegExp(r'admin\.rpc\(').allMatches(edge).length, 3);
      expect(edge, contains('SUPABASE_SERVICE_ROLE_KEY'));
    });

    test('the mail text carries the code and an expiry, and never anything else secret', () {
      final mail = _read('supabase/functions/send-email-verification/mail.ts');
      expect(mail, contains('CODE_MINUTES = 10'));
      expect(mail, contains('If you did not ask for this'));
    });
  });

  group('app', () {
    test('Verified status is read from the server answer only', () {
      final repo = _read('lib/data/repositories/contact_email_verification_repository.dart');
      expect(repo, contains("'verify_contact_email'"));
      expect(repo, contains("'send-email-verification'"));
      // The app never asks for, receives or compares the code itself.
      expect(repo.contains('code_hash'), isFalse);
    });

    test('registration and account creation do not require verification', () {
      for (final f in [
        'lib/presentation/screens/auth/register_screen.dart',
        'lib/presentation/screens/admin/add_new_member_screen.dart',
        'lib/presentation/screens/admin/create_officer_account_screen.dart',
        'lib/data/services/auth_service.dart',
      ]) {
        final src = _read(f);
        expect(src.contains('verify_contact_email'), isFalse, reason: f);
        expect(src.contains('send-email-verification'), isFalse, reason: f);
        expect(src.contains('ContactEmailVerification'), isFalse, reason: f);
      }
    });

    test('every Edit Profile uses the same verification widget', () {
      for (final f in [
        'lib/presentation/screens/farmer/farmer_edit_profile_screen.dart',
        'lib/presentation/screens/buyer/buyer_edit_profile_screen.dart',
        'lib/presentation/screens/admin/admin_edit_profile_screen.dart',
      ]) {
        expect(_read(f), contains('ContactEmailVerification('), reason: f);
      }
    });
  });
}
