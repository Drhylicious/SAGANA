import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/admin_profile_model.dart';
import 'package:sagana/data/services/admin_profile_state_service.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/presentation/widgets/admin_top_bar.dart';
import 'package:sagana/presentation/widgets/buyer_top_bar.dart';
import 'package:sagana/presentation/widgets/farmer_top_bar.dart';
import 'package:sagana/presentation/widgets/sagana_logo_mark.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

/// The primary screens of every role show  (logo) | title  in the top bar.
/// Secondary screens keep what they had (a back button, or the plain logo).

Future<void> _pump(WidgetTester tester, Widget bar, {double width = 390}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: Align(alignment: Alignment.topCenter, child: bar)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Widget _admin({required bool primary, String title = 'Dashboard'}) =>
    AdminTopBar(title: title, enableMenu: primary);

Widget _farmer({required bool primary, VoidCallback? onBack, String title = 'Home'}) =>
    FarmerTopBar(
      title: title,
      enableMenu: primary,
      onBack: onBack,
      onProfileTap: () {},
      onNotificationTap: () {},
    );

Widget _buyer({required bool primary, String title = 'Browse'}) =>
    BuyerTopBar(title: title, enableMenu: primary, onNotificationTap: () {});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockStorageChannels();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final dir = Directory.systemTemp.createTempSync('sagana_topbar');
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
    await Supabase.initialize(url: 'http://localhost:54321', publishableKey: 'test-key');
  });


  setUp(() {
    AdminProfileStateService.instance.updateProfile(
      const AdminProfileModel(
        userId: 'a1',
        email: 'm@example.com',
        fullName: 'Jane Manager',
      ),
    );
  });
  tearDown(() => AdminProfileStateService.instance.clear());

  final logo = find.byType(SaganaLogoMark);
  final divider = find.byKey(const ValueKey('logo-title-divider'));

  group('primary screens: logo | title', () {
    final bars = <String, Widget Function(String title)>{
      'Manager / Officer': (t) => _admin(primary: true, title: t),
      'Farmer': (t) => _farmer(primary: true, title: t),
      'Buyer': (t) => _buyer(primary: true, title: t),
    };

    for (final e in bars.entries) {
      testWidgets('${e.key}: logo, then a divider, then the title, on one line', (
        tester,
      ) async {
        await runIgnoringFontErrors(() async {
          await _pump(tester, e.value('My Title'));
          final title = find.text('My Title');
          expect(logo, findsOneWidget);
          expect(divider, findsOneWidget);
          expect(title, findsOneWidget);
          final logoBox = tester.getRect(logo);
          final dividerBox = tester.getRect(divider);
          final titleBox = tester.getRect(title);
          // Left to right: logo, divider, title.
          expect(logoBox.right, lessThanOrEqualTo(dividerBox.left));
          expect(dividerBox.right, lessThanOrEqualTo(titleBox.left));
          // Even space (12 px) either side of the divider.
          expect(dividerBox.left - logoBox.right, closeTo(12, 0.5));
          expect(titleBox.left - dividerBox.right, closeTo(12, 0.5));
          // One line, centred.
          expect(tester.getCenter(logo).dy, closeTo(tester.getCenter(divider).dy, 1));
          expect(tester.getCenter(logo).dy, closeTo(tester.getCenter(title).dy, 1.5));
          expect(tester.takeException(), isNull);
        });
      });
    }

    testWidgets('the logo is the existing asset, the same size on all three', (tester) async {
      await runIgnoringFontErrors(() async {
        final sizes = <Size>[];
        for (final bar in bars.values) {
          await _pump(tester, bar('T'));
          sizes.add(tester.getSize(logo));
          final image = tester.widget<Image>(
            find.descendant(of: logo, matching: find.byType(Image)),
          );
          expect((image.image as AssetImage).assetName, 'assets/images/sagana_icon.png');
        }
        expect(sizes.toSet(), {const Size(38, 38)});
      });
    });

    testWidgets('title, logo and divider sit at the same spot on the three bars', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final logoSpots = <Offset>[];
        final dividerSpots = <Offset>[];
        final titleLefts = <double>[];
        for (final bar in bars.values) {
          await _pump(tester, bar('T'));
          logoSpots.add(tester.getTopLeft(logo).translate(0, 0));
          dividerSpots.add(tester.getTopLeft(divider));
          titleLefts.add(tester.getTopLeft(find.text('T')).dx);
        }
        // Same left edge and spacing for all three (the Farmer bar adds its
        // status-bar padding above, so only horizontal positions are compared).
        expect(logoSpots.map((o) => o.dx).toSet().length, 1);
        expect(dividerSpots.map((o) => o.dx).toSet().length, 1);
        expect(titleLefts.toSet().length, 1);
      });
    });

    testWidgets('a long title is cut with an ellipsis, not overflowing, on a narrow phone', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        for (final bar in bars.values) {
          await _pump(tester, bar('A very long screen title that cannot fit'), width: 320);
          expect(tester.takeException(), isNull);
        }
      });
    });
  });

  group('secondary screens are unchanged', () {
    testWidgets('Farmer: a pushed screen keeps its back button, no logo, no divider', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _farmer(primary: false, onBack: () {}, title: 'Details'));
        expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
        expect(logo, findsNothing);
        expect(divider, findsNothing);
      });
    });

    testWidgets('Farmer: even with a back button, no divider appears', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, _farmer(primary: true, onBack: () {}, title: 'Details'));
        expect(divider, findsNothing);
      });
    });

    testWidgets('a bar reused without the drawer keeps the plain logo and title', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        for (final bar in [
          _admin(primary: false),
          _buyer(primary: false),
          _farmer(primary: false),
        ]) {
          await _pump(tester, bar);
          expect(logo, findsOneWidget);
          expect(divider, findsNothing);
        }
      });
    });
  });

  group('the Pending Applicant bar is drawn by the same pieces', () {
    test('it uses the shared logo and divider, not its own copy', () {
      final src = File('lib/presentation/widgets/pending_applicant_views.dart')
          .readAsStringSync();
      expect(src, contains('SaganaLogoMark('));
      expect(src, contains('SaganaLogoDivider('));
      expect(src.contains("Image.asset('assets/images/sagana_icon.png'"), isFalse);
    });

    test('no role bar draws the logo image on its own any more', () {
      for (final f in [
        'lib/presentation/widgets/admin_top_bar.dart',
        'lib/presentation/widgets/buyer_top_bar.dart',
        'lib/presentation/widgets/farmer_top_bar.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src.contains('sagana_icon.png'), isFalse, reason: f);
        expect(src, contains('SaganaLogoMark('), reason: f);
      }
    });
  });

  group('every primary screen opts in (enableMenu)', () {
    String read(String p) => File(p).readAsStringSync();

    test('Manager / Officer: the five drawer screens', () {
      for (final f in [
        'lib/presentation/screens/admin/admin_dashboard_screen.dart',
        'lib/presentation/screens/admin/farmer_management_screen.dart',
        'lib/presentation/screens/admin/loan_dashboard_screen.dart',
        'lib/presentation/screens/admin/marketplace_dashboard_screen.dart',
        'lib/presentation/screens/admin/operational_reports_screen.dart',
      ]) {
        expect(read(f), contains('enableMenu: true'), reason: f);
      }
    });

    test('Farmer: the root tabs', () {
      for (final f in [
        'lib/presentation/screens/farmer/farmer_dashboard_screen.dart',
        'lib/presentation/screens/farmer/harvest_hub_screen.dart',
        'lib/presentation/screens/farmer/my_listings_screen.dart',
        'lib/presentation/screens/farmer/farmer_analytics_screen.dart',
        'lib/presentation/screens/farmer/farmer_profile_screen.dart',
      ]) {
        expect(read(f), contains('enableMenu: true'), reason: f);
      }
    });

    test('Buyer: Browse, Orders, Prices, Account', () {
      for (final f in [
        'lib/presentation/screens/buyer/marketplace_browse_screen.dart',
        'lib/presentation/screens/buyer/my_orders_screen.dart',
        'lib/presentation/screens/buyer/price_monitoring_screen.dart',
        'lib/presentation/screens/buyer/buyer_account_screen.dart',
      ]) {
        expect(read(f), contains('enableMenu: true'), reason: f);
      }
    });
  });
}
