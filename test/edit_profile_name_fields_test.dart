import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/admin_profile_model.dart';
import 'package:sagana/data/models/buyer_profile_model.dart';
import 'package:sagana/data/models/farmer_profile_model.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/presentation/screens/admin/admin_edit_profile_screen.dart';
import 'package:sagana/presentation/screens/buyer/buyer_edit_profile_screen.dart';
import 'package:sagana/presentation/screens/farmer/farmer_edit_profile_screen.dart';
import 'package:sagana/presentation/widgets/app_dropdown_field.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

/// Edit Profile for Farmer, Buyer and Manager / Officer: the name is entered in
/// Surname, First Name, M.I. and Suffix, never in one Full Name field.

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: screen,
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

const _split = (
  full: 'Juan D. Dela Cruz Jr.',
  surname: 'Dela Cruz',
  first: 'Juan',
  mi: 'D',
  suffix: 'Jr.',
);

FarmerProfileModel _farmer({bool split = true}) => FarmerProfileModel(
  userId: 'u1',
  fullName: _split.full,
  surname: split ? _split.surname : null,
  firstName: split ? _split.first : null,
  middleInitial: split ? _split.mi : null,
  suffix: split ? _split.suffix : null,
  capitalShares: 0,
  isVerified: true,
  primaryCrops: const [],
);

BuyerProfileModel _buyer({bool split = true}) => BuyerProfileModel(
  userId: 'u1',
  fullName: _split.full,
  surname: split ? _split.surname : null,
  firstName: split ? _split.first : null,
  middleInitial: split ? _split.mi : null,
  suffix: split ? _split.suffix : null,
  email: 'juan@sagana.local',
  memberSince: DateTime(2026, 1, 1),
  totalOrders: 0,
  completedOrders: 0,
  totalSpent: 0,
);

AdminProfileModel _admin({bool split = true}) => AdminProfileModel(
  userId: 'u1',
  email: 'juan@sagana.local',
  fullName: _split.full,
  surname: split ? _split.surname : null,
  firstName: split ? _split.first : null,
  middleInitial: split ? _split.mi : null,
  suffix: split ? _split.suffix : null,
);

String _text(WidgetTester tester, String key) {
  final field = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextField),
  );
  return tester.widget<TextField>(field).controller!.text;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockStorageChannels();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // The Buyer screen's cached-data notice reads the local cache.
    final dir = Directory.systemTemp.createTempSync('sagana_edit_profile');
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
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-key',
    );
  });

  final screens = <String, ({Widget Function(bool split) build, String save})>{
    'Farmer': (
      build: (split) => FarmerEditProfileScreen(initialProfile: _farmer(split: split)),
      save: 'Save',
    ),
    'Buyer': (
      build: (split) => BuyerEditProfileScreen(initialProfile: _buyer(split: split)),
      save: 'Save',
    ),
    'Manager / Officer': (
      build: (split) => AdminEditProfileScreen(initialProfile: _admin(split: split)),
      save: 'Save Changes',
    ),
  };

  for (final entry in screens.entries) {
    group('${entry.key} Edit Profile', () {
      testWidgets('shows Surname, First Name, M.I. and Suffix, filled from the account, and no Full Name field', (
        tester,
      ) async {
        await runIgnoringFontErrors(() async {
          await _pump(tester, entry.value.build(true));
          expect(find.text('Surname *'), findsOneWidget);
          expect(find.text('First Name *'), findsOneWidget);
          expect(find.text('M.I.'), findsOneWidget);
          expect(find.text('Suffix'), findsOneWidget);
          expect(_text(tester, 'name-surname'), 'Dela Cruz');
          expect(_text(tester, 'name-first'), 'Juan');
          expect(_text(tester, 'name-middle'), 'D');
          // The saved suffix is the selected value of the standard dropdown.
          final dropdown = tester.widget<AppDropdownField<String>>(
            find.byKey(const ValueKey('name-suffix')),
          );
          expect(dropdown.value, 'Jr.');

          // One name input only: no field labelled Full Name.
          expect(find.text('Full Name'), findsNothing);
          expect(find.text('Full name'), findsNothing);
          // The complete name is shown as text, built from the parts.
          expect(find.text('Full name: Juan D. Dela Cruz Jr.'), findsOneWidget);
          expect(find.byKey(const ValueKey('name-legacy-notice')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      testWidgets('Surname and First Name sit on one row, M.I. and Suffix on the next', (
        tester,
      ) async {
        await runIgnoringFontErrors(() async {
          await _pump(tester, entry.value.build(true));
          Rect box(String key) => tester.getRect(find.byKey(ValueKey(key)));
          final surname = box('name-surname');
          final first = box('name-first');
          final middle = box('name-middle');
          final suffix = box('name-suffix');
          expect((surname.top - first.top).abs(), lessThan(2));
          expect(first.left, greaterThan(surname.right));
          // Suffix has its label above the box, M.I. inside: the bottoms line up.
          expect((middle.bottom - suffix.bottom).abs(), lessThan(8));
          expect(middle.top, greaterThan(surname.bottom));
          // Same column widths in both rows.
          expect((surname.width - middle.width).abs(), lessThan(2));
          expect((first.width - suffix.width).abs(), lessThan(2));
        });
      });

      testWidgets('an emptied Surname or First Name is flagged on the field when Save is tapped', (
        tester,
      ) async {
        await runIgnoringFontErrors(() async {
          await _pump(tester, entry.value.build(true));
          await tester.enterText(
            find.descendant(
              of: find.byKey(const ValueKey('name-surname')),
              matching: find.byType(TextField),
            ),
            '',
          );
          await tester.tap(find.text(entry.value.save));
          await tester.pump();
          expect(find.text('Surname is required'), findsOneWidget);
          expect(find.text('First name is required'), findsNothing);
        });
      });

      testWidgets('an account saved before the name was split: fields empty, the stored name is shown, nothing is guessed', (
        tester,
      ) async {
        await runIgnoringFontErrors(() async {
          await _pump(tester, entry.value.build(false));
          expect(_text(tester, 'name-surname'), '');
          expect(_text(tester, 'name-first'), '');
          expect(_text(tester, 'name-middle'), '');
          final notice = find.byKey(const ValueKey('name-legacy-notice'));
          expect(notice, findsOneWidget);
          expect(
            tester.widget<Text>(notice).data,
            contains('Juan D. Dela Cruz Jr.'),
          );
          expect(find.text('Full Name'), findsNothing);
        });
      });

      testWidgets('legacy account: Save with the name fields left empty is not blocked by the name', (
        tester,
      ) async {
        await runIgnoringFontErrors(() async {
          await _pump(tester, entry.value.build(false));
          await tester.tap(find.text(entry.value.save));
          await tester.pump();
          expect(find.text('Surname is required'), findsNothing);
          expect(find.text('First name is required'), findsNothing);
        });
      });

      testWidgets('legacy account: filling only one of the two required fields is flagged', (
        tester,
      ) async {
        await runIgnoringFontErrors(() async {
          await _pump(tester, entry.value.build(false));
          await tester.enterText(
            find.descendant(
              of: find.byKey(const ValueKey('name-first')),
              matching: find.byType(TextField),
            ),
            'Juan',
          );
          await tester.tap(find.text(entry.value.save));
          await tester.pump();
          expect(find.text('Surname is required'), findsOneWidget);
        });
      });
    });
  }
}
