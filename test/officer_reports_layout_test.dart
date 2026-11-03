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

/// The Reports hub for the two staff roles. The tools row fills the width for
/// both: the Manager's three cards (Balik-Tangkilik included) side by side, the
/// Officer's two (no Balik-Tangkilik) as two equal columns with no empty slot.
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

  ftest('Officer: two equal columns filling the same width as the Manager row, no empty slot', (tester) async {
    await show(tester, 'admin');
    final mAnalytics = cardOf(tester, 'Analytics Dashboard');
    final mExport = cardOf(tester, 'Export Center');
    final sales = cardOf(tester, 'Sales Report');

    await show(tester, 'officer');
    final analytics = cardOf(tester, 'Analytics Dashboard');
    final export = cardOf(tester, 'Export Center');

    // Side by side, same top, same size.
    expect(export.top, closeTo(analytics.top, 0.5));
    expect(export.width, closeTo(analytics.width, 0.5));
    expect(export.height, closeTo(analytics.height, 0.5));
    // Together they span the same width as the Manager's row of three, and the
    // first column lines up with the first column of Detailed Reports.
    expect(analytics.left, closeTo(mAnalytics.left, 0.5));
    expect(export.right, closeTo(mExport.right, 0.5), reason: 'no empty slot on the right');
    expect(analytics.left, closeTo(sales.left, 0.5));
  });

  ftest('Manager: the original three tools in one row, Balik included', (tester) async {
    await show(tester, 'admin');
    expect(find.text('Analytics Dashboard'), findsOneWidget);
    expect(find.text('Balik-Tangkilik Management'), findsOneWidget);
    expect(find.text('Export Center'), findsOneWidget);

    final a = cardOf(tester, 'Analytics Dashboard');
    final b = cardOf(tester, 'Balik-Tangkilik Management');
    final e = cardOf(tester, 'Export Center');
    expect(a.top, closeTo(b.top, 0.5));
    expect(b.top, closeTo(e.top, 0.5));
    expect(a.left, lessThan(b.left));
    expect(b.left, lessThan(e.left));
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
