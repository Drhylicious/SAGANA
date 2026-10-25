import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/utils/contact_email.dart';
import 'package:sagana/data/repositories/contact_email_verification_repository.dart';
import 'package:sagana/presentation/widgets/contact_email_verification.dart';

import 'support/ignore_font_errors.dart';

// ── What counts as verified ─────────────────────────────────────────────────

void rules() {
  group('ContactEmail rules', () {
    test('the contact email is the one verified; a generated sign-in address is not an email', () {
      expect(ContactEmail.effective(contactEmail: ' Ana@Gmail.com ', signInEmail: 'x@sagana.local'), 'ana@gmail.com');
      expect(ContactEmail.effective(contactEmail: null, signInEmail: 'OFF-0001@sagana.local'), isNull);
      expect(ContactEmail.effective(contactEmail: '  ', signInEmail: 'mgr@coop.ph'), 'mgr@coop.ph');
    });

    test('verified only while the address equals the proven one', () {
      expect(ContactEmail.isVerified(contactEmail: 'ana@gmail.com', verifiedEmail: 'ANA@gmail.com'), isTrue);
      // Changed address: unverified again, whatever was proven before.
      expect(ContactEmail.isVerified(contactEmail: 'new@gmail.com', verifiedEmail: 'ana@gmail.com'), isFalse);
      // Nothing proven yet (every existing account at first).
      expect(ContactEmail.isVerified(contactEmail: 'ana@gmail.com', verifiedEmail: null), isFalse);
      // No address.
      expect(ContactEmail.isVerified(contactEmail: null, signInEmail: 'a@sagana.local', verifiedEmail: 'ana@gmail.com'), isFalse);
      // Changing back to the proven address is verified again.
      expect(ContactEmail.isVerified(contactEmail: 'ana@gmail.com', verifiedEmail: 'ana@gmail.com'), isTrue);
    });

    test('the Manager is verified through their real sign-in email', () {
      expect(ContactEmail.isVerified(contactEmail: null, signInEmail: 'mgr@coop.ph', verifiedEmail: 'mgr@coop.ph'), isTrue);
    });
  });

  group('server answers are read strictly', () {
    test('request: every status maps, anything else is an error (never "sent")', () {
      expect(EmailCodeRequestResult.fromJson({'status': 'sent', 'email': 'a***@x.com', 'resend_after': 60}).sent, isTrue);
      expect(EmailCodeRequestResult.fromJson({'status': 'cooldown', 'retry_after': 41}).retryAfter, 41);
      expect(EmailCodeRequestResult.fromJson({'status': 'limit', 'retry_after': 900}).status, EmailCodeRequestStatus.limit);
      expect(EmailCodeRequestResult.fromJson({'status': 'already_verified'}).status, EmailCodeRequestStatus.alreadyVerified);
      expect(EmailCodeRequestResult.fromJson({'status': 'no_email'}).status, EmailCodeRequestStatus.noEmail);
      expect(EmailCodeRequestResult.fromJson({'status': 'send_failed'}).status, EmailCodeRequestStatus.sendFailed);
      expect(EmailCodeRequestResult.fromJson({'status': 'unauthorized'}).status, EmailCodeRequestStatus.unauthorized);
      for (final bad in [null, 'sent', 42, <String, dynamic>{}, {'status': 'SENT'}, {'status': 'ok'}]) {
        expect(EmailCodeRequestResult.fromJson(bad).status, EmailCodeRequestStatus.error, reason: '$bad');
        expect(EmailCodeRequestResult.fromJson(bad).sent, isFalse);
      }
    });

    test('check: only an explicit "verified" verifies', () {
      expect(EmailCodeCheckResult.fromJson({'status': 'verified'}).verified, isTrue);
      final wrong = EmailCodeCheckResult.fromJson({'status': 'invalid_code', 'attempts_left': 3});
      expect(wrong.status, EmailCodeCheckStatus.invalidCode);
      expect(wrong.attemptsLeft, 3);
      expect(wrong.verified, isFalse);
      expect(EmailCodeCheckResult.fromJson({'status': 'expired'}).status, EmailCodeCheckStatus.expired);
      expect(EmailCodeCheckResult.fromJson({'status': 'too_many_attempts'}).status, EmailCodeCheckStatus.tooManyAttempts);
      expect(EmailCodeCheckResult.fromJson({'status': 'no_code'}).status, EmailCodeCheckStatus.noCode);
      expect(EmailCodeCheckResult.fromJson({'status': 'email_changed'}).status, EmailCodeCheckStatus.emailChanged);
      for (final bad in [null, true, 'verified', {'status': 'VERIFIED'}, {'verified': true}, <String, dynamic>{}]) {
        expect(EmailCodeCheckResult.fromJson(bad).verified, isFalse, reason: '$bad');
        expect(EmailCodeCheckResult.fromJson(bad).status, EmailCodeCheckStatus.error, reason: '$bad');
      }
    });
  });
}

// ── The widget ──────────────────────────────────────────────────────────────

class _Fake implements ContactEmailVerifier {
  final List<EmailCodeRequestResult> requests;
  final List<EmailCodeCheckResult> checks;
  int requested = 0;
  final codesTried = <String>[];
  _Fake({List<EmailCodeRequestResult>? requests, List<EmailCodeCheckResult>? checks})
      : requests = requests ?? [],
        checks = checks ?? [];

  @override
  Future<EmailCodeRequestResult> requestCode() async {
    requested++;
    return requests.isEmpty
        ? const EmailCodeRequestResult(EmailCodeRequestStatus.sent, retryAfter: 60, maskedEmail: 'a***@gmail.com')
        : requests.removeAt(0);
  }

  @override
  Future<EmailCodeCheckResult> checkCode(String code) async {
    codesTried.add(code);
    return checks.isEmpty
        ? const EmailCodeCheckResult(EmailCodeCheckStatus.verified)
        : checks.removeAt(0);
  }
}

const _sent = EmailCodeRequestResult(
  EmailCodeRequestStatus.sent,
  retryAfter: 60,
  maskedEmail: 'a***@gmail.com',
);

class _Host extends StatefulWidget {
  final String initialText;
  final String? savedEmail;
  final bool verified;
  final bool isOnline;
  final bool saveSucceeds;
  final _Fake verifier;
  final List<String> log;
  const _Host({
    required this.verifier,
    required this.log,
    this.initialText = 'ana@gmail.com',
    this.savedEmail = 'ana@gmail.com',
    this.verified = false,
    this.isOnline = true,
    this.saveSucceeds = true,
  });
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final TextEditingController email = TextEditingController(text: widget.initialText);
  late String? saved = widget.savedEmail;
  late bool verified = widget.verified;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(key: const ValueKey('email-field'), controller: email),
          ContactEmailVerification(
            emailController: email,
            savedEmail: saved,
            verified: verified,
            isOnline: widget.isOnline,
            verifier: widget.verifier,
            saveEmail: () async {
              widget.log.add('save:${email.text.trim()}');
              if (!widget.saveSucceeds) return false;
              setState(() => saved = email.text.trim().toLowerCase());
              return true;
            },
            onVerified: () {
              widget.log.add('verified');
              setState(() => verified = true);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester, _Host host) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: host,
    ),
  );
  await tester.pump();
}

Finder _action() => find.byKey(const ValueKey('verify-email-action'));
Finder _unverified() => find.byKey(const ValueKey('email-status-unverified'));
Finder _verifiedChip() => find.byKey(const ValueKey('email-status-verified'));
Finder _codeField() => find.byKey(const ValueKey('verify-email-code'));
Finder _confirm() => find.byKey(const ValueKey('verify-email-confirm'));
Finder _resend() => find.byKey(const ValueKey('verify-email-resend'));

Future<void> _openCodeEntry(WidgetTester tester) async {
  await tester.tap(_action());
  await tester.pump();
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String code) async {
  await tester.enterText(find.descendant(of: _codeField(), matching: find.byType(TextField)), code);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  rules();

  group('status line', () {
    testWidgets('an unverified address shows "Unverified" and a Verify Email action', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _Host(verifier: _Fake(), log: []));
        expect(_unverified(), findsOneWidget);
        expect(find.text('Unverified'), findsOneWidget);
        expect(_action(), findsOneWidget);
        expect(find.text('Verify Email'), findsOneWidget);
        expect(_verifiedChip(), findsNothing);
      });
    });

    testWidgets('a verified address shows "Verified" and no action', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _Host(verifier: _Fake(), log: [], verified: true));
        expect(_verifiedChip(), findsOneWidget);
        expect(find.text('Verified'), findsOneWidget);
        expect(_action(), findsNothing);
      });
    });

    testWidgets('no address, nothing shown', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _Host(verifier: _Fake(), log: [], initialText: '', savedEmail: null));
        expect(_unverified(), findsNothing);
        expect(_action(), findsNothing);
      });
    });

    testWidgets('typing a different address makes it Unverified at once, even if the saved one was verified', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _Host(verifier: _Fake(), log: [], verified: true));
        expect(_verifiedChip(), findsOneWidget);
        await tester.enterText(find.byKey(const ValueKey('email-field')), 'other@gmail.com');
        await tester.pump();
        expect(_unverified(), findsOneWidget);
        expect(_verifiedChip(), findsNothing);
        expect(_action(), findsOneWidget);
        // Typing the verified address back restores Verified.
        await tester.enterText(find.byKey(const ValueKey('email-field')), 'ANA@gmail.com');
        await tester.pump();
        expect(_verifiedChip(), findsOneWidget);
      });
    });
  });

  group('verifying', () {
    testWidgets('Verify Email sends a code and opens the code field; the saved address is not re-saved', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final log = <String>[];
        final fake = _Fake(requests: [_sent]);
        await _pump(tester, _Host(verifier: fake, log: log));
        await _openCodeEntry(tester);
        expect(fake.requested, 1);
        expect(log, isEmpty, reason: 'already saved: nothing to save first');
        expect(_codeField(), findsOneWidget);
        expect(find.textContaining('We sent a 6-digit code to a***@gmail.com'), findsOneWidget);
        expect(_action(), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a changed address is saved first, then the code is sent', (tester) async {
      await runIgnoringFontErrors(() async {
        final log = <String>[];
        final fake = _Fake(requests: [_sent]);
        await _pump(tester, _Host(verifier: fake, log: log));
        await tester.enterText(find.byKey(const ValueKey('email-field')), 'new@gmail.com');
        await tester.pump();
        await _openCodeEntry(tester);
        expect(log, ['save:new@gmail.com']);
        expect(fake.requested, 1);
        expect(_codeField(), findsOneWidget);
      });
    });

    testWidgets('if the address cannot be saved, no code is requested', (tester) async {
      await runIgnoringFontErrors(() async {
        final fake = _Fake();
        await _pump(tester, _Host(verifier: fake, log: [], saveSucceeds: false));
        await tester.enterText(find.byKey(const ValueKey('email-field')), 'bad@gmail.com');
        await tester.pump();
        await _openCodeEntry(tester);
        expect(fake.requested, 0);
        expect(_codeField(), findsNothing);
        expect(_unverified(), findsOneWidget);
      });
    });

    testWidgets('offline: a clear message and no server call', (tester) async {
      await runIgnoringFontErrors(() async {
        final fake = _Fake();
        await _pump(tester, _Host(verifier: fake, log: [], isOnline: false));
        await tester.tap(_action());
        await tester.pump();
        expect(fake.requested, 0);
        expect(find.textContaining("You're offline"), findsOneWidget);
        expect(_unverified(), findsOneWidget);
      });
    });

    testWidgets('the right code verifies: success shown, status Verified, host told', (tester) async {
      await runIgnoringFontErrors(() async {
        final log = <String>[];
        final fake = _Fake(requests: [_sent], checks: [const EmailCodeCheckResult(EmailCodeCheckStatus.verified)]);
        await _pump(tester, _Host(verifier: fake, log: log));
        await _openCodeEntry(tester);
        await _type(tester, '482913');
        await tester.tap(_confirm());
        await tester.pump();
        await tester.pump();
        expect(fake.codesTried, ['482913']);
        expect(log, ['verified']);
        expect(_verifiedChip(), findsOneWidget);
        expect(find.text('Your email address is verified.'), findsOneWidget);
        expect(_codeField(), findsNothing);
        expect(_action(), findsNothing);
      });
    });

    testWidgets('a wrong code stays Unverified and says how many tries are left', (tester) async {
      await runIgnoringFontErrors(() async {
        final log = <String>[];
        final fake = _Fake(
          requests: [_sent],
          checks: [const EmailCodeCheckResult(EmailCodeCheckStatus.invalidCode, attemptsLeft: 3)],
        );
        await _pump(tester, _Host(verifier: fake, log: log));
        await _openCodeEntry(tester);
        await _type(tester, '111111');
        await tester.tap(_confirm());
        await tester.pump();
        await tester.pump();
        expect(find.text('That code is not correct. Attempts left: 3.'), findsOneWidget);
        expect(log, isEmpty);
        expect(_unverified(), findsOneWidget);
        expect(_verifiedChip(), findsNothing);
        // The field is cleared and still open for another try.
        expect(_codeField(), findsOneWidget);
      });
    });

    testWidgets('less than six digits is refused on the field, without asking the server', (tester) async {
      await runIgnoringFontErrors(() async {
        final fake = _Fake(requests: [_sent]);
        await _pump(tester, _Host(verifier: fake, log: []));
        await _openCodeEntry(tester);
        await _type(tester, '12345');
        await tester.tap(_confirm());
        await tester.pump();
        expect(find.text('Enter the 6-digit code.'), findsOneWidget);
        expect(fake.codesTried, isEmpty);
      });
    });

    testWidgets('only digits can be typed, at most six', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _Host(verifier: _Fake(requests: [_sent]), log: []));
        await _openCodeEntry(tester);
        await _type(tester, '12ab34567890');
        final text = tester
            .widget<TextField>(find.descendant(of: _codeField(), matching: find.byType(TextField)))
            .controller!
            .text;
        expect(text, '123456');
      });
    });

    for (final c in <(EmailCodeCheckStatus, String)>[
      (EmailCodeCheckStatus.expired, 'This code has expired. Request a new one.'),
      (EmailCodeCheckStatus.tooManyAttempts, 'Too many incorrect attempts. Request a new code.'),
      (EmailCodeCheckStatus.noCode, 'No code is waiting. Request a new one.'),
      (EmailCodeCheckStatus.emailChanged, 'Your email address changed. Request a new code.'),
    ]) {
      testWidgets('${c.$1.name}: stays Unverified and goes back to "Verify Email"', (tester) async {
        await runIgnoringFontErrors(() async {
          final fake = _Fake(requests: [_sent], checks: [EmailCodeCheckResult(c.$1)]);
          await _pump(tester, _Host(verifier: fake, log: []));
          await _openCodeEntry(tester);
          await _type(tester, '123456');
          await tester.tap(_confirm());
          await tester.pump();
          await tester.pump();
          expect(find.text(c.$2), findsOneWidget);
          expect(_unverified(), findsOneWidget);
          expect(_codeField(), findsNothing);
          expect(_action(), findsOneWidget);
        });
      });
    }

    testWidgets('a server failure while checking leaves it Unverified with a retry message', (tester) async {
      await runIgnoringFontErrors(() async {
        final fake = _Fake(requests: [_sent], checks: [const EmailCodeCheckResult(EmailCodeCheckStatus.error)]);
        await _pump(tester, _Host(verifier: fake, log: []));
        await _openCodeEntry(tester);
        await _type(tester, '123456');
        await tester.tap(_confirm());
        await tester.pump();
        await tester.pump();
        expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
        expect(_unverified(), findsOneWidget);
      });
    });
  });

  group('sending problems', () {
    for (final c in <(EmailCodeRequestResult, String)>[
      (const EmailCodeRequestResult(EmailCodeRequestStatus.sendFailed), "We couldn't send the email. Please try again in a moment."),
      (const EmailCodeRequestResult(EmailCodeRequestStatus.limit, retryAfter: 900), 'Too many codes requested. Please try again later.'),
      (const EmailCodeRequestResult(EmailCodeRequestStatus.unauthorized), 'Your session has expired. Please sign in again.'),
      (const EmailCodeRequestResult(EmailCodeRequestStatus.error), 'Something went wrong. Please try again.'),
      (const EmailCodeRequestResult(EmailCodeRequestStatus.noEmail), 'Add an email address first.'),
    ]) {
      testWidgets('${c.$1.status.name}: message shown, nothing verified', (tester) async {
        await runIgnoringFontErrors(() async {
          await _pump(tester, _Host(verifier: _Fake(requests: [c.$1]), log: []));
          await _openCodeEntry(tester);
          expect(find.text(c.$2), findsOneWidget);
          expect(_codeField(), findsNothing);
          expect(_unverified(), findsOneWidget);
          expect(_action(), findsOneWidget, reason: 'can try again');
        });
      });
    }

    testWidgets('already verified on the server: the host is told and the line turns Verified', (tester) async {
      await runIgnoringFontErrors(() async {
        final log = <String>[];
        await _pump(
          tester,
          _Host(
            verifier: _Fake(requests: [const EmailCodeRequestResult(EmailCodeRequestStatus.alreadyVerified)]),
            log: log,
          ),
        );
        await _openCodeEntry(tester);
        expect(log, ['verified']);
        expect(_verifiedChip(), findsOneWidget);
      });
    });
  });

  group('resend and rate limiting', () {
    testWidgets('Resend is locked for a minute (counting down), then sends another code', (tester) async {
      await runIgnoringFontErrors(() async {
        final fake = _Fake(requests: [_sent, _sent]);
        await _pump(tester, _Host(verifier: fake, log: []));
        await _openCodeEntry(tester);
        expect(find.text('Resend in 60s'), findsOneWidget);
        expect(tester.widget<TextButton>(_resend()).onPressed, isNull);
        await tester.pump(const Duration(seconds: 25));
        expect(find.text('Resend in 35s'), findsOneWidget);
        await tester.pump(const Duration(seconds: 36));
        expect(find.text('Resend code'), findsOneWidget);
        expect(tester.widget<TextButton>(_resend()).onPressed, isNotNull);
        await tester.tap(_resend());
        await tester.pump();
        await tester.pump();
        expect(fake.requested, 2);
        expect(find.text('Resend in 60s'), findsOneWidget, reason: 'the clock restarts');
      });
    });

    testWidgets('the server cooldown is shown with the seconds left and Resend stays locked', (tester) async {
      await runIgnoringFontErrors(() async {
        final fake = _Fake(requests: [_sent, const EmailCodeRequestResult(EmailCodeRequestStatus.cooldown, retryAfter: 17)]);
        await _pump(tester, _Host(verifier: fake, log: []));
        await _openCodeEntry(tester);
        await tester.pump(const Duration(seconds: 61));
        await tester.tap(_resend());
        await tester.pump();
        await tester.pump();
        expect(find.text('Please wait 17 seconds before requesting another code.'), findsOneWidget);
        expect(find.text('Resend in 17s'), findsOneWidget);
      });
    });

    testWidgets('editing the address after a code was sent closes the code field: that code was for the old text', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _Host(verifier: _Fake(requests: [_sent]), log: []));
        await _openCodeEntry(tester);
        expect(_codeField(), findsOneWidget);
        await tester.enterText(find.byKey(const ValueKey('email-field')), 'changed@gmail.com');
        await tester.pump();
        expect(_codeField(), findsNothing);
        expect(_unverified(), findsOneWidget);
        expect(_action(), findsOneWidget);
      });
    });
  });

  testWidgets('layout: no overflow at 320 px with the code field open and an error showing', (tester) async {
    await runIgnoringFontErrors(() async {
      tester.view.physicalSize = const Size(320, 1000);
      await _pump(
        tester,
        _Host(
          verifier: _Fake(
            requests: [_sent],
            checks: [const EmailCodeCheckResult(EmailCodeCheckStatus.invalidCode, attemptsLeft: 2)],
          ),
          log: [],
          initialText: 'a-very-long-address.with.many.parts@some-long-domain-name.example.org',
          savedEmail: 'a-very-long-address.with.many.parts@some-long-domain-name.example.org',
        ),
      );
      await _openCodeEntry(tester);
      await _type(tester, '000000');
      await tester.tap(_confirm());
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
