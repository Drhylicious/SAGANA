import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/presentation/screens/admin/add_new_member_screen.dart';
import 'package:sagana/presentation/screens/admin/create_officer_account_screen.dart';
import 'package:sagana/presentation/widgets/account_form_widgets.dart';
import 'package:sagana/presentation/widgets/shared_widgets.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

Widget _host(Widget screen) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: screen,
);

Future<void> _pump(WidgetTester tester, Widget screen, {Size? size}) async {
  tester.view.physicalSize = size ?? const Size(900, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host(screen));
  await tester.pump(const Duration(milliseconds: 300));
}

List<String> _sectionTitles(WidgetTester tester) => tester
    .widgetList<AccountFormSection>(find.byType(AccountFormSection))
    .map((s) => s.title)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockStorageChannels();

  setUpAll(() async {
    // No network in tests: fall back to the default font instead of fetching.
    GoogleFonts.config.allowRuntimeFetching = false;
    // The two screens create their repositories on construction, which need a
    // Supabase client. A fake address is enough: nothing here makes a request.
    await Supabase.initialize(url: 'http://localhost:54321', publishableKey: 'test-key');
  });

  testWidgets('both screens use the same components, in the same order', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await _pump(tester, const AddNewMemberScreen());
      final farmerSections = _sectionTitles(tester);
      expect(find.byType(ManagerNoticeCard), findsOneWidget);
      expect(find.byType(TemporaryPasswordField), findsOneWidget);
      expect(find.byType(PrimaryButton), findsOneWidget);

      await _pump(tester, const CreateOfficerAccountScreen());
      final officerSections = _sectionTitles(tester);
      expect(find.byType(ManagerNoticeCard), findsOneWidget);
      expect(find.byType(TemporaryPasswordField), findsOneWidget);
      expect(find.byType(PrimaryButton), findsOneWidget);

      // Same first two sections, same words, same order.
      expect(farmerSections.take(2).toList(), [
        'Account Credentials',
        'Personal Information',
      ]);
      expect(officerSections.take(2).toList(), farmerSections.take(2).toList());
      // Then each form's own: Farmer has membership and crops, the Officer has
      // the officer position.
      expect(officerSections, [
        'Account Credentials',
        'Personal Information',
        'Officer',
      ]);
    });
  });

  testWidgets('both show the same Manager Notice heading', (tester) async {
    await runIgnoringFontErrors(() async {
      await _pump(tester, const AddNewMemberScreen());
      expect(find.text('Manager Notice'), findsOneWidget);
      await _pump(tester, const CreateOfficerAccountScreen());
      expect(find.text('Manager Notice'), findsOneWidget);
    });
  });

  testWidgets('the Officer form keeps its own fields (and DOB and gender are required)', (tester) async {
    await runIgnoringFontErrors(() async {
      await _pump(tester, const CreateOfficerAccountScreen());
      expect(find.text('Position'), findsOneWidget);
      expect(find.text('Surname *'), findsOneWidget);
      expect(find.text('First Name *'), findsOneWidget);
      expect(find.text('M.I.'), findsOneWidget);
      expect(find.text('Suffix'), findsOneWidget);
      expect(find.text('Full Name'), findsNothing);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Phone Number'), findsOneWidget);
      expect(find.text('Date of Birth *'), findsOneWidget);
      expect(find.text('Gender *'), findsOneWidget);
      expect(find.text('SAGANA Username'), findsOneWidget);
      expect(find.text('Temporary Password'), findsOneWidget);
      // Required, as on Create Farmer.
      // No membership or crop sections.
      expect(find.text('Cooperative Membership'), findsNothing);
      expect(find.text('Initial Crops'), findsNothing);
      expect(find.text('Create Officer Account'), findsOneWidget);
    });
  });

  testWidgets(
    'the Farmer form is unchanged: required DOB/gender, membership and crops',
    (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, const AddNewMemberScreen());
        expect(find.text('Date of Birth *'), findsOneWidget);
        expect(find.text('Gender *'), findsOneWidget);
        expect(find.text('Cooperative Membership'), findsOneWidget);
        expect(find.text('Initial Crops'), findsOneWidget);
        expect(find.text('Create Farmer Account'), findsOneWidget);
      });
    },
  );

  testWidgets('AUTO fills a secure 10-character password on both screens', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      for (final screen in <Widget>[
        const AddNewMemberScreen(),
        const CreateOfficerAccountScreen(),
      ]) {
        await _pump(tester, screen);
        await tester.tap(find.text('AUTO'));
        await tester.pump();
        final field = tester.widget<TextFormField>(
          find.descendant(
            of: find.byType(TemporaryPasswordField),
            matching: find.byType(TextFormField),
          ),
        );
        final password = field.controller!.text;
        expect(password.length, 10, reason: '${screen.runtimeType}');
        expect(RegExp(r'[A-Z]').hasMatch(password), isTrue);
        expect(RegExp(r'[a-z]').hasMatch(password), isTrue);
        expect(RegExp(r'[0-9]').hasMatch(password), isTrue);
      }
    });
  });

  testWidgets('both screens lay out without overflow on a narrow phone', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      for (final screen in <Widget>[
        const AddNewMemberScreen(),
        const CreateOfficerAccountScreen(),
      ]) {
        await _pump(tester, screen, size: const Size(320, 1600));
        expect(tester.takeException(), isNull, reason: '${screen.runtimeType}');
      }
    });
  });

  // Submitting an incomplete form on either screen.
  for (final entry in <String, Widget Function()>{
    'Create Farmer': () => const AddNewMemberScreen(),
    'Create Officer': () => const CreateOfficerAccountScreen(),
  }.entries) {
    final buttonLabel = entry.key == 'Create Farmer'
        ? 'Create Farmer Account'
        : 'Create Officer Account';

    testWidgets('${entry.key}: empty submit shows one message per field', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, entry.value());
        await tester.tap(find.text(buttonLabel));
        await tester.pump();

        expect(find.text('Date of birth is required'), findsOneWidget);
        expect(find.text('Gender is required'), findsOneWidget);
        // The old combined message must not appear under Gender (or anywhere).
        expect(find.text('Date of birth and gender are required.'), findsNothing);
        // Other required fields show theirs too.
        expect(find.text('Surname is required'), findsOneWidget);
        expect(find.text('First name is required'), findsOneWidget);
      });
    });

    testWidgets('${entry.key}: with everything else filled in, DOB and gender still block submit', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, entry.value());
        await tester.enterText(find.widgetWithText(TextFormField, 'e.g. juandelacruz'), 'qa_user1');
        await tester.enterText(
          find.descendant(
            of: find.byType(TemporaryPasswordField),
            matching: find.byType(TextFormField),
          ),
          'Abcdefg234',
        );
        await tester.enterText(find.byKey(const ValueKey('name-surname')), 'Santos');
        await tester.enterText(find.byKey(const ValueKey('name-first')), 'Maria');
        await tester.tap(find.text(buttonLabel));
        await tester.pump();

        expect(find.text('Date of birth is required'), findsOneWidget);
        expect(find.text('Gender is required'), findsOneWidget);

        // Pick a gender: only that error goes away.
        await tester.tap(find.byType(AccountGenderField));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Male').last);
        await tester.pumpAndSettle();
        expect(find.text('Gender is required'), findsNothing);
        expect(find.text('Date of birth is required'), findsOneWidget);

        // Pick a date of birth (the real calendar): that error goes away too.
        await tester.tap(find.byType(AccountDateOfBirthField));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.text('Date of birth is required'), findsNothing);
      });
    });
  }
}
