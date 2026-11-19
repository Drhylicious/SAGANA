import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/analytics_model.dart';
import 'package:sagana/data/models/farmer_profile_model.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/presentation/screens/farmer/farmer_edit_profile_screen.dart';
import 'package:sagana/presentation/widgets/planting_forecast_card.dart';
import 'package:sagana/presentation/widgets/top_harvested_crops_chart.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

/// TC 60.1 (Farmer Edit Profile phone box shows its own error) and TC 104.1
/// (Top Harvested Crops and Planting Forecast say only kg is counted).

Widget _app(Widget home) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: home,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockStorageChannels();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final dir = Directory.systemTemp.createTempSync('sagana_inline_errors');
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

  testWidgets(
    'Farmer Edit Profile: an invalid phone number is marked on the phone box and nothing is sent',
    (tester) async {
      await runIgnoringFontErrors(() async {
        tester.view.physicalSize = const Size(390, 2600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _app(
            FarmerEditProfileScreen(
              initialProfile: FarmerProfileModel(
                userId: 'u1',
                fullName: 'Juan D. Dela Cruz',
                surname: 'Dela Cruz',
                firstName: 'Juan',
                middleInitial: 'D',
                capitalShares: 0,
                isVerified: true,
                primaryCrops: const [],
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        final phoneField = find.ancestor(
          of: find.byIcon(Icons.phone_outlined),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(phoneField, '12345');
        await tester.pump();
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text('Please enter a valid Philippine mobile number.'),
          findsOneWidget,
        );
        expect(find.byType(SnackBar), findsNothing);

        // A valid number clears the error.
        await tester.enterText(phoneField, '09171234567');
        await tester.pump();
        expect(
          find.text('Please enter a valid Philippine mobile number.'),
          findsNothing,
        );
      });
    },
  );

  testWidgets('Top Harvested Crops says that only kg is counted', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: TopHarvestedCropsChart(
            crops: [
              TopSellingCrop(cropName: 'Ginger', volumeKg: 120, percentOfMax: 1),
            ],
          ),
        ),
      ),
    );
    expect(
      find.text('Totals count harvests recorded in kg only.'),
      findsOneWidget,
    );
    });
  });

  testWidgets('Planting Forecast header says that only kg is counted', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
    await tester.pumpWidget(
      _app(const Scaffold(body: PlantingForecastSectionHeader())),
    );
    expect(
      find.text('Totals count harvests recorded in kg only.'),
      findsOneWidget,
    );
    });
  });
}
