import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/presentation/widgets/quantity_unit_field.dart';

import 'support/ignore_font_errors.dart';

/// The Quantity | Unit input of Record New Harvest: a decimal quantity with no
/// unit baked in, a separate unit dropdown, and each field's own message
/// directly under it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final formKey = GlobalKey<FormState>();
  late TextEditingController controller;
  String? unit;
  var unitChanges = 0;
  var addUnitCalls = 0;
  String? addUnitResult;

  Future<void> pump(
    WidgetTester tester, {
    bool locked = false,
    String? initialUnit,
    double width = 360,
    bool withAddUnit = false,
  }) async {
    // A small phone: any overflow here would throw and fail the test.
    tester.view.physicalSize = Size(width, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    controller = TextEditingController();
    unit = initialUnit;
    unitChanges = 0;
    addUnitCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    QuantityUnitField(
                      controller: controller,
                      units: const ['kg', 'g', 'sack', 'piece'],
                      selectedUnit: unit,
                      unitLocked: locked,
                      addUnitLabel: '+ Unit',
                      onAddUnit: withAddUnit
                          ? () async {
                              addUnitCalls++;
                              return addUnitResult;
                            }
                          : null,
                      onUnitChanged: (u) => setState(() {
                        unit = u;
                        unitChanges++;
                      }),
                    ),
                    const SizedBox(height: 12),
                    const Text('below the row'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('labels: Quantity and Unit side by side, no fixed "kg"', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await pump(tester);
      expect(find.text('Quantity*'), findsOneWidget);
      expect(find.text('Unit*'), findsOneWidget);
      expect(find.text('Quantity (kg)*'), findsNothing);
      expect(find.text('KG'), findsNothing);
      // Same top edge: they are one row.
      expect(
        tester.getTopLeft(find.text('Quantity*')).dy,
        tester.getTopLeft(find.text('Unit*')).dy,
      );
      // Quantity is to the left of Unit.
      expect(
        tester.getTopLeft(find.text('Quantity*')).dx,
        lessThan(tester.getTopLeft(find.text('Unit*')).dx),
      );
    });
  });

  testWidgets('an empty form shows BOTH required messages, each under its own '
      'field and aligned to it', (tester) async {
    await runIgnoringFontErrors(() async {
      await pump(tester);
      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();

      final qtyError = find.text('Quantity is required');
      final unitError = find.text('Unit is required');
      expect(qtyError, findsOneWidget);
      expect(unitError, findsOneWidget);

      final qtyField = tester.getRect(find.byKey(const Key('quantityField')));
      final unitField = tester.getRect(find.byKey(const Key('unitField')));
      final qtyErr = tester.getRect(qtyError);
      final unitErr = tester.getRect(unitError);

      // Directly below its own field, inside its own column.
      expect(qtyErr.top, greaterThanOrEqualTo(qtyField.top));
      expect(qtyErr.center.dy, greaterThan(qtyField.top + 20));
      expect(qtyErr.left, greaterThanOrEqualTo(qtyField.left));
      expect(qtyErr.right, lessThanOrEqualTo(qtyField.right + 1));
      expect(unitErr.left, greaterThanOrEqualTo(unitField.left));
      expect(unitErr.right, lessThanOrEqualTo(unitField.right + 1));
      // The Quantity message is in the left column, not under Unit.
      expect(qtyErr.right, lessThan(unitField.left));
      // The two fields stay side by side with the same top.
      expect(qtyField.top, unitField.top);
    });
  });

  testWidgets('accepts 0.45, 1.25 and 10.75', (tester) async {
    await runIgnoringFontErrors(() async {
      await pump(tester, initialUnit: 'kg');
      for (final value in ['0.45', '1.25', '10.75']) {
        await tester.enterText(find.byKey(const Key('quantityField')), value);
        await tester.pump();
        expect(controller.text, value);
        expect(formKey.currentState!.validate(), isTrue, reason: value);
      }
    });
  });

  testWidgets('refuses zero, a third decimal and letters', (tester) async {
    await runIgnoringFontErrors(() async {
      await pump(tester, initialUnit: 'kg');

      await tester.enterText(find.byKey(const Key('quantityField')), '0');
      await tester.pump();
      expect(find.text('Quantity must be greater than 0'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('quantityField')), '0.45');
      await tester.pump();
      expect(find.text('Quantity must be greater than 0'), findsNothing);

      // A third decimal and letters are not typeable at all.
      await tester.enterText(find.byKey(const Key('quantityField')), '0.456');
      await tester.pump();
      expect(controller.text, isNot('0.456'));
      await tester.enterText(find.byKey(const Key('quantityField')), 'abc');
      await tester.pump();
      expect(controller.text, isNot('abc'));
    });
  });

  testWidgets('the unit is chosen from the list and is required', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await pump(tester);
      await tester.enterText(find.byKey(const Key('quantityField')), '2.5');
      expect(formKey.currentState!.validate(), isFalse); // no unit yet
      await tester.pump();
      expect(find.text('Unit is required'), findsOneWidget);
      expect(find.text('Quantity is required'), findsNothing);

      await tester.tap(find.text('Select unit'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('sack').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(unit, 'sack');
      expect(unitChanges, 1);
      expect(formKey.currentState!.validate(), isTrue);
    });
  });

  testWidgets('a locked unit shows kg and cannot be changed', (tester) async {
    await runIgnoringFontErrors(() async {
      await pump(tester, locked: true, initialUnit: 'kg');
      await tester.tap(find.text('kg').first);
      await tester.pump(const Duration(milliseconds: 300));
      // Whatever is opened, picking another unit must not change it.
      final other = find.text('sack');
      if (other.evaluate().isNotEmpty) {
        await tester.tap(other.last);
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(unit, 'kg');
      expect(unitChanges, 0);
    });
  });

  testWidgets('Quantity and Unit are the same height and share a top edge', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await pump(tester);
      final qty = tester.getRect(find.byKey(const Key('quantityField')));
      final unitRect = tester.getRect(find.byKey(const Key('unitField')));
      expect(qty.height, unitRect.height);
      expect(qty.top, unitRect.top);
      expect(qty.bottom, unitRect.bottom);
      expect(qty.height, kQuantityUnitFieldHeight);
      // Quantity is the wider of the two, as before.
      expect(qty.width, greaterThan(unitRect.width));
    });
  });

  testWidgets('Quantity stays the same height as Unit on a narrow phone', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await pump(tester, width: 320);
      expect(
        tester.getSize(find.byKey(const Key('quantityField'))).height,
        tester.getSize(find.byKey(const Key('unitField'))).height,
      );
    });
  });

  testWidgets('"+ Unit" adds a unit and selects it, no refresh needed', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await pump(tester, withAddUnit: true);
      addUnitResult = 'bunch';
      await tester.tap(find.text('Select unit'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('+ Unit'), findsOneWidget);
      await tester.tap(find.text('+ Unit'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(addUnitCalls, 1);
      expect(unit, 'bunch');
      expect(unitChanges, 1);
    });
  });

  testWidgets('cancelling "+ Unit" changes nothing', (tester) async {
    await runIgnoringFontErrors(() async {
      await pump(tester, withAddUnit: true);
      addUnitResult = null;
      await tester.tap(find.text('Select unit'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('+ Unit'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(addUnitCalls, 1);
      expect(unit, isNull);
      expect(unitChanges, 0);
    });
  });

  testWidgets('no "+ Unit" row without a handler, nor while the unit is locked', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await pump(tester); // no handler
      await tester.tap(find.text('Select unit'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('+ Unit'), findsNothing);
    });
    await runIgnoringFontErrors(() async {
      await pump(tester, locked: true, initialUnit: 'kg', withAddUnit: true);
      await tester.tap(find.text('kg').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('+ Unit'), findsNothing);
    });
  });

  testWidgets('no overflow on a narrow phone with both errors showing', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await pump(tester, width: 320);
      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('below the row'), findsOneWidget);
    });
  });
}
