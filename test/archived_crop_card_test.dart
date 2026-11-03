import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/theme/sagana_colors.dart';
import 'package:sagana/data/services/market_types_service.dart';
import 'package:sagana/presentation/screens/admin/crop_management_screen.dart';

import 'support/ignore_font_errors.dart';

const _public = MarketType(
  code: 'open_market',
  name: 'Public Market',
  nameTl: 'Pampublikong Market',
  buyerVisible: true,
  managerSetsPrice: false,
  sortOrder: 1,
  isActive: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => MarketTypes.instance.debugSet(types: [_public]));
  tearDown(() => MarketTypes.instance.debugSet());

  Future<void> show(WidgetTester tester, CropMasterItem crop, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: ArchivedCropCard(
              crop: crop,
              onRestore: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const longCrop = CropMasterItem(
    id: '1',
    cropName: 'A Very Long Crop Name That Keeps Going',
    category: 'Root & Spice Crop',
    cropType: 'open_market',
    description:
        'A long description that goes on for more than two lines so the card has to clamp it instead of growing without limit on a small screen.',
    isActive: false,
    sortOrder: 1,
  );
  const plainCrop = CropMasterItem(
    id: '2',
    cropName: 'Ube',
    category: 'Vegetable',
    cropType: 'open_market',
    isActive: false,
    sortOrder: 2,
  );

  for (final size in const [Size(320, 568), Size(412, 915)]) {
    testWidgets('archived card fits at ${size.width.toInt()} wide', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await show(tester, longCrop, size);
        expect(find.text('ARCHIVED'), findsOneWidget);
        expect(find.text('Public Market'), findsOneWidget);
        expect(find.text('Restore'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  gridCardTests();

  testWidgets('a crop with no photo or description still lays out', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await show(tester, plainCrop, const Size(360, 640));
      expect(find.text('Ube'), findsOneWidget);
      expect(find.text('Vegetable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

// The grid card: crop name, then category, then market type.
void gridCardTests() {
  testWidgets('grid card shows name, category, market type in order, no overflow', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const crop = CropMasterItem(
        id: '1',
        cropName: 'A Very Long Crop Name That Keeps Going',
        category: 'Root & Spice Crop',
        cropType: 'open_market',
        isActive: true,
        sortOrder: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.66,
                  children: [
                    CropCard(
                      crop: crop,
                      cs: Theme.of(context).colorScheme,
                      sagana: context.saganaColors,
                      onTap: () {},
                      onArchive: () {},
                      onDelete: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final name = tester.getTopLeft(find.textContaining('A Very Long')).dy;
      final category = tester.getTopLeft(find.text('Root & Spice Crop')).dy;
      final market = tester.getTopLeft(find.text('Public Market')).dy;
      expect(name, lessThan(category));
      expect(category, lessThan(market));
      expect(tester.takeException(), isNull);
    });
  });
}
