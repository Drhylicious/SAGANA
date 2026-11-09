import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/workflow_event_model.dart';
import 'package:sagana/presentation/widgets/edit_request_widgets.dart';
import 'package:sagana/presentation/widgets/listing_history_widgets.dart';

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

WorkflowEvent event(
  String action, {
  String? role,
  String? name,
  String? by,
  String? reason,
  Map<String, dynamic> details = const {},
  DateTime? at,
}) => WorkflowEvent(
  id: '$action-${at?.millisecondsSinceEpoch ?? 0}',
  action: action,
  actorId: name == null ? null : 'u-$name',
  actorRole: role,
  actorName: name,
  by: by,
  reason: reason,
  details: details,
  createdAt: at ?? DateTime.now(),
);

void main() {
  group('Terminology: the Farmer edits a listing, they do not "request changes"', () {
    final en = read('lib/core/l10n/app_en.arb');
    final detail = read('lib/presentation/screens/farmer/farmer_listing_detail_screen.dart');

    test('the action on a published listing is "Edit Listing"', () {
      final l = lookupAppLocalizations(const Locale('en'));
      expect(l.leRequestTitle, 'Edit Listing');
      expect(l.editListingAction, 'Edit Listing');
      expect(l.leSubmitRequest, 'Submit for Approval');
      expect(l.leCancelRequest, 'Cancel Edit');
      expect(detail, contains('.leRequestTitle'));
    });

    test('no Farmer-facing string says "Request a Change" / "Request Changes"', () {
      for (final key in [
        'leRequestTitle', 'leSubmitRequest', 'leRequestSent', 'leCancelRequest', 'leCancelRequestTitle',
        'leCancelRequestBody', 'leRequestCancelled', 'leRequestFailed', 'lePendingBannerTitle',
        'lePendingBannerBody', 'leRejectedBannerTitle', 'leRejectedBannerBody', 'editListingApprovedNote',
      ]) {
        final line = RegExp('"$key": "([^"]*)"').firstMatch(en)!.group(1)!.toLowerCase();
        expect(line.contains('request a change'), isFalse, reason: key);
        expect(line.contains('request changes'), isFalse, reason: key);
      }
    });

    test('Tagalog has the same keys', () {
      final tl = read('lib/core/l10n/app_tl.arb');
      for (final k in ['leRequestTitle', 'leSubmitRequest', 'leRejectedBannerBody', 'leStatusPendingEdit', 'lePendingTabAll', 'leFieldPhotoLocked']) {
        expect(tl, contains('"$k"'), reason: k);
      }
    });
  });

  group('Editable fields: quantity, asking price and description only', () {
    final edit = read('lib/presentation/screens/farmer/edit_listing_screen.dart');
    final repo = read('lib/data/repositories/listing_repository.dart');

    test('the Edit screen has no photo capture or upload', () {
      for (final banned in ['captureCropPhoto', 'uploadListingPhoto', 'setCropPhotoOnline', 'refreshPhoto', '_newPhoto', 'CropRepository']) {
        expect(edit, isNot(contains(banned)), reason: banned);
      }
      expect(edit, contains('l.leFieldPhotoLocked'));
    });

    test('neither edit call can send a photo (creating a listing is a different call)', () {
      final start = repo.indexOf('Future<void> updateListing(');
      final end = repo.indexOf('Future<void> cancelEditRequest(');
      final edits = repo.substring(start, end);
      expect(edits, contains("'update_my_listing'"));
      expect(edits, contains("'request_listing_edit'"));
      expect(edits, isNot(contains('p_photo_url')));
      expect(edits, isNot(contains('p_refresh_photo')));
    });

    test('the crop and the unit are shown locked', () {
      expect(edit, contains('_locked(_listing.displayName)'));
      expect(edit, contains('unitOrDefault(_listing.unit)'));
    });

    test('SQL: both edit functions refuse a photo and keep their signatures', () {
      final sql = sqlCode('supabase_schema/supabase_schema_listing_edit_fields.sql');
      expect(sql, contains('FUNCTION public.update_my_listing('));
      expect(sql, contains('FUNCTION public.request_listing_edit('));
      expect('cannot be changed in an edit'.allMatches(sql).length, 2);
      expect(sql, contains('IF p_refresh_photo THEN'));
      expect(sql, contains('IF v_photo IS NOT NULL THEN'));
      expect(sql, isNot(contains('UPDATE marketplace_listings SET photo_url')));
      expect(sql, contains('Run supabase_schema_listing_edit_approval.sql first'));
    });

    test('SQL: an approval still changes only quantity, price and description', () {
      final sql = sqlCode('supabase_schema/supabase_schema_listing_edit_approval.sql');
      final start = sql.indexOf('FUNCTION public.approve_listing_edit(');
      final body = sql.substring(start, sql.indexOf(r'$$;', sql.indexOf(r'AS $$', start)));
      final update = body.substring(body.indexOf('UPDATE marketplace_listings'), body.indexOf('WHERE id = l.id;'));
      expect(update, contains('volume_kg'));
      expect(update, contains('price_per_kg'));
      expect(update, contains('description'));
      for (final column in ['crop_name', 'crop_id', 'unit ', 'inventory_batch_id', 'status', 'farmer_id']) {
        expect(update, isNot(contains(column)), reason: column);
      }
    });
  });

  group('Edited listings are clearly distinguishable in Pending Approvals', () {
    final src = read('lib/presentation/screens/admin/pending_approvals_screen.dart');

    test('All, New Listings and Edited Listings tabs, with an edit labelled on its card', () {
      expect(src, contains('l10n.lePendingTabAll'));
      expect(src, contains('l10n.lePendingTabNew'));
      expect(src, contains('l10n.lePendingTabEdits'));
      expect(src, contains('_allSection('));
      expect(src, contains('class _EditRequestCard'));
      expect(src, contains('l10n.leEditRequestBadge'));
    });

    test('a pending edit has a short status, and its own colour and Edited Listing badge, so it never reads as a new listing', () {
      final l = lookupAppLocalizations(const Locale('en'));
      // Short on purpose (not "Edit Pending Approval"): the Edited Listing badge says what it is.
      expect(editRequestStatusLabel(l, 'pending'), 'Pending');
      expect(l.leEditRequestBadge, 'Edited Listing');
      expect(editRequestStatusColor('pending'), isNot(editRequestStatusColor('approved')));
      expect(editRequestStatusColor('pending'), isNot(const Color(0xFFFFB300)),
          reason: 'amber is the new-listing pending colour');
      expect(editRequestStatusLabel(l, 'rejected'), l.listingStateDisapproved);
    });

    test('the All tab puts everything waiting first and filters both kinds with one set of chips', () {
      expect(src, contains('_decisionOfListing('));
      expect(src, contains('_decisionOfEdit('));
      expect(src, contains('if (a.pending != b.pending) return a.pending ? -1 : 1;'));
    });
  });

  group('Listing history: filters and open edit', () {
    test('Decisions keeps approvals and disapprovals of the listing and of its edits', () {
      for (final a in ['approved', 'disapproved', 'withdrawn', 'edit_approved', 'edit_rejected']) {
        expect(listingHistoryMatches(ListingHistoryFilter.decisions, event(a)), isTrue, reason: a);
      }
      for (final a in ['submitted', 'edit_requested', 'edited', 'sold_out']) {
        expect(listingHistoryMatches(ListingHistoryFilter.decisions, event(a)), isFalse, reason: a);
      }
    });

    test('Edits keeps every step of an edit', () {
      for (final a in ['edited', 'edit_requested', 'edit_approved', 'edit_rejected', 'edit_cancelled']) {
        expect(listingHistoryMatches(ListingHistoryFilter.edits, event(a)), isTrue, reason: a);
      }
      expect(listingHistoryMatches(ListingHistoryFilter.edits, event('approved')), isFalse);
      expect(listingHistoryMatches(ListingHistoryFilter.all, event('anything')), isTrue);
    });

    test('an edit is "open" until it is approved, disapproved or cancelled', () {
      final t0 = DateTime(2026, 10, 29, 9);
      WorkflowEvent at(String a, int m) => event(a, at: t0.add(Duration(minutes: m)));
      expect(listingHistoryHasOpenEdit([at('submitted', 0), at('approved', 1)]), isFalse);
      expect(listingHistoryHasOpenEdit([at('approved', 1), at('edit_requested', 2)]), isTrue);
      expect(listingHistoryHasOpenEdit([at('edit_requested', 2), at('edit_rejected', 3)]), isFalse);
      expect(listingHistoryHasOpenEdit([at('edit_requested', 2), at('edit_cancelled', 3)]), isFalse);
      expect(listingHistoryHasOpenEdit([at('edit_requested', 2), at('edit_approved', 3), at('edit_requested', 4)]), isTrue);
    });

    test('every listing action has its own plain-language title and explanation', () {
      final l = lookupAppLocalizations(const Locale('en'));
      final titles = <String>{};
      for (final a in [
        'submitted', 'approved', 'disapproved', 'withdrawn', 'edited', 'edit_requested',
        'edit_approved', 'edit_rejected', 'edit_cancelled', 'sold_out', 'reopened',
      ]) {
        final t = listingHistoryText(l, a);
        expect(t.title, isNotEmpty, reason: a);
        expect(t.description, isNotEmpty, reason: a);
        titles.add(t.title);
      }
      expect(titles.length, 11, reason: 'no two actions share a title');
    });
  });

  group('Listing history: the screen', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 14, 30);
    final yesterday = today.subtract(const Duration(days: 1));
    final earlier = DateTime(2026, 9, 28, 20, 13);

    testWidgets('events are grouped by day: Today, Yesterday, then the date', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(localized(ListingHistoryTimeline(
          staffView: false,
          events: [
            event('submitted', by: 'you', at: earlier, details: {'quantity': 15, 'price': 20, 'unit': 'kg'}),
            event('approved', by: 'cooperative', at: yesterday),
            event('edit_requested', by: 'you', at: today),
          ],
        )));
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Yesterday'), findsOneWidget);
        expect(find.text('September 28, 2026'), findsOneWidget);
        // Newest first.
        expect(tester.getTopLeft(find.text('Edit submitted')).dy,
            lessThan(tester.getTopLeft(find.text('Listing approved')).dy));
        expect(tester.getTopLeft(find.text('Listing approved')).dy,
            lessThan(tester.getTopLeft(find.text('Listing submitted')).dy));
      });
    });

    testWidgets('each event says what happened in plain words', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(localized(ListingHistoryTimeline(
          staffView: false,
          events: [event('edit_approved', by: 'cooperative', at: today)],
        )));
        expect(find.text('Edit approved'), findsOneWidget);
        expect(find.text('The changes are now live on the Marketplace.'), findsOneWidget);
        expect(find.text('SP3 Cooperative'), findsOneWidget);
      });
    });

    testWidgets('an edit shows before -> after, with the unit and decimals', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(localized(ListingHistoryTimeline(
          staffView: false,
          events: [
            event('edit_approved', by: 'cooperative', at: today, details: {
              'unit': 'sack',
              'changes': {
                'quantity': {'from': 4.25, 'to': 6},
                'price': {'from': 12.5, 'to': 20.75},
                'description': {'from': 'Old text', 'to': 'New text'},
              },
            }),
          ],
        )));
        expect(find.text('4.25 sack'), findsOneWidget);
        expect(find.text('6 sack'), findsOneWidget);
        expect(find.text('₱12.50/sack'), findsOneWidget);
        expect(find.text('₱20.75/sack'), findsOneWidget);
        expect(find.text('Old text'), findsOneWidget);
        expect(find.text('New text'), findsOneWidget);
      });
    });

    testWidgets('a disapproval shows its reason in a highlighted callout', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(localized(ListingHistoryTimeline(
          staffView: false,
          events: [event('edit_rejected', by: 'cooperative', at: today, reason: 'The price is far above the market price.')],
        )));
        expect(find.text('Edit disapproved'), findsOneWidget);
        expect(find.text('The published listing was not changed.'), findsOneWidget);
        expect(find.text('REASON'), findsNothing);
        expect(find.text('Reason'), findsOneWidget);
        expect(find.text('The price is far above the market price.'), findsOneWidget);
      });
    });

    testWidgets('staff see who acted; a Farmer never does', (tester) async {
      await runIgnoringFontErrors(() async {
        final events = [
          event('approved', role: 'admin', name: 'Maria Santos', by: 'cooperative', at: today),
        ];
        await tester.pumpWidget(localized(ListingHistoryTimeline(staffView: true, events: events)));
        expect(find.text('Manager Maria Santos'), findsOneWidget);
        await tester.pumpWidget(localized(ListingHistoryTimeline(staffView: false, events: events)));
        await tester.pump();
        expect(find.textContaining('Maria Santos'), findsNothing);
        expect(find.text('SP3 Cooperative'), findsOneWidget);
      });
    });

    testWidgets('the filter chips show counts and narrow the list', (tester) async {
      await runIgnoringFontErrors(() async {
        final events = [
          event('submitted', by: 'you', at: earlier),
          event('approved', by: 'cooperative', at: yesterday),
          event('edit_requested', by: 'you', at: today),
        ];
        var selected = ListingHistoryFilter.all;
        await tester.pumpWidget(localized(StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              ListingHistoryFilterBar(
                selected: selected,
                events: events,
                onSelected: (f) => setState(() => selected = f),
              ),
              ListingHistoryTimeline(
                staffView: false,
                events: events.where((e) => listingHistoryMatches(selected, e)).toList(),
              ),
            ],
          ),
        )));
        expect(find.text('All · 3'), findsOneWidget);
        expect(find.text('Decisions · 1'), findsOneWidget);
        expect(find.text('Edits · 1'), findsOneWidget);
        await tester.tap(find.text('Edits · 1'));
        await tester.pump();
        expect(find.text('Edit submitted'), findsOneWidget);
        expect(find.text('Listing submitted'), findsNothing);
      });
    });

    testWidgets('a filter with no matches says so', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(localized(const ListingHistoryTimeline(staffView: false, events: [])));
        expect(find.text('Nothing here matches this filter.'), findsOneWidget);
      });
    });

    testWidgets('the same screen reads in Tagalog', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(localized(
          ListingHistoryTimeline(staffView: false, events: [event('edit_approved', by: 'cooperative', at: today)]),
          locale: const Locale('tl'),
        ));
        expect(find.text('Naaprubahan ang pag-edit'), findsOneWidget);
        expect(find.text('Ngayon'), findsOneWidget);
      });
    });

    test('the screen wires the header, the filter and the staff / Farmer split', () {
      final src = read('lib/presentation/screens/shared/listing_history_screen.dart');
      expect(src, contains('ListingHistoryHeaderCard('));
      expect(src, contains('ListingHistoryFilterBar('));
      expect(src, contains('listingHistoryHasOpenEdit(_events)'));
      expect(src, contains('WorkflowEventRepository().fetch'));
      expect(src, contains('ListingRepository().fetchMyHistory'));
    });
  });
}
