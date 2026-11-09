import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/utils/app_error_message.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/program_model.dart';
import 'package:sagana/presentation/widgets/app_multi_select_field.dart';

import 'support/ignore_font_errors.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

DistributionItem _item(
  String id,
  String name,
  String category, {
  String? source,
  String? farmer,
}) => DistributionItem.fromMap({
  'id': id,
  'item_name': name,
  'category': category,
  'unit': 'kg',
  'quantity_on_hand': 15,
  'source': source,
  'source_farmer_id': farmer,
});

CooperativeProgram _sales(List<String> sources) => CooperativeProgram.fromMap({
  'id': 'p',
  'program_name': 'Peanut Cookies',
  'program_type': 'food',
  'benefit_type': 'grant',
  'program_purpose': 'sales',
  'description': 'd',
  'budget': 100,
  'image_url': 'x',
  'season_year': 2026,
  'status': 'active',
  'member_count': 0,
  'source_categories': sources,
});

void main() {
  distributionSourcesTests();
  programFormHasNoSubtitlesTests();
  final en = lookupAppLocalizations(const Locale('en'));
  final sql = _read(
    'supabase_schema/supabase_schema_program_rework_p11_sales_sources_cancel.sql',
  );
  final code = sql
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('--'))
      .join('\n');

  group('Items offered to a Product Sales program', () {
    final tomato = _item(
      '1',
      'Tomato',
      'Harvest Stock',
      source: 'Jhon Drhy M. Salangsang',
      farmer: 'f1',
    );
    final scythe = _item('2', 'Scythe', 'Tools & Equipment');
    final pig = _item('3', 'Pig', 'Livestock');
    final seeds = _item('4', 'Rice Seeds', 'Seeds');
    final all = [tomato, scythe, pig, seeds];

    test('only items in the selected categories are offered', () {
      expect(itemsInSources(all, ['Seeds']).map((i) => i.itemName), [
        'Rice Seeds',
      ]);
    });

    test('several sources can be selected together', () {
      expect(
        itemsInSources(all, ['Harvest Stock', 'Seeds']).map((i) => i.itemName),
        ['Tomato', 'Rice Seeds'],
      );
    });

    test('unrelated categories (Scythe, Pig) never appear unless chosen', () {
      final names = itemsInSources(all, [
        'Harvest Stock',
      ]).map((i) => i.itemName);
      expect(names, ['Tomato']);
      expect(names, isNot(contains('Scythe')));
      expect(names, isNot(contains('Pig')));
    });

    test('no source chosen offers nothing; case and spaces do not matter', () {
      expect(itemsInSources(all, []), isEmpty);
      expect(itemsInSources(all, ['  seeds ']).map((i) => i.itemName), [
        'Rice Seeds',
      ]);
    });

    test('an item shows as its plain name, not "Tomato — Farmer"', () {
      expect(tomato.displayName, 'Tomato');
      expect(tomato.displayName.contains('—'), isFalse);
    });
  });

  group('Product Sales program: Distribute from', () {
    test('the sources are read from the program', () {
      expect(_sales(['Seeds', 'Harvest Stock']).sourceCategories, [
        'Seeds',
        'Harvest Stock',
      ]);
      expect(
        CooperativeProgram.fromMap({
          'id': 'p',
          'program_name': 'n',
          'program_type': 't',
          'benefit_type': 'grant',
          'season_year': 2026,
          'status': 'active',
          'member_count': 0,
        }).sourceCategories,
        isEmpty,
      );
    });

    test(
      'a Product Sales program with no source is Incomplete; with one it is complete',
      () {
        expect(_sales([]).missingFields, ['sources']);
        expect(_sales([]).isIncomplete, isTrue);
        expect(_sales(['Seeds']).isIncomplete, isFalse);
      },
    );

    test('a Distribution program does not need sources', () {
      final d = CooperativeProgram.fromMap({
        'id': 'p',
        'program_name': 'n',
        'program_type': 't',
        'benefit_type': 'grant',
        'program_purpose': 'distribution',
        'description': 'd',
        'budget': 1,
        'image_url': 'x',
        'distribution_item_id': 'i',
        'season_year': 2026,
        'status': 'active',
        'member_count': 0,
      });
      expect(d.missingFields, isNot(contains('sources')));
    });

    test(
      'the form requires at least one category, for create and edit alike',
      () {
        final screen = _read(
          'lib/presentation/screens/admin/program_management_screen.dart',
        );
        expect(screen, contains('programMgmtSourcesRequired'));
        expect(screen, contains('AppMultiSelectField('));
        expect(screen.contains('FilterChip('), isFalse);
        // The same field and the same save, for Product Sales AND Distribution.
        expect(
          'sourcesField()'.allMatches(screen).length,
          3,
        ); // 1 definition + 2 uses
        expect(
          'sourceCategories: selectedSources,'.allMatches(screen).length,
          2,
        ); // create + edit
        expect(screen.contains('selectedItemId'), isFalse);
      },
    );

    test(
      'the options are the live Inventory categories, read again each time the form opens',
      () {
        final screen = _read(
          'lib/presentation/screens/admin/program_management_screen.dart',
        );
        expect(
          screen,
          contains('CategoryRepository().fetchInventoryCategories()'),
        );
        expect(screen, contains('Future<void> _showProgramSheet'));
        expect(screen, contains('_inventoryCategories = freshCategories'));
        // New categories are saved in the same table the form reads.
        expect(
          _read('lib/data/repositories/category_repository.dart'),
          contains("_addCategory('inventory_categories', name)"),
        );
        expect(
          _read('lib/data/repositories/category_repository.dart'),
          contains("_fetchNames('inventory_categories')"),
        );
      },
    );

    test('the card names the missing field in plain words', () {
      final card = _read('lib/presentation/widgets/admin_program_card.dart');
      expect(card, contains("case 'sources':"));
      expect(en.programMgmtFieldSources, 'Distribute from');
    });
  });

  group('Manage Products: the + button opens a modal', () {
    final page = _read(
      'lib/presentation/screens/admin/program_products_screen.dart',
    );

    test('there is no add form or button at the top of the page', () {
      expect(page.contains('_addPanel'), isFalse);
      expect(page.contains('_adding'), isFalse);
      expect(page, contains('floatingActionButton'));
      expect(page, contains('onPressed: _openAddModal'));
    });

    test(
      'the modal is a management modal with the usual Cancel and Add buttons',
      () {
        expect(page, contains('showManagementModal<bool>'));
        expect(page, contains('ManagementModalShell('));
        expect(page, contains('l10n.prodAddTitle'));
      },
    );

    test(
      'items come only from the program\'s sources; with none chosen it says so',
      () {
        expect(page, contains('fetchProgramSources(widget.programId)'));
        expect(
          page,
          contains('fetchEligibleInventoryForSaleProgram(categories: sources)'),
        );
        expect(page, contains('l10n.prodNoSources'));
        expect(page, contains('l10n.prodNoItemsInSources'));
      },
    );

    test('the item shows as name, then stock and unit', () {
      expect(page, contains('formatQuantityUnit(i.quantityOnHand, i.unit)'));
      expect(page, contains('itemPickerNames(items)'));
    });

    test('a refusal from the database is explained in plain words', () {
      expect(page, contains('friendlyError(l10n, e, st)'));
      expect(
        messageForDatabaseText(en, 'PRODUCT_NOT_IN_SOURCE: x'),
        en.errProductNotInSource,
      );
    });
  });

  group(
    'Cooperative orders: who can cancel (replaces the old Purchase Requests screen)',
    () {
      test(
        'Program Management has no purchase review any more; Cooperative orders are in Marketplace > Orders',
        () {
          expect(
            File(
              'lib/presentation/screens/admin/program_purchase_review_screen.dart',
            ).existsSync(),
            isFalse,
          );
          final repo = _read('lib/data/repositories/program_repository.dart');
          expect(repo.contains('cancel_program_purchase'), isFalse);
          expect(repo.contains('confirm_program_purchase'), isFalse);
        },
      );

      test(
        'the Farmer cancels their own pending order, through the Cooperative order repository',
        () {
          final repo = _read(
            'lib/data/repositories/cooperative_order_repository.dart',
          );
          expect(repo, contains("'cancel_program_purchase'"));
          final farmer = _read(
            'lib/presentation/screens/farmer/farmer_program_order_detail_screen.dart',
          );
          expect(farmer, contains('o.isPending'));
          expect(farmer, contains('_cancel'));
        },
      );

      test(
        'only the Farmer cancels, and only while Pending: staff have no cancel (as for a Marketplace order)',
        () {
          final staff = _read(
            'lib/presentation/screens/admin/admin_program_order_detail_screen.dart',
          );
          expect(staff.contains('_cancel'), isFalse);
          final sql = _read(
            'supabase_schema/supabase_schema_unify_m09_cooperative_cancel_pending_only.sql',
          );
          final cancel = sql.substring(
            sql.indexOf('FUNCTION public.cancel_program_purchase'),
          );
          expect(cancel.contains('_pp_staff_guard()'), isFalse);
          expect(
            cancel,
            contains("o.status <> 'pending'"),
          ); // the Farmer: pending only
        },
      );
    },
  );

  group('p11 SQL contract (read from the script)', () {
    test('a sources column, the Incomplete rule and the add-product guard', () {
      expect(
        sql,
        contains('ADD COLUMN IF NOT EXISTS source_categories TEXT[]'),
      );
      expect(sql, contains("THEN 'sources' END"));
      expect(sql, contains('BEFORE INSERT ON public.program_products'));
      expect(sql, contains('PRODUCT_NOT_IN_SOURCE'));
    });

    test(
      'only adding is guarded: existing products, prices and the On sale switch are untouched',
      () {
        expect(
          sql.contains('BEFORE UPDATE ON public.program_products'),
          isFalse,
        );
        expect(sql.contains('UPDATE OR'), isFalse);
      },
    );

    test(
      'it stops if the live cancel function is not the version it extends',
      () {
        expect(sql, contains('pg_get_functiondef'));
        expect(
          sql,
          contains('differs from the version this migration extends'),
        );
      },
    );

    test('nothing is deleted or rewritten', () {
      for (final w in [
        'DELETE FROM',
        'DROP TABLE',
        'TRUNCATE',
        'UPDATE public.program_product_purchases SET status',
      ]) {
        expect(code.contains(w), isFalse, reason: w);
      }
    });
  });

  group('Multi-select dropdown', () {
    Future<void> pump(
      WidgetTester tester,
      List<String> options,
      List<List<String>> log, {
      List<String> initial = const [],
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                var values = [...initial];
                return StatefulBuilder(
                  builder: (context, setInner) => Padding(
                    padding: const EdgeInsets.all(20),
                    child: AppMultiSelectField(
                      values: values,
                      options: options,
                      hintText: 'Select categories',
                      labelText: 'Distribute from *',
                      onChanged: (v) {
                        log.add(v);
                        setInner(() => values = v);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('opens a list, ticks several, and shows them in the field', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final log = <List<String>>[];
        await pump(tester, ['Seeds', 'Livestock', 'Harvest Stock'], log);
        expect(find.text('Select categories'), findsOneWidget);
        await tester.tap(find.text('Select categories'));
        await tester.pump();
        expect(find.text('Livestock'), findsOneWidget);
        await tester.tap(find.text('Seeds'));
        await tester.pump();
        await tester.tap(find.text('Livestock'));
        await tester.pump();
        expect(log.last, ['Seeds', 'Livestock']);
        // Untick works too.
        await tester.tap(find.text('Seeds'));
        await tester.pump();
        expect(log.last, ['Livestock']);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets(
      'a category added later is offered as soon as the options include it',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final options = ['Seeds'];
          late StateSetter rebuild;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    rebuild = setState;
                    return AppMultiSelectField(
                      values: const [],
                      options: options,
                      hintText: 'Select categories',
                      onChanged: (_) {},
                    );
                  },
                ),
              ),
            ),
          );
          await tester.tap(find.text('Select categories'));
          await tester.pump();
          expect(find.text('Dairy'), findsNothing);
          rebuild(() => options.add('Dairy'));
          await tester.pump(); // rebuild the form
          await tester.pump(); // the open list refreshes right after that frame
          await tester.pump();
          expect(find.text('Dairy'), findsOneWidget);
        });
      },
    );
  });
}

void programFormHasNoSubtitlesTests() {
  group(
    'Program form: no subtitles under the fields (Create and Edit share one form)',
    () {
      test('no field carries helper text', () {
        final screen = _read(
          'lib/presentation/screens/admin/program_management_screen.dart',
        );
        final start = screen.indexOf('Future<void> _showProgramSheet');
        final end = screen.indexOf('Widget _requestsMenu');
        final form = screen.substring(start, end);
        expect(form.contains('helperText'), isFalse);
        expect(form.contains('helperMaxLines'), isFalse);
        expect(
          form.contains('Distribution: the cooperative gives an item'),
          isFalse,
        );
      });

      test('the helper strings are gone from both languages', () {
        for (final f in ['app_en.arb', 'app_tl.arb']) {
          final text = _read('lib/core/l10n/$f');
          for (final k in [
            'programMgmtDistributesFromHelper',
            'programMgmtSourcesHelper',
            'programMgmtMemberDiscountHelper',
          ]) {
            expect(text.contains('"$k"'), isFalse, reason: '$f has $k');
          }
        }
      });

      test('Create and Edit use the same single form', () {
        final screen = _read(
          'lib/presentation/screens/admin/program_management_screen.dart',
        );
        expect('Future<void> _showProgramSheet'.allMatches(screen).length, 1);
        expect(screen, contains('_showProgramSheet(null)')); // create
      });
    },
  );
}

void distributionSourcesTests() {
  group('Distribution programs distribute from categories too', () {
    final sql = _read(
      'supabase_schema/supabase_schema_program_rework_p11_sales_sources_cancel.sql',
    );
    final screen = _read(
      'lib/presentation/screens/admin/program_management_screen.dart',
    );

    test(
      'the form has no single-item picker any more; Create and Edit use the categories field',
      () {
        expect(screen.contains('programMgmtDistributesFromLabel'), isFalse);
        expect(screen.contains('programMgmtNoItemsToDistribute'), isFalse);
      },
    );

    test(
      'staff pick an item from the program\'s categories when distributing',
      () {
        expect(screen, contains('itemsInSources(_items, p.sourceCategories)'));
        expect(screen, contains('programMgmtChooseItemToGive'));
        expect(screen, contains('_distItemId'));
        expect(screen, contains('programMgmtNoItemsInCategories'));
      },
    );

    test(
      'an older program with one configured item still works until edited',
      () {
        expect(screen, contains('p.distributionItemId'));
        final older = CooperativeProgram.fromMap({
          'id': 'p',
          'program_name': 'Peanut Seed Distribution',
          'program_type': 'crop',
          'benefit_type': 'grant',
          'program_purpose': 'distribution',
          'description': 'd',
          'budget': 100,
          'image_url': 'x',
          'distribution_item_id': 'item-1',
          'season_year': 2026,
          'status': 'active',
          'member_count': 2,
        });
        expect(older.canDistribute, isTrue);
        expect(older.isIncomplete, isFalse);
      },
    );

    test('with categories and no item, it can distribute', () {
      final p = CooperativeProgram.fromMap({
        'id': 'p',
        'program_name': 'Seeds',
        'program_type': 'crop',
        'benefit_type': 'grant',
        'program_purpose': 'distribution',
        'description': 'd',
        'budget': 100,
        'image_url': 'x',
        'season_year': 2026,
        'status': 'active',
        'member_count': 0,
        'source_categories': ['Seeds', 'Fertilizer'],
      });
      expect(p.canDistribute, isTrue);
      expect(p.isIncomplete, isFalse);
    });

    test(
      'the database lets staff give an item from the categories, and nothing else changes',
      () {
        final start = sql.indexOf('FUNCTION public.distribute_program_benefit');
        final fn = sql.substring(
          start,
          sql.indexOf(r'$function$;', start + 10),
        );
        expect(fn, contains('not in a category this program distributes from'));
        for (final kept in [
          'already received a distribution',
          'Insufficient stock',
          'no longer distributes items',
          'public.is_staff()',
          'FOR UPDATE',
        ]) {
          expect(fn, contains(kept), reason: kept);
        }
      },
    );

    test('an older column name is renamed, not lost', () {
      expect(
        sql,
        contains('RENAME COLUMN sale_source_categories TO source_categories'),
      );
    });
  });
}
