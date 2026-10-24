import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/buyer_address_model.dart';
import 'package:sagana/presentation/screens/buyer/add_edit_address_screen.dart';
import 'package:sagana/presentation/widgets/app_dropdown_field.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

Widget _host(Widget screen) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: screen,
);

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(900, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host(screen));
  await tester.pump(const Duration(milliseconds: 400));
}

// An address a Buyer saved before the area was fixed: somewhere else entirely.
final _oldAddress = BuyerAddressModel(
  id: 'a1',
  userId: 'u1',
  label: 'Home',
  addressLine: '5, Mabini St, Poblacion, Quezon City, NCR, 1100',
  latitude: 14.6,
  longitude: 121.0,
  notes: 'Gate is green',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  regionCode: '1300000000',
  regionName: 'National Capital Region (NCR)',
  provinceName: null,
  cityMunicipalityName: 'Quezon City',
  barangayName: 'Poblacion',
  postalCode: '1100',
  street: 'Mabini St',
  building: 'Unit 2',
  houseNo: '5',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockStorageChannels();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Supabase.initialize(url: 'http://localhost:54321', publishableKey: 'test-key');
  });

  const fixedValues = {
    'region': 'MIMAROPA Region',
    'province': 'Marinduque',
    'city': 'Torrijos',
    'barangay': 'Payanas',
    'postal': '4903',
  };

  Finder fixedField(String name) => find.byKey(ValueKey('fixed-address-$name'));

  testWidgets('Add Address shows the five fixed values, locked', (tester) async {
    await runIgnoringFontErrors(() async {
      await _pump(tester, const AddEditAddressScreen());

      for (final e in fixedValues.entries) {
        expect(fixedField(e.key), findsOneWidget, reason: e.key);
        final field = tester.widget<TextFormField>(fixedField(e.key));
        expect(field.initialValue, e.value, reason: e.key);
        final editable = tester.widget<EditableText>(
          find.descendant(of: fixedField(e.key), matching: find.byType(EditableText)),
        );
        expect(editable.readOnly, isTrue, reason: '${e.key} must be read-only');
      }
    });
  });

  testWidgets('only street, building and house number are typed', (tester) async {
    await runIgnoringFontErrors(() async {
      await _pump(tester, const AddEditAddressScreen());
      expect(find.text('Street *'), findsOneWidget);
      expect(find.text('Building'), findsOneWidget);
      expect(find.text('House No. *'), findsOneWidget);
      // The old free-form picker (Region / Province / City / Barangay lists
      // and a postal code box) is gone.
      expect(find.byType(AppDropdownField), findsNothing);
      expect(find.text('Select'), findsNothing);
      expect(find.text('Postal Code *'), findsNothing);
      expect(find.text('Postal Code'), findsOneWidget); // the locked field's label
    });
  });

  testWidgets('Edit Address of an older address elsewhere shows the fixed area', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await _pump(tester, AddEditAddressScreen(existing: _oldAddress));

      for (final e in fixedValues.entries) {
        expect(
          tester.widget<TextFormField>(fixedField(e.key)).initialValue,
          e.value,
          reason: e.key,
        );
      }
      expect(find.text('National Capital Region (NCR)'), findsNothing);
      expect(find.text('Quezon City'), findsNothing);
      // What the person typed is kept.
      expect(find.widgetWithText(TextFormField, 'Mabini St'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Unit 2'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '5'), findsOneWidget);
    });
  });

  test('what is saved comes from the fixed constants, for everyone', () {
    final src = File('lib/presentation/screens/buyer/add_edit_address_screen.dart')
        .readAsStringSync();
    for (final c in const [
      'regionCode', 'regionName', 'provinceCode', 'provinceName', 'cityCode',
      'cityName', 'barangayCode', 'barangayName', 'postalCode',
    ]) {
      expect(src, contains('FarmerRegistrationAddress.$c'), reason: c);
    }
    expect(src, contains('FarmerRegistrationAddress.composeLine('));
    // No role switch and no free-form picker any more.
    expect(src, isNot(contains('_isFarmer')));
    expect(src, isNot(contains('PsgcAddressFields')));
    expect(src, isNot(contains('toStructure')));
  });
}
