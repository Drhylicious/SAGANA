import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/presentation/screens/auth/login_screen.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

/// Password recovery after verification became the rule:
///   * email recovery (emailed code): verified sign-in emails only;
///   * Password Assistance (the Manager sets a temporary password): everyone.

String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

Future<void> _pump(WidgetTester tester, {required Future<bool> Function(String) eligible}) async {
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
      home: LoginScreen(otpEligibility: eligible),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _forgot(WidgetTester tester, String identifier) async {
  await tester.enterText(find.byType(TextFormField).first, identifier);
  await tester.pump();
  await tester.tap(find.text('Forgot Password?'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockStorageChannels();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final dir = Directory.systemTemp.createTempSync('sagana_recovery');
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

  group('Login → Forgot Password', () {
    testWidgets('a VERIFIED email gets the emailed-code route', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, eligible: (_) async => true);
        await _forgot(tester, 'ana@gmail.com');
        expect(find.text('Reset Password'), findsOneWidget);
        expect(find.text('Send Reset Link'), findsOneWidget);
        expect(find.byKey(const ValueKey('recovery-verified-only-notice')), findsNothing);
      });
    });

    testWidgets('an email that is NOT eligible gets the explanation and Password Assistance', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, eligible: (_) async => false);
        await _forgot(tester, 'ana@gmail.com');
        // No emailed-code screen.
        expect(find.text('Reset Password'), findsNothing);
        expect(find.text('Send Reset Link'), findsNothing);
        // The reason, in plain words, and the other route.
        expect(find.byKey(const ValueKey('recovery-verified-only-notice')), findsOneWidget);
        expect(find.text('Email recovery needs a verified email'), findsOneWidget);
        expect(find.textContaining('has been verified in Edit Profile'), findsOneWidget);
        expect(find.text('Need Help Signing In?'), findsOneWidget);
        expect(find.text('Request Temporary Password'), findsOneWidget);
      });
    });

    testWidgets('the explanation is the same for every ineligible email: it reveals nothing about the account', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final seen = <String>[];
        await _pump(tester, eligible: (i) async {
          seen.add(i);
          return false;
        });
        await _forgot(tester, 'unverified.user@gmail.com');
        final a = tester.widgetList<Text>(find.descendant(
          of: find.byKey(const ValueKey('recovery-verified-only-notice')),
          matching: find.byType(Text),
        )).map((t) => t.data).toList();
        expect(seen, ['unverified.user@gmail.com']);
        // Same words for an address nobody has.
        // Close the sheet (its Cancel button needs the app's router).
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
        await _forgot(tester, 'nobody.at.all@gmail.com');
        final b = tester.widgetList<Text>(find.descendant(
          of: find.byKey(const ValueKey('recovery-verified-only-notice')),
          matching: find.byType(Text),
        )).map((t) => t.data).toList();
        expect(b, a);
      });
    });

    testWidgets('Password Assistance works with an unverified email: ask for the username, then request', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, eligible: (_) async => false);
        await _forgot(tester, 'ana@gmail.com');
        final request = find.widgetWithText(ElevatedButton, 'Request Temporary Password');
        // Off until a username is typed: an email is not a username.
        expect(tester.widget<ElevatedButton>(request).onPressed, isNull);
        await tester.enterText(find.byKey(const ValueKey('recovery-username')), 'ana.reyes');
        await tester.pump();
        expect(tester.widget<ElevatedButton>(request).onPressed, isNotNull);
        await tester.tap(request);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        // The request was made (the server is unreachable here; the screen still
        // confirms, as it always has, so a username cannot be probed).
        expect(find.text('Request sent. An SP3 Manager will assist you.'), findsOneWidget);
      });
    });

    testWidgets('a username (not an email) goes straight to Password Assistance, unchanged', (tester) async {
      await runIgnoringFontErrors(() async {
        var asked = false;
        await _pump(tester, eligible: (_) async {
          asked = true;
          return true;
        });
        await _forgot(tester, 'ana.reyes');
        expect(asked, isFalse, reason: 'a username never goes to the emailed-code check');
        expect(find.text('Need Help Signing In?'), findsOneWidget);
        // The username typed on the login screen is used; no explanation needed.
        expect(find.byKey(const ValueKey('recovery-verified-only-notice')), findsNothing);
        expect(find.byKey(const ValueKey('recovery-username')), findsNothing);
        final request = find.widgetWithText(ElevatedButton, 'Request Temporary Password');
        expect(tester.widget<ElevatedButton>(request).onPressed, isNotNull);
      });
    });
  });

  group('database', () {
    final sql = _read('supabase_schema/supabase_schema_registration_19_recovery_verified_email_only.sql');
    final live = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

    test('the rule: a real sign-in email that equals the verified one', () {
      final rule = live.substring(live.indexOf('FUNCTION public.recovery_email_is_verified'), live.indexOf('GRANT EXECUTE ON FUNCTION public.recovery_email_is_verified'));
      expect(rule, contains("NOT LIKE '%@sagana.local'"));
      expect(rule, contains('ui.verified_contact_email IS NOT NULL'));
      expect(rule, contains('lower(btrim(u.email)) = lower(btrim(ui.verified_contact_email))'));
      expect(rule, contains('false'), reason: 'unknown account -> false');
    });

    test('the Login screen question and the hook question both use the one rule', () {
      expect('public.recovery_email_is_verified('.allMatches(live).length, greaterThanOrEqualTo(3));
      final otp = live.substring(live.indexOf('FUNCTION public.can_use_otp_reset'), live.indexOf('GRANT EXECUTE ON FUNCTION public.can_use_otp_reset(TEXT) TO anon'));
      expect(otp, contains('RETURN public.recovery_email_is_verified(v_user_id)'));
      expect(otp, isNot(contains("NOT LIKE '%@sagana.local'")), reason: 'no longer "any real email"');
      final hook = live.substring(live.indexOf('FUNCTION public.may_receive_recovery_email'));
      expect(hook, contains('public.recovery_email_is_verified(u.id)'));
    });

    test('the rule and the hook check are not callable by app users; the Login question still is', () {
      expect(live, contains('REVOKE ALL ON FUNCTION public.recovery_email_is_verified(uuid) FROM PUBLIC, anon, authenticated;'));
      expect(live, contains('REVOKE ALL ON FUNCTION public.may_receive_recovery_email(text) FROM PUBLIC, anon, authenticated;'));
      expect(live, contains('GRANT EXECUTE ON FUNCTION public.can_use_otp_reset(TEXT) TO anon;'));
    });

    test('Password Assistance is not touched by this script', () {
      // (Block 2 may CHECK that it is still callable; nothing may change it.)
      expect(RegExp(r'(CREATE|ALTER|DROP)s+(OR REPLACEs+)?FUNCTIONs+public.request_password_assistance').hasMatch(live), isFalse);
      expect(RegExp(r'(GRANT|REVOKE)[^;]*request_password_assistance').hasMatch(live), isFalse);
      expect(live.contains('password_reset_requests'), isFalse);
      expect(live.contains('admin_reset_user_password'), isFalse);
    });

    test('sign-in is not touched', () {
      expect(live.contains('UPDATE auth.users'), isFalse);
      expect(live.contains('resolve_login_email'), isFalse);
      expect(live.contains('promote_contact_email'), isFalse);
    });
  });

  group('the Send Email hook (the backend gate)', () {
    final hook = _read('supabase/functions/auth-send-email/index.ts');

    test('only Supabase may call it: the signature is checked first', () {
      expect(hook, contains('new Webhook(secret).verify('));
      expect(hook, contains('return hookError(401, "Invalid signature")'));
      expect(hook.indexOf('.verify('), lessThan(hook.indexOf('admin.rpc("may_receive_recovery_email"')));
    });

    test('an unverified address is never sent to: the check comes before the send, and a "no" returns early', () {
      final check = hook.indexOf('admin.rpc("may_receive_recovery_email"');
      final blocked = hook.indexOf('if (allowed !== true)');
      final send = hook.indexOf('await sendMail(');
      expect(check, isNonNegative);
      expect(blocked, greaterThan(check));
      expect(send, greaterThan(blocked));
      // The "no" branch returns before the send and does not send.
      final branch = hook.substring(blocked, send);
      expect(branch, contains('return ok();'));
      expect(branch.contains('sendMail'), isFalse);
    });

    test('a "no" answers like an unknown address (success, nothing sent), so accounts cannot be probed', () {
      final branch = hook.substring(hook.indexOf('if (allowed !== true)'), hook.indexOf('// 3. Send the code.'));
      expect(branch, contains('return ok();'));
      expect(branch, isNot(contains('hookError')));
      expect(hook, contains('maskEmail(email)'));
    });

    test('it fails closed: if the database cannot be asked, nothing is sent', () {
      final branch = hook.substring(hook.indexOf('if (error) {'), hook.indexOf('if (allowed !== true)'));
      expect(branch, contains('return hookError(500'));
      expect(branch.contains('sendMail'), isFalse);
    });

    test('only recovery mail is handled; every other kind is refused', () {
      expect(hook, contains('classify(event.email_data?.email_action_type) !== "recovery"'));
      expect(hook, contains('SAGANA does not send this kind of email.'));
    });

    test('the reset code never goes to a log', () {
      for (final line in hook.split('\n').where((l) => l.contains('console.'))) {
        expect(line.contains('token'), isFalse, reason: line);
      }
    });

    test('the README says how to turn it on, and that it must be on', () {
      final readme = _read('supabase/functions/auth-send-email/README.md');
      expect(readme, contains('--no-verify-jwt'));
      expect(readme, contains('SEND_EMAIL_HOOK_SECRET'));
      expect(readme, contains('Authentication'));
      expect(readme, contains('Hooks'));
    });
  });

  group('the two recovery routes stay separate', () {
    test('the emailed-code route is still the same calls; Password Assistance is still the username RPC', () {
      final auth = _read('lib/data/services/auth_service.dart');
      expect(auth, contains("'can_use_otp_reset'"));
      expect(auth, contains('resetPasswordForEmail'));
      expect(auth, contains("'request_password_assistance'"));
    });
  });
}
