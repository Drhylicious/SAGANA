import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/utils/input_validation_utils.dart';
import 'package:sagana/data/repositories/price_management_repository.dart';
import 'package:sagana/data/services/market_types_service.dart';
import 'package:sagana/presentation/screens/admin/price_management_screen.dart';
import 'package:sagana/presentation/widgets/app_dropdown_field.dart';
import 'package:sagana/presentation/widgets/management_modal.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

const _coop = MarketType(
  code: 'sp3_cooperative',
  name: 'Cooperative Market',
  nameTl: 'Market ng Kooperatiba',
  buyerVisible: false,
  managerSetsPrice: true,
  sortOrder: 2,
  isActive: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockStorageChannels();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-key',
    );
  });

  group('unit name rules', () {
    test('normalizes case and spacing', () {
      expect(normalizeUnitName('  Crate  '), 'crate');
      expect(normalizeUnitName('Half   Sack'), 'half sack');
      expect(normalizeUnitName(null), '');
    });

    test('accepts ordinary units', () {
      for (final u in ['kg', 'g', 'crate', 'half sack', 'm.t', 'pcs/box']) {
        expect(checkUnitName(u), isNull, reason: u);
      }
    });

    test('rejects empty, too long and odd characters', () {
      expect(checkUnitName('   '), UnitIssue.empty);
      expect(checkUnitName('x' * 21), UnitIssue.tooLong);
      expect(checkUnitName('1kg'), UnitIssue.invalidCharacters);
      expect(checkUnitName('kg!'), UnitIssue.invalidCharacters);
      expect(checkUnitName("kg'; drop"), UnitIssue.invalidCharacters);
    });
  });

  testWidgets('Unit Cost box is as tall as the Unit dropdown beside it', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      final costKey = GlobalKey();
      final unitKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: AppDropdownField<String>(
                      key: unitKey,
                      value: 'kg',
                      hintText: 'Unit',
                      items: const ['kg'],
                      itemLabel: (u) => u,
                      onChanged: (_) {},
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      key: costKey,
                      // A small font keeps the field's own height below 50, so the
                      // minimum height is what is being measured (the app's 14px
                      // Inter gives about 40).
                      style: const TextStyle(fontSize: 8),
                      decoration: const InputDecoration(
                        hintText: '0.00',
                        prefixText: '₱ ',
                        isDense: true,
                        constraints: BoxConstraints(minHeight: 50),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      // The dropdown's own bordered box, not the whole field column.
      final unit = tester
          .getSize(
            find.descendant(
              of: find.byKey(unitKey),
              matching: find.byType(GestureDetector),
            ),
          )
          .height;
      final cost = tester.getSize(find.byKey(costKey)).height;
      expect(cost, closeTo(unit, 1.0));
    });
  });

  group('Add Price Entry unit dropdown', () {
    setUp(() => MarketTypes.instance.debugSet(types: [_coop]));
    tearDown(() => MarketTypes.instance.debugSet());

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
                  builder: (_) => AddPriceEntrySheet(
                    availableCrops: const [],
                    units: const ['kg', 'g', 'sack'],
                    repo: PriceManagementRepository(),
                    onSaved: () {},
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
      // Open the Unit dropdown (shows its current value, kg).
      await tester.tap(find.text('kg'));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('lists the shared units and a compact + Unit row', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await open(tester);
        expect(find.text('g'), findsWidgets);
        expect(find.text('sack'), findsOneWidget);
        expect(find.text('+ Unit'), findsOneWidget);
        expect(find.byIcon(Icons.add_circle_outline_rounded), findsNothing);
        await tester.tapAt(const Offset(5, 5)); // close the menu
        await tester.pump(const Duration(milliseconds: 300));
      });
    });

    testWidgets('+ Unit refuses empty, odd and duplicate names inline', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await open(tester);
        await tester.tap(find.text('+ Unit'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Add New Unit'), findsOneWidget);

        await tester.tap(find.text('Add'));
        await tester.pump();
        expect(find.text('Unit name is required'), findsOneWidget);

        await tester.enterText(find.byType(TextField).last, '9lives');
        await tester.tap(find.text('Add'));
        await tester.pump();
        expect(
          find.text(
            'Start with a letter. Use only letters, numbers, spaces, . / or -',
          ),
          findsOneWidget,
        );

        // Same unit as an existing one, whatever the case or spacing.
        await tester.enterText(find.byType(TextField).last, '  SACK ');
        await tester.tap(find.text('Add'));
        await tester.pump();
        expect(find.text('"sack" already exists'), findsOneWidget);
        expect(find.text('Add New Unit'), findsOneWidget);
        await tester.tap(find.text('Cancel').last);
        await tester.pump(const Duration(milliseconds: 300));
      });
    });
  });
}
