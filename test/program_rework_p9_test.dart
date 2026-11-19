import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/utils/app_error_message.dart';
import 'package:sagana/data/models/program_outcome_model.dart';


String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

String _fn(String sql, String name, String until) {
  final start = sql.indexOf('FUNCTION public.$name');
  expect(start, greaterThan(0), reason: name);
  return sql.substring(start, sql.indexOf(until, start + 10));
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final tl = lookupAppLocalizations(const Locale('tl'));
  final sql = _read('supabase_schema/supabase_schema_program_rework_p9_outcome_decisions_remove_settings.sql');
  final code = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

  group('Report Outcome form', () {
    final form = _read('lib/presentation/screens/farmer/report_outcome_screen.dart');

    test('the Area planted and its unit are gone', () {
      expect(form.contains('_areaCtrl'), isFalse);
      expect(form.contains('_areaUnit'), isFalse);
      expect(form.contains('outcAreaPlanted'), isFalse);
    });

    test('nothing is optional: every date is a required form field', () {
      expect(form.contains('(optional)'), isFalse);
      expect('_DateFormField('.allMatches(form).length, 4); // 1 class + 3 uses
      expect(form, contains('requiredMessage: l10n.outcDateRequired'));
      expect(form, contains('l10n.outcCauseRequired'));
      expect(form, contains('l10n.outcExplanationRequired'));
      expect(form, contains('_photos.isNotEmpty'));
      for (final l in [en, tl]) {
        for (final label in [l.outcHarvestDate, l.outcPlantedDate, l.outcFailureDate, l.outcExplanation]) {
          expect(label, endsWith('*'));
          expect(label.toLowerCase().contains('optional') || label.toLowerCase().contains('opsyonal'), isFalse);
        }
      }
    });

    test('the Farmer form no longer asks for a quantity or unit (the reviewer records the return)', () {
      expect(form.contains('QuantityUnitField('), isFalse);
      expect(form.contains('promptAddUnit('), isFalse);
    });

    test('the two outcome cards have the same height', () {
      expect(form, contains('IntrinsicHeight('));
      expect(form, contains('CrossAxisAlignment.stretch'));
    });

    test('the repository no longer sends an area', () {
      final repo = _read('lib/data/repositories/farmer_program_repository.dart');
      expect(repo, contains("'p_area': null"));
      expect(repo.contains('double? area,'), isFalse);
    });
  });

  group('Successful outcome: the return is decided after verification', () {
    final detail = _read('lib/presentation/screens/admin/program_outcome_detail_screen.dart');

    test('finalizing still needs the review and the field verification (database)', () {
      final f = _fn(sql, 'finalize_program_outcome', r'$function$;');
      expect(f, contains("v_r.review_decision IS DISTINCT FROM 'validated'"));
      expect(f, contains('v_r.verified_by IS NULL'));
      expect(f, contains('FOR UPDATE'));
    });

    test('the quantity and unit are required and come from the reviewer, not the program', () {
      final f = _fn(sql, 'finalize_program_outcome', r'$function$;');
      expect(f, contains('RETURN_QUANTITY'));
      expect(f, contains('p_return_quantity'));
      expect(f, contains('p_return_unit'));
      final open = _fn(sql, '_program_open_return', r'$function$;');
      expect(open, contains('p_quantity, p_quantity'));
      expect(open.contains('return_quantity'), isFalse); // never the program's fixed quantity
    });

    test('the return record is created only by confirming a Successful outcome', () {
      final f = _fn(sql, 'finalize_program_outcome', r'$function$;');
      expect(f, contains("IF p_final_outcome = 'successful' THEN"));
      expect(f, contains('_program_open_return(p_report_id, p_return_quantity, p_return_unit)'));
    });

    test('the old 3-argument finalize is dropped so it cannot bypass the new rule', () {
      expect(sql, contains('DROP FUNCTION IF EXISTS public.finalize_program_outcome(UUID, TEXT, TEXT);'));
    });

    test("only the Quantity is asked; the unit is the item's own, shown beside the number", () {
      expect(detail, contains('_returnInputs'));
      expect(detail, contains("Key('returnQuantityField')"));
      expect(detail, contains('suffixText: _returnUnit'));
      expect(detail.contains('QuantityUnitField('), isFalse);
      expect(detail, contains('returnQuantity: successful && _r.isHarvestReturn ? qty : null'));
      expect(detail, contains('outcReturnQtyRequired'));
    });

    test('the staff list says whether a harvest return applies', () {
      expect(sql, contains("'is_harvest_return'"));
      final model = OutcomeReport.fromMap({
        'id': 'r',
        'program_member_id': 'm',
        'program_id': 'p',
        'program_name': 'Peanut Seed Distribution',
        'farmer_id': 'f',
        'farmer_name': 'Ellen',
        'reported_outcome': 'successful',
        'explanation': 'x',
        'status': 'pending_validation',
        'submitted_at': '2026-11-04T01:00:00Z',
        'is_harvest_return': true,
        'return_item_name': 'Peanut Seeds',
        'item_unit': 'kg',
      });
      expect(model.isHarvestReturn, isTrue);
      expect(model.returnItemName, 'Peanut Seeds');
      expect(model.itemUnit, 'kg');
    });
  });

  group('Failed outcome: the four decisions are made after verification', () {
    final detail = _read('lib/presentation/screens/admin/program_outcome_detail_screen.dart');

    test('one of the four decisions is required to finalize as Failed', () {
      final f = _fn(sql, 'finalize_program_outcome', r'$function$;');
      for (final r in [
        'closed_no_further_obligation',
        'eligible_for_reassessment',
        'referred_for_loan_assessment',
        'pending_cooperative_decision',
      ]) {
        expect(f, contains("'$r'"), reason: r);
      }
      expect(f, contains('RESOLUTION_INVALID'));
    });

    test('the note is required except for Pending Cooperative Decision', () {
      final f = _fn(sql, 'finalize_program_outcome', r'$function$;');
      expect(f, contains("p_resolution <> 'pending_cooperative_decision' AND v_rnote IS NULL"));
      final later = _fn(sql, 'record_failed_resolution', r'$function$;');
      expect(later, contains("p_resolution <> 'pending_cooperative_decision' AND v_note IS NULL"));
    });

    test('the decision is recorded under the reviewer, and creates no loan', () {
      final open = _fn(sql, '_program_open_resolution', r'$function$;');
      expect(open, contains('auth.uid()'));
      for (final s in ['farmer_loans', 'loan_requests', 'issue_loan']) {
        expect(code.contains(s), isFalse, reason: s);
      }
    });

    test('the screen lists the four decisions with none preselected', () {
      expect(detail, contains('_decisionInputs'));
      expect(detail, contains('FailedResolution.all'));
      expect(detail, contains('String? _decision;'));
      expect(detail, contains('outcDecisionRequired'));
    });
  });

  group('Harvest Return settings are removed', () {
    test('the three settings functions are dropped; limits and deadline are not applied', () {
      for (final f in ['set_underreport_tolerance', 'set_assistance_setting', 'get_program_settings']) {
        expect(sql, contains('DROP FUNCTION IF EXISTS public.$f'), reason: f);
      }
      final blocker = _fn(sql, '_assistance_blocker', r'$function$;');
      expect(blocker.contains('program_settings'), isFalse);
      expect(blocker, contains("status = 'pending'")); // only the duplicate guard stays
    });

    test('nothing historical is deleted', () {
      expect(code, isNot(contains('DELETE FROM')));
      expect(code, isNot(contains('DROP TABLE')));
      expect(code, isNot(contains('TRUNCATE')));
    });

    test('no screen, repository or string refers to the settings any more', () {
      for (final f in [
        'lib/presentation/screens/admin/program_management_screen.dart',
        'lib/data/repositories/program_assistance_repository.dart',
        'lib/data/models/program_assistance_model.dart',
        'lib/presentation/widgets/program_return_panel.dart',
        'lib/presentation/screens/farmer/my_programs_screen.dart',
      ]) {
        final src = _read(f);
        for (final s in ['setUnderreportTolerance', 'setSetting', 'AssistancePolicy', 'retSettings', 'assistSettings', 'underreportFlag', 'retUnderreport']) {
          expect(src.contains(s), isFalse, reason: '$f has $s');
        }
      }
    });

    test('the pending-request refusal is translated', () {
      expect(messageForDatabaseText(en, 'ASSIST_PENDING: x'), en.errAssistPending);
      expect(messageForDatabaseText(tl, 'RETURN_QUANTITY: x'), tl.errReturnQuantity);
    });
  });

  group('Product Sales are visible and purchasable for every active Farmer', () {
    final p4 = _read('supabase_schema/supabase_schema_program_rework_p4_member_pricing.sql');
    final details = _read('lib/presentation/screens/farmer/program_details_screen.dart');
    final browse = _read('lib/presentation/screens/farmer/browse_programs_screen.dart');

    test('the database does not require enrollment to read products or to buy', () {
      final policy = p4.substring(p4.indexOf('CREATE POLICY "program_products: farmers read available"'));
      final body = policy.substring(0, policy.indexOf(');'));
      expect(body.contains('program_members'), isFalse);
      expect(body, contains("cp.status = 'active' AND cp.program_purpose = 'sales'"));
      final buy = p4.substring(p4.indexOf('FUNCTION public.request_program_purchase'), p4.indexOf('v_is_member := EXISTS'));
      expect(buy, contains('Any active cooperative member may buy'));
      expect(buy.contains('not enrolled'), isFalse);
    });

    test('enrollment only decides the price, and only the program\'s own members get it', () {
      expect(p4, contains('CASE WHEN v_is_member THEN COALESCE(v_program.member_discount_percent, 0) ELSE 0 END'));
      expect(p4, contains('is_member_price'));
    });

    test('the cause: Program Details showed products only to enrolled Farmers. It now shows them to everyone', () {
      expect(details, contains('Widget _productsCard'));
      final notEnrolled = details.substring(details.indexOf('List<Widget> _buildNotEnrolledSections'));
      expect(notEnrolled, contains('_productsCard(context)'));
      expect(notEnrolled, contains('if (_isSalesProgram)'));
    });

    test('Cooperative Products are sold in the Marketplace now: no separate Shop button or catalog', () {
      expect(browse.contains('onViewProducts'), isFalse);
      expect(browse.contains('catShopChip'), isFalse);
      expect(File('lib/presentation/screens/farmer/program_product_catalog_screen.dart').existsSync(), isFalse);
    });

    test('the Marketplace shows them to any active Farmer, enrolled or not (enrollment only decides the price)', () {
      final tab = _read('lib/presentation/screens/farmer/farmer_marketplace_tab.dart');
      expect(tab, contains('_CooperativeProductCard'));
      expect(tab.contains('isMember'), isFalse); // no enrollment gate on the screen
      final repo = _read('lib/data/repositories/farmer_program_repository.dart');
      expect(repo, contains('fetchCooperativeProducts'));
      expect(repo, contains('memberOf.contains'));
    });
  });
}

