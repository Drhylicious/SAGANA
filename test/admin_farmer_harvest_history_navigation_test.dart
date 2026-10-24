import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/presentation/screens/admin/farmer_harvest_history_screen.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockStorageChannels();

  // Same sandbox note as farmer_details_navigation_test.dart.
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // The screen creates its repository on construction, which needs a
    // Supabase client. A fake address is enough: nothing here depends on a
    // reply, and a failed request is handled by the screen.
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-key',
    );
  });

  testWidgets('admin harvest history screen opens in view-only form', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      // Rendered directly, for the same reason as the farmer details test.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AdminFarmerHarvestHistoryScreen(farmerId: 'farmer-123'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AdminFarmerHarvestHistoryScreen), findsOneWidget);
      // The screen's title is "Harvest History". It has no logging control.
      expect(find.text('Harvest History'), findsOneWidget);
      expect(find.text('Log New Harvest'), findsNothing);
    });
  });
}
