import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/listing_edit_request_model.dart';
import 'package:sagana/data/models/workflow_event_model.dart';
import 'package:sagana/presentation/widgets/workflow_timeline.dart';

import 'support/ignore_font_errors.dart';

String read(String path) => File(path).readAsStringSync();

String sqlCode(String path) =>
    read(path).split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

Widget localized(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: AppTheme.lightTheme,
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Map<String, dynamic> requestRow({String status = 'pending', Map<String, dynamic> extra = const {}}) => {
  'id': 'r1',
  'listing_id': 'l1',
  'farmer_id': 'f1',
  'status': status,
  'unit': 'sack',
  'original_quantity': 4.25,
  'original_price': 12.50,
  'original_description': 'First',
  'original_photo_url': 'https://x/old.jpg',
  'proposed_quantity': 6.0,
  'proposed_price': 12.50,
  'proposed_description': 'Second',
  'proposed_photo_url': null,
  'created_at': '2026-10-29T01:00:00Z',
  ...extra,
};

WorkflowEvent event(String action, {String? role, String? name, String? by, String? reason, Map<String, dynamic> details = const {}, int minute = 0}) =>
    WorkflowEvent(
      id: '$action$minute',
      action: action,
      actorId: name == null ? null : 'u-$name',
      actorRole: role,
      actorName: name,
      by: by,
      reason: reason,
      details: details,
      createdAt: DateTime(2026, 10, 29, 9, minute),
    );

void main() {
  group('ListingEditRequest', () {
    test('keeps decimals and the unit; compares in hundredths', () {
      final r = ListingEditRequest.fromMap(requestRow());
      expect(r.unit, 'sack');
      expect(r.originalQuantity, 4.25);
      expect(r.proposedQuantity, 6.0);
      expect(r.changesQuantity, isTrue);
      expect(r.changesPrice, isFalse);
      expect(r.changesDescription, isTrue);
      expect(r.changesPhoto, isFalse);
      expect(r.isPending, isTrue);
    });

    test('a photo URL means the photo is being changed', () {
      final r = ListingEditRequest.fromMap(requestRow(extra: {'proposed_photo_url': 'https://x/new.jpg'}));
      expect(r.changesPhoto, isTrue);
    });

    test('staff context compares against what is published now, not the original', () {
      final r = ListingEditRequest.fromMap(requestRow(), extra: {
        'current_quantity': 5.0,
        'current_remaining': 3.5,
        'current_price': 14.0,
        'farmer_name': 'Juan',
        'crop_name': 'Ginger',
      });
      expect(r.shownQuantity, 5.0);
      expect(r.shownPrice, 14.0);
      expect(r.orderedSoFar, 1.5);
      expect(r.farmerName, 'Juan');
    });

    test('a Farmer-side copy has no reviewer', () {
      final r = ListingEditRequest.fromMap(requestRow(status: 'rejected', extra: {'review_reason': 'Too high'}));
      expect(r.reviewedBy, isNull);
      expect(r.reviewReason, 'Too high');
      expect(r.isRejected, isTrue);
    });
  });

  group('Who did it: staff see names, a Farmer never does', () {
    final l = lookupAppLocalizations(const Locale('en'));

    test('staff view: role and name', () {
      final e = event('approved', role: 'admin', name: 'Maria Santos');
      expect(workflowActorLabel(l, e, staffView: true), 'Manager Maria Santos');
      final o = event('ready_for_pickup', role: 'officer', name: 'Pedro Reyes');
      expect(workflowActorLabel(l, o, staffView: true), 'Officer Pedro Reyes');
    });

    test('two staff members on one transaction stay separate', () {
      final a = workflowActorLabel(l, event('approved', role: 'admin', name: 'Maria Santos'), staffView: true);
      final b = workflowActorLabel(l, event('completed', role: 'officer', name: 'Pedro Reyes'), staffView: true);
      expect(a, isNot(b));
    });

    test('Farmer view: only You / SP3 Cooperative / System, even if a name were present', () {
      expect(workflowActorLabel(l, event('submitted', by: 'you'), staffView: false), 'You');
      expect(workflowActorLabel(l, event('approved', by: 'cooperative', role: 'admin', name: 'Maria Santos'), staffView: false),
          'SP3 Cooperative');
      expect(workflowActorLabel(l, event('sold_out', by: 'system'), staffView: false), 'System');
    });

    testWidgets('the timeline shows the staff name to staff and hides it from a Farmer', (tester) async {
      await runIgnoringFontErrors(() async {
        final events = [
          event('submitted', role: 'farmer', name: 'Juan Dela Cruz', by: 'you', minute: 1),
          event('approved', role: 'admin', name: 'Maria Santos', by: 'cooperative', minute: 2),
          event('edit_rejected', role: 'officer', name: 'Pedro Reyes', by: 'cooperative', reason: 'Price too high.', minute: 3),
        ];
        await tester.pumpWidget(localized(WorkflowTimeline(events: events, staffView: true)));
        expect(find.textContaining('Manager Maria Santos'), findsOneWidget);
        expect(find.textContaining('Officer Pedro Reyes'), findsOneWidget);
        expect(find.text('Price too high.'), findsOneWidget);

        await tester.pumpWidget(localized(WorkflowTimeline(events: events, staffView: false)));
        await tester.pump();
        expect(find.textContaining('Maria Santos'), findsNothing);
        expect(find.textContaining('Pedro Reyes'), findsNothing);
        expect(find.textContaining('SP3 Cooperative'), findsNWidgets(2));
        // The reason a request was disapproved is for the Farmer.
        expect(find.text('Price too high.'), findsOneWidget);
      });
    });

    testWidgets('what changed is shown with the unit', (tester) async {
      await runIgnoringFontErrors(() async {
        final e = event('edit_approved', role: 'admin', name: 'Maria Santos', details: {
          'unit': 'sack',
          'changes': {
            'quantity': {'from': 4.25, 'to': 6},
            'price': {'from': 12.5, 'to': 20},
            'description': {'from': 'a', 'to': 'b'},
            'photo': true,
          },
        });
        await tester.pumpWidget(localized(WorkflowTimeline(events: [e], staffView: true)));
        expect(find.text('Quantity: 4.25 sack → 6 sack'), findsOneWidget);
        expect(find.text('Price: ₱12.50/sack → ₱20.00/sack'), findsOneWidget);
        expect(find.text('Description updated'), findsOneWidget);
        expect(find.text('Photo replaced'), findsOneWidget);
      });
    });

    testWidgets('newest first, in Tagalog too', (tester) async {
      await runIgnoringFontErrors(() async {
        final events = [
          event('submitted', role: 'farmer', by: 'you', minute: 1),
          event('approved', role: 'admin', name: 'Maria Santos', by: 'cooperative', minute: 5),
        ];
        await tester.pumpWidget(localized(WorkflowTimeline(events: events, staffView: false), locale: const Locale('tl')));
        final approved = tester.getTopLeft(find.text('Naaprubahan')).dy;
        final submitted = tester.getTopLeft(find.text('Isinumite')).dy;
        expect(approved, lessThan(submitted));
      });
    });
  });

  group('listing_edit_approval.sql', () {
    final sql = sqlCode('supabase_schema/supabase_schema_listing_edit_approval.sql');

    String fn(String name) {
      final start = sql.indexOf('FUNCTION public.$name(');
      expect(start, greaterThanOrEqualTo(0), reason: name);
      final end = sql.indexOf(r'$$;', sql.indexOf(r'AS $$', start));
      return sql.substring(start, end);
    }

    test('a request never touches the published listing, the batch or any order', () {
      final body = fn('request_listing_edit');
      expect(body, isNot(contains('UPDATE marketplace_listings')));
      expect(body, isNot(contains('UPDATE inventory_batches')));
      expect(body, isNot(contains('_apply_batch_reservation')));
      expect(body, contains('INSERT INTO listing_edit_requests'));
    });

    test('a request needs an approved listing with quantity left, and only one is open per listing', () {
      final body = fn('request_listing_edit');
      expect(body, contains("l.status <> 'approved'"));
      expect(body, contains('l.remaining_kg <= 0'));
      expect(body, contains('already have an edit request'));
      expect(sql, contains('CREATE UNIQUE INDEX IF NOT EXISTS uq_listing_edit_requests_one_pending'));
      expect(sql, contains("WHERE status = 'pending'"));
    });

    test('a request keeps the quantity above what is ordered and validates decimals and the photo owner', () {
      final body = fn('request_listing_edit');
      expect(body, contains('p_quantity <= v_ordered'));
      expect(body, contains('round(p_quantity, 2)'));
      expect(body, contains('round(p_price_per_kg, 2)'));
      expect(body, contains("'/listing_photos/' || v_uid::text"));
    });

    test('approval is staff only, re-checks the listing as it is now, and applies the change', () {
      final body = fn('approve_listing_edit');
      expect(body, contains('NOT public.is_staff()'));
      expect(body, contains('FROM marketplace_listings WHERE id = r.listing_id FOR UPDATE'));
      expect(body, contains('v_ordered := l.volume_kg - l.remaining_kg'));
      expect(body, contains('r.proposed_quantity <= v_ordered'));
      expect(body, contains('remaining_kg = l.remaining_kg + v_delta'));
      expect(body, contains('_release_batch_reservation'));
      expect(body, contains("status = 'approved', reviewed_by = v_uid"));
    });

    test('approval never changes the crop, unit, batch or status, and leaves orders alone', () {
      final body = fn('approve_listing_edit');
      final update = body.substring(body.indexOf('UPDATE marketplace_listings'), body.indexOf('WHERE id = l.id;'));
      for (final column in ['crop_name', 'crop_id', 'unit', 'inventory_batch_id', 'status', 'farmer_id']) {
        expect(update, isNot(contains('$column ')), reason: column);
      }
      expect(body, isNot(contains('UPDATE orders')));
    });

    test('disapproval needs a reason, rejects only the request, and tells the Farmer the reason', () {
      final body = fn('reject_listing_edit');
      expect(body, contains("v_reason = ''"));
      expect(body, contains("SET status = 'rejected'"));
      expect(body, isNot(contains('UPDATE marketplace_listings')));
      expect(body, isNot(contains('UPDATE inventory_batches')));
      expect(body, contains('Reason: '));
      expect(body, contains('NOT public.is_staff()'));
    });

    test('a pending listing is still edited directly; an approved one is refused', () {
      final body = fn('update_my_listing');
      expect(body, contains("l.status = 'approved'"));
      expect(body, contains('edit request for approval'));
      expect(body, contains("l.status <> 'pending_review'"));
    });

    test('the Farmer cannot read the request or history tables, only the safe functions', () {
      expect(sql, contains('CREATE POLICY "listing_edit_requests: staff reads"'));
      expect(sql, contains('CREATE POLICY "workflow_events: staff reads"'));
      expect(sql, isNot(contains('farmer reads')));
      expect(sql, isNot(contains('FOR INSERT')));
      final reqs = fn('get_my_listing_edit_requests');
      expect(reqs, isNot(contains('reviewed_by')));
      final hist = fn('get_my_listing_history');
      expect(hist, isNot(contains('e.actor_id,')));
      expect(hist, contains("'cooperative'"));
      expect(hist, contains("'you'"));
    });

    test('history is written only by triggers and the functions above', () {
      for (final trigger in [
        'trg_zz_wf_listing', 'trg_zz_wf_order', 'trg_zz_wf_market_linking',
        'trg_zz_wf_market_linking_sale', 'trg_zz_wf_enrollment',
      ]) {
        expect(sql, contains('CREATE TRIGGER $trigger'), reason: trigger);
      }
      expect(sql, contains('REVOKE ALL ON FUNCTION public._wf_log'));
      expect(sql, contains('auth.uid()'));
    });

    test('every status change records the actor, the role and the from/to status', () {
      expect(sql, contains('actor_id'));
      expect(sql, contains('actor_role'));
      expect(sql, contains('from_status'));
      expect(sql, contains('to_status'));
      expect(sql, contains("'disapproved'"));
      expect(sql, contains('CASE WHEN NEW.status = \'rejected\' THEN NEW.admin_notes END'));
    });

    test('a listing that stops being published closes its open request', () {
      expect(sql, contains('trg_listing_close_edit_requests'));
      expect(sql, contains("OLD.status = 'approved' AND NEW.status <> 'approved'"));
    });

    test('it needs the earlier scripts', () {
      expect(sql, contains('Run supabase_schema_farmer_listing_edit.sql first'));
      expect(sql, contains('Run supabase_schema_ginger_any_unit.sql first'));
    });
  });

  group('Screens', () {
    test('Pending Approvals separates New Listings from Edit Requests and shows old -> new', () {
      final src = read('lib/presentation/screens/admin/pending_approvals_screen.dart');
      expect(src, contains('l10n.lePendingTabNew'));
      expect(src, contains('l10n.lePendingTabEdits'));
      expect(src, contains('fetchEditRequests()'));
      expect(src, contains('class _EditRequestCard'));
      expect(src, contains('l10n.wfDetailQuantity('));
      expect(src, contains("'listing_edit_requests'"));
    });

    test('the review screen compares published vs requested, and disapproval requires a reason', () {
      final src = read('lib/presentation/screens/admin/listing_edit_request_screen.dart');
      expect(src, contains('class EditRequestComparison'));
      expect(src, contains('l.leCurrent'));
      expect(src, contains('approveEditRequest('));
      expect(src, contains('rejectEditRequest('));
      expect(src, contains('l.leReasonRequired'));
      expect(src, contains('AppToast.show(ctx, l.leReasonRequired'));
    });

    test('the Farmer sees the pending banner, can cancel it, and opens the history', () {
      final src = read('lib/presentation/screens/farmer/farmer_listing_detail_screen.dart');
      expect(src, contains('_pendingRequestCard('));
      expect(src, contains('cancelEditRequest('));
      expect(src, contains('_rejectedRequestCard('));
      expect(src, contains('AppRoutes.farmerListingHistory'));
      final edit = read('lib/presentation/screens/farmer/edit_listing_screen.dart');
      expect(edit, contains('bool get _requestMode => _listing.isLive'));
      expect(edit, contains('_listingRepo.requestEdit('));
    });

    test('the Farmer history screen never uses the staff repository', () {
      final src = read('lib/presentation/screens/shared/listing_history_screen.dart');
      expect(src, contains('widget.staffView'));
      expect(src, contains('fetchMyHistory'));
      final farmerRoute = read('lib/presentation/navigation/app_router.dart');
      final start = farmerRoute.indexOf('path: AppRoutes.farmerListingHistory');
      expect(farmerRoute.substring(start, start + 800), contains('staffView: false'));
    });

    test('Marketplace Order Management, Market Linking and offers show who acted', () {
      expect(read('lib/presentation/screens/admin/admin_order_detail_screen.dart'), contains("entityType: 'order'"));
      expect(read('lib/presentation/screens/admin/market_linking_screen.dart'), contains("entityType: 'market_linking'"));
      expect(read('lib/presentation/screens/admin/listing_review_screen.dart'), contains('AppRoutes.adminListingHistory'));
      final offer = read('lib/presentation/screens/shared/coop_offer_negotiation_screen.dart');
      expect(offer, contains('staffNames: _forFarmer ? null : _staffNames'));
      expect(offer, contains('_forFarmer\n        ? const <String, String>{}'));
    });

    test('no Farmer or Buyer screen reads the staff history', () {
      for (final dir in ['lib/presentation/screens/farmer', 'lib/presentation/screens/buyer']) {
        for (final f in Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
          final src = f.readAsStringSync();
          expect(src, isNot(contains('WorkflowEventRepository')), reason: f.path);
          expect(src, isNot(contains("from('workflow_events')")), reason: f.path);
        }
      }
    });

    test('the pending count includes edit requests', () {
      expect(read('lib/data/repositories/admin_listing_repository.dart'), contains('countPendingEditRequests()'));
      expect(read('lib/data/repositories/admin_dashboard_repository.dart'), contains("from('listing_edit_requests')"));
    });
  });

  group('Strings', () {
    test('English and Tagalog both have every new key', () {
      final en = read('lib/core/l10n/app_en.arb');
      final tl = read('lib/core/l10n/app_tl.arb');
      for (final k in [
        'leRequestTitle', 'leSubmitRequest', 'leRequestSent', 'leCancelRequest', 'lePendingBannerTitle',
        'leRejectedBannerTitle', 'leViewHistory', 'lePendingTabNew', 'lePendingTabEdits', 'leEditRequestTitle',
        'leApproveAction', 'leDisapproveAction', 'leDisapproveHint', 'leReasonRequired', 'wfActivityTitle',
        'wfRoleAdmin', 'wfRoleOfficer', 'wfByCooperative', 'wfActEditApproved', 'wfActEditRejected',
        'wfActSaleRecorded', 'wfActReadyForPickup', 'wfDetailQuantity', 'wfHistoryAction',
      ]) {
        expect(en, contains('"$k"'), reason: 'en $k');
        expect(tl, contains('"$k"'), reason: 'tl $k');
      }
    });
  });
}
