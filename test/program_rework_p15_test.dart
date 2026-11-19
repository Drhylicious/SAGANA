import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/utils/app_error_message.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  programTypeTests();
  final en = lookupAppLocalizations(const Locale('en'));
  final p15 = _read('supabase_schema/supabase_schema_program_rework_p15_return_same_item.sql');
  final p14 = _read('supabase_schema/supabase_schema_program_rework_p14_remove_three_programs.sql');
  String fn(String sql, String name) {
    final start = sql.indexOf('FUNCTION public.$name');
    expect(start, greaterThan(0), reason: name);
    return sql.substring(start, sql.indexOf(r'$function$;', start + 10));
  }

  group('Harvest Return: the Farmer returns the same item they were given', () {
    test('the return is opened for the distributed item, in that item\'s unit', () {
      final f = fn(p15, '_program_open_return');
      expect(f, contains('v_m.inventory_item_id'));
      expect(f, contains('distributed_item_name'));
      expect(f, contains('RETURN_UNIT'));
      expect(f, contains('inventory_item_id'));
      expect(f.contains('crop_master'), isFalse); // no crop chosen at program level
      expect(f.contains('return_crop_id'), isFalse);
    });

    test('the confirmed quantity is added back to THAT item, once, with a ledger row', () {
      final f = fn(p15, 'record_program_return_receipt');
      expect(f, contains('v_ret.inventory_item_id'));
      expect(f, contains('quantity_on_hand = quantity_on_hand + p_quantity'));
      expect(f, contains("'restock'"));
      expect(f, contains('FOR UPDATE'));
      expect(f, contains('RETURN_OVER_RECEIPT')); // still never more than due
    });

    test('a return opened under the old (crop) rule still works', () {
      final f = fn(p15, 'record_program_return_receipt');
      expect(f, contains("'harvest_received'"));
      expect(f, contains('ELSE'));
    });

    test('a Harvest Return program no longer needs a return crop', () {
      expect(fn(p15, 'finalize_program_outcome'), contains("v_returns := (v_p.benefit_type = 'revenue_share');"));
      final missing = p15.substring(p15.indexOf('FUNCTION public.program_missing_fields'), p15.indexOf(r'$$;', p15.indexOf(r'AS $$')));
      expect(missing.contains("'return_crop'"), isFalse);
      expect(missing, contains("'return_quantity'"));
      expect(missing, contains("'return_unit'"));
    });

    test('the staff list says which item and unit', () {
      final f = fn(p15, 'get_program_outcome_reports');
      expect(f, contains("'return_item_name'"));
      expect(f, contains("'item_unit'"));
    });

    test('nothing is deleted or rewritten', () {
      final code = p15.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
      for (final w in ['DELETE FROM', 'DROP TABLE', 'TRUNCATE', 'DROP COLUMN']) {
        expect(code.contains(w), isFalse, reason: w);
      }
      expect(code, contains('ALTER COLUMN crop_id DROP NOT NULL'));
    });

    test('p13 re-run cannot bring the old crop rule back', () {
      final p13 = _read('supabase_schema/supabase_schema_program_rework_p13_outcome_any_staff.sql');
      expect(p13.contains('v_p.return_crop_id IS NOT NULL'), isFalse);
    });

    test('the refusals are explained in plain words', () {
      expect(messageForDatabaseText(en, 'RETURN_UNIT: x'), en.errReturnUnit);
      expect(messageForDatabaseText(en, 'RETURN_ITEM: x'), en.errReturnItem);
    });

    test('the program form has no crop picker and no unit (the Inventory item\'s unit is used)', () {
      final screen = _read('lib/presentation/screens/admin/program_management_screen.dart');
      expect(screen.contains('selectedCropId'), isFalse);
      expect(screen.contains('_cropOptions'), isFalse);
      expect(screen.contains('QuantityUnitField('), isFalse);
      expect(screen.contains('selectedUnit'), isFalse);
      // The quantity to return is decided on the outcome screen after the field check, not in this form.
      expect(screen.contains("Key('returnQuantityField')"), isFalse);
    });

    test('Farmer and staff screens name the item that was given, not a crop', () {
      expect(_read('lib/presentation/screens/farmer/my_programs_screen.dart'), contains('entry.itemName'));
      final detail = _read('lib/presentation/screens/admin/program_outcome_detail_screen.dart');
      expect(detail, contains('_r.returnItemName'));
      expect(detail, contains('_returnUnit = _r.itemUnit'));
    });
  });

  group('Removing three empty programs (p14)', () {
    final code = p14.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

    test('it targets exactly those three, by exact name', () {
      for (final n in ['Organic Farming Assistance Program', 'Government Seed Distribution', 'Government Fertilizer Distribution']) {
        expect(code, contains("'$n'"), reason: n);
      }
      expect(code, contains('<> 3')); // stops unless exactly three match
    });

    test('it refuses to run if any of them has members, approved requests, purchases or outcomes', () {
      for (final t in ['program_members', 'program_enrollment_requests', 'program_product_purchases', 'program_outcome_reports', 'program_returns', 'program_assistance_requests']) {
        expect(code, contains(t), reason: t);
      }
      expect(code, contains("status = 'approved'"));
      expect(code, contains('Nothing was changed'));
    });

    test('the delete guard is switched off and straight back on, inside one transaction', () {
      expect(code, contains('DISABLE TRIGGER trg_protect_program_from_delete'));
      expect(code, contains('ENABLE TRIGGER trg_protect_program_from_delete'));
      expect(code.indexOf('DISABLE TRIGGER'), lessThan(code.indexOf('ENABLE TRIGGER')));
      expect(code, contains('BEGIN;'));
      expect(code, contains('COMMIT;'));
    });

    test('it deletes only from cooperative_programs, by id, never other programs', () {
      expect('DELETE FROM'.allMatches(code).length, 1);
      expect(code, contains('DELETE FROM public.cooperative_programs WHERE id = ANY (v_ids)'));
    });
  });
}

void programTypeTests() {
  final p16 = _read('supabase_schema/supabase_schema_program_rework_p16_program_types.sql');
  final code = p16.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

  group('Program Type: a managed dropdown, separate from Program Purpose (p16)', () {
    test('a lookup table holds the types, seeded with the three starting ones', () {
      expect(code, contains('CREATE TABLE IF NOT EXISTS public.program_types'));
      for (final t in ["'Crop'", "'Livestock'", "'Processed Products'"]) {
        expect(code, contains(t), reason: t);
      }
      expect(code, contains('lower(btrim(name))')); // "crop" and "Crop" are the same type
    });

    test('everyone signed in may read; only the Manager or an Officer may add', () {
      expect(code, contains('FOR SELECT TO authenticated USING (is_active = TRUE)'));
      expect(code, contains('public.is_staff()'));
      expect(code, contains("('table', 'program_types', 'dashboard')"));
    });

    test('the three programs are classified by exact name, changing only program_type', () {
      expect(code, contains("SET program_type = 'Crop'"));
      expect(code, contains("program_name = 'Peanut Seed Distribution'"));
      expect(code, contains("SET program_type = 'Livestock'"));
      expect(code, contains("program_name = 'Livestock Dispersal'"));
      expect(code, contains("SET program_type = 'Processed Products'"));
      expect(code, contains("program_name = 'Peanut Cookies'"));
      // Purpose, status, members and everything else are not written.
      for (final w in ['program_purpose =', 'SET status', 'DELETE FROM', 'DROP TABLE', 'DROP COLUMN']) {
        expect(code.contains(w), isFalse, reason: w);
      }
    });

    test('the form uses a dropdown with "+ Add New Program Type", fed by the table', () {
      final screen = _read('lib/presentation/screens/admin/program_management_screen.dart');
      expect(screen.contains('typeCtrl'), isFalse);
      expect(screen, contains('addNewLabel: l10n.programTypeAddNew'));
      final flat = screen.replaceAll(RegExp(r'\s+'), '');
      expect(flat, contains('CategoryRepository().fetchProgramTypes()'));
      expect(RegExp(r'CategoryRepository\(\)\.addProgramType\(name,?\)').hasMatch(flat), isTrue);
      final repo = _read('lib/data/repositories/category_repository.dart');
      expect(repo, contains("_fetchNames('program_types')"));
      expect(repo, contains("_addCategory('program_types', name)"));
    });

    test('Program Purpose (Distribution / Product Sales) is untouched', () {
      final screen = _read('lib/presentation/screens/admin/program_management_screen.dart');
      expect(screen, contains("items: const ['distribution', 'sales']"));
    });

    test('icons and colours do not depend on capital letters, and Processed Products has its own', () {
      final screen = _read('lib/presentation/screens/admin/program_management_screen.dart');
      expect(screen, contains('type.trim().toLowerCase()'));
      expect(screen, contains("case 'processed products':"));
    });

    test('item selection does not depend on the type (it uses categories)', () {
      final products = _read('lib/presentation/screens/admin/program_products_screen.dart');
      expect(products.contains('programType'), isFalse);
    });
  });
}
