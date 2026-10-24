import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/price_record_model.dart';
import 'package:sagana/data/repositories/price_management_repository.dart';
import 'package:sagana/data/services/market_types_service.dart';
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
                builder: (_) => UpdatePriceSheet(
                  price: PriceRecordModel(
                    id: 'p1',
                    cropId: 'c1',
                    cropName: 'Copra',
                    price: 40,
                    unit: 'kg',
                    priceType: 'sp3_cooperative',
                    recordedAt: DateTime(2026, 10, 1),
                  ),
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

  Finder saveButton() => find.text('Update Price').last;

  testWidgets('Source / Reference is required, marked, and checked inline', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await open(tester);
      expect(find.text('Source / Reference Document *'), findsOneWidget);
      expect(find.text('New Price (₱/kg) *'), findsOneWidget);
      expect(find.text('Effective Date *'), findsOneWidget);

      // Empty.
      await tester.tap(saveButton());
      await tester.pump();
      expect(find.text('Source / reference is required'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      // Whitespace only counts as empty.
      final source = find.byType(TextFormField).last;
      await tester.enterText(source, '     ');
      await tester.pump();
      expect(find.text('Source / reference is required'), findsOneWidget);
    });
  });

  testWidgets('a bad price is flagged inline too, not with a snackbar', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await open(tester);
      final price = find.byType(TextFormField).first;
      await tester.enterText(price, '');
      await tester.tap(saveButton());
      await tester.pump();
      expect(find.text('Price is required'), findsOneWidget);

      await tester.enterText(price, '0');
      await tester.pump();
      expect(find.text('Price must be greater than 0'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  testWidgets('the notification notice no longer names a member count', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await open(tester);
      expect(
        find.text(
          'Updating this price will send a notification to all registered members.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('push notification'), findsNothing);
      expect(find.textContaining(RegExp(r'\d+ registered')), findsNothing);
    });
  });
}
