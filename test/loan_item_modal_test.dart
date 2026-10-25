import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/admin_loan_model.dart';
import 'package:sagana/presentation/screens/admin/issue_new_loan_screen.dart';
import 'package:sagana/presentation/widgets/management_modal.dart';

import 'support/ignore_font_errors.dart';

/// The Add Input Item dialog of Issue New Loan: required fields with inline
/// errors, no duplicate items, quantities limited to 2 decimals, stock limit,
/// and line totals rounded to centavos. Runs on a 360 px phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const urea = LoanCatalogItem(
    loanItemId: 'l1',
    inventoryItemId: 'inv-urea',
    itemName: 'Urea',
    category: 'Fertilizer',
    unit: 'bag',
    quantityOnHand: 10,
    unitPrice: 360,
  );
  const seed = LoanCatalogItem(
    loanItemId: 'l2',
    inventoryItemId: 'inv-seed',
    itemName: 'Corn Seed',
    category: 'Seeds',
    unit: 'kg',
    quantityOnHand: 50,
    unitPrice: 33.33,
  );

  void ftest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) => runIgnoringFontErrors(() => body(tester)));

  LoanItemDraft? saved;

  Future<void> open(
    WidgetTester tester, {
    Set<String> taken = const {},
    List<LoanCatalogItem> catalog = const [urea, seed],
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    saved = null;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showManagementModal(
                context: context,
                builder: (_) => AddLoanItemModalBody(
                  loanCatalog: catalog,
                  takenInventoryIds: taken,
                  onSave: (d) => saved = d,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.text('Select a loanable item'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(label).last);
    await tester.pump(const Duration(milliseconds: 300));
  }

  ftest('confirming an empty dialog flags the item and the quantity', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('Confirm'));
    await tester.pump();

    expect(find.text('Select an item.'), findsOneWidget);
    expect(find.text('Enter the quantity.'), findsOneWidget);
    expect(saved, isNull);
  });

  ftest('an item already on the loan is not offered again', (tester) async {
    await open(tester, taken: {'inv-urea'});

    await tester.tap(find.text('Select a loanable item'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Corn Seed (kg)'), findsOneWidget);
    expect(find.text('Urea (bag)'), findsNothing);

    // Close the open list the way a user would, before the test ends.
    await tester.tap(find.text('Corn Seed (kg)'));
    await tester.pump(const Duration(milliseconds: 300));
  });

  ftest('when every loanable item is on the loan it says so', (tester) async {
    await open(tester, taken: {'inv-urea', 'inv-seed'});

    expect(
      find.text('Every loanable item is already in this loan.'),
      findsOneWidget,
    );
    expect(find.text('Confirm'), findsNothing);
  });

  ftest('quantity is limited to 2 decimals and checked against stock', (
    tester,
  ) async {
    await open(tester);
    await choose(tester, 'Urea (bag)');

    await tester.enterText(find.byType(TextFormField), '1.234');
    await tester.pump();
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '1.23',
    );

    await tester.enterText(find.byType(TextFormField), '11');
    await tester.pump();
    expect(find.textContaining('only 10 bag available'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pump();
    expect(saved, isNull);
  });

  ftest('zero is not a quantity', (tester) async {
    await open(tester);
    await choose(tester, 'Urea (bag)');

    await tester.enterText(find.byType(TextFormField), '0');
    await tester.pump();

    expect(find.text('Quantity must be greater than zero.'), findsOneWidget);
  });

  ftest('a valid item is saved with its line total in centavos', (tester) async {
    await open(tester);
    await choose(tester, 'Corn Seed (kg)');

    await tester.enterText(find.byType(TextFormField), '3');
    await tester.pump();
    expect(find.text('₱99.99'), findsOneWidget); // 3 x 33.33, shown as the line total

    await tester.tap(find.text('Confirm'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(saved, isNotNull);
    expect(saved!.itemName, 'Corn Seed');
    expect(saved!.quantity, 3);
    expect(saved!.lineTotal, 99.99); // exactly, not 99.99000000000001
  });
}
