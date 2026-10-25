import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level checks for the Harvest rework: batch numbers are issued by the
/// database, quantities are decimals, and every quantity carries its unit.
///
/// These read the SQL and Dart files. They cannot run the SQL: that is what
/// supabase_schema_harvest_batch_number_test.sql (run in the Supabase SQL
/// editor) is for. The numbering model at the bottom restates the SQL's rules
/// in Dart so the rules themselves (crop letters, per-crop sequence, yearly
/// restart) are checked here too.
String read(String path) => File(path).readAsStringSync();

int count(String source, String needle) => needle.allMatches(source).length;

void main() {
  unitAddTests();
  final sql = read(
    'supabase_schema/supabase_schema_harvest_batch_number_and_units.sql',
  );

  group('the migration', () {
    test('issues the number in the database, whatever the client sends', () {
      expect(sql, contains('CREATE OR REPLACE FUNCTION public.next_batch_number'));
      expect(sql, contains('BEFORE INSERT ON public.harvest_records'));
      expect(sql, contains('NEW.batch_number := public.next_batch_number'));
      expect(sql, contains('whatever a client sent is replaced'));
    });

    test('the number has the agreed shape', () {
      expect(
        sql,
        contains(
          "'BATCH-' || v_token || '-' || to_char(p_harvest_date, 'YYMMDD')",
        ),
      );
      expect(sql, contains("lpad(v_seq::TEXT, 4, '0')"));
      // The crop name is the Crop Management name, letters and digits only.
      expect(sql, contains('FROM public.crop_master WHERE id = p_crop_master_id'));
      expect(sql, contains("regexp_replace(v_name, '[^A-Za-z0-9]', '', 'g')"));
    });

    test('every crop gets its own letter, dynamically, never by name', () {
      expect(sql, contains('ADD COLUMN IF NOT EXISTS batch_prefix TEXT'));
      expect(sql, contains('BEFORE INSERT ON public.crop_master'));
      expect(sql, contains('uq_crop_master_batch_prefix'));
      expect(sql, contains('A cro')); // protect trigger message starts "A crop's"
      // No crop name is hardcoded anywhere in the numbering.
      for (final crop in ['Potato', 'Palay', 'Peanut', 'Ginger', 'Banana']) {
        final code = sql
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('--'))
            .join('\n');
        expect(code.contains("'$crop'"), isFalse, reason: crop);
      }
    });

    test('the sequence is per crop and per harvest year, and restarts', () {
      expect(sql, contains('PRIMARY KEY (crop_master_id, year)'));
      expect(sql, contains('ON CONFLICT (crop_master_id, year)'));
      expect(sql, contains('last_seq = public.batch_number_counters.last_seq + 1'));
      expect(sql, contains('EXTRACT(YEAR FROM p_harvest_date)'));
      expect(sql, contains('BETWEEN 2000 AND 2099'));
    });

    test('the inventory batch copies the number and unit from its harvest', () {
      expect(sql, contains('BEFORE INSERT ON public.inventory_batches'));
      expect(sql, contains('NEW.batch_number := v_number'));
      expect(sql, contains('NEW.unit := v_unit'));
    });

    test('a number and a unit can never change', () {
      expect(sql, contains('A batch number cannot be changed.'));
      expect(sql, contains('The unit of a harvest or batch cannot be changed.'));
      expect(sql, contains('BEFORE UPDATE OF batch_number, unit ON public.harvest_records'));
      expect(sql, contains('BEFORE UPDATE OF batch_number, unit ON public.inventory_batches'));
    });

    test('old records are untouched: nothing updates or deletes them', () {
      final code = sql
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n');
      expect(RegExp(r'UPDATE\s+public\.harvest_records', caseSensitive: false).hasMatch(code), isFalse);
      expect(RegExp(r'UPDATE\s+public\.inventory_batches', caseSensitive: false).hasMatch(code), isFalse);
      expect(RegExp(r'DELETE\s+FROM', caseSensitive: false).hasMatch(code), isFalse);
      expect(RegExp(r'DROP\s+(TABLE|COLUMN)', caseSensitive: false).hasMatch(code), isFalse);
      // Every new column defaults to kg, which is what every old row was.
      expect(count(sql, "ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'kg'"), 7);
    });

    test('units come from the existing units table and follow the batch', () {
      expect(sql, contains('SELECT 1 FROM public.units WHERE is_active AND lower(name) = NEW.unit'));
      for (final table in [
        'marketplace_listings',
        'cooperative_purchase_offers',
        'informal_sales',
      ]) {
        expect(sql, contains('BEFORE INSERT ON public.$table'), reason: table);
      }
      expect(sql, contains('BEFORE INSERT ON public.orders'));
      expect(sql, contains('copy_offer_unit_to_transaction'));
    });

    test('Ginger (exclusive channel) stays kg and DA-AMAD-only', () {
      expect(sql, contains('v_channel IS NOT NULL AND NEW.unit <> \'kg\''));
      // The migration does not touch the exclusive channel rules themselves.
      expect(sql.contains('exclusive_channel = '), isFalse);
      expect(sql.contains('enforce_selling_channel'), isFalse);
    });

    test('quantity columns stay DECIMAL(10,2) (0.45 is stored exactly)', () {
      final harvest = read('supabase_schema/supabase_schema_harvest.sql');
      expect(count(harvest, 'quantity_kg'), greaterThanOrEqualTo(2));
      expect(harvest, contains('quantity_kg              DECIMAL(10,2)'));
      expect(harvest, contains('available_kg      DECIMAL(10,2)'));
      expect(sql.contains('ALTER COLUMN quantity_kg'), isFalse);
    });
  });

  group('the app', () {
    test('never makes up a batch number any more', () {
      expect(read('lib/core/utils/app_utils.dart').contains('generateBatchNumber'), isFalse);
      final repo = read('lib/data/repositories/harvest_entry_repository.dart');
      // The harvest row is inserted without a number; the batch row is sent
      // the number read back from the saved harvest.
      final insertBlock = repo.substring(
        repo.indexOf(".from('harvest_records')\n        .insert({"),
        repo.indexOf(".select()\n        .single();"),
      );
      expect(insertBlock.contains("'batch_number'"), isFalse);
      expect(repo, contains("'batch_number': harvest.batchNumber"));
      expect(repo, contains("'unit': unit"));
    });

    test('the offline queue holds the unit but no made-up number', () {
      final repo = read('lib/data/repositories/harvest_entry_repository.dart');
      final queued = repo.substring(
        repo.indexOf('savePendingHarvest({'),
        repo.indexOf('// Locally-constructed'),
      );
      expect(queued.contains('batch_number'), isFalse);
      expect(queued, contains("'unit': unit"));
    });

    test('the form has Quantity and Unit, not "Quantity (kg)"', () {
      final form = read('lib/presentation/screens/farmer/harvest_entry_form_screen.dart');
      expect(form.contains('Quantity (kg)'), isFalse);
      expect(form, contains('QuantityUnitField('));
      expect(form, contains('UnitRepository'));
      expect(form, contains("'Assigned when you submit'"));
      final widget = read('lib/presentation/widgets/quantity_unit_field.dart');
      expect(widget, contains("'Quantity*'"));
      expect(widget, contains("'Unit*'"));
      expect(widget, contains('Unit is required'));
    });

    test('no whole-number rounding of a quantity is left in the harvest chain', () {
      for (final f in [
        'lib/presentation/screens/farmer/create_listing_screen.dart',
        'lib/presentation/screens/farmer/manage_inventory_screen.dart',
        'lib/presentation/screens/farmer/harvest_entry_form_screen.dart',
        'lib/presentation/screens/farmer/harvest_history_screen.dart',
        'lib/presentation/screens/farmer/my_listings_screen.dart',
        'lib/presentation/screens/farmer/farmer_listing_detail_screen.dart',
        'lib/presentation/screens/farmer/listing_success_screen.dart',
        'lib/presentation/screens/farmer/farmer_orders_screen.dart',
        'lib/presentation/screens/farmer/farmer_transaction_history_screen.dart',
        'lib/presentation/widgets/disposal_action_sheet.dart',
        'lib/presentation/widgets/harvest_log_widgets.dart',
        'lib/presentation/screens/buyer/my_orders_screen.dart',
        'lib/presentation/screens/buyer/order_detail_screen.dart',
      ]) {
        final src = read(f);
        expect(
          RegExp(r'(quantityKg|availableKg|volumeKg|remainingKg|displayAvailableKg)\s*!?\.toStringAsFixed\(0\)').hasMatch(src),
          isFalse,
          reason: '$f still rounds a quantity to a whole number',
        );
      }
    });

    test('prices are shown with their centavos', () {
      for (final f in [
        'lib/presentation/screens/buyer/listing_details_screen.dart',
        'lib/presentation/screens/admin/order_management_screen.dart',
        'lib/presentation/screens/admin/buyer_order_history_screen.dart',
      ]) {
        expect(
          RegExp(r'(pricePerKg|totalPrice)\.toStringAsFixed\(0\)').hasMatch(read(f)),
          isFalse,
          reason: f,
        );
      }
    });

    test('create listing sends decimals and suggests a price only in the same unit', () {
      final screen = read('lib/presentation/screens/farmer/create_listing_screen.dart');
      expect(screen, contains('parseDecimal(_quantityController.text'));
      expect(screen, contains('unit: batch.unit'));
      final dash = read('lib/data/repositories/dashboard_repository.dart');
      expect(dash, contains("query.ilike('unit', unit.trim())"));
      final listing = read('lib/data/repositories/listing_repository.dart');
      expect(listing, contains("'p_quantity_kg': roundQuantity(volumeKg)"));
      expect(listing, contains("'p_price_per_kg': roundQuantity(pricePerKg)"));
    });

    test('every explicit select over a unit-bearing table asks for the unit', () {
      expect(read('lib/data/repositories/buyer_marketplace_repository.dart'), contains('price_per_kg, unit, '));
      expect(count(read('lib/data/repositories/buyer_order_repository.dart'), 'price_per_kg, unit, total_price'), 2);
      expect(count(read('lib/data/repositories/admin_order_repository.dart'), 'price_per_kg, unit'), 2);
      expect(count(read('lib/data/repositories/admin_listing_repository.dart'), 'price_per_kg, unit, '), 2);
      expect(read('lib/data/models/cooperative_offer_model.dart'), contains('offered_quantity_kg, unit, offered_at'));
    });

    test('kg totals only add kg rows', () {
      for (final f in [
        'lib/data/repositories/harvest_repository.dart',
        'lib/data/repositories/dashboard_repository.dart',
        'lib/data/repositories/analytics_repository.dart',
        'lib/data/repositories/admin_reports_repository.dart',
        'lib/data/repositories/admin_dashboard_repository.dart',
        'lib/data/repositories/farmer_details_repository.dart',
        'lib/data/repositories/inventory_repository.dart',
      ]) {
        expect(read(f), contains('isKg('), reason: f);
      }
    });
  });

  group('numbering rules (a Dart model of the SQL, not the SQL itself)', () {
    test('letters run A..Z then AA, AB, never run out', () {
      expect(_prefix(1), 'A');
      expect(_prefix(2), 'B');
      expect(_prefix(26), 'Z');
      expect(_prefix(27), 'AA');
      expect(_prefix(28), 'AB');
      expect(_prefix(52), 'AZ');
      expect(_prefix(53), 'BA');
    });

    test('the examples from the requirement', () {
      final n = _Numbering();
      n.addCrop('Potato'); // A
      n.addCrop('Palay'); // B
      expect(n.issue('Potato', DateTime(2026, 10, 25)), 'BATCH-POTATO-261025-A0001');
      expect(n.issue('Potato', DateTime(2026, 10, 25)), 'BATCH-POTATO-261025-A0002');
      expect(n.issue('Palay', DateTime(2026, 10, 25)), 'BATCH-PALAY-261025-B0001');
      expect(n.issue('Palay', DateTime(2026, 10, 25)), 'BATCH-PALAY-261025-B0002');
    });

    test('the same crop continues across days and months of the year', () {
      final n = _Numbering()..addCrop('Potato');
      expect(n.issue('Potato', DateTime(2026, 1, 3)), 'BATCH-POTATO-260103-A0001');
      expect(n.issue('Potato', DateTime(2026, 6, 20)), 'BATCH-POTATO-260620-A0002');
      expect(n.issue('Potato', DateTime(2026, 12, 31)), 'BATCH-POTATO-261231-A0003');
    });

    test('a different crop has its own letter and starts again at 0001', () {
      final n = _Numbering()
        ..addCrop('Potato')
        ..addCrop('Palay')
        ..addCrop('Sweet Potato');
      n.issue('Potato', DateTime(2026, 5, 1));
      n.issue('Potato', DateTime(2026, 5, 2));
      expect(n.issue('Sweet Potato', DateTime(2026, 5, 2)), 'BATCH-SWEETPOTATO-260502-C0001');
    });

    test('every sequence restarts at 0001 in a new year, letters stay', () {
      final n = _Numbering()
        ..addCrop('Potato')
        ..addCrop('Palay');
      n.issue('Potato', DateTime(2026, 12, 30));
      n.issue('Potato', DateTime(2026, 12, 31));
      n.issue('Palay', DateTime(2026, 12, 31));
      expect(n.issue('Potato', DateTime(2027, 1, 1)), 'BATCH-POTATO-270101-A0001');
      expect(n.issue('Palay', DateTime(2027, 1, 1)), 'BATCH-PALAY-270101-B0001');
    });

    test('a late entry for last year continues LAST year\'s sequence', () {
      final n = _Numbering()..addCrop('Potato');
      n.issue('Potato', DateTime(2026, 12, 30)); // 0001 of 2026
      n.issue('Potato', DateTime(2027, 1, 2)); // 0001 of 2027
      expect(n.issue('Potato', DateTime(2026, 12, 31)), 'BATCH-POTATO-261231-A0002');
    });

    test('numbers are unique and grow past 9999', () {
      final n = _Numbering()..addCrop('Potato');
      final seen = <String>{};
      for (var i = 0; i < 10005; i++) {
        expect(seen.add(n.issue('Potato', DateTime(2026, 3, 1))), isTrue);
      }
      expect(n.issue('Potato', DateTime(2026, 3, 1)), 'BATCH-POTATO-260301-A10006');
    });

    test('a new crop added later needs no code change', () {
      final n = _Numbering();
      for (var i = 0; i < 30; i++) {
        n.addCrop('Crop $i');
      }
      expect(n.prefixOf('Crop 0'), 'A');
      expect(n.prefixOf('Crop 25'), 'Z');
      expect(n.prefixOf('Crop 26'), 'AA');
      expect(n.prefixOf('Crop 29'), 'AD');
    });

    test('every number matches the shape the SQL checks for', () {
      final n = _Numbering()..addCrop('Palay (Rice)');
      final number = n.issue('Palay (Rice)', DateTime(2026, 10, 25));
      expect(number, 'BATCH-PALAYRICE-261025-A0001');
      expect(
        RegExp(r'^BATCH-[A-Z0-9]+-[0-9]{6}-[A-Z]+[0-9]{4,}$').hasMatch(number),
        isTrue,
      );
    });
  });
}

// ── A model of the SQL's rules ───────────────────────────────────────────────

String _prefix(int index) {
  var q = index;
  var letters = '';
  while (q > 0) {
    q -= 1;
    letters = String.fromCharCode(65 + (q % 26)) + letters;
    q ~/= 26;
  }
  return letters;
}

class _Numbering {
  final _prefixes = <String, String>{};
  final _counters = <String, int>{}; // '<crop>|<year>'
  var _last = 0;

  void addCrop(String name) {
    _last += 1;
    _prefixes[name] = _prefix(_last);
  }

  String prefixOf(String name) => _prefixes[name]!;

  String issue(String crop, DateTime harvestDate) {
    final key = '$crop|${harvestDate.year}';
    final seq = (_counters[key] ?? 0) + 1;
    _counters[key] = seq;
    final token = crop.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final yy = (harvestDate.year % 100).toString().padLeft(2, '0');
    final mm = harvestDate.month.toString().padLeft(2, '0');
    final dd = harvestDate.day.toString().padLeft(2, '0');
    return 'BATCH-$token-$yy$mm$dd-${_prefixes[crop]}${seq.toString().padLeft(4, '0')}';
  }
}

/// "+ Unit" in Record New Harvest reuses the one Add Unit flow.
void unitAddTests() {
  group('Record New Harvest "+ Unit"', () {
    test('uses the shared Add Unit dialog and repository', () {
      final form = read('lib/presentation/screens/farmer/harvest_entry_form_screen.dart');
      expect(form, contains('promptAddUnit('));
      expect(form, contains('repo: _unitRepo'));
      expect(form, contains('onAddUnit: _addUnit'));
      expect(form, contains('unitAddCompact'));
      // The new unit joins the list the dropdown shows, with no reload.
      expect(form, contains('_units = [..._units, added]'));
      // Price Management uses the very same dialog.
      expect(read('lib/presentation/screens/admin/price_management_screen.dart'),
          contains('promptAddUnit('));
    });

    test('a Farmer\'s addition is not written to the Manager activity log', () {
      final repo = read('lib/data/repositories/unit_repository.dart');
      expect(repo, contains("role == 'admin' || role == 'officer'"));
    });

    test('the database lets only an active Farmer insert, and nothing else', () {
      final sql = read('supabase_schema/supabase_schema_farmer_add_unit.sql');
      expect(sql, contains('CREATE POLICY "units: active farmer adds"'));
      expect(sql, contains('FOR INSERT TO authenticated'));
      expect(sql, contains("r.role = 'farmer' AND r.status = 'active'"));
      final code = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
      expect(RegExp(r'FOR (UPDATE|DELETE|ALL)').hasMatch(code), isFalse);
      expect(sql, contains(">= 10"));
    });
  });
}
