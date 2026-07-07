import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/routes/app_routes.dart';

void main() {
  testWidgets('farmer management localization keys are available', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context);
            expect(l10n.farmerMgmtTitle, isNotEmpty);
            expect(l10n.farmerMgmtAdd, isNotEmpty);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  test('farmer management route is registered', () {
    expect(AppRoutes.farmerManagement, '/admin/farmers');
  });
}
