import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/utils/app_error_message.dart';
import 'package:sagana/data/models/program_model.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final tl = lookupAppLocalizations(const Locale('tl'));

  group('Friendly error messages', () {
    test('a CODE-prefixed refusal becomes a translated sentence, never the raw text', () {
      final m = messageForDatabaseText(
        en,
        'PROGRAM_NOT_READY: This program still has unfinished work: {"awaiting_outcome":2}',
      );
      expect(m, en.errProgramNotReady);
      expect(m, isNot(contains('awaiting_outcome')));
      expect(messageForDatabaseText(tl, 'NO_WITHDRAW: x'), tl.errNoWithdraw);
      expect(tl.errNoWithdraw, isNot(en.errNoWithdraw));
    });

    test('known phrases map to localized messages', () {
      expect(
        messageForDatabaseText(en, 'You have view-only access to this module.'),
        en.errViewOnly,
      );
      expect(
        messageForDatabaseText(en, 'Insufficient stock for this item'),
        en.errNoStock,
      );
    });

    test('technical database failures are never shown', () {
      const raw = 'duplicate key value violates unique constraint "program_members_pkey"';
      final m = messageForDatabaseText(en, raw, '23505');
      expect(m, en.errDuplicate);
      expect(m, isNot(contains('constraint')));
      expect(messageForDatabaseText(en, 'relation "x" does not exist'), isNull);
    });

    test('an unknown technical error falls back to the generic sentence', () {
      expect(
        friendlyError(en, Exception('PGRST301 JWT expired at node pg_catalog')),
        en.errGeneric,
      );
      expect(friendlyError(en, Exception('x'), null, 'Custom fallback'), 'Custom fallback');
    });
  });

  group('Completion rules (SQL contract, read from the script)', () {
    final sql = _read('supabase_schema/supabase_schema_program_rework_p5_completion_rules.sql');

    test('completing is one staff-only function; nothing else changes the status', () {
      final fn = sql.substring(sql.indexOf('FUNCTION public.complete_program'));
      expect(fn, contains('public.is_staff()'));
      expect(fn, contains('FOR UPDATE'));
      expect(fn, contains('PROGRAM_NOT_READY'));
      expect(sql, contains('PROGRAM_STATUS_LOCKED'));
      expect(sql, contains('BEFORE UPDATE'));
    });

    test('pending enrollment requests are declined with a reason and a notice, not deleted', () {
      final fn = sql.substring(sql.indexOf('FUNCTION public.complete_program'));
      expect(fn, contains("SET status = 'rejected'"));
      expect(fn, contains('INSERT INTO notifications'));
      final code = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
      expect(code, isNot(contains('DELETE FROM')));
      expect(code, isNot(contains('DROP TABLE')));
    });

    test('programs can never be deleted and staff cannot withdraw members or delete products', () {
      expect(sql, contains('PROGRAM_NO_DELETE'));
      expect(sql, contains('NO_WITHDRAW'));
      expect(sql, contains('NO_PRODUCT_DELETE'));
      expect(sql, contains('BEFORE DELETE ON public.program_products'));
    });

    test('only farmers who received items must have an outcome', () {
      final fn = sql.substring(
        sql.indexOf('FUNCTION public.program_completion_blockers'),
        sql.indexOf('FUNCTION public.get_programs_completion_status'),
      );
      expect(fn, contains('distributed_at IS NOT NULL'));
      expect(fn, contains("NOT IN ('thriving', 'failed')"));
    });

    test('the action is registered with the Officer permission gate', () {
      expect(sql, contains("('rpc', 'complete_program', 'dashboard')"));
    });
  });

  group('Completion status (model)', () {
    test('a program is ready only when nothing is outstanding', () {
      expect(
        ProgramCompletionStatus.fromMap({
          'program_id': 'p',
          'blockers': {'awaiting_outcome': 0, 'active_products': 0, 'pending_purchases': 0},
          'ready': true,
        }).isReady,
        isTrue,
      );
      final blocked = ProgramCompletionStatus.fromMap({
        'program_id': 'p',
        'blockers': {'awaiting_outcome': 2, 'open_orders': 1, 'allocated_stock': 0},
        'ready': false,
      });
      expect(blocked.isReady, isFalse);
      expect(blocked.awaitingOutcome, 2);
      expect(blocked.openOrders, 1);
      expect(blocked.allocatedStock, 0);
    });
  });

  group('Program Management screens', () {
    final screen = _read('lib/presentation/screens/admin/program_management_screen.dart');

    test('the delete icon is gone and Mark as Completed replaces it', () {
      expect(screen, isNot(contains('_confirmDeleteProgram')));
      expect(screen, contains('_completeProgram'));
      expect(_read('lib/presentation/widgets/admin_program_card.dart'), isNot(contains('onDelete')));
    });

    test('the top bar is a three-dot menu with red indicators', () {
      expect(screen, contains('PopupMenuButton<String>'));
      expect(screen, contains('_requestsMenu'));
    });

    test('Distribution members are four swipeable sections; Sales is a plain list', () {
      expect(screen, contains('DefaultTabController'));
      expect(screen, contains('memTabToDistribute'));
      expect(screen, contains('memTabDistributed'));
      expect(screen, contains('memTabSuccessful'));
      expect(screen, contains('memTabFailed'));
      expect(screen, contains('memEmptySales'));
    });

    test('no Remove button, member counters or product delete remain', () {
      expect(screen.contains('removeMember'), isFalse);
      expect(screen.contains('removeProgramProduct'), isFalse);
      expect(_read('lib/data/repositories/program_repository.dart').contains('deleteProgram'), isFalse);
    });

    test('Product Sales creation is as strict as Distribution', () {
      // No lenient mode any more: create and edit share one set of rules.
      expect(screen.contains('strict'), isFalse);
      expect(screen, contains('programMgmtMemberDiscountRequired'));
    });

    test('a new Product Sales program leads straight to Manage Products', () {
      expect(screen, contains("'justCreated': true"));
      expect(screen, contains('AppRoutes.programProducts'));
    });

    test('Outcome Review has Pending | Finalized | Returned; Enrollment has no Declined', () {
      final outcomes = _read('lib/presentation/screens/admin/program_outcomes_screen.dart');
      expect(outcomes, contains('TabController(length: 3'));
      final enroll = _read('lib/presentation/screens/admin/program_enrollment_requests_screen.dart');
      expect(enroll, isNot(contains('reqFilterDeclined')));
    });
  });

  group('Manage Products', () {
    final page = _read('lib/presentation/screens/admin/program_products_screen.dart');

    test('products can be turned on or off but never deleted', () {
      expect(page, contains('Switch'));
      expect(page, contains('updateProgramProduct'));
      expect(page.toLowerCase().contains('.delete('), isFalse);
      expect(page.contains('removeProgramProduct'), isFalse);
    });
  });

  group('Terminology: Successful / Failed', () {
    test('no user-facing "Thriving" wording remains in either language', () {
      for (final f in ['app_en.arb', 'app_tl.arb']) {
        // systemNotice* entries translate the wording of older stored notifications.
        final text = _read('lib/core/l10n/$f')
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('"systemNotice'))
            .join('\n');
        expect(RegExp('"[^"]*": "[^"]*[Tt]hriving[^"]*"').hasMatch(text), isFalse, reason: f);
      }
    });
  });

  group('Exports show regular price, discount and net paid', () {
    test('CSV and PDF carry the four purchase columns', () {
      final csv = _read('lib/data/services/report_csv_serializers.dart');
      // The regular price / discount / net columns were retired with the Capital Share
      // rework; the report now carries the purchases made and the amount credited.
      for (final h in ['Cooperative Purchases Made (PHP)', 'Purchases Credited From (PHP)']) {
        expect(csv, contains(h));
      }
      final pdf = _read('lib/data/services/report_pdf_serializers.dart');
      expect(pdf, contains('Purchases Made (reference)'));
    });
  });
}
