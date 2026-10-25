import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The loan reference is issued by the database (LRN-YYYYMMDD-XXXX), and the
/// app only displays what it is given. These read the sources so a script or a
/// screen that drifts from that rule is caught: an old LN-YYYY-### builder
/// coming back, a screen that formats the reference itself, or the Loans
/// screens losing the shared form components.
String read(String path) => File(path).readAsStringSync();

void main() {
  final sql = read('supabase_schema/supabase_schema_loan_reference_number.sql');

  test('the SQL issues LRN-YYYYMMDD-XXXX in Philippine time, like Orders', () {
    expect(sql, contains("'LRN-'"));
    expect(sql, contains("to_char(v_local, 'YYYYMMDD')"));
    expect(sql, contains("'Asia/Manila'"));
    // The same A001 ... Z999, AA001 layout Orders use, not a second copy of it.
    expect(sql, contains('public.format_order_sequence(v_seq)'));
    expect(sql, isNot(contains('CREATE OR REPLACE FUNCTION public.format_loan')));
  });

  test('one counter row per year, locked while a number is issued', () {
    expect(sql, contains('CREATE TABLE IF NOT EXISTS public.loan_reference_counters'));
    expect(sql, contains('ON CONFLICT (year) DO UPDATE SET last_seq = loan_reference_counters.last_seq + 1'));
    expect(sql, contains('REVOKE ALL ON public.loan_reference_counters FROM PUBLIC, anon, authenticated'));
  });

  test('a trigger issues the number and nothing can change it afterwards', () {
    expect(sql, contains('BEFORE INSERT ON public.farmer_loans'));
    expect(sql, contains('NEW.reference_no := public.next_loan_reference'));
    expect(sql, contains('BEFORE UPDATE OF reference_no ON public.farmer_loans'));
    expect(sql, contains('A loan reference number cannot be changed.'));
  });

  test('issue_loan no longer builds an LN- number and reads the issued one back', () {
    final start = sql.indexOf('CREATE OR REPLACE FUNCTION public.issue_loan');
    final fn = sql.substring(start, sql.indexOf(r'$function$;', start));
    expect(fn, isNot(contains("'LN-'")));
    expect(fn, isNot(contains('pg_advisory_xact_lock')));
    expect(fn, contains('RETURNING fl.id, fl.reference_no INTO v_loan_id, v_reference_no'));
    // The insert leaves reference_no to the trigger.
    final insert = fn.substring(fn.indexOf('INSERT INTO farmer_loans AS fl ('));
    expect(insert.substring(0, insert.indexOf(') VALUES')), isNot(contains('reference_no')));
  });

  test('existing loans are never rewritten by the script', () {
    final code = sql
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('--'))
        .join('\n');
    expect(RegExp(r'UPDATE\s+(public\.)?farmer_loans\b', caseSensitive: false).hasMatch(code), isFalse);
    expect(RegExp(r'DELETE\s+FROM\s+(public\.)?farmer_loans\b', caseSensitive: false).hasMatch(code), isFalse);
  });

  test('screens show the reference as stored, never rebuilding it', () {
    for (final f in [
      'lib/data/models/admin_loan_model.dart',
      'lib/data/models/loan_model.dart',
      'lib/data/repositories/admin_loan_repository.dart',
      'lib/presentation/screens/admin/loan_history_screen.dart',
      'lib/presentation/screens/admin/record_payment_screen.dart',
      'lib/presentation/screens/admin/issue_new_loan_screen.dart',
      'lib/presentation/screens/farmer/my_loans_screen.dart',
    ]) {
      final src = read(f);
      expect(src.contains("'LN-"), isFalse, reason: f);
      expect(src.contains("'LRN-"), isFalse, reason: f);
    }
  });

  test('Record Payment and Issue New Loan share the Manager form components', () {
    for (final f in [
      'lib/presentation/screens/admin/record_payment_screen.dart',
      'lib/presentation/screens/admin/issue_new_loan_screen.dart',
    ]) {
      final src = read(f);
      expect(src, contains('AccountFormSection('), reason: f);
      expect(src, contains('AccountFieldLabel('), reason: f);
      expect(src, contains('PrimaryButton('), reason: f);
      expect(src, contains('Form('), reason: f);
    }
  });

  test('Loan History uses the loan choice chips, with the date period behind a filter', () {
    final src = read('lib/presentation/screens/admin/loan_history_screen.dart');
    expect(src, contains('LoanChoiceChip('));
    expect(src.contains('ListingStatusFilterChip'), isFalse);
    expect(src.contains('_buildPeriodChips'), isFalse);
    expect(src, contains('LoanPeriodFilterModal'));
    // Record Payment's Monthly / Full Balance use the same chip.
    expect(read('lib/presentation/screens/admin/record_payment_screen.dart'), contains('LoanChoiceChip('));
  });
}
