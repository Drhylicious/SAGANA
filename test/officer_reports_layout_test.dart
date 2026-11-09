import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/presentation/screens/admin/operational_reports_screen.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

/// The Reports hub for the two staff roles. Detailed Reports and Management
/// Tools use the same two-column card grid as the Dashboard and Marketplace
/// tabs. The Manager's three tools (Balik-Tangkilik included) sit in one row
/// that scrolls sideways; the Officer's two (no Balik-Tangkilik) fill a fixed
/// row with no empty slot.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    final dir = Directory.systemTemp.createTempSync('sagana_reports_layout');
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

  void ftest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) => runIgnoringFontErrors(() => body(tester)));

  Future<void> show(WidgetTester tester, String role, {double width = 360}) async {
    // Real file IO must run outside the test's fake clock.
    await tester.runAsync(
      () => HiveService.saveUserSession(userId: 'u1', email: 'u@x.y', role: role),
    );
    tester.view.physicalSize = Size(width, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const OperationalReportsScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    // The test font is taller than Poppins/Inter, so overflows in the existing
    // cards are set aside; the assertions here are about placement.
    tester.takeException();
  }

  // The card that contains [label].
  Rect cardOf(WidgetTester tester, String label) {
    final container = find.ancestor(
      of: find.text(label),
      matching: find.byType(Container),
    );
    // The nearest bordered card: the first Container ancestor that is a card.
    return tester.getRect(container.first);
  }

  for (final width in [320.0, 360.0, 412.0]) {
    ftest('Officer at $width px: only Analytics Dashboard and Export Center, no Balik', (
      tester,
    ) async {
      await show(tester, 'officer', width: width);
      expect(find.text('Analytics Dashboard'), findsOneWidget);
      expect(find.text('Export Center'), findsOneWidget);
      expect(find.text('Balik-Tangkilik Management'), findsNothing);
      // The test font is taller than Poppins/Inter, so render overflows in the
      // existing cards are set aside; the assertions here are about placement.
      tester.takeException();
    });
  }

  ftest('Officer: the two tools are one full row of the same card grid', (tester) async {
    await show(tester, 'officer');
    final analytics = cardOf(tester, 'Analytics Dashboard');
    final export = cardOf(tester, 'Export Center');
    final sales = cardOf(tester, 'Sales Report');
    final harvest = cardOf(tester, 'Harvest Report');

    // Side by side, same top, same size as every Detailed Reports card.
    expect(export.top, closeTo(analytics.top, 0.5));
    expect(export.size.width, closeTo(analytics.size.width, 0.5));
    expect(export.size.height, closeTo(analytics.size.height, 0.5));
    expect(analytics.size.width, closeTo(sales.size.width, 0.5));
    expect(analytics.size.height, closeTo(sales.size.height, 0.5));
    // The same two columns as Detailed Reports, so no empty slot on the right.
    expect(analytics.left, closeTo(sales.left, 0.5));
    expect(export.right, closeTo(harvest.right, 0.5));
  });

  ftest('Manager: the three tools are one row of cards that scrolls sideways', (tester) async {
    await show(tester, 'admin', width: 360);
    expect(find.text('Analytics Dashboard'), findsOneWidget);
    expect(find.text('Balik-Tangkilik Management'), findsOneWidget);
    expect(find.text('Export Center'), findsOneWidget);

    final a = cardOf(tester, 'Analytics Dashboard');
    final b = cardOf(tester, 'Balik-Tangkilik Management');
    final e = cardOf(tester, 'Export Center');
    final sales = cardOf(tester, 'Sales Report');

    // One row: same top and height, left to right, same height as every card
    // of Detailed Reports (the strip cards are only a little narrower).
    expect(a.top, closeTo(b.top, 0.5));
    expect(b.top, closeTo(e.top, 0.5));
    expect(a.left, lessThan(b.left));
    expect(b.left, lessThan(e.left));
    expect(a.left, closeTo(sales.left, 0.5), reason: 'starts at the page margin');
    for (final card in [a, b, e]) {
      expect(card.size.width, closeTo(a.size.width, 0.5));
      expect(card.size.height, closeTo(sales.size.height, 0.5));
    }
    expect(a.size.width, lessThan(sales.size.width));
    // Two cards fill the content width, and the third starts inside the screen
    // edge, so the row visibly continues.
    expect(b.right, lessThan(sales.left + 2 * sales.size.width + 12));
    expect(e.left, lessThan(360));
    tester.takeException();
  });

  ftest('Manager: dragging the row sideways brings Export Center fully into view', (tester) async {
    await show(tester, 'admin', width: 360);
    final before = cardOf(tester, 'Export Center');
    expect(before.right, greaterThan(360), reason: 'cut off before scrolling');

    final drag = find.ancestor(
      of: find.text('Analytics Dashboard'),
      matching: find.byType(Scrollable),
    );
    // The innermost Scrollable around the tools is the horizontal one.
    await tester.drag(drag.first, const Offset(-400, 0));
    await tester.pump(const Duration(milliseconds: 400));
    final after = cardOf(tester, 'Export Center');
    expect(after.right, lessThanOrEqualTo(360));
    expect(after.left, lessThan(before.left));
    tester.takeException();
  });

  ftest('Both roles keep the Executive Snapshot and Detailed Reports', (tester) async {
    for (final role in ['admin', 'officer']) {
      await show(tester, role);
      expect(find.text('Detailed Reports'), findsOneWidget, reason: role);
      expect(find.text('Sales Report'), findsOneWidget, reason: role);
    }
  });
}
