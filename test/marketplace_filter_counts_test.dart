import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/data/repositories/market_linking_repository.dart';
import 'package:sagana/data/services/market_types_service.dart';
import 'package:sagana/presentation/screens/admin/da_amad_enrollment_screen.dart';
import 'package:sagana/presentation/widgets/listing_filter_modal.dart';

import 'support/ignore_font_errors.dart';

String src(String path) => File(path).readAsStringSync();

Widget host(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

DaAmadEnrollmentModel enrollment(
  String id,
  String farmer,
  DaAmadEnrollmentStatus status, {
  required DateTime submitted,
  DateTime? reviewed,
  String? notes,
  String? reviewer,
  int requests = 0,
  bool enrolledWithoutReview = false,
}) => DaAmadEnrollmentModel(
  id: id,
  farmerId: farmer,
  farmerName: 'Farmer $farmer',
  status: status,
  adminNotes: notes,
  submittedAt: submitted,
  reviewedAt: reviewed,
  reviewerName: reviewer,
  requestCount: requests,
  enrolledWithoutReview: enrolledWithoutReview,
);

void main() {
  group('filter chip with a count', () {
    testWidgets('prints "Label (n)", including (0), and marks the selected one', (tester) async {
      await runIgnoringFontErrors(() async {
        String? tapped;
        await tester.pumpWidget(
          host(
            MarketplaceFilterBar<String?>(
              selected: 'pending',
              onSelected: (v) => tapped = v,
              options: const [
                MarketplaceFilterOption<String?>(value: null, label: 'All', count: 5, color: Colors.green),
                MarketplaceFilterOption<String?>(value: 'pending', label: 'Pending', count: 3, color: Colors.amber),
                MarketplaceFilterOption<String?>(value: 'done', label: 'Completed', count: 0, color: Colors.green),
              ],
            ),
          ),
        );
        await tester.pump();
        expect(find.text('All (5)'), findsOneWidget);
        expect(find.text('Pending (3)'), findsOneWidget);
        expect(find.text('Completed (0)'), findsOneWidget);

        await tester.tap(find.text('Completed (0)'));
        expect(tapped, 'done');
        await tester.tap(find.text('All (5)'));
        expect(tapped, isNull, reason: 'the "All" option has the value null');
      });
    });

    testWidgets('a chip without a count prints just its label (other screens keep working)', (tester) async {
      await runIgnoringFontErrors(() async {
        final cs = ColorScheme.fromSeed(seedColor: Colors.green);
        await tester.pumpWidget(
          host(ListingStatusFilterChip(label: 'All', active: true, color: Colors.green, onTap: () {}, cs: cs)),
        );
        await tester.pump();
        expect(find.text('All'), findsOneWidget);
      });
    });

    testWidgets('the market row shows All Markets plus each market with its count', (tester) async {
      await runIgnoringFontErrors(() async {
        MarketTypes.instance.debugSet(
          types: const [
            MarketType(code: 'cooperative_market', name: 'Cooperative Market', buyerVisible: false, managerSetsPrice: true, sortOrder: 1, isActive: true),
            MarketType(code: 'public_market', name: 'Public Market', buyerVisible: true, managerSetsPrice: false, sortOrder: 2, isActive: true),
          ],
        );
        addTearDown(() => MarketTypes.instance.debugSet());
        await tester.pumpWidget(
          host(
            ListingMarketFilterRow(
              value: null,
              onChanged: (_) {},
              total: 7,
              counts: const {'cooperative_market': 4, 'public_market': 3},
            ),
          ),
        );
        await tester.pump();
        expect(find.text('All Markets (7)'), findsOneWidget);
        expect(find.text('Cooperative Market (4)'), findsOneWidget);
        expect(find.text('Public Market (3)'), findsOneWidget);
      });
    });
  });

  group('every Marketplace screen counts its chips from the loaded records', () {
    String s(String f) => src('lib/presentation/screens/admin/$f');

    test('All Listings: market counts', () {
      final t = s('all_listings_screen.dart');
      expect(t.contains('_marketCounts'), isTrue);
      expect(t.contains('total: _allListings.length'), isTrue);
    });

    test('Listing Approvals: All / Pending / Approved / Disapproved with counts', () {
      final t = s('pending_approvals_screen.dart');
      expect(t.contains('MarketplaceFilterBar<ListingApproval?>'), isTrue);
      expect(t.contains('count: _allListings.length'), isTrue);
      expect(t.contains('_approvalCounts'), isTrue);
    });

    test('Order Management: All / Pending Orders / Approved / Completed / Cancelled with counts', () {
      final t = s('order_management_screen.dart');
      expect(t.contains('MarketplaceFilterBar<String?>'), isTrue);
      expect(t.contains('count: _allOrders.length'), isTrue);
      expect(t.contains('_statusCounts'), isTrue);
      expect(t.contains('orderMgmtChipPending'), isTrue);
    });

    test('Market Linking: uses the shared bar, no private chip row, counts not narrowed by the search', () {
      final t = s('market_linking_screen.dart');
      expect(t.contains('MarketplaceFilterBar<_MlFilter>'), isTrue);
      expect(t.contains('class _FilterChips'), isFalse);
      expect(t.contains('matchesSearch(_query)).where((e) => _matches(e, f))'), isFalse);
    });

    test('Offer to Cooperative: every chip, including All, has a count', () {
      final t = s('offer_to_cooperative_screen.dart');
      expect(t.contains('MarketplaceFilterBar<CoopOfferFilter>'), isTrue);
      expect(t.contains('count: _countFor(f)'), isTrue);
      expect(t.contains("'\${f.label(l10n, forFarmer: false)} (\${_countFor(f)})'"), isFalse);
    });

    test('Enrollments: two swipeable sections Pending / Enrolled with counts, no search, no hard-coded English', () {
      final t = s('da_amad_enrollment_screen.dart');
      expect(t.contains('TabBarView('), isTrue, reason: 'swipe between the sections');
      expect(t.contains('TabBar('), isTrue, reason: 'tappable section headers');
      expect(t.contains('TabController(length: 2'), isTrue);
      expect(t.contains(r'(${_pending.length})'), isTrue);
      expect(t.contains(r'(${_enrolled.length})'), isTrue);
      expect(t.contains('TextField'), isFalse, reason: 'the search bar is gone');
      expect(t.contains('_searchCtrl'), isFalse);
      expect(t.contains('MarketplaceFilterBar'), isFalse);
      expect(t.contains("'Reviewed'"), isFalse);
      expect(t.contains('Reviewed ('), isFalse);
      expect(t.contains('ScaffoldMessenger'), isFalse, reason: 'messages from a dialog use AppToast');
    });

    test('the screens whose counts must move on their own listen for changes', () {
      for (final e in {
        'all_listings_screen.dart': 'marketplace_listings',
        'pending_approvals_screen.dart': 'marketplace_listings',
        'order_management_screen.dart': "'orders'",
        'market_linking_screen.dart': 'market_linking_programs',
        'da_amad_enrollment_screen.dart': 'da_amad_enrollments',
        'offer_to_cooperative_screen.dart': 'cooperative_purchase_offers',
      }.entries) {
        final t = s(e.key);
        expect(t.contains('TableChangeWatcher('), isTrue, reason: e.key);
        expect(t.contains(e.value), isTrue, reason: e.key);
        expect(t.contains('_watcher?.dispose()') || t.contains('Watcher?.dispose()'), isTrue, reason: e.key);
      }
    });
  });

  group('enrollment queue', () {
    final t0 = DateTime.utc(2026, 10, 1);

    test('Pending holds only undecided applications, oldest first', () {
      final lists = splitEnrollments([
        enrollment('p2', 'B', DaAmadEnrollmentStatus.pending, submitted: t0.add(const Duration(days: 2))),
        enrollment('p1', 'A', DaAmadEnrollmentStatus.pending, submitted: t0),
        enrollment('a1', 'C', DaAmadEnrollmentStatus.approved, submitted: t0, reviewed: t0.add(const Duration(days: 1))),
      ]);
      expect(lists.pending.map((e) => e.id), ['p1', 'p2']);
      expect(lists.reviewed.map((e) => e.id), ['a1']);
    });

    test('Enrolled holds only approved farmers (including already-enrolled), never declined or pending', () {
      final lists = splitEnrollments(
        [
          enrollment('a1', 'A', DaAmadEnrollmentStatus.approved, submitted: t0, reviewed: t0.add(const Duration(days: 1))),
          enrollment('r1', 'B', DaAmadEnrollmentStatus.rejected, submitted: t0, reviewed: t0.add(const Duration(days: 2))),
          enrollment('p1', 'C', DaAmadEnrollmentStatus.pending, submitted: t0),
        ],
        enrolledOnly: [
          enrollment('enrolled-D', 'D', DaAmadEnrollmentStatus.approved, submitted: t0, requests: 1, enrolledWithoutReview: true),
        ],
      );
      expect(lists.enrolled.map((e) => e.id).toSet(), {'a1', 'enrolled-D'});
      expect(lists.pending.map((e) => e.id), ['p1']);
    });

    test('a declined farmer who applied again is only in Pending until approved', () {
      final lists = splitEnrollments([
        enrollment('old', 'A', DaAmadEnrollmentStatus.rejected, submitted: t0, reviewed: t0.add(const Duration(days: 1))),
        enrollment('new', 'A', DaAmadEnrollmentStatus.pending, submitted: t0.add(const Duration(days: 3))),
      ]);
      expect(lists.pending.map((e) => e.id), ['new']);
      expect(lists.enrolled, isEmpty);
    });

    test('Reviewed holds approved, declined and already-enrolled farmers, most recent first', () {
      final lists = splitEnrollments(
        [
          enrollment('a1', 'A', DaAmadEnrollmentStatus.approved, submitted: t0, reviewed: t0.add(const Duration(days: 1))),
          enrollment('r1', 'B', DaAmadEnrollmentStatus.rejected, submitted: t0, reviewed: t0.add(const Duration(days: 5)), notes: 'No Ginger yet'),
        ],
        enrolledOnly: [
          enrollment('enrolled-C', 'C', DaAmadEnrollmentStatus.approved,
              submitted: t0.subtract(const Duration(days: 30)), requests: 2, enrolledWithoutReview: true),
        ],
      );
      expect(lists.reviewed.map((e) => e.id), ['r1', 'a1', 'enrolled-C']);
      expect(lists.reviewed.last.enrolledWithoutReview, isTrue);
      expect(lists.pending, isEmpty);
    });

    test('a declined farmer who applied again keeps the old row as history', () {
      final lists = splitEnrollments([
        enrollment('old', 'A', DaAmadEnrollmentStatus.rejected, submitted: t0, reviewed: t0.add(const Duration(days: 1))),
        enrollment('new', 'A', DaAmadEnrollmentStatus.pending, submitted: t0.add(const Duration(days: 3))),
      ]);
      expect(lists.pending.map((e) => e.id), ['new']);
      expect(lists.reviewed.single.id, 'old');
      expect(lists.reviewed.single.isSuperseded, isTrue);
    });

    test('the latest decision of a farmer is not marked as history', () {
      final lists = splitEnrollments([
        enrollment('r', 'A', DaAmadEnrollmentStatus.rejected, submitted: t0, reviewed: t0.add(const Duration(days: 1))),
        enrollment('a', 'A', DaAmadEnrollmentStatus.approved, submitted: t0.add(const Duration(days: 3)), reviewed: t0.add(const Duration(days: 4))),
      ]);
      final byId = {for (final e in lists.reviewed) e.id: e};
      expect(byId['a']!.isSuperseded, isFalse);
      expect(byId['r']!.isSuperseded, isTrue);
    });
  });

  group('enrollment card', () {
    testWidgets('approved: status, who reviewed it, when, and the request count', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(
            EnrollmentCard(
              item: enrollment('a', 'Juan', DaAmadEnrollmentStatus.approved,
                  submitted: DateTime(2026, 10, 1),
                  reviewed: DateTime(2026, 10, 3),
                  reviewer: 'Maria Manager',
                  requests: 3),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Farmer Juan'), findsOneWidget);
        expect(find.text('Enrolled'), findsOneWidget);
        expect(find.text('Applied Oct 1, 2026'), findsOneWidget);
        expect(find.text('Approved Oct 3, 2026 by Maria Manager'), findsOneWidget);
        expect(find.text('Sale requests: 3'), findsOneWidget);
        expect(find.text('Review application'), findsNothing);
      });
    });

    testWidgets('declined: shows the reason', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(
            EnrollmentCard(
              item: enrollment('r', 'Ana', DaAmadEnrollmentStatus.rejected,
                  submitted: DateTime(2026, 10, 1), reviewed: DateTime(2026, 10, 2), notes: 'No Ginger on roster'),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Declined'), findsOneWidget);
        expect(find.text('Reason: No Ginger on roster'), findsOneWidget);
      });
    });

    testWidgets('already in Market Linking without an application: Enrolled, no review date', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(
            EnrollmentCard(
              item: enrollment('e', 'Pedro', DaAmadEnrollmentStatus.approved,
                  submitted: DateTime(2026, 9, 1), requests: 2, enrolledWithoutReview: true),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Enrolled'), findsOneWidget);
        expect(find.textContaining('Approved '), findsNothing);
        expect(find.textContaining('Reviewed '), findsNothing);
        expect(find.textContaining('Applied '), findsNothing);
        expect(find.text('Sale requests: 2'), findsOneWidget);
      });
    });

    testWidgets('pending: a Review button that opens the review', (tester) async {
      await runIgnoringFontErrors(() async {
        var opened = 0;
        await tester.pumpWidget(
          host(
            EnrollmentCard(
              item: enrollment('p', 'Lito', DaAmadEnrollmentStatus.pending, submitted: DateTime(2026, 10, 4)),
              onReview: () => opened++,
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Pending review'), findsOneWidget);
        await tester.tap(find.text('Review application'));
        expect(opened, 1);
      });
    });

    testWidgets('Tagalog', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(
            EnrollmentCard(
              item: enrollment('r', 'Ana', DaAmadEnrollmentStatus.rejected,
                  submitted: DateTime(2026, 10, 1), reviewed: DateTime(2026, 10, 2), notes: 'Walang Luya'),
            ),
            locale: const Locale('tl'),
          ),
        );
        await tester.pump();
        expect(find.text('Tinanggihan'), findsOneWidget);
        expect(find.text('Dahilan: Walang Luya'), findsOneWidget);
      });
    });
  });
}
