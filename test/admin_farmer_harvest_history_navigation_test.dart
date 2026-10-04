import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/presentation/screens/admin/farmer_harvest_history_screen.dart';

import 'support/test_storage_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockStorageChannels();

  testWidgets('admin harvest history screen opens in view-only form', (
    tester,
  ) async {
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
}
