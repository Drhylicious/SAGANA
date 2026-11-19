import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/utils/app_error_message.dart';
import 'package:sagana/data/models/program_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

DistributionItem _item(String id, String name, {String? source, String category = 'Harvest Stock'}) =>
    DistributionItem.fromMap({
      'id': id,
      'item_name': name,
      'category': category,
      'unit': 'kg',
      'quantity_on_hand': 15,
      'source': source,
    });

void main() {
  sqlScriptsAreWellFormedTests();
  final en = lookupAppLocalizations(const Locale('en'));
  final sql = _read('supabase_schema/supabase_schema_program_rework_p13_outcome_any_staff.sql');
  final code = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
  String fn(String name) {
    final start = code.indexOf('FUNCTION public.$name');
    expect(start, greaterThan(0), reason: name);
    return code.substring(start, code.indexOf(r'$function$;', start + 10));
  }

  group('Field verification: Manager or Officer, one person may do every step', () {
    test('the separation constraint is dropped', () {
      expect(code, contains('DROP CONSTRAINT IF EXISTS outcome_reviewer_is_not_verifier'));
    });

    test('verification is open to any Manager or Officer', () {
      final v = fn('verify_program_outcome');
      expect(v, contains('public.is_staff()'));
      expect(v.contains("role = 'officer'"), isFalse);
      expect(v.contains('different person'), isFalse);
      expect(v.contains('reviewed_by = v_uid'), isFalse);
    });

    test('review no longer blocks the person who verified', () {
      final r = fn('review_program_outcome');
      expect(r.contains('verified_by = v_uid'), isFalse);
      expect(r.contains('different person'), isFalse);
    });

    test('accountability is kept: who reviewed, who verified, who decided are all recorded', () {
      expect(fn('review_program_outcome'), contains('reviewed_by_name'));
      expect(fn('verify_program_outcome'), contains('verified_by_name'));
      expect(fn('verify_program_outcome'), contains('verified_by_role'));
      expect(fn('finalize_program_outcome'), contains('finalized_by_name'));
      expect(fn('finalize_program_outcome'), contains('finalized_by_role'));
    });

    test('a decision still needs the review AND the field verification first', () {
      final f = fn('finalize_program_outcome');
      expect(f, contains("review_decision IS DISTINCT FROM 'validated'"));
      expect(f, contains('verified_by IS NULL'));
      expect(f, contains('RETURN_QUANTITY'));
      expect(f, contains('RESOLUTION_INVALID'));
    });

    test('the staff screen shows every step to whoever has Manage access', () {
      final d = _read('lib/presentation/screens/admin/program_outcome_detail_screen.dart');
      expect(d.contains('_isOfficer'), isFalse);
      expect(d.contains('wouldBreakSeparation'), isFalse);
      expect(d, contains('_by(l10n, r.verifiedByName'));
      expect(d, contains('_by(l10n, r.finalizedByName'));
    });

    test('no string tells staff that only an Officer or a different person may act', () {
      for (final f in ['app_en.arb', 'app_tl.arb']) {
        final t = _read('lib/core/l10n/$f');
        for (final k in ['outcSeparationReview', 'outcSeparationVerify', 'outcOfficerOnly', 'errSeparation', 'errOfficerOnly']) {
          expect(t.contains('"$k"'), isFalse, reason: '$f has $k');
        }
      }
    });
  });

  group('Items with the same name in a pick list', () {
    test('a unique name stays plain', () {
      final names = itemPickerNames([_item('1', 'Tomato', source: 'Jhon Drhy M. Salangsang'), _item('2', 'Scythe')]);
      expect(names['1'], 'Tomato');
      expect(names['2'], 'Scythe');
    });

    test('two items with the same name are told apart by their source', () {
      final names = itemPickerNames([
        _item('1', 'Tomato', source: 'Jhon Drhy M. Salangsang'),
        _item('2', 'Tomato', source: 'Ellen Rosal'),
        _item('3', 'Scythe'),
      ]);
      expect(names['1'], 'Tomato (Jhon Drhy M. Sala…)');
      expect(names['2'], 'Tomato (Ellen Rosal)');
      expect(names['3'], 'Scythe');
    });

    test('the comparison ignores case and spaces; no source means no suffix to add', () {
      final names = itemPickerNames([_item('1', ' tomato ', source: 'A'), _item('2', 'Tomato')]);
      expect(names['1'], endsWith('(A)')); // recognised as the same name
      expect(names['2'], 'Tomato');
    });

    test('both pick lists use it', () {
      expect(_read('lib/presentation/screens/admin/program_products_screen.dart'), contains('itemPickerNames(items)'));
      expect(_read('lib/presentation/screens/admin/program_management_screen.dart'), allOf(contains('itemPickerNames('), contains('eligible,')));
    });
  });

  group('Saving a program: the real reason is shown, not a silent failure', () {
    test('a missing column or function is explained in plain words', () {
      for (final code in ['PGRST204', 'PGRST202', '42703', '42883']) {
        expect(
          friendlyError(en, PostgrestException(message: 'Could not find the column', code: code)),
          en.errNeedsDbUpdate,
          reason: code,
        );
      }
    });

    test('create and update no longer swallow errors', () {
      final repo = _read('lib/data/repositories/program_repository.dart');
      final update = repo.substring(repo.indexOf('Future<bool> updateProgram'), repo.indexOf('Future<List<CooperativeProgram>>', repo.indexOf('Future<bool> updateProgram')) < 0 ? repo.length : repo.indexOf('Future<List<CooperativeProgram>>', repo.indexOf('Future<bool> updateProgram')));
      expect(update, contains('rethrow;'));
      final form = _read('lib/presentation/screens/admin/program_management_screen.dart');
      expect('friendlyError(l10n, e, st, l10n.adminInvFailedTryAgain)'.allMatches(form).length, greaterThanOrEqualTo(2));
    });
  });
}

void sqlScriptsAreWellFormedTests() {
  group(r'SQL scripts: dollar-quoting is intact (a "DO $" once broke p11)', () {
    final dir = Directory('supabase_schema');
    final scripts = dir
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'supabase_schema_program_rework_(5a|p\d+|preflight).*\.sql$').hasMatch(f.path))
        .toList();

    test('there are scripts to check', () => expect(scripts.length, greaterThan(8)));

    for (final f in scripts) {
      final name = f.path.split(RegExp(r'[\/]')).last;
      test(name, () {
        final text = f.readAsStringSync().replaceAll('\r\n', '\n');
        final code = text.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
        // Every DO block is opened and closed with a full $$.
        expect(RegExp(r'(^|[^$])DO \$(?!\$)').hasMatch(code), isFalse, reason: r'a "DO $" with a single dollar');
        expect(RegExp(r'END \$;').hasMatch(code), isFalse, reason: r'an "END $;" with a single dollar');
        // Quote markers come in pairs.
        expect('\$\$'.allMatches(code).length % 2, 0, reason: r'unbalanced $$');
        expect('\$function\$'.allMatches(code).length % 2, 0, reason: r'unbalanced $function$');
        // BEGIN/COMMIT are paired when a script uses a transaction.
        if (RegExp(r'^BEGIN;', multiLine: true).hasMatch(code)) {
          expect(RegExp(r'^COMMIT;', multiLine: true).hasMatch(code), isTrue, reason: 'BEGIN without COMMIT');
        }
      });
    }
  });
}
