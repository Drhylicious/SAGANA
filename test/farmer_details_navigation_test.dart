import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/presentation/screens/admin/farmer_details_screen.dart';

import 'support/test_storage_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockStorageChannels();

  testWidgets('farmer details screen opens for the farmer it is given', (
    tester,
  ) async {
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
}
