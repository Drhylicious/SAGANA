import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/presentation/widgets/admin_top_bar.dart';
import 'package:sagana/presentation/widgets/buyer_top_bar.dart';
import 'package:sagana/presentation/widgets/top_bar_spacer.dart';

import 'support/ignore_font_errors.dart';

/// A phone's status bar / camera cut-out is reported as MediaQuery top padding.
/// Top bars must grow by it, and the space reserved under them must too, or the
/// bar draws over the status icons and hides the first rows of the screen.
Widget _app(Widget child, {double topInset = 40}) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  builder: (context, home) => MediaQuery(
    data: MediaQuery.of(context).copyWith(padding: EdgeInsets.only(top: topInset)),
    child: home!,
  ),
  home: Scaffold(body: Align(alignment: Alignment.topCenter, child: child)),
);

void main() {
  testWidgets('TopBarSpacer adds the status-bar height', (tester) async {
    await tester.pumpWidget(_app(const TopBarSpacer(height: 72)));
    expect(tester.getSize(find.byType(TopBarSpacer)).height, 72 + 40);
  });

  testWidgets('TopBarSpacer is unchanged when there is no status bar', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const TopBarSpacer(height: 72), topInset: 0));
    expect(tester.getSize(find.byType(TopBarSpacer)).height, 72);
  });

  testWidgets('Buyer top bar sits below the status bar', (tester) async {
    await runIgnoringFontErrors(() async {
      await tester.pumpWidget(
        _app(BuyerTopBar(title: 'Orders', onNotificationTap: () {})),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getSize(find.byType(BuyerTopBar)).height, 64 + 40);
      // The title is inside the 64 px below the inset, not under the status bar.
      expect(tester.getTopLeft(find.text('Orders')).dy, greaterThanOrEqualTo(40));
    });
  });

  test('Manager top bar header extent includes the status bar', () {
    const withInset = AdminTopBarDelegate(title: 't', topPadding: 40);
    const without = AdminTopBarDelegate(title: 't');
    expect(withInset.maxExtent, 104);
    expect(withInset.minExtent, 104);
    expect(without.maxExtent, 64);
    expect(withInset.shouldRebuild(without), isTrue);
  });
}
