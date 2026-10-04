import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';

// Replaces the default counter template, which pumped the whole app. The app
// needs Hive and Supabase at startup, so that test could not run in isolation.
// This checks what the localization work depends on: the English and Tagalog
// delegates resolve, and a registration string comes back in each language.
void main() {
  for (final entry in {'en': 'Next', 'tl': 'Susunod'}.entries) {
    testWidgets('localized string resolves for "${entry.key}"', (tester) async {
      String? resolved;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(entry.key),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) {
              resolved = AppLocalizations.of(context).registerNext;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, entry.value);
    });
  }
}
