import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/services/market_types_service.dart';
import 'package:sagana/data/repositories/price_management_repository.dart';
import 'package:sagana/presentation/screens/admin/price_management_screen.dart';
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

  setUp(() => MarketTypes.instance.debugSet(types: [_coop]));
  tearDown(() => MarketTypes.instance.debugSet());

  Future<void> openForm(WidgetTester tester) async {
    // A small phone: any overflow in the form would throw and fail the test.
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
                  availableCrops: const [
                    {
                      'id': 'c1',
                      'crop_name': 'Copra',
                      'crop_type': 'sp3_cooperative',
                    },
                  ],
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
  }

  Finder submitButton() => find.text('Add Price Entry').last;

  testWidgets('an empty form shows inline errors, not a snackbar', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await openForm(tester);
      expect(find.text('Crop Name *'), findsOneWidget);
      expect(find.text('Price (₱) *'), findsOneWidget);
      expect(find.text('Source / Reference *'), findsOneWidget);

      await tester.tap(submitButton());
      await tester.pump();

      expect(find.text('Crop name is required'), findsOneWidget);
      expect(find.text('Price is required'), findsOneWidget);
      expect(find.text('Source / reference is required'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  testWidgets('invalid values are rejected with their own message', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await openForm(tester);
      final fields = find.byType(TextFormField);
      // 0 = crop, 1 = price, 2 = source
      await tester.enterText(fields.at(0), 'Nonexistent');
      await tester.enterText(fields.at(1), '0');
      await tester.enterText(fields.at(2), 'x' * 151);
      await tester.tap(submitButton());
      await tester.pump();
      expect(find.text('Select a crop from the list'), findsOneWidget);
      expect(find.text('Price must be greater than 0'), findsOneWidget);
      expect(find.text('Use 150 characters or fewer'), findsOneWidget);

      await tester.enterText(fields.at(1), '12.345');
      await tester.pump();
      expect(find.text('Use at most 2 decimal places'), findsOneWidget);

      await tester.enterText(fields.at(1), '500000');
      await tester.pump();
      expect(find.text('Price cannot be more than ₱100000'), findsOneWidget);

      await tester.enterText(fields.at(1), '.');
      await tester.pump();
      expect(find.text('Please enter a valid price.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
