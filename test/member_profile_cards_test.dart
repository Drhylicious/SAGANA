import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/admin_reports_model.dart';
import 'package:sagana/data/models/buyer_address_model.dart';
import 'package:sagana/data/models/contribution_model.dart';
import 'package:sagana/data/models/farmer_profile_model.dart';
import 'package:sagana/presentation/widgets/address_map_widgets.dart';
import 'package:sagana/presentation/widgets/member_patronage_card.dart';
import 'package:sagana/presentation/widgets/member_profile_cards.dart';

import 'support/ignore_font_errors.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 3000);
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
        body: ListView(padding: const EdgeInsets.all(20), children: [child]),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

FarmerProfileModel _profile({
  String? surname,
  String? firstName,
  String? middle,
  String? suffix,
  String? farmAddress,
  String? street,
  String? building,
  String? houseNo,
  double? lat,
  double? lng,
  String? ownership,
  String? soil,
  String? email,
  String? phone,
  List<String> crops = const [],
}) => FarmerProfileModel(
  userId: 'u1',
  fullName: 'Marc Louie M. Yañez Jr.',
  contactEmail: email,
  phoneNumber: phone,
  surname: surname,
  firstName: firstName,
  middleInitial: middle,
  suffix: suffix,
  dateOfBirth: DateTime(1990, 3, 7),
  gender: 'male',
  memberSince: DateTime(2026, 10, 2),
  farmName: 'Yañez Farm',
  farmAddress: farmAddress,
  farmStreet: street,
  farmBuilding: building,
  farmHouseNo: houseNo,
  farmLatitude: lat,
  farmLongitude: lng,
  landAreaHectares: 1.5,
  yearsFarming: 8,
  farmOwnershipType: ownership,
  soilType: soil,
  capitalShares: 0,
  isVerified: true,
  primaryCrops: crops,
);

BuyerAddressModel _address({
  String label = 'Home',
  bool isDefault = true,
  double? lat,
  double? lng,
  String street = 'Mabini St',
  String? notes,
}) => BuyerAddressModel(
  id: 'a-$label',
  userId: 'u1',
  label: label,
  addressLine: '5, $street, Payanas, Torrijos, Marinduque, MIMAROPA Region, 4903',
  latitude: lat,
  longitude: lng,
  notes: notes,
  isDefault: isDefault,
  createdAt: DateTime(2026, 10, 1),
  updatedAt: DateTime(2026, 10, 1),
  regionName: 'MIMAROPA Region',
  provinceName: 'Marinduque',
  cityMunicipalityName: 'Torrijos',
  barangayName: 'Payanas',
  postalCode: '4903',
  street: street,
  houseNo: '5',
);

MemberContribution _contribution() => const MemberContribution(
  id: 'c1',
  farmerId: 'u1',
  year: 2026,
  totalSalesAmount: 0,
  palaySalesKg: 100,
  palaySalesAmount: 0,
  peanutSalesKg: 50,
  peanutSalesAmount: 0,
  otherCropsQtyKg: 25,
  estimatedBalikTangkilik: 1000,
  estimatedInterestOnCapital: 234.5,
  status: 'not_yet_computed',
);

const _row = MemberContributionRow(
  farmerId: 'u1',
  farmerName: 'Marc',
  palayQtyKg: 100,
  palayAmount: 2000,
  peanutQtyKg: 50,
  peanutAmount: 3000,
  totalAmount: 5000,
  sharePercent: 12.5,
  programPurchasesAmount: 800,
  purchaseSharePercent: 4.0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Identity card: header details in two rows', () {
    testWidgets('Email | Phone on the first row, Date of Birth | Gender on the second, equal tiles', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberIdentityCard(
            profile: _profile(email: 'juan@gmail.com', phone: '09171234567'),
          ),
        );
        final tile = (String label) => tester.getRect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(Container),
          ).first,
        );
        final email = tile('Email Address');
        final phone = tile('Phone Number');
        final dob = tile('Date of Birth');
        final gender = tile('Gender');
        // Row 1 and row 2 each sit on one line, row 2 below row 1.
        expect((email.top - phone.top).abs(), lessThan(1));
        expect((dob.top - gender.top).abs(), lessThan(1));
        expect(dob.top, greaterThan(email.bottom));
        // Left column and right column line up, and every tile is the same size.
        expect((email.left - dob.left).abs(), lessThan(1));
        expect((phone.left - gender.left).abs(), lessThan(1));
        expect((email.width - phone.width).abs(), lessThan(1));
        expect((dob.width - gender.width).abs(), lessThan(1));
        expect((email.width - dob.width).abs(), lessThan(1));
        expect((email.height - phone.height).abs(), lessThan(1));
        expect((dob.height - gender.height).abs(), lessThan(1));

        expect(find.text('juan@gmail.com'), findsOneWidget);
        expect(find.text('09171234567'), findsOneWidget);
        expect(find.text('1990-03-07'), findsOneWidget);
        expect(find.text('Male'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('the complete name sits under the picture, above the tiles, centred, and only once', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberIdentityCard(profile: _profile(email: 'a@b.com', phone: '0917')),
        );
        // Built from the parts: First M. Surname Suffix.
        final name = find.byKey(const ValueKey('member-header-name'));
        expect(name, findsOneWidget);
        expect(find.text('Marc Louie M. Yañez Jr.'), findsOneWidget);
        expect(tester.widget<Text>(name).textAlign, TextAlign.center);

        final avatar = tester.getRect(find.byType(Container).at(2));
        final nameBox = tester.getRect(name);
        final firstTile = tester.getRect(
          find.ancestor(of: find.text('Email Address'), matching: find.byType(Container)).first,
        );
        expect(nameBox.top, greaterThan(avatar.top));
        expect(nameBox.bottom, lessThan(firstTile.top));
        // The Personal Information section is gone, so no name parts are repeated.
        expect(find.text('Personal Information'), findsNothing);
        expect(find.text('Surname'), findsNothing);
        expect(find.text('M.I.'), findsNothing);
      });
    });

    testWidgets('a long name wraps instead of overflowing on a narrow phone', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        tester.view.physicalSize = const Size(320, 3000);
        await _pump(
          tester,
          MemberIdentityCard(
            profile: FarmerProfileModel(
              userId: 'u3',
              fullName: 'Maria Concepcion Alessandra D. de la Cruz-Villanueva III',
              capitalShares: 0,
              isVerified: true,
              primaryCrops: const [],
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('missing values show a dash and keep the tile size', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberIdentityCard(
            profile: FarmerProfileModel(
              userId: 'u2',
              fullName: 'Ana Reyes',
              capitalShares: 0,
              isVerified: false,
              primaryCrops: const [],
            ),
          ),
        );
        expect(find.text('–'), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      });
    });
  });

  // The labels of the separate address fields. None of them is shown any more:
  // the complete address already holds every part.
  const componentLabels = [
    'Region',
    'Province',
    'City / Municipality',
    'Barangay',
    'Postal Code',
    'Street',
    'Building',
    'House No.',
  ];
  void expectNoComponentRows() {
    for (final label in componentLabels) {
      expect(find.text(label), findsNothing, reason: label);
    }
  }

  group('Residential Address', () {
    testWidgets('no saved address', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, const MemberResidentialAddressCard(addresses: []));
        expect(find.text('Residential Address'), findsOneWidget);
        expect(find.text('No address saved yet.'), findsOneWidget);
        expect(find.byType(AddressMapPreview), findsNothing);
      });
    });

    testWidgets('one complete address, then its map: no separate address fields', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberResidentialAddressCard(
            addresses: [_address(lat: 13.32, lng: 122.04, notes: 'Blue gate')],
          ),
        );
        expect(find.text('Residential Address'), findsOneWidget);
        expect(find.text('Complete Address'), findsOneWidget);
        // The whole address is one piece of text, exactly as saved.
        final address = find.byKey(const ValueKey('member-residential-address-0'));
        expect(address, findsOneWidget);
        expect(
          tester.widget<SelectableText>(address).data,
          '5, Mabini St, Payanas, Torrijos, Marinduque, MIMAROPA Region, 4903',
        );
        // None of its parts is repeated as a row of its own.
        expectNoComponentRows();
        expect(find.text('Mabini St'), findsNothing);
        expect(find.text('4903'), findsNothing);
        // The map is directly below the address.
        expect(find.byType(AddressMapPreview), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(AddressMapPreview)).dy,
          greaterThan(tester.getBottomLeft(address).dy),
        );
        expect(find.text('Blue gate'), findsOneWidget);
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Default'), findsOneWidget);
        expect(find.text('No map pin saved for this address.'), findsNothing);
      });
    });

    testWidgets('the map shows this address\'s own pin', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberResidentialAddressCard(addresses: [_address(lat: 13.32, lng: 122.04)]),
        );
        final map = tester.widget<AddressMapPreview>(
          find.byKey(const ValueKey('member-residential-map-0')),
        );
        expect(map.pin!.latitude, 13.32);
        expect(map.pin!.longitude, 122.04);
      });
    });

    testWidgets('an address with no pin says so; every saved address is listed', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberResidentialAddressCard(
            addresses: [
              _address(),
              _address(label: 'Relative', isDefault: false, street: 'Luna St'),
            ],
          ),
        );
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Relative'), findsOneWidget);
        expect(find.text('Default'), findsOneWidget);
        expect(find.text('Complete Address'), findsNWidgets(2));
        expect(
          tester.widget<SelectableText>(
            find.byKey(const ValueKey('member-residential-address-1')),
          ).data,
          contains('Luna St'),
        );
        expect(find.byType(AddressMapPreview), findsNothing);
        expect(find.text('No map pin saved for this address.'), findsNWidgets(2));
        expectNoComponentRows();
      });
    });

    testWidgets('a single address that is not the default needs no label', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberResidentialAddressCard(addresses: [_address(isDefault: false)]),
        );
        expect(find.text('Home'), findsNothing);
        expect(find.text('Default'), findsNothing);
        expect(find.byKey(const ValueKey('member-residential-address-0')), findsOneWidget);
      });
    });
  });

  group('Farm Details', () {
    const fullLine =
        '12, Barn B, Rizal St, Payanas, Torrijos, Marinduque, MIMAROPA Region, 4903';
    FarmerProfileModel structured({double? lat, double? lng}) => _profile(
      farmAddress: fullLine,
      street: 'Rizal St',
      building: 'Barn B',
      houseNo: '12',
      lat: lat,
      lng: lng,
      ownership: 'Owned',
      soil: 'rain_fed',
      crops: const ['Ginger', 'Palay'],
    );

    testWidgets('one card: Farm Address, then Farm Information, then Farm Location', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberFarmSection(profile: structured(lat: 13.3213, lng: 122.0394)),
        );
        expect(find.byType(AddressSectionCard), findsOneWidget);
        expect(find.text('Farm Details'), findsOneWidget);
        double y(String t) => tester.getTopLeft(find.text(t).first).dy;
        expect(y('Farm Details'), lessThan(y('Farm Address')));
        expect(y('Farm Address'), lessThan(y('Farm Information')));
        expect(y('Farm Information'), lessThan(y('Farm Location')));
        // The map comes after the farm information.
        expect(
          tester.getTopLeft(find.byType(AddressMapPreview)).dy,
          greaterThan(y('Farm Location')),
        );

        expect(find.text('Yañez Farm'), findsOneWidget);
        expect(find.text('1.50 ha'), findsOneWidget);
        expect(find.text('8 years'), findsOneWidget);
        expect(find.text('Owned'), findsOneWidget);
        expect(find.text('Rain fed'), findsOneWidget);
        expect(find.text('Ginger'), findsOneWidget);
        expect(find.text('Palay'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('the farm address is one complete line, not split into fields', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, MemberFarmSection(profile: structured()));
        expect(find.text('Complete Address'), findsOneWidget);
        expect(
          tester.widget<SelectableText>(find.byKey(const ValueKey('member-farm-address'))).data,
          fullLine,
        );
        expectNoComponentRows();
        expect(find.text('Rizal St'), findsNothing);
        expect(find.text('Barn B'), findsNothing);
      });
    });

    testWidgets('a farm saved as plain text shows that line', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberFarmSection(
            profile: _profile(farmAddress: 'Sitio Bato, Payanas, Torrijos'),
          ),
        );
        expect(
          tester.widget<SelectableText>(find.byKey(const ValueKey('member-farm-address'))).data,
          'Sitio Bato, Payanas, Torrijos',
        );
        expectNoComponentRows();
      });
    });

    testWidgets('only the separate parts saved: the same complete line is built from them', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberFarmSection(
            profile: _profile(street: 'Rizal St', building: 'Barn B', houseNo: '12'),
          ),
        );
        expect(
          tester.widget<SelectableText>(find.byKey(const ValueKey('member-farm-address'))).data,
          fullLine,
        );
      });
    });

    testWidgets('no farm address and no pin: both say so, with no map', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, MemberFarmSection(profile: _profile()));
        expect(find.text('No farm address saved yet.'), findsOneWidget);
        expect(find.text('Complete Address'), findsNothing);
        expect(
          find.text('The farmer has not pinned the farm on the map yet.'),
          findsOneWidget,
        );
        expect(find.byType(AddressMapPreview), findsNothing);
        expect(find.text('No crops registered yet'), findsOneWidget);
        // Soil is not shown when nothing is stored.
        expect(find.text('Soil Type'), findsNothing);
      });
    });

    testWidgets('a farm pin shows a green map pin and the exact coordinates', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberFarmSection(profile: structured(lat: 13.3213, lng: 122.0394)),
        );
        final map = tester.widget<AddressMapPreview>(find.byKey(const ValueKey('member-farm-map')));
        expect(map.pin!.latitude, 13.3213);
        expect(map.pin!.longitude, 122.0394);
        expect(map.pinColor, isNot(const AddressMapPreview(pin: null).pinColor),
            reason: 'farm pin is green; a home pin is red');
        expect(find.text('13.3213° N, 122.0394° E'), findsOneWidget);
      });
    });

    testWidgets('the farm and the residence never share an address or a pin', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          Column(
            children: [
              MemberResidentialAddressCard(
                addresses: [_address(street: 'Home Only St', lat: 13.5, lng: 122.5)],
              ),
              MemberFarmSection(profile: structured(lat: 13.3213, lng: 122.0394)),
            ],
          ),
        );
        final home = tester.widget<SelectableText>(
          find.byKey(const ValueKey('member-residential-address-0')),
        );
        final farm = tester.widget<SelectableText>(
          find.byKey(const ValueKey('member-farm-address')),
        );
        expect(home.data, contains('Home Only St'));
        expect(home.data, isNot(contains('Rizal St')));
        expect(farm.data, contains('Rizal St'));
        expect(farm.data, isNot(contains('Home Only St')));

        final homeMap = tester.widget<AddressMapPreview>(
          find.byKey(const ValueKey('member-residential-map-0')),
        );
        final farmMap = tester.widget<AddressMapPreview>(
          find.byKey(const ValueKey('member-farm-map')),
        );
        expect(homeMap.pin!.latitude, 13.5);
        expect(homeMap.pin!.longitude, 122.5);
        expect(farmMap.pin!.latitude, 13.3213);
        expect(farmMap.pin!.longitude, 122.0394);
        expect(homeMap.pinColor, isNot(farmMap.pinColor));
      });
    });
  });

  group('where the cards read their data from', () {
    final cards = File('lib/presentation/widgets/member_profile_cards.dart').readAsStringSync();
    final repo = File('lib/data/repositories/farmer_details_repository.dart').readAsStringSync();

    test('the residential map uses the saved address\'s coordinates, the farm map the farm\'s', () {
      expect(cards, contains('LatLng(a.latitude!, a.longitude!)'));
      expect(cards, contains('LatLng(p.farmLatitude!, p.farmLongitude!)'));
      // Neither card reads the other\'s coordinates.
      expect(cards.contains('a.farmLatitude'), isFalse);
      expect(cards.contains('p.latitude'), isFalse);
    });

    test('the complete addresses are the saved ones (address_line / farm_address)', () {
      expect(cards, contains('address: a.addressLine'));
      expect(cards, contains("p.farmAddress?.trim()"));
      final model = File('lib/data/models/buyer_address_model.dart').readAsStringSync();
      expect(model, contains("addressLine: map['address_line'] as String"));
      final farmer = File('lib/data/models/farmer_profile_model.dart').readAsStringSync();
      expect(farmer, contains("farmAddress:        map['farm_address'] as String?"));
      // Both are read for the member being viewed, from their own records.
      final addresses = repo.substring(repo.indexOf('fetchAddresses(String farmerId)'));
      expect(addresses.substring(0, addresses.indexOf('fetchFarmerProfile')), allOf(contains(".from('buyer_addresses')"), contains(".eq('user_id', farmerId)")));
      expect(repo, contains(".from('farmer_profiles')"));
    });

    test('the separate address parts are no longer shown', () {
      for (final key in [
        'registerRegionLabel',
        'registerProvinceLabel',
        'registerCityLabel',
        'registerBarangayLabel',
        'registerPostalLabel',
        'registerStreetLabel',
        'registerBuildingLabel',
        'registerHouseNoLabel',
      ]) {
        expect(cards.contains(key), isFalse, reason: key);
      }
    });
  });

  group('Patronage card (Contribution tab)', () {
    testWidgets('year summary, breakdown and shares come from the same sources as before', (
      tester,
    ) async {
      var opened = 0;
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberPatronageCard(
            row: _row,
            contribution: _contribution(),
            year: 2026,
            onViewFull: () => opened++,
          ),
        );
        expect(find.text('Member Patronage (2026)'), findsOneWidget);
        // member_contributions: estimated total = 1000 + 234.5, volume 100+50+25.
        expect(find.text('₱1234.50'), findsOneWidget);
        expect(find.text('175kg'), findsOneWidget);
        // Member Patronage Report row: combined total 5000 + 800.
        expect(find.text('₱5,800'), findsOneWidget);
        expect(find.text('12.5%'), findsOneWidget);
        expect(find.text('4.0%'), findsOneWidget);
        expect(find.textContaining('Palay: 100 kg'), findsOneWidget);
        expect(find.textContaining('Peanut: 50 kg'), findsOneWidget);
        expect(find.textContaining('Purchases:'), findsOneWidget);

        await tester.tap(find.text('View Full Contribution'));
        expect(opened, 1);
      });
    });

    testWidgets('no activity: the summary still shows and the empty line explains', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberPatronageCard(
            row: null,
            contribution: null,
            year: 2026,
            onViewFull: () {},
          ),
        );
        expect(find.text('₱0.00'), findsOneWidget);
        expect(find.text('No records'), findsOneWidget);
        expect(find.text('No patronage activity recorded for 2026.'), findsOneWidget);
      });
    });
  });

  group('Member Details screen layout', () {
    final source = File(
      'lib/presentation/screens/admin/farmer_details_screen.dart',
    ).readAsStringSync();

    test('Profile tab: identity, residential, farm - and no patronage', () {
      int at(String s) {
        final i = source.indexOf(s);
        expect(i, isNonNegative, reason: s);
        return i;
      }

      final personal = at('MemberIdentityCard(');
      final residential = at('MemberResidentialAddressCard(');
      final farm = at('MemberFarmSection(');
      final contribution = at('_ContributionCard(');
      final patronage = at('MemberPatronageCard(');
      expect(personal, lessThan(residential));
      expect(residential, lessThan(farm));
      // Patronage is in the Contribution tab, after the capital card.
      expect(farm, lessThan(contribution));
      expect(contribution, lessThan(patronage));
      // The old private cards are gone from the screen.
      expect(source.contains('MemberPersonalInfoCard'), isFalse,
          reason: 'no separate Personal Information card');
      expect(source.contains('_IdentityCard'), isFalse);
      expect(source.contains('_MemberPatronageCard'), isFalse);
      expect(source.contains('_FarmDetailsCard'), isFalse);
      expect(source.contains('_AddressCard'), isFalse);
      // The patronage card appears once, not on both tabs.
      expect('MemberPatronageCard('.allMatches(source).length, 1);
    });

    test('the app bar says Farmer Details; the name is under the picture, not in the app bar', () {
      expect(source, contains('title: l10n.farmerDetailsTitle'));
      expect(source, isNot(contains('title: profile.fullName')));
      expect(source, contains('MemberIdentityCard(profile: profile)'));
    });

    test('the patronage data is still loaded from the Report and member_contributions', () {
      expect(source.contains('fetchMemberContributionReport(_patronageYear)'), isTrue);
      expect(source.contains('fetchCurrentYearContribution'), isTrue);
    });
  });
}
