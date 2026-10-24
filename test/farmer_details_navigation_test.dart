import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/presentation/screens/admin/farmer_details_screen.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockStorageChannels();

  // The sandbox has no internet and the app's text uses Google Fonts. Fonts are
  // not fetched, and any font error from a download already started is ignored
  // (see support/ignore_font_errors.dart); every other error still fails.
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

  testWidgets('farmer details screen opens for the farmer it is given', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      // The screen is rendered directly. Going through the router would
      // redirect to sign-in, because the test has no signed-in user.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const FarmerDetailsScreen(farmerId: 'farmer-123'),
        ),
      );
      // A bounded pump: the loading indicator animates, so pumpAndSettle would
      // never finish.
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(FarmerDetailsScreen), findsOneWidget);
    });
  });
}
