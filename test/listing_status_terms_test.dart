import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/data/models/marketplace_listing_model.dart';
import 'package:sagana/data/repositories/admin_listing_repository.dart';
import 'package:sagana/presentation/widgets/listing_status_badge.dart';

import 'support/ignore_font_errors.dart';

MarketplaceListingModel farmerListing(String status, {double remaining = 50}) {
  return MarketplaceListingModel(
    id: 'l-$status-$remaining',
    farmerId: 'f1',
    cropName: 'Palay',
    pricePerKg: 20,
    volumeKg: 100,
    remainingKg: remaining,
    status: status,
    createdAt: DateTime(2026, 10, 1),
  );
}

AdminListingModel adminListing(String status, {double remaining = 50}) {
  return AdminListingModel(
    id: 'a-$status-$remaining',
    farmerId: 'f1',
    farmerName: 'Juan',
    cropName: 'Palay',
    volumeKg: 100,
    remainingKg: remaining,
    pricePerKg: 20,
    status: status,
    createdAt: DateTime(2026, 10, 1),
  );
}

Widget host(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('listing state from the stored status and the stock left', () {
    test('every stored status maps to one state', () {
      expect(listingStateOf(status: 'pending_review', remainingKg: 100), ListingState.pendingApproval);
      expect(listingStateOf(status: 'approved', remainingKg: 40), ListingState.available);
      expect(listingStateOf(status: 'sold', remainingKg: 0), ListingState.soldOut);
      expect(listingStateOf(status: 'rejected', remainingKg: 0), ListingState.disapproved);
      expect(listingStateOf(status: 'withdrawn', remainingKg: 0), ListingState.withdrawn);
      expect(listingStateOf(status: 'something_else', remainingKg: 1), isNull);
    });

    test('approved with nothing left is Sold Out, from the inventory not the label', () {
      expect(listingStateOf(status: 'approved', remainingKg: 0), ListingState.soldOut);
      expect(listingStateOf(status: 'approved', remainingKg: 0.01), ListingState.available);
    });

    test('a pending listing is never Sold Out, even with 0 remaining', () {
      expect(listingStateOf(status: 'pending_review', remainingKg: 0), ListingState.pendingApproval);
    });

    test('approval outcome: a sold listing was approved; withdrawn was never decided', () {
      expect(listingApprovalOf('pending_review'), ListingApproval.pending);
      expect(listingApprovalOf('approved'), ListingApproval.approved);
      expect(listingApprovalOf('sold'), ListingApproval.approved);
      expect(listingApprovalOf('rejected'), ListingApproval.disapproved);
      expect(listingApprovalOf('withdrawn'), isNull);
    });
  });

  group('Farmer and Manager models agree on Sold Out', () {
    test('MarketplaceListingModel', () {
      expect(farmerListing('approved', remaining: 10).isAvailable, isTrue);
      expect(farmerListing('approved', remaining: 10).isSoldOut, isFalse);
      expect(farmerListing('approved', remaining: 0).isAvailable, isFalse);
      expect(farmerListing('approved', remaining: 0).isSoldOut, isTrue);
      expect(farmerListing('sold', remaining: 0).isSoldOut, isTrue);
      expect(farmerListing('rejected', remaining: 0).isSoldOut, isFalse);
      expect(farmerListing('withdrawn', remaining: 0).isSoldOut, isFalse);
    });

    test('AdminListingModel', () {
      expect(adminListing('approved', remaining: 10).isSoldOut, isFalse);
      expect(adminListing('approved', remaining: 0).isSoldOut, isTrue);
      expect(adminListing('sold', remaining: 0).isSoldOut, isTrue);
      expect(adminListing('rejected', remaining: 0).isSoldOut, isFalse);
      expect(adminListing('approved', remaining: 0).statusLabel, 'Sold Out');
      expect(adminListing('approved', remaining: 5).statusLabel, 'Available');
      expect(adminListing('pending_review').statusLabel, 'Pending Approval');
      expect(adminListing('rejected').statusLabel, 'Disapproved');
    });
  });

  group('Farmer My Listings filter', () {
    final listings = [
      farmerListing('pending_review'),
      farmerListing('approved', remaining: 30),
      farmerListing('approved', remaining: 0), // fully taken: Sold Out
      farmerListing('sold', remaining: 0),
      farmerListing('rejected', remaining: 0),
      farmerListing('withdrawn', remaining: 0),
    ];

    int count(ListingFilter f) => listings.where(f.matches).length;

    test('each chip matches what its label says', () {
      expect(count(ListingFilter.all), 6);
      expect(count(ListingFilter.pending), 1);
      expect(count(ListingFilter.available), 1);
      expect(count(ListingFilter.soldOut), 2);
      expect(count(ListingFilter.disapproved), 1);
      expect(count(ListingFilter.withdrawn), 1);
    });

    test('every listing is in exactly one status chip', () {
      final statusChips = ListingFilter.values.where((f) => f != ListingFilter.all);
      for (final l in listings) {
        expect(statusChips.where((f) => f.matches(l)).length, 1, reason: l.id);
      }
    });
  });

  group('badge wording', () {
    testWidgets('availability view (All Listings and the Farmer)', (tester) async {
      await runIgnoringFontErrors(() async {
        Widget badge(String s, double r) => Builder(
          builder: (c) => ListingStatusBadge.forListing(c, status: s, remainingKg: r),
        );
        await tester.pumpWidget(
          host(
            Column(
              children: [
                badge('pending_review', 10),
                badge('approved', 10),
                badge('approved', 0),
                badge('sold', 0),
                badge('rejected', 0),
              ],
            ),
          ),
        );
        await tester.pump();
        expect(find.text('PENDING APPROVAL'), findsOneWidget);
        expect(find.text('AVAILABLE'), findsOneWidget);
        expect(find.text('SOLD OUT'), findsNWidgets(2));
        expect(find.text('DISAPPROVED'), findsOneWidget);
        // The old words are gone.
        expect(find.text('LIVE'), findsNothing);
        expect(find.text('REJECTED'), findsNothing);
        expect(find.text('PENDING REVIEW'), findsNothing);
      });
    });

    testWidgets('approval view (Listing Approvals)', (tester) async {
      await runIgnoringFontErrors(() async {
        Widget badge(String s) =>
            Builder(builder: (c) => ListingStatusBadge.forApproval(c, status: s));
        await tester.pumpWidget(
          host(Column(children: [badge('pending_review'), badge('approved'), badge('sold'), badge('rejected')])),
        );
        await tester.pump();
        expect(find.text('PENDING APPROVAL'), findsOneWidget);
        expect(find.text('APPROVED'), findsNWidgets(2)); // approved + sold
        expect(find.text('DISAPPROVED'), findsOneWidget);
      });
    });

    testWidgets('Tagalog has a translation for every state', (tester) async {
      await runIgnoringFontErrors(() async {
        late AppLocalizations tl;
        await tester.pumpWidget(
          host(
            Builder(
              builder: (c) {
                tl = AppLocalizations.of(c);
                return const SizedBox();
              },
            ),
            locale: const Locale('tl'),
          ),
        );
        await tester.pump();
        for (final s in ListingState.values) {
          expect(listingStateLabel(tl, s), isNotEmpty);
        }
        expect(listingStateLabel(tl, ListingState.soldOut), isNot('Sold Out'));
      });
    });
  });

  group('Sold Out greying', () {
    testWidgets('greys the card only when active', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(const SoldOutGrey(active: true, child: Text('card'))),
        );
        expect(find.byType(ColorFiltered), findsOneWidget);
        expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, lessThan(1));

        await tester.pumpWidget(
          host(const SoldOutGrey(active: false, child: Text('card'))),
        );
        expect(find.byType(ColorFiltered), findsNothing);
        expect(find.text('card'), findsOneWidget);
      });
    });
  });
}
