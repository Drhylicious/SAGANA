import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/presentation/widgets/listing_status_badge.dart';

import 'support/ignore_font_errors.dart';

Widget host(Widget child) => MaterialApp(
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// The text shown by the badge on a listing card (All Listings / My Listings).
Future<String> cardBadgeText(WidgetTester tester, String status, double remaining) async {
  await tester.pumpWidget(
    host(
      Builder(
        builder: (c) => ListingStatusBadge.forListing(c, status: status, remainingKg: remaining),
      ),
    ),
  );
  await tester.pump();
  return tester.widget<Text>(find.byType(Text).first).data!;
}

/// The badge text inside the banner at the top of Listing Review.
Future<String> headerBadgeText(WidgetTester tester, String status, double remaining, double volume) async {
  await tester.pumpWidget(
    host(ListingStatusHeader(status: status, remainingKg: remaining, volumeKg: volume)),
  );
  await tester.pump();
  return tester.widget<Text>(find.byType(Text).first).data!;
}

void main() {
  group('Listing Review status banner', () {
    testWidgets('a fully ordered listing reads Sold Out, not Available (the reported bug)', (tester) async {
      await runIgnoringFontErrors(() async {
        // Peanut, 25 kg listed, approved, nothing left.
        await tester.pumpWidget(
          host(const ListingStatusHeader(status: 'approved', remainingKg: 0, volumeKg: 25)),
        );
        await tester.pump();
        expect(find.text('SOLD OUT'), findsOneWidget);
        expect(find.text('AVAILABLE'), findsNothing);
        expect(find.text('0 of 25 kg left'), findsOneWidget);
      });
    });

    testWidgets('a listing with stock left reads Available with the quantity', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(const ListingStatusHeader(status: 'approved', remainingKg: 25, volumeKg: 50)),
        );
        await tester.pump();
        expect(find.text('AVAILABLE'), findsOneWidget);
        expect(find.text('25 of 50 kg left'), findsOneWidget);
      });
    });

    testWidgets('a listing stored as sold reads Sold Out', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(const ListingStatusHeader(status: 'sold', remainingKg: 0, volumeKg: 40)),
        );
        await tester.pump();
        expect(find.text('SOLD OUT'), findsOneWidget);
      });
    });

    testWidgets('pending and disapproved listings show the quantity listed, not stock left', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(const ListingStatusHeader(status: 'pending_review', remainingKg: 50, volumeKg: 50)),
        );
        await tester.pump();
        expect(find.text('PENDING APPROVAL'), findsOneWidget);
        expect(find.text('50 kg listed'), findsOneWidget);

        await tester.pumpWidget(
          host(const ListingStatusHeader(status: 'rejected', remainingKg: 0, volumeKg: 50)),
        );
        await tester.pump();
        expect(find.text('DISAPPROVED'), findsOneWidget);
        expect(find.text('50 kg listed'), findsOneWidget);
      });
    });

    testWidgets('fractional quantities keep their decimals', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(const ListingStatusHeader(status: 'approved', remainingKg: 2.5, volumeKg: 10)),
        );
        await tester.pump();
        expect(find.text('2.50 of 10 kg left'), findsOneWidget);
      });
    });
  });

  group('Listing Review and the list always agree', () {
    // Every stored status against stock left and none left: the badge on a
    // listing card and the badge in the Listing Review banner must be the same.
    const statuses = ['pending_review', 'approved', 'sold', 'rejected', 'withdrawn'];
    const stocks = [0.0, 10.0];

    for (final status in statuses) {
      for (final stock in stocks) {
        testWidgets('$status with $stock kg left', (tester) async {
          await runIgnoringFontErrors(() async {
            final onCard = await cardBadgeText(tester, status, stock);
            final onReview = await headerBadgeText(tester, status, stock, 50);
            expect(onReview, onCard);
          });
        });
      }
    }
  });
}
