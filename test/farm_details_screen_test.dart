import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/constants/app_constants.dart';
import 'package:sagana/core/constants/farmer_registration_address.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/farmer_profile_model.dart';
import 'package:sagana/presentation/screens/farmer/edit_farm_details_screen.dart';
import 'package:sagana/presentation/widgets/address_map_widgets.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

Widget _host(Widget screen) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: screen,
);

Future<void> _pump(
  WidgetTester tester,
  FarmerProfileModel profile, {
  Size size = const Size(900, 3600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host(EditFarmDetailsScreen(initialProfile: profile)));
  await tester.pump(const Duration(milliseconds: 400));
}

FarmerProfileModel _profile({
  String? address,
  String? street,
  String? building,
  String? houseNo,
  double? lat,
  double? lng,
}) => FarmerProfileModel(
  userId: 'u1',
  fullName: 'Juan Cruz',
  farmName: 'Cruz Farm',
  farmAddress: address,
  farmStreet: street,
  farmBuilding: building,
  farmHouseNo: houseNo,
  farmLatitude: lat,
  farmLongitude: lng,
  capitalShares: 0,
  isVerified: true,
  primaryCrops: const ['Ginger'],
);

// Barangay Payanas, Torrijos (OpenStreetMap place node).
const _payanas = LatLng(13.3213, 122.0394);
// The old map start, about 35 km north of Torrijos (open sea).
const _oldDefault = LatLng(13.6302, 121.9392);

// A structured farm with a pin at Payanas.
FarmerProfileModel _structured() => _profile(
  address: '12, Barn B, Rizal St, Payanas, Torrijos, Marinduque, MIMAROPA Region, 4903',
  street: 'Rizal St',
  building: 'Barn B',
  houseNo: '12',
  lat: _payanas.latitude,
  lng: _payanas.longitude,
);

Finder _saveButton() => find.text('Save Farm Details');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockStorageChannels();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Supabase.initialize(url: 'http://localhost:54321', publishableKey: 'test-key');
  });

  group('layout: the farm address first, then the farm map', () {
    testWidgets('order is Farm Address, Farm Location (map), Basic Information, Primary Crops', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _structured());
        double y(String text) => tester.getTopLeft(find.text(text).first).dy;

        expect(y('Farm Address'), lessThan(y('Farm Location')));
        expect(y('Farm Location'), lessThan(y('Basic Information')));
        expect(y('Basic Information'), lessThan(y('Primary Crops')));
        // "View Full Map" sits below the address fields, above the map.
        expect(y('Street *'), lessThan(y('View Full Map')));
        expect(y('View Full Map'),
            lessThan(tester.getTopLeft(find.byType(AddressMapPreview)).dy));
      });
    });

    testWidgets('uses the same section cards and map pieces as My Addresses', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _structured());
        expect(find.byType(AddressSectionCard), findsNWidgets(4));
        expect(find.byType(ViewFullMapLink), findsOneWidget);
        expect(find.byType(AddressMapPreview), findsOneWidget);
      });
    });

    testWidgets('lays out on a narrow phone without overflow', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _structured(), size: const Size(320, 3600));
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('address: the fixed area, with only street / building / house no. typed', () {
    testWidgets('Region, Province, Municipality, Barangay and Postal Code are locked', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _structured());
        final expected = {
          'region': 'MIMAROPA Region',
          'province': 'Marinduque',
          'city': 'Torrijos',
          'barangay': 'Payanas',
          'postal': '4903',
        };
        expected.forEach((key, value) {
          final field = find.byKey(ValueKey('fixed-address-$key'));
          expect(field, findsOneWidget, reason: key);
          final editable = tester.widget<TextField>(
            find.descendant(of: field, matching: find.byType(TextField)),
          );
          expect(editable.readOnly, isTrue, reason: '$key is locked');
          expect(
            tester.widget<EditableText>(
              find.descendant(of: field, matching: find.byType(EditableText)),
            ).controller.text,
            value,
            reason: key,
          );
        });
      });
    });

    testWidgets('a structured farm shows its saved street, building and house no.', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _structured());
        expect(find.text('Rizal St'), findsOneWidget);
        expect(find.text('Barn B'), findsOneWidget);
        expect(find.text('12'), findsOneWidget);
        expect(find.byKey(const ValueKey('farm-address-legacy-notice')), findsNothing);
      });
    });

    testWidgets('a farm with no address yet requires Street and House No.', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _profile());
        await tester.ensureVisible(_saveButton());
        await tester.tap(_saveButton());
        await tester.pump();
        // One message under Street and one under House No.
        expect(find.text('This field is required.'), findsNWidgets(2));
      });
    });

    testWidgets('an old free-text address is shown, kept, and does not block saving', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _profile(address: 'Near the old barangay hall'));
        expect(find.byKey(const ValueKey('farm-address-legacy-notice')), findsOneWidget);
        expect(find.textContaining('Near the old barangay hall'), findsOneWidget);

        // Leaving the typed fields empty is accepted: no address error appears.
        await tester.ensureVisible(_saveButton());
        await tester.tap(_saveButton());
        await tester.pump();
        expect(find.text('This field is required.'), findsNothing);
      });
    });

    testWidgets('typing any part of the address for an old farm makes Street and House No. required', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _profile(address: 'Near the old barangay hall'));
        await tester.enterText(find.widgetWithText(TextFormField, 'Building'), 'Barn A');
        await tester.ensureVisible(_saveButton());
        await tester.tap(_saveButton());
        await tester.pump();
        expect(find.text('This field is required.'), findsNWidgets(2));
      });
    });
  });

  group('map: the farm pin, not a home address', () {
    testWidgets('shows the saved farm coordinates', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _structured());
        final shown = tester.widget<Text>(find.byKey(const ValueKey('farm-pin-coordinates')));
        expect(shown.data, '13.32130° N, 122.03940° E');
        final preview = tester.widget<AddressMapPreview>(find.byType(AddressMapPreview));
        expect(preview.pin, _payanas);
      });
    });

    testWidgets('the preview map is static (no accidental pin moves)', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _structured());
        final map = tester.widget<fm.FlutterMap>(find.byType(fm.FlutterMap));
        expect(map.options.interactionOptions.flags, fm.InteractiveFlag.none);
      });
    });

    testWidgets('a farm without a pin says so and offers View Full Map', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _profile(street: 'Rizal St', houseNo: '12'));
        expect(find.text('No farm pin yet. Use View Full Map to place it.'), findsOneWidget);
        expect(find.byKey(const ValueKey('farm-pin-coordinates')), findsNothing);
        expect(find.text('View Full Map'), findsOneWidget);
      });
    });

    testWidgets('a pin in Payanas gets no warning', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _structured());
        expect(find.byKey(const ValueKey('farm-pin-far-warning')), findsNothing);
      });
    });

    testWidgets('a pin far from Barangay Payanas gets a gentle warning (it can still be saved)', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          _profile(
            street: 'Rizal St',
            houseNo: '12',
            lat: _oldDefault.latitude,
            lng: _oldDefault.longitude,
          ),
        );
        expect(find.byKey(const ValueKey('farm-pin-far-warning')), findsOneWidget);
        // A warning only: the pin is still shown and Save is still offered.
        expect(find.byKey(const ValueKey('farm-pin-coordinates')), findsOneWidget);
        expect(find.text('Save Farm Details'), findsOneWidget);
      });
    });

    testWidgets('View Full Map opens the farm picker, titled Farm Location', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _structured());
        await tester.tap(find.text('View Full Map'));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        final picker = tester.widget<LocationPinPickerScreen>(
          find.byType(LocationPinPickerScreen),
        );
        expect(picker.title, 'Farm Location');
        expect(picker.initialLocation, _payanas);
        // A farm pin is green, a home address pin is red.
        expect(picker.pinColor, AppConstants.primaryGreen);
      });
    });
  });

  group('the map starts on Barangay Payanas', () {
    test('the shared default centre is Payanas, not the old point in the sea', () {
      const d = Distance();
      expect(d.as(LengthUnit.Meter, kAddressMapCenter, _payanas), lessThan(50));
      expect(d.as(LengthUnit.Kilometer, kAddressMapCenter, _oldDefault), greaterThan(30));
      expect(FarmerRegistrationAddress.mapCenterLatitude, 13.3213);
      expect(FarmerRegistrationAddress.mapCenterLongitude, 122.0394);
    });

    test('no screen still hard-codes the old centre', () {
      for (final path in [
        'lib/presentation/screens/farmer/edit_farm_details_screen.dart',
        'lib/presentation/screens/farmer/farm_location_full_map_screen.dart',
        'lib/presentation/screens/buyer/add_edit_address_screen.dart',
        'lib/presentation/widgets/address_map_widgets.dart',
      ]) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final src = file.readAsStringSync();
        expect(src, isNot(contains('13.6302')), reason: path);
        expect(src, isNot(contains('121.9392')), reason: path);
      }
    });
  });

  group('farm data and home addresses stay separate', () {
    final screen = File(
      'lib/presentation/screens/farmer/edit_farm_details_screen.dart',
    ).readAsStringSync();
    final repo = File(
      'lib/data/repositories/farmer_profile_repository.dart',
    ).readAsStringSync();

    test('the Farm Details screen never touches the home address book', () {
      final code = screen
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('BuyerAddress')));
      expect(code, isNot(contains('buyer_addresses')));
    });

    test('the farm is saved on farmer_profiles, in the farm columns', () {
      final start = repo.indexOf('Future<void> updateFarmDetailsOnline');
      final body = repo.substring(start, start + 4200);
      expect(body, contains(".from('farmer_profiles')"));
      for (final col in [
        'farm_address',
        'farm_street',
        'farm_building',
        'farm_house_no',
        'farm_latitude',
        'farm_longitude',
      ]) {
        expect(body, contains("'$col'"), reason: col);
      }
      expect(body, isNot(contains('buyer_addresses')));
    });

    test('the one-line farm address is the same text the database check expects', () {
      final line = FarmerRegistrationAddress.composeLine(
        houseNo: '12',
        building: '',
        street: 'Rizal St',
      );
      expect(line, '12, Rizal St, Payanas, Torrijos, Marinduque, MIMAROPA Region, 4903');
      final sql = File(
        'supabase_schema/supabase_schema_registration_13_farm_address_parts.sql',
      ).readAsStringSync();
      expect(sql, contains("'Payanas', 'Torrijos', 'Marinduque', 'MIMAROPA Region', '4903'"));
      for (final col in ['farm_street', 'farm_building', 'farm_house_no']) {
        expect(sql, contains('ADD COLUMN IF NOT EXISTS $col'));
      }
    });

    test('the model reads the new columns', () {
      final m = FarmerProfileModel.fromMap({
        'user_id': 'u1',
        'full_name': 'Juan Cruz',
        'farm_address': 'a',
        'farm_street': 'Rizal St',
        'farm_building': 'Barn B',
        'farm_house_no': '12',
        'farm_latitude': 13.3213,
        'farm_longitude': 122.0394,
      });
      expect(m.farmStreet, 'Rizal St');
      expect(m.farmBuilding, 'Barn B');
      expect(m.farmHouseNo, '12');
      expect(m.hasStructuredFarmAddress, isTrue);
      expect(m.hasCoordinates, isTrue);
      // An older farm: only the one-line text.
      final old = FarmerProfileModel.fromMap({
        'user_id': 'u2',
        'full_name': 'Ana',
        'farm_address': 'Near the hall',
      });
      expect(old.hasStructuredFarmAddress, isFalse);
    });
  });
}
