import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/presentation/widgets/app_dropdown_field.dart';
import 'package:sagana/presentation/widgets/person_name_fields.dart';

import 'support/ignore_font_errors.dart';

/// Hosts the fields in a form with a Validate button, in either look, and keeps
/// the chosen suffix the way the real screens do.
class _Host extends StatefulWidget {
  const _Host({required this.style, required this.onSuffix});
  final PersonNameFieldsStyle style;
  final ValueChanged<String?> onSuffix;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final formKey = GlobalKey<FormState>();
  final surname = TextEditingController();
  final first = TextEditingController();
  final middle = TextEditingController();
  String? suffix;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          PersonNameFields(
            style: widget.style,
            surnameController: surname,
            firstNameController: first,
            middleInitialController: middle,
            suffix: suffix,
            onSuffixChanged: (v) {
              setState(() => suffix = v);
              widget.onSuffix(v);
            },
          ),
          TextButton(
            onPressed: () => formKey.currentState!.validate(),
            child: const Text('Validate'),
          ),
        ],
      ),
    ),
  );
}

Future<_HostState> _pump(
  WidgetTester tester,
  PersonNameFieldsStyle style, {
  ValueChanged<String?>? onSuffix,
  Size size = const Size(900, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: _Host(style: style, onSuffix: onSuffix ?? (_) {}),
    ),
  );
  await tester.pump();
  return tester.state<_HostState>(find.byType(_Host));
}

Finder _surname() => find.byKey(const ValueKey('name-surname'));
Finder _first() => find.byKey(const ValueKey('name-first'));
Finder _middle() => find.byKey(const ValueKey('name-middle'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('sign-up look: M.I. has no icon and its label is not cut off', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await _pump(tester, PersonNameFieldsStyle.auth, size: const Size(360, 1200));
      final middle = tester.widget<TextFormField>(_middle());
      final field = tester.widget<TextField>(
        find.descendant(of: _middle(), matching: find.byType(TextField)),
      );
      expect(field.decoration!.prefixIcon, isNull, reason: 'no icon: the row is shared');
      expect(middle.controller, isNotNull);
      // The full label is on screen and fits inside its field.
      final label = find.text('M.I.');
      expect(label, findsOneWidget);
      final labelBox = tester.getRect(label);
      final fieldBox = tester.getRect(_middle());
      expect(labelBox.right, lessThanOrEqualTo(fieldBox.right));
      // Suffix is the app's standard dropdown (as Gender is), and sits on the
      // same bottom line as M.I., so the two boxes line up in one row.
      expect(find.byType(AppDropdownField<String>), findsOneWidget);
      final suffixBox = tester.getRect(find.byKey(const ValueKey('name-suffix')));
      expect((suffixBox.bottom - fieldBox.bottom).abs(), lessThan(8));
    });
  });

  for (final style in PersonNameFieldsStyle.values) {
    group('${style.name} look', () {
      testWidgets('labels: Surname and First Name required, the rest optional', (
        tester,
      ) async {
        await runIgnoringFontErrors(() async {
          await _pump(tester, style);
          expect(find.text('Surname *'), findsOneWidget);
          expect(find.text('First Name *'), findsOneWidget);
          expect(find.text('M.I.'), findsOneWidget);
          expect(find.text('Suffix'), findsOneWidget);
          // The single Full Name field is gone.
          expect(find.textContaining('Full Name'), findsNothing);
        });
      });

      testWidgets('empty: only Surname and First Name complain', (tester) async {
        await runIgnoringFontErrors(() async {
          await _pump(tester, style);
          await tester.tap(find.text('Validate'));
          await tester.pump();
          expect(find.text('Surname is required'), findsOneWidget);
          expect(find.text('First name is required'), findsOneWidget);
          // Middle initial and suffix are optional: nothing is flagged.
          expect(find.text('Enter one letter only'), findsNothing);
        });
      });

      testWidgets('a one-letter surname is too short', (tester) async {
        await runIgnoringFontErrors(() async {
          await _pump(tester, style);
          await tester.enterText(_surname(), 'C');
          await tester.enterText(_first(), 'Juan');
          await tester.tap(find.text('Validate'));
          await tester.pump();
          expect(find.text('Must be 2 to 60 characters'), findsOneWidget);
          expect(find.text('First name is required'), findsNothing);
        });
      });

      testWidgets('digits and symbols cannot be typed into a name', (tester) async {
        await runIgnoringFontErrors(() async {
          final host = await _pump(tester, style);
          await tester.enterText(_first(), 'J0h@n_9');
          await tester.pump();
          expect(host.first.text, 'Jhn');
          await tester.enterText(_surname(), "O'Brien-Dela Peña");
          await tester.pump();
          expect(host.surname.text, "O'Brien-Dela Peña");
        });
      });

      testWidgets('middle initial: one letter (a period is allowed), at most two characters', (
        tester,
      ) async {
        await runIgnoringFontErrors(() async {
          final host = await _pump(tester, style);
          await tester.enterText(_surname(), 'Cruz');
          await tester.enterText(_first(), 'Juan');

          await tester.enterText(_middle(), 'd.');
          await tester.tap(find.text('Validate'));
          await tester.pump();
          expect(find.text('Enter one letter only'), findsNothing);

          // Digits are not typed; more than two characters are cut off.
          await tester.enterText(_middle(), '1');
          await tester.pump();
          expect(host.middle.text, '');
          await tester.enterText(_middle(), 'abc');
          await tester.pump();
          expect(host.middle.text, 'ab');
          await tester.tap(find.text('Validate'));
          await tester.pump();
          expect(find.text('Enter one letter only'), findsOneWidget);
        });
      });

      testWidgets('Suffix offers None, Jr., Sr., II, III, IV and V', (tester) async {
        await runIgnoringFontErrors(() async {
          String? picked = 'unset';
          await _pump(tester, style, onSuffix: (v) => picked = v);

          await tester.tap(find.byKey(const ValueKey('name-suffix')));
          await tester.pumpAndSettle();
          for (final label in ['Jr.', 'Sr.', 'II', 'III', 'IV', 'V']) {
            expect(find.text(label), findsWidgets, reason: label);
          }
          expect(find.text('None'), findsWidgets);

          await tester.tap(find.text('III').last);
          await tester.pumpAndSettle();
          expect(picked, 'III');

          // Back to none.
          await tester.tap(find.byKey(const ValueKey('name-suffix')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('None').last);
          await tester.pumpAndSettle();
          expect(picked, isNull);
        });
      });

      testWidgets('the complete name is shown as First M. Surname Suffix', (
        tester,
      ) async {
        await runIgnoringFontErrors(() async {
          await _pump(tester, style);
          // Nothing to show until both required parts are typed.
          expect(find.byKey(const ValueKey('name-preview')), findsNothing);

          await tester.enterText(_surname(), 'Cruz');
          await tester.enterText(_first(), 'Juan');
          await tester.pump();
          expect(find.text('Full name: Juan Cruz'), findsOneWidget);

          await tester.enterText(_middle(), 'd');
          await tester.pump();
          expect(find.text('Full name: Juan D. Cruz'), findsOneWidget);

          await tester.tap(find.byKey(const ValueKey('name-suffix')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Jr.').last);
          await tester.pumpAndSettle();
          expect(find.text('Full name: Juan D. Cruz Jr.'), findsOneWidget);
        });
      });

      testWidgets('lays out without overflow on a narrow phone', (tester) async {
        await runIgnoringFontErrors(() async {
          await _pump(tester, style, size: const Size(320, 1200));
          await tester.enterText(_surname(), 'Dela Cruz-Santos');
          await tester.enterText(_first(), 'Marc Louie');
          await tester.tap(find.text('Validate'));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      });
    });
  }

  group('PersonNameInput (a saved name loaded into the fields)', () {
    test('an account with parts loads them as stored', () {
      final input = PersonNameInput()
        ..load(
          fullName: 'Juan D. Cruz Jr.',
          surnameValue: 'Cruz',
          firstNameValue: 'Juan',
          middleInitialValue: 'D',
          suffixValue: 'Jr.',
        );
      expect(input.surname.text, 'Cruz');
      expect(input.firstName.text, 'Juan');
      expect(input.middleInitial.text, 'D');
      expect(input.suffix, 'Jr.');
      expect(input.legacyFullName, isNull);
      expect(input.parts!.fullName, 'Juan D. Cruz Jr.');
      input.dispose();
    });

    test('an older account is NOT split: fields empty, stored name kept, nothing to save', () {
      final input = PersonNameInput()
        ..load(
          fullName: 'Maria Luisa Santos',
          surnameValue: null,
          firstNameValue: null,
        );
      expect(input.surname.text, '');
      expect(input.firstName.text, '');
      expect(input.legacyFullName, 'Maria Luisa Santos');
      expect(input.isBlank, isTrue);
      expect(input.parts, isNull);
      expect(input.displayName('Farmer'), 'Maria Luisa Santos');
      input.dispose();
    });

    test('completing an older account yields the parts to save', () {
      final input = PersonNameInput()
        ..load(fullName: 'Maria Luisa Santos', surnameValue: null, firstNameValue: null);
      input.surname.text = 'Santos';
      input.firstName.text = 'Maria Luisa';
      expect(input.parts!.toColumns()['first_name'], 'Maria Luisa');
      expect(input.displayName('Farmer'), 'Maria Luisa Santos');
      input.dispose();
    });
  });

  testWidgets('legacy account: empty fields are allowed, one filled field is not', (tester) async {
    await runIgnoringFontErrors(() async {
      final surname = TextEditingController();
      final first = TextEditingController();
      final middle = TextEditingController();
      final formKey = GlobalKey<FormState>();
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Form(
              key: formKey,
              child: PersonNameFields(
                style: PersonNameFieldsStyle.profile,
                surnameController: surname,
                firstNameController: first,
                middleInitialController: middle,
                suffix: null,
                onSuffixChanged: (_) {},
                allowAllBlank: true,
                legacyFullName: 'Maria Luisa Santos',
              ),
            ),
          ),
        ),
      );
      expect(formKey.currentState!.validate(), isTrue);
      expect(find.byKey(const ValueKey('name-legacy-notice')), findsOneWidget);
      surname.text = 'Santos';
      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('First name is required'), findsOneWidget);
      first.text = 'Maria Luisa';
      expect(formKey.currentState!.validate(), isTrue);
    });
  });
}
