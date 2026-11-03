import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/theme/sagana_colors.dart';
import 'package:sagana/data/models/admin_loan_model.dart';
import 'package:sagana/presentation/screens/admin/loan_item_management_screen.dart';

import 'support/ignore_font_errors.dart';

const _long = LoanCatalogItem(
  loanItemId: 'l1',
  inventoryItemId: 'i1',
  itemName: 'A Very Long Fertilizer Name That Keeps Going',
  category: 'Tools & Equipment',
  unit: 'sack',
  quantityOnHand: 12,
  unitPrice: 1250.5,
  source: 'Board Resolution No. 102, series of 2026, approved at the annual meeting',
);
const _plain = LoanCatalogItem(
  loanItemId: 'l2',
  inventoryItemId: 'i2',
  itemName: 'Urea',
  category: 'Fertilizer',
  unit: 'bag',
  quantityOnHand: 3,
  unitPrice: 900,
  isLoanEligible: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, Size size, Widget Function(BuildContext) child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Padding(padding: const EdgeInsets.all(20), child: child(context)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final size in const [Size(320, 568), Size(412, 915)]) {
    testWidgets('catalog grid card fits at ${size.width.toInt()}', (tester) async {
      await runIgnoringFontErrors(() async {
        await pump(
          tester,
          size,
          (context) => GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.58,
            children: [
              LoanItemCard(
                item: _long,
                cs: Theme.of(context).colorScheme,
                sagana: context.saganaColors,
                icon: Icons.handyman_rounded,
                onTap: () {},
              ),
            ],
          ),
        );
        expect(find.textContaining('₱1250.50'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('archived card fits at ${size.width.toInt()}', (tester) async {
      await runIgnoringFontErrors(() async {
        await pump(
          tester,
          size,
          (context) => ArchivedLoanItemCard(item: _long, onRestore: () {}),
        );
        expect(find.text('ARCHIVED'), findsOneWidget);
        expect(find.text('Restore'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('archived card with no source shows the not-recorded note', (tester) async {
    await runIgnoringFontErrors(() async {
      await pump(tester, const Size(360, 640), (_) => ArchivedLoanItemCard(item: _plain, onRestore: () {}));
      expect(find.text('Urea'), findsOneWidget);
      expect(find.text('Source not recorded'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Restore calls back', (tester) async {
    await runIgnoringFontErrors(() async {
      var restored = 0;
      await pump(tester, const Size(360, 640), (_) => ArchivedLoanItemCard(item: _plain, onRestore: () => restored++));
      await tester.tap(find.text('Restore'));
      expect(restored, 1);
    });
  });
}
