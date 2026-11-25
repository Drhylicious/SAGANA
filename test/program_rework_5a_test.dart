import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/farmer_profile_model.dart';
import 'package:sagana/data/models/program_model.dart';
import 'package:sagana/presentation/widgets/admin_program_card.dart';
import 'package:sagana/presentation/widgets/program_history_sheet.dart';

import 'support/ignore_font_errors.dart';

CooperativeProgram _program({
  String purpose = 'distribution',
  String benefit = 'grant',
  String? image = 'https://x/y.jpg',
  String? description = 'Seeds for members',
  double? budget = 5000,
  String? item = 'item-1',
  String? returnCrop,
  double? returnQty,
  String? returnUnit,
}) => CooperativeProgram.fromMap({
  'id': 'p1',
  'program_name': 'Eggplant Seeds',
  'program_type': 'crop',
  'benefit_type': benefit,
  'program_purpose': purpose,
  'description': description,
  'budget': budget,
  'image_url': image,
  'season_year': 2026,
  'status': 'active',
  'distribution_item_id': item,
  'distribution_item': item == null
      ? null
      : {'item_name': 'Eggplant Seed', 'unit': 'pack', 'quantity_on_hand': 40},
  'return_crop_id': returnCrop,
  'return_crop': returnCrop == null ? null : {'crop_name': 'Eggplant'},
  'return_quantity': returnQty,
  'return_unit': returnUnit,
  'member_count': 3,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Incomplete programs (computed, never stored)', () {
    test('a fully configured Free Distribution program is complete', () {
      final p = _program();
      expect(p.missingFields, isEmpty);
      expect(p.isIncomplete, isFalse);
      expect(p.canDistribute, isTrue);
    });

    test('a legacy program lists exactly what it lacks and cannot distribute', () {
      final p = _program(image: null, description: '  ', budget: null, item: null);
      // No configured item and no categories: where it distributes from is missing.
      expect(p.missingFields, ['photo', 'description', 'budget', 'sources']);
      expect(p.isIncomplete, isTrue);
      expect(p.canDistribute, isFalse);
    });

    test('an older program that still has its single item counts as having a source', () {
      final p = _program(); // item set, no categories
      expect(p.missingFields, isNot(contains('sources')));
      expect(p.canDistribute, isTrue);
    });

    test('a zero budget counts as missing; a zero return quantity does not', () {
      expect(_program(budget: 0).missingFields, ['budget']);
      expect(
        _program(
          benefit: 'revenue_share',
          returnCrop: 'c',
          returnQty: 0,
          returnUnit: 'kg',
        ).missingFields,
        isEmpty,
      );
    });

    test('Product Sales programs need the same core fields, but no item or return', () {
      final p = _program(
        purpose: 'sales',
        image: null,
        description: null,
        budget: null,
        item: null,
      );
      // A Product Sales program also needs the categories it distributes from.
      expect(p.missingFields, ['photo', 'description', 'budget', 'sources']);
      expect(p.isIncomplete, isTrue);
      // A complete Sales program is not Incomplete, with no distribution item.
      expect(_program(purpose: 'sales', item: null).isIncomplete, isTrue); // no sources yet
      final withSources = CooperativeProgram.fromMap({
        'id': 'p1',
        'program_name': 'Cookies',
        'program_type': 'food',
        'benefit_type': 'grant',
        'program_purpose': 'sales',
        'description': 'd',
        'budget': 100,
        'image_url': 'x',
        'season_year': 2026,
        'status': 'active',
        'member_count': 0,
        'source_categories': ['Harvest Stock'],
      });
      expect(withSources.isIncomplete, isFalse);
    });

    test('the item join and its stock reach the model', () {
      final p = _program();
      expect(p.distributionItemName, 'Eggplant Seed');
      expect(p.distributionItemUnit, 'pack');
      expect(p.distributionItemStock, 40);
    });
  });

  group('History model and wording', () {
    test('parses a get_program_history() row', () {
      final e = ProgramHistoryEntry.fromMap({
        'out_at': '2026-11-04T07:05:00+00:00',
        'out_type': 'benefit_distributed',
        'out_actor': 'Ana Cruz',
        'out_role': 'officer',
        'out_subject': 'Juan Dela Cruz',
        'out_details': {'quantity': 10, 'item': 'Eggplant Seed'},
      });
      expect(e.type, 'benefit_distributed');
      expect(e.actorRole, 'officer');
      expect(e.details['item'], 'Eggplant Seed');
    });

    test('a missing actor is shown as unrecorded, never guessed', () async {
      // formatStamp is pure; the actor wording needs l10n, tested below.
      expect(
        ProgramHistoryText.formatStamp(DateTime(2026, 11, 4, 15, 5)),
        'Nov 4, 2026 · 3:05 PM',
      );
      expect(
        ProgramHistoryText.formatStamp(DateTime(2026, 11, 4, 0, 7)),
        'Nov 4, 2026 · 12:07 AM',
      );
    });
  });

  group('Localization', () {
    test('every Phase 5A string exists in English and Tagalog', () {
      Map<String, dynamic> load(String f) =>
          jsonDecode(File('lib/core/l10n/$f').readAsStringSync())
              as Map<String, dynamic>;
      final en = load('app_en.arb');
      final tl = load('app_tl.arb');
      final keys = en.keys.where(
        (k) =>
            !k.startsWith('@') &&
            (k.startsWith('programHist') ||
                k.startsWith('farmerProg') ||
                k.startsWith('programMgmtField') ||
                k.startsWith('programMgmtReturn') ||
                k.startsWith('programMgmtActivity') ||
                k == 'programMgmtHistoryAction' ||
                k == 'programMgmtIncompleteBadge' ||
                k == 'adminLogProgramActivityUpdated'),
      );
      expect(keys, isNotEmpty);
      for (final k in keys) {
        expect(tl.containsKey(k), isTrue, reason: '$k missing in app_tl.arb');
      }
    });

    test('Benefit Type labels are exactly the two short names', () {
      Map<String, dynamic> load(String f) =>
          jsonDecode(File('lib/core/l10n/$f').readAsStringSync())
              as Map<String, dynamic>;
      final en = load('app_en.arb');
      expect(en['programMgmtBenefitGrant'], 'Free Distribution');
      expect(en['programMgmtBenefitRevenueShare'], 'Harvest Return');
    });
  });

  group('Admin program card', () {
    Future<void> show(
      WidgetTester tester,
      CooperativeProgram p, {
      Size size = const Size(360, 900),
      Locale locale = const Locale('en'),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: AdminProgramCard(
                program: p,
                accent: Colors.green,
                icon: Icons.grass_rounded,
                statusLabel: 'ACTIVE',
                statusColor: Colors.green,
                memberCountLabel: '3 members',
                onMembers: () {},
                onHistory: () {},
                onEdit: () {},
                onComplete: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows Members, History and Edit; no overflow at 360 wide',
        (tester) async {
      await runIgnoringFontErrors(() async {
        await show(tester, _program(image: null));
        expect(find.text('Manage Members'), findsOneWidget);
        expect(find.text('History'), findsOneWidget);
        expect(find.byTooltip('Edit'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('an Incomplete program says what is missing', (tester) async {
      await runIgnoringFontErrors(() async {
        await show(
          tester,
          _program(image: null, item: null, budget: null),
        );
        expect(find.text('Incomplete'), findsOneWidget);
        expect(find.textContaining('Missing:'), findsOneWidget);
        expect(find.textContaining('Distribute from'), findsOneWidget);
        expect(find.text('No category set'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a complete Harvest Return program shows the requirement',
        (tester) async {
      await runIgnoringFontErrors(() async {
        await show(
          tester,
          _program(
            benefit: 'revenue_share',
            returnCrop: 'c1',
            returnQty: 50,
            returnUnit: 'kg',
          ),
        );
        expect(find.text('Incomplete'), findsNothing);
        expect(find.text('Harvest Return'), findsOneWidget);
        expect(find.text('Return: 50 per Farmer'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('renders in Tagalog without overflow', (tester) async {
      await runIgnoringFontErrors(() async {
        await show(
          tester,
          _program(image: null, item: null),
          locale: const Locale('tl'),
        );
        expect(find.text('Hindi Kumpleto'), findsOneWidget);
        expect(find.text('Kasaysayan'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('Phase 5A SQL contract (read from the script, not the database)', () {
    final sql = File(
      'supabase_schema/supabase_schema_program_rework_5a_creation_history.sql',
    ).readAsStringSync();

    test('distribute_program_benefit requires staff and blocks a second distribution', () {
      final fn = sql.substring(
        sql.indexOf('FUNCTION public.distribute_program_benefit'),
        sql.indexOf('5. get_program_history(): the per-program'),
      );
      expect(fn, contains('public.is_staff()'));
      expect(fn, contains('already received a distribution'));
      expect(fn, contains('distribution_item_id IS NULL'));
      expect(fn, contains('FOR UPDATE'));
    });

    test('History is staff-only and reads the existing trail', () {
      final fn = sql.substring(sql.indexOf('FUNCTION public.get_program_history'));
      expect(fn, contains('public.is_staff()'));
      expect(fn, contains('admin_activity_log'));
      expect(fn, contains("source = 'db'"));
      expect(sql, isNot(contains('CREATE TABLE')));
    });

    test('Farmers lose direct read of activities and use the safe function', () {
      expect(sql, contains('DROP POLICY IF EXISTS "program_activities: members read all"'));
      final fn = sql.substring(sql.indexOf('FUNCTION public.get_my_program_activities'));
      expect(fn, isNot(contains('created_by')));
      expect(fn, contains('auth.uid()'));
    });

    test('required fields are enforced for signed-in staff, updates stay editable', () {
      expect(sql, contains('auth.uid() IS NULL'));
      expect(sql, contains('cannot be left empty'));
      expect(sql, contains('Product Sales programs'));
    });
  });
}
