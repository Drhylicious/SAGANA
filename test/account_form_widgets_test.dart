import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/theme/sagana_colors.dart';
import 'package:sagana/presentation/widgets/account_form_widgets.dart';

import 'support/ignore_font_errors.dart';

Widget _host(Widget child, {String locale = 'en', double width = 360}) =>
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(locale),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );

void main() {
  // No network in tests: fall back to the default font instead of fetching.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('ManagerNoticeCard shows its title and body', (tester) async {
    await tester.pumpWidget(
      _host(const ManagerNoticeCard(title: 'Manager Notice', body: 'Body text')),
    );
    expect(find.text('Manager Notice'), findsOneWidget);
    expect(find.text('Body text'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
  });

  testWidgets('AccountFormSection shows an icon, a title and its children', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => AccountFormSection(
            icon: Icons.lock_person_rounded,
            title: 'Account Credentials',
            cs: Theme.of(context).colorScheme,
            sagana: context.saganaColors,
            children: const [Text('child one'), Text('child two')],
          ),
        ),
      ),
    );
    expect(find.text('Account Credentials'), findsOneWidget);
    expect(find.byIcon(Icons.lock_person_rounded), findsOneWidget);
    expect(find.text('child one'), findsOneWidget);
    expect(find.text('child two'), findsOneWidget);
  });

  testWidgets('AccountFormSection shortens a very long title instead of overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => AccountFormSection(
            icon: Icons.eco_rounded,
            title: 'Paunang mga Pananim at Iba Pang Napakahabang Pamagat',
            cs: Theme.of(context).colorScheme,
            sagana: context.saganaColors,
            trailing: const Text('Add'),
            children: const [SizedBox(height: 10)],
          ),
        ),
        width: 280,
      ),
    );
    expect(tester.takeException(), isNull, reason: 'no overflow at 280 px');
    expect(find.text('Add'), findsOneWidget);
  });

  group('TemporaryPasswordField', () {
    testWidgets('AUTO fills the field through onGenerate, and show/hide toggles', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var obscure = true;
      var generated = 0;

      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => TemporaryPasswordField(
              controller: controller,
              obscure: obscure,
              onToggleObscure: () => setState(() => obscure = !obscure),
              onGenerate: () => setState(() {
                generated++;
                controller.text = 'Abcdefg234';
                obscure = false;
              }),
              requiredMessage: 'required',
              tooShortMessage: 'too short',
            ),
          ),
        ),
      );

      expect(find.text('AUTO'), findsOneWidget);
      await tester.tap(find.text('AUTO'));
      await tester.pump();
      expect(generated, 1);
      expect(controller.text, 'Abcdefg234');
      expect(obscure, isFalse);

      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();
      expect(obscure, isTrue);
    });

    testWidgets('empty and short passwords are refused with the given messages', (
      tester,
    ) async {
      final key = GlobalKey<FormState>();
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          Form(
            key: key,
            child: TemporaryPasswordField(
              controller: controller,
              obscure: false,
              onToggleObscure: () {},
              onGenerate: () {},
              requiredMessage: 'Password is required',
              tooShortMessage: 'Minimum 8 characters',
            ),
          ),
        ),
      );

      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Password is required'), findsOneWidget);

      controller.text = '1234567';
      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Minimum 8 characters'), findsOneWidget);

      controller.text = '12345678';
      expect(key.currentState!.validate(), isTrue);
    });

    testWidgets('the AUTO badge is translated', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          TemporaryPasswordField(
            controller: controller,
            obscure: true,
            onToggleObscure: () {},
            onGenerate: () {},
            requiredMessage: 'r',
            tooShortMessage: 's',
          ),
          locale: 'tl',
        ),
      );
      expect(find.text('AWTOMATIKO'), findsOneWidget);
    });
  });

  group('AccountDateOfBirthField and AccountGenderField', () {
    // A small form that holds both fields, so validate() behaves as it does
    // on the real screens.
    Widget form(
      GlobalKey<FormState> key, {
      Future<DateTime?> Function(BuildContext, DateTime?)? pick,
      void Function(DateTime?)? onDob,
    }) {
      DateTime? dob;
      String? gender;
      return StatefulBuilder(
        builder: (context, setState) => Form(
          key: key,
          child: Column(
            children: [
              AccountDateOfBirthField(
                value: dob,
                onChanged: (d) {
                  setState(() => dob = d);
                  onDob?.call(d);
                },
                hint: 'Select date',
                requiredMessage: 'Date of birth is required',
                underAgeMessage: 'The member must be at least 18 years old.',
                pickDate: pick,
              ),
              AccountGenderField(
                value: gender,
                options: const {'male': 'Male', 'female': 'Female'},
                onChanged: (v) => setState(() => gender = v),
                hint: 'Select gender',
                requiredMessage: 'Gender is required',
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('each empty field shows its OWN message, once', (tester) async {
      await runIgnoringFontErrors(() async {
        final key = GlobalKey<FormState>();
        await tester.pumpWidget(_host(form(key)));

        expect(key.currentState!.validate(), isFalse);
        await tester.pump();

        expect(find.text('Date of birth is required'), findsOneWidget);
        expect(find.text('Gender is required'), findsOneWidget);
        // Neither field shows the other's message, or the old combined one.
        expect(find.text('Date of birth and gender are required.'), findsNothing);
      });
    });

    testWidgets('both fields draw the red error state', (tester) async {
      await runIgnoringFontErrors(() async {
        final key = GlobalKey<FormState>();
        await tester.pumpWidget(_host(form(key)));
        key.currentState!.validate();
        await tester.pump();

        final decorators = tester
            .widgetList<InputDecorator>(find.byType(InputDecorator))
            .where((d) => d.decoration.errorText != null)
            .map((d) => d.decoration.errorText)
            .toList();
        expect(decorators, containsAll(['Date of birth is required', 'Gender is required']));
      });
    });

    testWidgets('choosing a gender clears only the gender error', (tester) async {
      await runIgnoringFontErrors(() async {
        final key = GlobalKey<FormState>();
        await tester.pumpWidget(_host(form(key)));
        key.currentState!.validate();
        await tester.pump();

        await tester.tap(find.byType(AccountGenderField));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Female').last);
        await tester.pumpAndSettle();

        expect(find.text('Gender is required'), findsNothing);
        expect(find.text('Date of birth is required'), findsOneWidget);
      });
    });

    testWidgets('a valid date of birth clears its error and is reported', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final key = GlobalKey<FormState>();
        DateTime? reported;
        await tester.pumpWidget(
          _host(
            form(
              key,
              pick: (_, __) async => DateTime(1990, 5, 17),
              onDob: (d) => reported = d,
            ),
          ),
        );
        key.currentState!.validate();
        await tester.pump();
        expect(find.text('Date of birth is required'), findsOneWidget);

        await tester.tap(find.text('Select date'));
        await tester.pumpAndSettle();

        expect(reported, DateTime(1990, 5, 17));
        expect(find.text('1990-05-17'), findsOneWidget);
        expect(find.text('Date of birth is required'), findsNothing);
      });
    });

    testWidgets('an under-18 date is refused with the age message', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final key = GlobalKey<FormState>();
        DateTime? reported = DateTime(1990, 1, 1);
        final now = DateTime.now();
        await tester.pumpWidget(
          _host(
            form(
              key,
              pick: (_, __) async => DateTime(now.year - 10, now.month, now.day),
              onDob: (d) => reported = d,
            ),
          ),
        );

        await tester.tap(find.text('Select date'));
        await tester.pumpAndSettle();
        // The age dialog appears first.
        expect(find.text('Age Requirement'), findsOneWidget);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        // The date was not kept, and the field says why (not "required").
        expect(reported, isNull);
        expect(find.text('The member must be at least 18 years old.'), findsOneWidget);
        expect(find.text('Date of birth is required'), findsNothing);
        expect(key.currentState!.validate(), isFalse);
      });
    });
  });
}
