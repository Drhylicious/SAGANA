import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/user_model.dart';
import 'package:sagana/data/services/auth_service.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/presentation/screens/auth/login_screen.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

/// An email signs a person in only once it is VERIFIED; a username always does.
///
/// The rule lives in the database (script 21): Supabase Auth finds a person by
/// auth.users.email, and that column only ever holds the generated
/// username@sagana.local address or the verified address. The SQL itself was run
/// on Postgres for all four roles; the checks here pin its shape, and test what
/// the Login screen says when an email does not get in.

String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _live(String sql) =>
    sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

String _fn(String live, String name) {
  final a = live.indexOf('FUNCTION public.$name');
  expect(a, isNonNegative, reason: name);
  final end = live.contains(r'$function$;') && live.indexOf(r'$function$;', a) >= 0
      ? live.indexOf(r'$function$;', a) + 11
      : live.indexOf(r'$$;', a) + 3;
  return live.substring(a, end);
}

typedef _SignIn = Future<UserModel> Function({
  required String identifier,
  required String password,
});

Future<void> _pump(WidgetTester tester, {required _SignIn signIn}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: LoginScreen(signIn: signIn),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _signInWith(WidgetTester tester, String identifier) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), identifier);
  await tester.enterText(fields.at(1), 'whatever-password');
  await tester.pump();
  await tester.tap(find.text('Sign In').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockStorageChannels();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final dir = Directory.systemTemp.createTempSync('sagana_login_verified');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
    await HiveService.init();
    await Supabase.initialize(url: 'http://localhost:54321', publishableKey: 'test-key');
  });

  group('Login screen: what an email that does not get in is told', () {
    const hint = 'An email can only be used to sign in after it has been verified';

    testWidgets('a wrong pair typed as an EMAIL explains verification and points to the username',
        (tester) async {
      await runIgnoringFontErrors(() async {
        final asked = <String>[];
        await _pump(
          tester,
          signIn: ({required identifier, required password}) async {
            asked.add(identifier);
            throw const AuthException('Invalid login credentials');
          },
        );
        await _signInWith(tester, 'jd@gmail.com');
        expect(asked, ['jd@gmail.com'], reason: 'the screen does not decide; Auth does');
        expect(find.textContaining(hint), findsOneWidget);
        expect(find.textContaining('sign in with your username'), findsOneWidget);
        expect(find.textContaining('verify it in Edit Profile'), findsOneWidget);
      });
    });

    testWidgets('a wrong pair typed as a USERNAME gets the ordinary message', (tester) async {
      await runIgnoringFontErrors(() async {
        final asked = <String>[];
        await _pump(
          tester,
          signIn: ({required identifier, required password}) async {
            asked.add(identifier);
            throw const AuthException('Invalid login credentials');
          },
        );
        await _signInWith(tester, 'amane');
        expect(asked, ['amane'], reason: 'a username goes through as typed, verified or not');
        expect(find.text('Incorrect username or password. Please try again.'), findsOneWidget);
        expect(find.textContaining(hint), findsNothing);
      });
    });

    testWidgets('only a credentials failure gets the hint (a server problem does not)',
        (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          signIn: ({required identifier, required password}) async {
            throw const AuthException('Email rate limit exceeded');
          },
        );
        await _signInWith(tester, 'jd@gmail.com');
        expect(find.textContaining(hint), findsNothing);
      });
    });

    test('credentials failures are recognised, nothing else is', () {
      expect(AuthService.isInvalidCredentials(const AuthException('Invalid login credentials')), isTrue);
      expect(AuthService.isInvalidCredentials(const AuthException('invalid credentials')), isTrue);
      expect(AuthService.isInvalidCredentials(const AuthException('Email not confirmed')), isFalse);
      expect(AuthService.isInvalidCredentials(Exception('Invalid login credentials')), isFalse);
    });

    test('the message is the same for every email (it says nothing about which accounts exist)', () {
      final login = _read('lib/presentation/screens/auth/login_screen.dart');
      expect(login, contains('AuthService.isInvalidCredentials(e)'));
      expect(login, contains('loginEmailNotVerifiedHint'));
    });
  });

  group('the app does not give an email a way in', () {
    final auth = _read('lib/data/services/auth_service.dart');

    test('sign-in goes to Supabase Auth with whatever address it is given; no role is barred from a verified email', () {
      expect(auth, contains('_client.auth.signInWithPassword('));
      // An Officer used to be signed out when they signed in with an email. The
      // database now decides which emails are sign-ins (verified ones only), so a
      // verified Officer email works and an unverified one never gets this far.
      expect(auth.contains('Officer accounts must log in with a SAGANA username'), isFalse);
      expect(auth.contains("role == 'officer' && !authEmail"), isFalse);
    });

    test('nothing in the app sets a sign-in email directly', () {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final text = f.readAsStringSync();
        expect(text.contains('UserAttributes(email'), isFalse, reason: f.path);
        expect(text.contains('updateUser(UserAttributes(email'), isFalse, reason: f.path);
      }
    });

    test('Farmer and Buyer saving an email still goes through promote_contact_email', () {
      for (final f in [
        'lib/data/repositories/farmer_profile_repository.dart',
        'lib/data/repositories/buyer_profile_repository.dart',
      ]) {
        expect(_read(f), contains("'promote_contact_email'"), reason: f);
      }
    });

    test('a Farmer/Buyer whose email becomes a sign-in has the cached session refreshed and is told', () {
      final widget = _read('lib/presentation/widgets/contact_email_verification.dart');
      expect(widget, contains('Future<void> announceEmailSignInEnabled('));
      expect(widget, contains('auth.refreshSession()'));
      for (final f in [
        'lib/presentation/screens/farmer/farmer_edit_profile_screen.dart',
        'lib/presentation/screens/buyer/buyer_edit_profile_screen.dart',
      ]) {
        expect(_read(f), contains('announceEmailSignInEnabled(context, _savedEmail)'), reason: f);
      }
    });
  });

  group('script 21 (source checks; the SQL itself was run on Postgres for all four roles)', () {
    final sql = _read('supabase_schema/supabase_schema_registration_21_login_verified_email_only.sql');
    final live = _live(sql);

    test('it needs script 20 first', () {
      expect(live, contains("column_name = 'pending_contact_email'"));
      expect(live, contains("RAISE EXCEPTION 'Run script 20 (change email) before this one.'"));
    });

    test('saving an email copies it into the sign-in only while it is the verified one', () {
      final p = _fn(live, 'promote_contact_email');
      expect(p, contains('v_target := CASE WHEN v_new IS NOT NULL AND v_new = v_verified'));
      expect(p, contains("lower(btrim(v_username)) || '@sagana.local'"));
      // Farmers and Buyers only; an Officer's or Manager's sign-in is never rewritten here.
      expect(p, contains("v_role NOT IN ('farmer', 'buyer')"));
      // The contact email is one statement, the sign-in another.
      expect(p, contains('SET contact_email = v_new'));
      expect(p, contains("IF v_current IS DISTINCT FROM v_target THEN"));
      expect(p, isNot(contains('verified_contact_email =')));
      expect(live, contains('REVOKE ALL ON FUNCTION public.promote_contact_email(text) FROM PUBLIC, anon;'));
      expect(live, contains('GRANT EXECUTE ON FUNCTION public.promote_contact_email(text) TO authenticated;'));
    });

    test('keeps the one-email-one-account rules of the old function', () {
      final p = _fn(live, 'promote_contact_email');
      expect(p, contains('public.is_valid_email(v_new)'));
      expect(p, contains("LIKE '%@sagana.local'"));
      expect(p, contains('This email address is already used by another account.'));
      expect(p, contains('Not authenticated'));
    });

    test('the guard allows a username address or the verified address, nothing else', () {
      final g = _fn(live, 'auth_email_verified_only');
      expect(g, contains("LIKE '%@sagana.local'"));
      expect(g, contains('ui.verified_contact_email IS NOT NULL'));
      expect(g, contains('lower(btrim(ui.verified_contact_email)) = lower(btrim(NEW.email))'));
      expect(g, contains('RAISE EXCEPTION'));
      expect(g, contains('SECURITY DEFINER'));
      expect(live, contains('BEFORE UPDATE OF email ON auth.users'));
      expect(live, contains('WHEN (NEW.email IS DISTINCT FROM OLD.email)'));
      expect(live, contains('REVOKE ALL ON FUNCTION public.auth_email_verified_only() FROM PUBLIC, anon, authenticated;'));
    });

    test('the clean-up only touches Farmers, Buyers and Officers, keeps their email, and runs before the guard', () {
      final keep = live.indexOf('SET contact_email = lower(btrim(u.email))');
      final demote = live.indexOf("SET email = lower(btrim(ui.username)) || '@sagana.local'");
      final guard = live.indexOf('CREATE TRIGGER trg_auth_email_verified_only');
      expect(keep, isNonNegative);
      expect(demote, greaterThan(keep), reason: 'the address is kept on the profile before it is taken off the sign-in');
      expect(guard, greaterThan(demote));
      final cleanup = live.substring(keep, guard);
      expect("role IN ('farmer', 'buyer', 'officer')".allMatches(cleanup).length, 3);
      expect(cleanup.contains("'admin'"), isFalse, reason: 'the Manager has no username to fall back to');
      expect(cleanup, contains("<> lower(btrim(u.email))"));
    });

    test('the sign-in follows a changed or removed contact email (Officers remove theirs directly)', () {
      final t = _fn(live, 'signin_follows_contact_email');
      expect(t, contains("r.role IN ('farmer', 'buyer', 'officer')"));
      expect(t, contains("LIKE '%@sagana.local'"));
      expect(t, contains("lower(btrim(coalesce(NEW.contact_email, ''))) IS DISTINCT FROM v_current"));
      expect(live, contains('AFTER UPDATE OF contact_email ON public.user_information'));
      expect(live, contains('WHEN (NEW.contact_email IS DISTINCT FROM OLD.contact_email)'));
      // A Manager has no username: they are never demoted.
      expect(t, contains('NEW.username IS NULL'));
      expect(t.contains("'admin'"), isFalse);
    });

    test('it only reads the proof; it never writes it', () {
      expect(live.contains('verified_contact_email ='), isFalse);
      expect(live.contains('contact_email_verified_at ='), isFalse);
      expect(live.contains('INSERT INTO auth.users'), isFalse);
    });

    test('it ships its own read-only check and report', () {
      expect(sql, contains('-- BLOCK 1 —'));
      expect(sql, contains('-- BLOCK 2 —'));
      expect(sql, contains("'PROBLEM: unverified email is a sign-in'"));
      expect(sql, contains('no account signs in with an unverified email'));
    });
  });

  group('script 20 supports it: the proof is recorded before any sign-in email is switched', () {
    final live = _live(_read('supabase_schema/supabase_schema_registration_20_change_email_pending.sql'));
    String verifyFn() => _fn(live, 'verify_contact_email');

    test('Manager branch: proof first, then the sign-in', () {
      final verify = verifyFn();
      final proof = verify.indexOf('verified_contact_email    = r.email');
      final authUpdate = verify.indexOf('UPDATE auth.users');
      expect(proof, isNonNegative);
      expect(authUpdate, greaterThan(proof));
    });

    test('Farmer/Buyer branch: proof first, then the sign-in; taken meanwhile is refused', () {
      final verify = verifyFn();
      final start = verify.indexOf("v_login := EXISTS");
      expect(start, isNonNegative);
      final branch = verify.substring(start);
      expect(branch.indexOf('SET verified_contact_email'), lessThan(branch.indexOf('UPDATE auth.users')));
      expect(branch, contains("'email_in_use'"));
      expect(branch, contains('lower(btrim(u.contact_email)) = r.email'));
    });
  });
}
