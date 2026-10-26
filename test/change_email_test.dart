import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/utils/contact_email.dart';
import 'package:sagana/data/models/admin_profile_model.dart';
import 'package:sagana/data/repositories/contact_email_verification_repository.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/presentation/screens/admin/admin_edit_profile_screen.dart';
import 'package:sagana/presentation/widgets/contact_email_verification.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

/// Manager and Officer can change their email. A new address is only PENDING until
/// its code is entered; the email in use (and the verified one) stay until then.

String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

class _Fake implements ContactEmailVerifier {
  final List<EmailCodeRequestResult> requests;
  final List<EmailCodeCheckResult> checks;
  PendingEmailStatus pendingAnswer;
  final pendingNamed = <String>[];
  final passwordsSent = <String?>[];
  final codesTried = <String>[];
  _Fake({
    List<EmailCodeRequestResult>? requests,
    List<EmailCodeCheckResult>? checks,
    this.pendingAnswer = PendingEmailStatus.pending,
  })  : requests = requests ?? [],
        checks = checks ?? [];

  @override
  Future<PendingEmailResult> setPendingEmail(String email) async {
    pendingNamed.add(email);
    return PendingEmailResult(pendingAnswer);
  }

  @override
  Future<EmailCodeRequestResult> requestCode({String? currentPassword}) async {
    passwordsSent.add(currentPassword);
    return requests.isEmpty
        ? const EmailCodeRequestResult(EmailCodeRequestStatus.sent, retryAfter: 60, maskedEmail: 'n***@gmail.com')
        : requests.removeAt(0);
  }

  @override
  Future<EmailCodeCheckResult> checkCode(String code) async {
    codesTried.add(code);
    return checks.isEmpty ? const EmailCodeCheckResult(EmailCodeCheckStatus.verified) : checks.removeAt(0);
  }
}

Finder _action() => find.byKey(const ValueKey('verify-email-action'));
Finder _password() => find.byKey(const ValueKey('verify-email-password'));
Finder _code() => find.byKey(const ValueKey('verify-email-code'));
Finder _unverified() => find.byKey(const ValueKey('email-status-unverified'));
Finder _verified() => find.byKey(const ValueKey('email-status-verified'));
Finder _noteCurrent() => find.byKey(const ValueKey('verify-email-note-current'));
Finder _noteSignIn() => find.byKey(const ValueKey('verify-email-note-signin'));

Widget _app(Widget home) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: home,
);

void _size(WidgetTester tester, {double w = 390, double h = 2600}) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// ── The widget ──────────────────────────────────────────────────────────────

class _Host extends StatefulWidget {
  final _Fake fake;
  final String text;
  final String? active;
  final bool activeVerified;
  final String? saved;
  final bool signIn;
  final bool needsPassword;
  final List<String> log;
  const _Host({
    required this.fake,
    required this.log,
    this.text = 'new@gmail.com',
    this.active = 'old@gmail.com',
    this.activeVerified = true,
    this.saved,
    this.signIn = false,
    this.needsPassword = false,
  });
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final email = TextEditingController(text: widget.text);
  late String? saved = widget.saved ?? widget.active;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          TextField(key: const ValueKey('email-field'), controller: email),
          ContactEmailVerification(
            emailController: email,
            savedEmail: saved,
            verified: ContactEmail.isVerified(
              contactEmail: saved,
              verifiedEmail: widget.activeVerified ? widget.active : null,
            ),
            activeEmail: widget.active,
            activeVerified: widget.activeVerified,
            signInEmail: widget.signIn,
            requiresPasswordWhenChanged: widget.needsPassword,
            verifier: widget.fake,
            saveEmail: () async {
              widget.log.add('save:${email.text.trim()}');
              final r = await widget.fake.setPendingEmail(email.text.trim());
              if (r.stored) setState(() => saved = email.text.trim().toLowerCase());
              return r.stored;
            },
            onSignInEmailChanged: () => widget.log.add('signin-changed'),
            onVerified: () => widget.log.add('verified'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _pumpHost(WidgetTester tester, _Host host) async {
  _size(tester);
  await tester.pumpWidget(_app(host));
  await tester.pump();
}

Future<void> _tapVerify(WidgetTester tester) async {
  await tester.tap(_action());
  await tester.pump();
  await tester.pump();
}

void parsing() {
  group('answers are read strictly', () {
    test('pending address result', () {
      expect(PendingEmailResult.fromJson({'status': 'pending'}).status, PendingEmailStatus.pending);
      expect(PendingEmailResult.fromJson({'status': 'cleared'}).stored, isTrue);
      expect(PendingEmailResult.fromJson({'status': 'in_use'}).stored, isFalse);
      expect(PendingEmailResult.fromJson({'status': 'invalid_format'}).status, PendingEmailStatus.invalidFormat);
      expect(PendingEmailResult.fromJson({'status': 'reserved'}).status, PendingEmailStatus.reserved);
      for (final bad in [null, 'pending', 3, <String, dynamic>{}, {'status': 'PENDING'}, {'status': 'ok'}]) {
        expect(PendingEmailResult.fromJson(bad).status, PendingEmailStatus.error, reason: '$bad');
        expect(PendingEmailResult.fromJson(bad).stored, isFalse);
      }
    });

    test('password statuses and the sign-in flag', () {
      expect(EmailCodeRequestResult.fromJson({'status': 'password_required'}).status, EmailCodeRequestStatus.passwordRequired);
      expect(EmailCodeRequestResult.fromJson({'status': 'wrong_password'}).status, EmailCodeRequestStatus.wrongPassword);
      expect(EmailCodeCheckResult.fromJson({'status': 'verified', 'signin_changed': true}).signInChanged, isTrue);
      expect(EmailCodeCheckResult.fromJson({'status': 'verified'}).signInChanged, isFalse);
      expect(EmailCodeCheckResult.fromJson({'status': 'verified', 'signin_changed': 'yes'}).signInChanged, isFalse);
      expect(EmailCodeCheckResult.fromJson({'status': 'email_in_use'}).status, EmailCodeCheckStatus.emailInUse);
      expect(EmailCodeCheckResult.fromJson({'status': 'email_in_use'}).verified, isFalse);
    });
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockStorageChannels();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final dir = Directory.systemTemp.createTempSync('sagana_change_email');
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

  parsing();

  group('changing an email: the guidance', () {
    testWidgets('a new address is Unverified, and says the current email stays in use until it is verified', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pumpHost(tester, _Host(fake: _Fake(), log: [], signIn: true, needsPassword: true));
        expect(_unverified(), findsOneWidget);
        expect(_verified(), findsNothing);
        expect(_noteCurrent(), findsOneWidget);
        expect(find.textContaining('old@gmail.com'), findsWidgets);
        expect(find.textContaining('stays in use until you verify this new address'), findsOneWidget);
        // A Manager is told this is also their sign-in.
        expect(_noteSignIn(), findsOneWidget);
        expect(find.textContaining('sign in with it'), findsOneWidget);
      });
    });

    testWidgets('an Officer is not shown the sign-in note or a password box', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pumpHost(tester, _Host(fake: _Fake(), log: []));
        expect(_noteCurrent(), findsOneWidget);
        expect(_noteSignIn(), findsNothing);
        expect(_password(), findsNothing);
      });
    });

    testWidgets('the first email ever added has no "current email" note', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pumpHost(tester, _Host(fake: _Fake(), log: [], active: null, activeVerified: false, saved: null));
        expect(_unverified(), findsOneWidget);
        expect(_noteCurrent(), findsNothing);
        expect(_password(), findsNothing);
      });
    });

    testWidgets('typing the email in use back shows ITS status (Verified), with no change notes', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pumpHost(
          tester,
          _Host(fake: _Fake(), log: [], text: 'old@gmail.com', signIn: true, needsPassword: true, saved: 'pending@gmail.com'),
        );
        expect(_verified(), findsOneWidget);
        expect(_noteCurrent(), findsNothing);
        expect(_password(), findsNothing);
        expect(_action(), findsNothing);
      });
    });

    testWidgets('not a valid email: the message is on the field and nothing can be sent', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pumpHost(tester, _Host(fake: _Fake(), log: [], text: 'new@gmail'));
        expect(find.byKey(const ValueKey('verify-email-format-error')), findsOneWidget);
        expect(find.text('Enter a valid email address.'), findsOneWidget);
        expect(_action(), findsNothing);
        expect(_unverified(), findsNothing);
        // Fixing it brings the normal line back.
        await tester.enterText(find.byKey(const ValueKey('email-field')), 'new@gmail.com');
        await tester.pump();
        expect(find.byKey(const ValueKey('verify-email-format-error')), findsNothing);
        expect(_action(), findsOneWidget);
      });
    });
  });

  group('changing a Manager\'s sign-in email', () {
    testWidgets('the password is asked for first: nothing is saved or sent without it', (tester) async {
      await runIgnoringFontErrors(() async {
        final fake = _Fake();
        final log = <String>[];
        await _pumpHost(tester, _Host(fake: fake, log: log, signIn: true, needsPassword: true));
        expect(_password(), findsOneWidget);
        await _tapVerify(tester);
        expect(find.text('Enter your current password to change your sign-in email.'), findsOneWidget);
        expect(fake.pendingNamed, isEmpty);
        expect(fake.passwordsSent, isEmpty);
        expect(_code(), findsNothing);
      });
    });

    testWidgets('with the password: the new address is named, the code is requested with the password, the code box opens', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final fake = _Fake();
        final log = <String>[];
        await _pumpHost(tester, _Host(fake: fake, log: log, signIn: true, needsPassword: true));
        await tester.enterText(find.descendant(of: _password(), matching: find.byType(TextField)), 's3cret');
        await _tapVerify(tester);
        expect(log, ['save:new@gmail.com']);
        expect(fake.pendingNamed, ['new@gmail.com']);
        expect(fake.passwordsSent, ['s3cret']);
        expect(_code(), findsOneWidget);
        expect(find.textContaining('n***@gmail.com'), findsOneWidget);
        // The password box is out of the way once the code is on its way.
        expect(_password(), findsNothing);
      });
    });

    testWidgets('a wrong password is refused clearly, the box clears, and no code field opens', (tester) async {
      await runIgnoringFontErrors(() async {
        final fake = _Fake(requests: [const EmailCodeRequestResult(EmailCodeRequestStatus.wrongPassword)]);
        await _pumpHost(tester, _Host(fake: fake, log: [], signIn: true, needsPassword: true));
        await tester.enterText(find.descendant(of: _password(), matching: find.byType(TextField)), 'nope');
        await _tapVerify(tester);
        expect(find.text('That password is not correct.'), findsOneWidget);
        expect(_code(), findsNothing);
        expect(_password(), findsOneWidget);
        expect(tester.widget<TextField>(find.descendant(of: _password(), matching: find.byType(TextField))).controller!.text, '');
        expect(_unverified(), findsOneWidget);
      });
    });

    testWidgets('the right code: the Manager is told the sign-in changed, and the host is told it is verified', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final fake = _Fake(checks: [const EmailCodeCheckResult(EmailCodeCheckStatus.verified, signInChanged: true)]);
        final log = <String>[];
        await _pumpHost(tester, _Host(fake: fake, log: log, signIn: true, needsPassword: true));
        await tester.enterText(find.descendant(of: _password(), matching: find.byType(TextField)), 's3cret');
        await _tapVerify(tester);
        await tester.enterText(find.descendant(of: _code(), matching: find.byType(TextField)), '123456');
        await tester.tap(find.byKey(const ValueKey('verify-email-confirm')));
        await tester.pump();
        await tester.pump();
        expect(log, ['save:new@gmail.com', 'signin-changed', 'verified']);
        expect(fake.codesTried, ['123456']);
      });
    });

    testWidgets('someone took the address meanwhile: refused, nothing is switched, back to the button', (tester) async {
      await runIgnoringFontErrors(() async {
        final fake = _Fake(checks: [const EmailCodeCheckResult(EmailCodeCheckStatus.emailInUse)]);
        final log = <String>[];
        await _pumpHost(tester, _Host(fake: fake, log: log, signIn: true, needsPassword: true));
        await tester.enterText(find.descendant(of: _password(), matching: find.byType(TextField)), 's3cret');
        await _tapVerify(tester);
        await tester.enterText(find.descendant(of: _code(), matching: find.byType(TextField)), '123456');
        await tester.tap(find.byKey(const ValueKey('verify-email-confirm')));
        await tester.pump();
        await tester.pump();
        expect(find.text('That email address is now used by another account. Choose a different one.'), findsOneWidget);
        expect(log.contains('verified'), isFalse);
        expect(log.contains('signin-changed'), isFalse);
        expect(_code(), findsNothing);
        expect(_unverified(), findsOneWidget);
      });
    });

    testWidgets('an address that cannot be stored (already used by another account) stops before any code is sent', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final fake = _Fake(pendingAnswer: PendingEmailStatus.inUse);
        await _pumpHost(tester, _Host(fake: fake, log: [], signIn: true, needsPassword: true));
        await tester.enterText(find.descendant(of: _password(), matching: find.byType(TextField)), 's3cret');
        await _tapVerify(tester);
        expect(fake.passwordsSent, isEmpty);
        expect(_code(), findsNothing);
      });
    });
  });

  group('the Officer: a contact email only', () {
    testWidgets('no password; the right code verifies, with no sign-in change reported', (tester) async {
      await runIgnoringFontErrors(() async {
        final fake = _Fake();
        final log = <String>[];
        await _pumpHost(tester, _Host(fake: fake, log: log));
        await _tapVerify(tester);
        expect(fake.passwordsSent, [null]);
        await tester.enterText(find.descendant(of: _code(), matching: find.byType(TextField)), '654321');
        await tester.tap(find.byKey(const ValueKey('verify-email-confirm')));
        await tester.pump();
        await tester.pump();
        expect(log, ['save:new@gmail.com', 'verified']);
      });
    });
  });

  group('Edit Profile screen', () {
    AdminProfileModel manager({String? pending}) => AdminProfileModel(
      userId: 'u1',
      email: 'manager@coop.ph',
      fullName: 'Rosa Dela Cruz',
      surname: 'Dela Cruz',
      firstName: 'Rosa',
      verifiedContactEmail: 'manager@coop.ph',
      pendingContactEmail: pending,
    );
    AdminProfileModel officer({String? pending, String? verified}) => AdminProfileModel(
      userId: 'u1',
      email: 'OFF-0001@sagana.local',
      fullName: 'Omar Santos',
      surname: 'Santos',
      firstName: 'Omar',
      contactEmail: 'omar@gmail.com',
      verifiedContactEmail: verified,
      pendingContactEmail: pending,
    );

    TextField emailField(WidgetTester tester) => tester.widget<TextField>(
      find.descendant(of: find.widgetWithText(TextFormField, 'Email Address').first, matching: find.byType(TextField)).first,
    );

    testWidgets('Manager: the email is editable, the verified current email shows Verified', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.runAsync(() => _setRole('admin'));
        _size(tester);
        await tester.pumpWidget(_app(AdminEditProfileScreen(initialProfile: manager(), verifier: _Fake())));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Email address cannot be changed.'), findsNothing);
        expect(find.byIcon(Icons.lock_outline_rounded), findsNothing, reason: 'no lock icon on the email field');
        expect(_verified(), findsOneWidget);
        expect(_action(), findsNothing);
      });
    });

    testWidgets('Manager: typing a new email shows Unverified, the guidance and the password box; the verified one is kept', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await tester.runAsync(() => _setRole('admin'));
        _size(tester);
        await tester.pumpWidget(_app(AdminEditProfileScreen(initialProfile: manager(), verifier: _Fake())));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(find.widgetWithText(TextFormField, 'manager@coop.ph').first, 'rosa@coop.ph');
        await tester.pump();
        expect(_unverified(), findsOneWidget);
        expect(find.textContaining('manager@coop.ph, stays in use'), findsOneWidget);
        expect(_noteSignIn(), findsOneWidget);
        expect(_password(), findsOneWidget);
      });
    });

    testWidgets('Manager: a change already started is shown where it was left, as Unverified, with the current email kept', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await tester.runAsync(() => _setRole('admin'));
        _size(tester);
        await tester.pumpWidget(_app(AdminEditProfileScreen(initialProfile: manager(pending: 'rosa@coop.ph'), verifier: _Fake())));
        await tester.pump(const Duration(milliseconds: 400));
        expect(emailField(tester).controller!.text, 'rosa@coop.ph');
        expect(_unverified(), findsOneWidget);
        expect(find.textContaining('manager@coop.ph, stays in use'), findsOneWidget);
      });
    });

    testWidgets('Manager: the email cannot be saved blank (it is how they sign in)', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.runAsync(() => _setRole('admin'));
        _size(tester);
        await tester.pumpWidget(_app(AdminEditProfileScreen(initialProfile: manager(), verifier: _Fake())));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(find.widgetWithText(TextFormField, 'manager@coop.ph').first, '');
        await tester.pump();
        await tester.tap(find.text('Save Changes'));
        await tester.pump();
        expect(find.textContaining('cannot be left blank'), findsOneWidget);
      });
    });

    testWidgets('Officer: editable, no password box, the contact email stays until the new one is verified', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await tester.runAsync(() => _setRole('officer'));
        _size(tester);
        await tester.pumpWidget(_app(AdminEditProfileScreen(initialProfile: officer(verified: 'omar@gmail.com'), verifier: _Fake())));
        await tester.pump(const Duration(milliseconds: 400));
        expect(emailField(tester).enabled, isTrue);
        expect(_verified(), findsOneWidget);
        await tester.enterText(find.widgetWithText(TextFormField, 'omar@gmail.com').first, 'omar.new@gmail.com');
        await tester.pump();
        expect(_unverified(), findsOneWidget);
        expect(find.textContaining('omar@gmail.com, stays in use'), findsOneWidget);
        expect(_password(), findsNothing);
        expect(find.textContaining('sagana.local'), findsNothing);
      });
    });

    testWidgets('Officer: Verify Email names the new address as pending, then a right code makes it the verified one', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await tester.runAsync(() => _setRole('officer'));
        _size(tester);
        final fake = _Fake();
        await tester.pumpWidget(_app(AdminEditProfileScreen(initialProfile: officer(verified: 'omar@gmail.com'), verifier: fake)));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(find.widgetWithText(TextFormField, 'omar@gmail.com').first, 'omar.new@gmail.com');
        await tester.pump();
        await tester.tap(_action());
        // A changed address gets the domain check first. It reaches for the network
        // (which does not exist here) and gives up after 6 seconds, which is "no
        // verdict", so the save carries on.
        await tester.pump(const Duration(seconds: 7));
        await tester.pump(const Duration(milliseconds: 300));
        expect(fake.pendingNamed, ['omar.new@gmail.com']);
        expect(_code(), findsOneWidget);
        await tester.enterText(find.descendant(of: _code(), matching: find.byType(TextField)), '111111');
        await tester.tap(find.byKey(const ValueKey('verify-email-confirm')));
        await tester.pump();
        await tester.pump();
        expect(_verified(), findsOneWidget);
        expect(find.text('Your email address is verified.'), findsOneWidget);
      });
    });
  });

  group('database and Edge Function (source checks; the SQL itself was run on Postgres)', () {
    final sql = _read('supabase_schema/supabase_schema_registration_20_change_email_pending.sql');
    final live = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
    final edge = _read('supabase/functions/send-email-verification/index.ts');
    String fn(String name) {
      final a = live.indexOf('FUNCTION public.$name');
      expect(a, isNonNegative, reason: name);
      return live.substring(a, live.indexOf(r'$$;', a) + 3);
    }

    test('a new address is only pending: naming it never touches the email in use', () {
      final set = fn('set_pending_contact_email');
      expect(set, contains('SET pending_contact_email'));
      expect(set.contains('UPDATE auth.users'), isFalse);
      expect(set.contains('SET contact_email'), isFalse);
      expect(set.contains('verified_contact_email'), isFalse);
      expect(live, contains('REVOKE ALL ON FUNCTION public.set_pending_contact_email(text) FROM PUBLIC, anon;'));
      expect(live, contains('GRANT EXECUTE ON FUNCTION public.set_pending_contact_email(text) TO authenticated;'));
    });

    test('the switch happens only inside verify, only after the right code, and only the Manager\'s sign-in changes', () {
      expect('UPDATE auth.users'.allMatches(live).length, 1);
      final verify = fn('verify_contact_email');
      expect(verify, contains('UPDATE auth.users'));
      // The auth update is inside the admin-only branch.
      final adminBranch = verify.indexOf('IF v_admin THEN');
      expect(adminBranch, isNonNegative);
      expect(verify.indexOf('UPDATE auth.users'), greaterThan(adminBranch));
      // It is after the code was compared.
      expect(verify.indexOf('UPDATE auth.users'), greaterThan(verify.indexOf('IF v_hash <> r.code_hash')));
      // Someone else may have taken the address: re-checked at the moment of the switch.
      expect(verify, contains("'email_in_use'"));
      expect(verify, contains("role = 'admin'"));
    });

    test('the pending column can only be written by the two functions (the lock covers it)', () {
      final guard = fn('user_information_verified_email_guard');
      expect(guard, contains('NEW.pending_contact_email IS DISTINCT FROM OLD.pending_contact_email'));
      expect(guard, contains('Email verification can only be recorded by the verification process.'));
    });

    test('the code goes to the pending address, and a pending change is never "already verified"', () {
      final issue = fn('issue_contact_email_code');
      expect(issue, contains('v_email := coalesce(v_pending, public.effective_contact_email(p_user_id))'));
      expect(issue, contains('IF v_pending IS NULL AND EXISTS'));
      expect(live, contains('REVOKE ALL ON FUNCTION public.issue_contact_email_code(uuid) FROM PUBLIC, anon, authenticated;'));
    });

    test('limits and the app-side promise are unchanged from script 18', () {
      final issue = fn('issue_contact_email_code');
      expect(issue, contains("interval '10 minutes'"));
      expect(issue, contains('sends_in_hour >= 5'));
      expect(issue, contains('sends_in_day >= 10'));
      expect(fn('verify_contact_email'), contains('attempts >= 5'));
    });

    test('recovery and sign-in lookups are not rewritten here', () {
      expect(live.contains('can_use_otp_reset'), isFalse);
      expect(live.contains('recovery_email_is_verified'), isFalse);
      expect(live.contains('resolve_login_email'), isFalse);
      expect(live.contains('promote_contact_email'), isFalse);
    });

    test('Edge Function: a Manager changing their sign-in email must pass the password check BEFORE a code is issued', () {
      final needs = edge.indexOf('admin.rpc("email_change_needs_password"');
      final pw = edge.indexOf('signInWithPassword');
      final issue = edge.indexOf('admin.rpc("issue_contact_email_code"');
      expect(needs, isNonNegative);
      expect(pw, greaterThan(needs));
      expect(issue, greaterThan(pw));
      expect(edge, contains('return json(200, { status: "password_required" })'));
      expect(edge, contains('return json(200, { status: "wrong_password" })'));
      // The password check does not leave a session behind.
      expect(edge, contains('persistSession: false, autoRefreshToken: false'));
    });

    test('Edge Function: the password is never logged or returned', () {
      for (final line in edge.split('\n').where((l) => l.contains('console.'))) {
        // (a function's name may contain the word; the password VALUE must not be logged)
        expect(RegExp(r'(?<![_a-zA-Z])password(?![_a-zA-Z])').hasMatch(line), isFalse, reason: line);
      }
      final answers = RegExp(r'json\(\d+,\s*\{[^}]*\}').allMatches(edge).map((m) => m.group(0)!);
      for (final a in answers) {
        expect(a.contains('password,'), isFalse, reason: a);
        expect(a.contains('current_password'), isFalse, reason: a);
      }
    });
  });
}

Future<void> _setRole(String role) => HiveService.saveUserSession(userId: 'u1', email: 'x@y.z', role: role);
