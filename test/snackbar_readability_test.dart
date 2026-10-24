import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/constants/app_constants.dart';
import 'package:sagana/core/theme/app_theme.dart';

// Regression test for the "Disapprove" SnackBar.
//
// The app theme's SnackBar text style had no colour. A SnackBar's own text
// style replaces Flutter's default (onInverseSurface), so the text colour came
// out null, and Flutter paints a null text colour BLACK. Rendered and measured
// at the time: black on charcoal 1.6:1 (unreadable), on red 4.2:1.
//
// This opens real SnackBars under the app's light and dark themes with every
// fill the app uses and checks the resolved text colour against the fill.

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Every fill a SnackBar uses in the app. null = the theme's default fill.
  final fills = <String, Color?>{
    'charcoal (Disapprove / Suspend)': AppConstants.charcoal,
    'red (errors)': AppConstants.errorRed,
    'green (success)': AppConstants.midGreen,
    'amber (warnings)': AppConstants.snackbarWarning,
    'grey (info)': AppConstants.onSurfaceVariant,
    'theme default': null,
  };

  for (final theme in <String, ThemeData Function()>{
    'light': () => AppTheme.lightTheme,
    'dark': () => AppTheme.darkTheme,
  }.entries) {
    for (final fill in fills.entries) {
      testWidgets('${theme.key} theme, ${fill.key}: text is readable', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.value(),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: const Text('Application disapproved'),
                      backgroundColor: fill.value,
                    ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final context = tester.element(find.text('Application disapproved'));
        final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
        final snackTheme = Theme.of(context).snackBarTheme;
        final background = snackBar.backgroundColor ??
            snackTheme.backgroundColor ??
            Theme.of(context).colorScheme.inverseSurface;

        // A null text colour is painted black.
        final textColor = DefaultTextStyle.of(context).style.color;
        expect(textColor, isNotNull, reason: 'SnackBar text colour must be set');
        final text = textColor ?? Colors.black;

        expect(
          _contrast(text, background),
          greaterThanOrEqualTo(4.5),
          reason: 'text #${text.toARGB32().toRadixString(16)} on '
              '#${background.toARGB32().toRadixString(16)}',
        );
      });
    }
  }
}
