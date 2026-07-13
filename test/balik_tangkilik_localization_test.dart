import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';

void main() {
  testWidgets('Balik Tangkilik history localization strings are available', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context);
            expect(l10n.balikTangkilikHistoryTitle, 'Distribution History');
            expect(
              l10n.balikTangkilikNoHistoryYet,
              'No distributions have been recorded yet.',
            );
            expect(l10n.balikTangkilikYearLogTitle(2024), '2024 Distribution');
            expect(l10n.balikTangkilikYearLogSubtitle(5), '5 members paid');
            return const SizedBox();
          },
        ),
      ),
    );
  });
}
