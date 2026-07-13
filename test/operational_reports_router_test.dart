import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/routes/app_routes.dart';

void main() {
  testWidgets('operational reports localization keys are available', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context);
            expect(l10n.reportsHubTitle, isNotEmpty);
            expect(l10n.reportsPerformanceSummary, isNotEmpty);
            expect(l10n.reportsDetailedReports, isNotEmpty);
            expect(l10n.reportsManagementTools, isNotEmpty);
            expect(l10n.reportsRecentReports, isNotEmpty);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  test('operational reports route is registered', () {
    expect(AppRoutes.operationalReports, '/admin/reports');
    expect(AppRoutes.adminAnalytics, '/admin/analytics');
  });
}
