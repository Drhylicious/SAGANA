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

  group('Residential Address', () {
    testWidgets('no saved address', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, const MemberResidentialAddressCard(addresses: []));
        expect(find.text('Residential Address'), findsOneWidget);
        expect(find.text('No address saved yet.'), findsOneWidget);
        expect(find.byType(AddressMapPreview), findsNothing);
      });
    });

    testWidgets('shows the address fields, a Default badge, and a map when pinned', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberResidentialAddressCard(
            addresses: [_address(lat: 13.32, lng: 122.04, notes: 'Blue gate')],
          ),
        );
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Default'), findsOneWidget);
        expect(find.text('Mabini St'), findsOneWidget);
        expect(find.text('Payanas'), findsOneWidget);
        expect(find.text('4903'), findsOneWidget);
        expect(find.text('Blue gate'), findsOneWidget);
        expect(find.byType(AddressMapPreview), findsOneWidget);
        expect(find.text('No map pin saved for this address.'), findsNothing);
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
        expect(find.byType(AddressMapPreview), findsNothing);
        expect(find.text('No map pin saved for this address.'), findsNWidgets(2));
      });
    });
  });

  group('Farm', () {
    FarmerProfileModel structured({double? lat, double? lng}) => _profile(
      farmAddress:
          '12, Barn B, Rizal St, Payanas, Torrijos, Marinduque, MIMAROPA Region, 4903',
      street: 'Rizal St',
      building: 'Barn B',
      houseNo: '12',
      lat: lat,
      lng: lng,
      ownership: 'Owned',
      soil: 'rain_fed',
      crops: const ['Ginger', 'Palay'],
    );

    testWidgets('information, address and location are three cards in the farmer\'s order', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberFarmSection(profile: structured(lat: 13.3213, lng: 122.0394)),
        );
        double y(String t) => tester.getTopLeft(find.text(t).first).dy;
        expect(y('Farm Information'), lessThan(y('Farm Address')));
        expect(y('Farm Address'), lessThan(y('Farm Location')));

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

    testWidgets('a structured farm address shows the fixed area plus the typed parts', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, MemberFarmSection(profile: structured()));
        expect(find.text('MIMAROPA Region'), findsWidgets);
        expect(find.text('Marinduque'), findsOneWidget);
        expect(find.text('Torrijos'), findsOneWidget);
        expect(find.text('Payanas'), findsOneWidget);
        expect(find.text('4903'), findsOneWidget);
        expect(find.text('Rizal St'), findsOneWidget);
        expect(find.text('Barn B'), findsOneWidget);
        expect(find.text('12'), findsOneWidget);
      });
    });

    testWidgets('a farm saved as plain text shows that line only', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          MemberFarmSection(
            profile: _profile(farmAddress: 'Sitio Bato, Payanas, Torrijos'),
          ),
        );
        expect(find.text('Sitio Bato, Payanas, Torrijos'), findsOneWidget);
        expect(find.text('Street'), findsNothing);
      });
    });

    testWidgets('no farm address and no pin: both say so, with no map', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, MemberFarmSection(profile: _profile()));
        expect(find.text('No farm address saved yet.'), findsOneWidget);
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
        final map = tester.widget<AddressMapPreview>(find.byType(AddressMapPreview));
        expect(map.pin!.latitude, 13.3213);
        expect(map.pin!.longitude, 122.0394);
        expect(map.pinColor, isNot(const AddressMapPreview(pin: null).pinColor),
            reason: 'farm pin is green; a home pin is red');
        expect(find.text('13.3213° N, 122.0394° E'), findsOneWidget);
      });
    });

    testWidgets('the farm never shows the residential address, and the reverse', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          Column(
            children: [
              MemberResidentialAddressCard(addresses: [_address(street: 'Home Only St')]),
              MemberFarmSection(profile: structured()),
            ],
          ),
        );
        expect(find.text('Home Only St'), findsOneWidget);
        expect(find.text('Rizal St'), findsOneWidget);
      });
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
