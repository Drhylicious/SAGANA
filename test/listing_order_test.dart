import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/constants/app_constants.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/utils/listing_order.dart';
import 'package:sagana/data/repositories/admin_listing_repository.dart';
import 'package:sagana/presentation/widgets/listing_status_badge.dart';

import 'support/ignore_font_errors.dart';

/// [name] is the position in the "newest first" order the listings arrive in.
AdminListingModel listing(String name, String status, {double remaining = 50, String? market}) {
  return AdminListingModel(
    id: name,
    farmerId: 'f1',
    farmerName: 'Juan',
    cropName: name,
    volumeKg: 100,
    remainingKg: remaining,
    pricePerKg: 20,
    status: status,
    marketType: market,
    createdAt: DateTime(2026, 10, 1),
  );
}

List<String> names(Iterable<AdminListingModel> l) => l.map((e) => e.cropName).toList();

void main() {
  group('stable group sort', () {
    test('moves whole groups and keeps the order inside each', () {
      final out = stableGroupSort<int>([5, 1, 4, 2, 3, 6], (n) => n.isEven ? 1 : 0);
      expect(out, [5, 1, 3, 4, 2, 6]);
    });

    test('is stable for a large run of equal groups (List.sort alone is not)', () {
      final items = List.generate(500, (i) => i);
      expect(stableGroupSort<int>(items, (_) => 0), items);
    });

    test('does not drop or duplicate anything', () {
      final items = [3, 1, 2, 3, 1];
      final out = stableGroupSort<int>(items, (n) => n);
      expect([...out]..sort(), [...items]..sort());
      expect(out.length, items.length);
    });

    test('empty and single', () {
      expect(stableGroupSort<int>(const [], (_) => 0), isEmpty);
      expect(stableGroupSort<int>([7], (_) => 0), [7]);
    });
  });

  group('All Listings: Sold Out at the very bottom', () {
    final arrived = [
      listing('Peanut', 'approved', remaining: 0), // Sold Out (no kg left)
      listing('Potato', 'approved'),
      listing('Eggplant', 'pending_review'),
      listing('Palay', 'sold', remaining: 0), // Sold Out (stored as sold)
      listing('Corn', 'rejected', remaining: 0),
      listing('Okra', 'approved'),
      listing('Rice', 'approved', remaining: 0), // Sold Out
    ];

    test('every Sold Out listing comes after every other listing', () {
      final out = orderForAllListings(arrived);
      final firstSoldOut = out.indexWhere((l) => l.isSoldOut);
      expect(out.sublist(firstSoldOut).every((l) => l.isSoldOut), isTrue);
      expect(out.sublist(0, firstSoldOut).any((l) => l.isSoldOut), isFalse);
    });

    test('the rest keep their order, and so do the Sold Out ones', () {
      final out = names(orderForAllListings(arrived));
      expect(out, ['Potato', 'Eggplant', 'Corn', 'Okra', 'Peanut', 'Palay', 'Rice']);
    });

    test('a Disapproved listing is not treated as Sold Out, even with 0 kg', () {
      final out = names(orderForAllListings(arrived));
      expect(out.indexOf('Corn'), lessThan(out.indexOf('Peanut')));
    });

    test('it follows the stock: an order cancelled brings a listing back up', () {
      final before = names(orderForAllListings([listing('A', 'approved', remaining: 0), listing('B', 'approved')]));
      expect(before, ['B', 'A']);
      final after = names(orderForAllListings([listing('A', 'approved', remaining: 5), listing('B', 'approved')]));
      expect(after, ['A', 'B']);
    });

    test('with a market filter applied first, the order inside it is the same', () {
      final cooperative = [
        listing('Peanut', 'approved', remaining: 0, market: 'coop'),
        listing('Palay', 'approved', market: 'coop'),
        listing('Potato', 'approved', market: 'public'),
      ].where((l) => l.marketType == 'coop');
      expect(names(orderForAllListings(cooperative)), ['Palay', 'Peanut']);
    });

    test('ordering twice changes nothing', () {
      final once = orderForAllListings(arrived);
      expect(names(orderForAllListings(once)), names(once));
    });
  });

  group('Listing Approvals: Pending, then Approved, Disapproved last', () {
    final arrived = [
      listing('Rejected1', 'rejected', remaining: 0),
      listing('Approved1', 'approved'),
      listing('Pending1', 'pending_review'),
      listing('Sold1', 'sold', remaining: 0),
      listing('Pending2', 'pending_review'),
      listing('Rejected2', 'rejected', remaining: 0),
      listing('Approved2', 'approved'),
      listing('FullyOrdered', 'approved', remaining: 0),
    ];

    test('groups are in the requested order', () {
      final out = orderForApprovals(arrived);
      int group(AdminListingModel l) => approvalGroup(l);
      expect(out.map(group).toList(), [0, 0, 1, 1, 1, 1, 2, 2]);
    });

    test('inside each group the original order is kept', () {
      expect(names(orderForApprovals(arrived)), [
        'Pending1', 'Pending2',
        'Approved1', 'Sold1', 'Approved2', 'FullyOrdered',
        'Rejected1', 'Rejected2',
      ]);
    });

    test('a sold-out listing was approved, so it sits with Approved', () {
      expect(approvalGroup(listing('x', 'sold', remaining: 0)), 1);
      expect(approvalGroup(listing('x', 'approved', remaining: 0)), 1);
    });

    test('a single approval filter keeps its own order', () {
      final onlyApproved = arrived.where((l) => !l.isPending && !l.isRejected);
      expect(names(orderForApprovals(onlyApproved)), ['Approved1', 'Sold1', 'Approved2', 'FullyOrdered']);
    });

    test('nothing is lost', () {
      expect(orderForApprovals(arrived).length, arrived.length);
    });
  });

  group('the screens apply the ordering after the filters', () {
    test('All Listings', () {
      final src = File('lib/presentation/screens/admin/all_listings_screen.dart').readAsStringSync();
      expect(src, contains('return orderForAllListings(list);'));
      expect(src.indexOf('_marketFilter != null'), lessThan(src.indexOf('orderForAllListings(list)')));
      expect(src.indexOf('_searchQuery.isNotEmpty'), lessThan(src.indexOf('orderForAllListings(list)')));
    });

    test('Listing Approvals', () {
      final src = File('lib/presentation/screens/admin/pending_approvals_screen.dart').readAsStringSync();
      expect(src, contains('return orderForApprovals(list);'));
      expect(src.indexOf('_approvalFilter == null'), lessThan(src.indexOf('orderForApprovals(list)')));
      expect(src.indexOf('_searchQuery.isNotEmpty'), lessThan(src.indexOf('orderForApprovals(list)')));
    });
  });

  group('status colours', () {
    testWidgets('each status has its own colour, the same on every screen', (tester) async {
      await runIgnoringFontErrors(() async {
        late ColorScheme cs;
        late Map<String, Color> state;
        late Map<String, Color> approval;
        late Map<String, Color?> accent;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Builder(
              builder: (c) {
                cs = Theme.of(c).colorScheme;
                state = {
                  for (final s in ListingState.values) s.name: listingStateColor(c, s),
                };
                approval = {
                  for (final a in ListingApproval.values) a.name: listingApprovalColor(c, a),
                };
                accent = {
                  for (final s in ListingState.values) s.name: listingAccentColor(c, s),
                };
                return const SizedBox();
              },
            ),
          ),
        );

        // Pending = amber, Available = green, Sold Out = grey, Disapproved = red.
        expect(state['pendingApproval'], AppConstants.warningAmber);
        expect(state['available'], AppConstants.successGreen);
        expect(state['soldOut'], cs.onSurfaceVariant);
        expect(state['disapproved'], cs.error);

        // The approval view uses the very same colours for the same outcomes.
        expect(approval['pending'], state['pendingApproval']);
        expect(approval['approved'], state['available']);
        expect(approval['disapproved'], state['disapproved']);

        // Pending and Disapproved are never the same colour as anything else.
        expect({state['pendingApproval'], state['available'], state['soldOut'], state['disapproved']}.length, 4);
        expect(state['disapproved'], isNot(state['pendingApproval']));

        // Only the two attention states get a card accent bar, in the badge colour.
        expect(accent['pendingApproval'], state['pendingApproval']);
        expect(accent['disapproved'], state['disapproved']);
        expect(accent['available'], isNull);
        expect(accent['soldOut'], isNull);
        expect(accent['withdrawn'], isNull);
        expect(listingAccentColor(tester.element(find.byType(SizedBox)), null), isNull);
      });
    });
  });
}
