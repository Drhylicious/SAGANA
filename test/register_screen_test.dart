import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/presentation/screens/auth/register_screen.dart';
import 'package:sagana/presentation/widgets/app_dropdown_field.dart';

Widget _host() => const MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: Locale('en'),
  home: RegisterScreen(),
);

Future<void> _pumpScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host());
  await tester.pump();
}

void main() {
  testWidgets('Farmer: Username is always visible and required, from the start', (
    tester,
  ) async {
    await _pumpScreen(tester);

    // Before any name is typed, the username field is already there.
    expect(find.text('Username *'), findsOneWidget);
    // The single Full Name field is now Surname + First Name (required) and
    // Middle Initial + Suffix (optional).
    expect(find.text('Surname *'), findsOneWidget);
    expect(find.text('First Name *'), findsOneWidget);
    expect(find.text('M.I.'), findsOneWidget);
    expect(find.text('Suffix'), findsOneWidget);
    expect(find.text('Full Name *'), findsNothing);
    expect(find.text('Choose a Username *'), findsNothing);
  });

  testWidgets('typing a name looks nothing up and shows no registry notice', (
    tester,
  ) async {
    await _pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Surname *'),
      'Salangsang',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'First Name *'),
      'Jhon Drhy',
    );
    // Longer than the old 600 ms registry debounce.
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('registry', findRichText: true), findsNothing);
    expect(find.textContaining('Registry', findRichText: true), findsNothing);
    expect(find.textContaining('Official SP3', findRichText: true), findsNothing);
    expect(find.textContaining('already exists', findRichText: true), findsNothing);
    // The name field is still just a text field (no spinner, no banner).
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Buyer: the label reads "Username" and the form is one step', (
    tester,
  ) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('Buyer'));
    await tester.pump();

    expect(find.text('Username *'), findsOneWidget);
    expect(find.text('Choose a Username *'), findsNothing);
    // No Farmer wizard for a Buyer.
    expect(find.textContaining('Step 1 of'), findsNothing);
    expect(find.text('Create Account'), findsWidgets);
  });

  testWidgets('Farmer: Next with the name empty flags Surname and First Name only', (
    tester,
  ) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('Next'));
    await tester.pump();

    expect(find.text('Surname is required'), findsOneWidget);
    expect(find.text('First name is required'), findsOneWidget);
    // Optional parts are never flagged.
    expect(find.text('Enter one letter only'), findsNothing);
    // Still on step 1.
    expect(find.text('Step 1 of 3'), findsOneWidget);
  });

  testWidgets('Farmer: a complete name clears the name errors and previews the full name', (
    tester,
  ) async {
    await _pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Surname *'),
      'Salangsang',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'First Name *'),
      'Jhon Drhy',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'M.I.'),
      'm',
    );
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();

    expect(find.text('Surname is required'), findsNothing);
    expect(find.text('First name is required'), findsNothing);
    expect(find.text('Full name: Jhon Drhy M. Salangsang'), findsOneWidget);
  });

  testWidgets('Suffix uses the same dropdown design as Gender', (tester) async {
    await _pumpScreen(tester);
    // Farmer: Suffix and Gender are both the app's standard dropdown.
    expect(find.byType(AppDropdownField<String>), findsNWidgets(2));
    expect(find.descendant(of: find.byKey(const ValueKey('name-suffix')), matching: find.text('Suffix')), findsOneWidget);
    expect(find.text('Gender *'), findsOneWidget);
  });

  testWidgets('Buyer: the same four name fields', (tester) async {
    await _pumpScreen(tester);
    await tester.tap(find.text('Buyer'));
    await tester.pump();

    expect(find.text('Surname *'), findsOneWidget);
    expect(find.text('First Name *'), findsOneWidget);
    expect(find.text('M.I.'), findsOneWidget);
    expect(find.text('Suffix'), findsOneWidget);
    expect(find.text('Full Name *'), findsNothing);
  });

  testWidgets('Farmer registration is a three-step wizard', (tester) async {
    await _pumpScreen(tester);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text('Personal Information'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });
}
