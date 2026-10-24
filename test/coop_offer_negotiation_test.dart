import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/data/models/cooperative_offer_model.dart';
import 'package:sagana/presentation/widgets/coop_offer_widgets.dart';

import 'support/ignore_font_errors.dart';

Map<String, dynamic> row({
  String status = 'pending',
  double? asking = 100,
  double? current = 100,
  String lastBy = 'farmer',
  int round = 1,
  double? agreed,
  double qty = 100,
  double? confirmedAmount,
}) {
  return {
    'id': 'o1',
    'farmer_id': 'f1',
    'farmer_name': 'Juan',
    'crop_name': 'Potato',
    'offered_quantity_kg': qty,
    'offered_at': DateTime(2026, 10, 1).toIso8601String(),
    'status': status,
    'asking_price_per_kg': asking,
    'current_price_per_kg': current,
    'agreed_price_per_kg': agreed,
    'last_proposed_by': lastBy,
    'negotiation_round': round,
    'confirmed_quantity_kg': status == 'confirmed' ? qty : null,
    'confirmed_amount': confirmedAmount,
  };
}

CooperativeOfferModel offer(Map<String, dynamic> r) => CooperativeOfferModel.fromMap(r);

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
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('whose turn it is', () {
    test('a new Farmer offer waits for the Cooperative', () {
      final o = offer(row());
      expect(o.awaitingCooperative, isTrue);
      expect(o.awaitingFarmer, isFalse);
    });

    test('after the Cooperative counters, the Farmer is up', () {
      final o = offer(row(current: 50, lastBy: 'cooperative', round: 2));
      expect(o.awaitingFarmer, isTrue);
      expect(o.awaitingCooperative, isFalse);
    });

    test('closed offers wait for nobody', () {
      for (final s in ['confirmed', 'declined', 'cancelled']) {
        final o = offer(row(status: s));
        expect(o.awaitingCooperative, isFalse, reason: s);
        expect(o.awaitingFarmer, isFalse, reason: s);
      }
    });

    test('an offer from before negotiation existed has no price and waits for the Cooperative', () {
      final o = CooperativeOfferModel.fromMap({
        'id': 'old',
        'farmer_id': 'f1',
        'crop_name': 'Palay',
        'offered_quantity_kg': 80,
        'offered_at': DateTime(2026, 9, 1).toIso8601String(),
        'status': 'pending',
      });
      expect(o.hasPrice, isFalse);
      expect(o.currentTotal, isNull);
      expect(o.negotiationRound, 1);
      expect(o.awaitingCooperative, isTrue);
    });
  });

  group('the example negotiation, step by step', () {
    // 100 -> 50 -> 100 -> 80, then the Farmer accepts 80.
    test('prices and totals follow the latest proposal', () {
      final steps = [
        offer(row(current: 100, lastBy: 'farmer', round: 1)),
        offer(row(current: 50, lastBy: 'cooperative', round: 2)),
        offer(row(current: 100, lastBy: 'farmer', round: 3)),
        offer(row(current: 80, lastBy: 'cooperative', round: 4)),
      ];
      expect(steps.map((s) => s.currentTotal), [10000, 5000, 10000, 8000]);
      expect(steps.map((s) => s.awaitingFarmer), [false, true, false, true]);
      expect(steps.last.negotiationRound, 4);
      // The asking price never changes.
      expect(steps.every((s) => s.askingPricePerKg == 100), isTrue);

      final accepted = offer(
        row(status: 'confirmed', current: 80, lastBy: 'cooperative', round: 4, agreed: 80, confirmedAmount: 8000),
      );
      expect(accepted.isConfirmed, isTrue);
      expect(accepted.agreedPricePerKg, 80);
      expect(accepted.settledAmount, 8000);
    });
  });

  group('list filters', () {
    final offers = [
      offer(row()), // Cooperative's turn
      offer(row(current: 50, lastBy: 'cooperative', round: 2)), // Farmer's turn
      offer(row(status: 'confirmed', agreed: 80, confirmedAmount: 8000)),
      offer(row(status: 'declined')),
      offer(row(status: 'cancelled')),
    ];

    test('every offer is in exactly one status chip', () {
      final chips = CoopOfferFilter.values.where((f) => f != CoopOfferFilter.all);
      for (final o in offers) {
        expect(chips.where((f) => f.matches(o)).length, 1);
      }
      expect(offers.where(CoopOfferFilter.all.matches).length, offers.length);
    });

    test('counts', () {
      int c(CoopOfferFilter f) => offers.where(f.matches).length;
      expect(c(CoopOfferFilter.awaitingCooperative), 1);
      expect(c(CoopOfferFilter.awaitingFarmer), 1);
      expect(c(CoopOfferFilter.accepted), 1);
      expect(c(CoopOfferFilter.declined), 1);
      expect(c(CoopOfferFilter.cancelled), 1);
    });
  });

  group('status wording by side', () {
    testWidgets('Manager and Farmer see the same offer in their own words', (tester) async {
      await runIgnoringFontErrors(() async {
        final farmerTurn = offer(row(current: 50, lastBy: 'cooperative', round: 2));
        final coopTurn = offer(row());
        late CoopOfferStatusView mgrOnCoopTurn, mgrOnFarmerTurn, farmerOnCoopTurn, farmerOnFarmerTurn;
        await tester.pumpWidget(
          host(
            Builder(
              builder: (c) {
                mgrOnCoopTurn = CoopOfferStatusView.of(c, coopTurn, forFarmer: false);
                mgrOnFarmerTurn = CoopOfferStatusView.of(c, farmerTurn, forFarmer: false);
                farmerOnCoopTurn = CoopOfferStatusView.of(c, coopTurn, forFarmer: true);
                farmerOnFarmerTurn = CoopOfferStatusView.of(c, farmerTurn, forFarmer: true);
                return const SizedBox();
              },
            ),
          ),
        );
        expect(mgrOnCoopTurn.label, 'Needs Response');
        expect(mgrOnCoopTurn.needsMyResponse, isTrue);
        expect(mgrOnFarmerTurn.label, 'Waiting for Farmer');
        expect(mgrOnFarmerTurn.needsMyResponse, isFalse);
        expect(farmerOnCoopTurn.label, 'Waiting for Cooperative');
        expect(farmerOnCoopTurn.needsMyResponse, isFalse);
        expect(farmerOnFarmerTurn.label, 'Counteroffer Received');
        expect(farmerOnFarmerTurn.needsMyResponse, isTrue);
      });
    });

    testWidgets('closed outcomes read the same to both', (tester) async {
      await runIgnoringFontErrors(() async {
        final labels = <String>[];
        await tester.pumpWidget(
          host(
            Builder(
              builder: (c) {
                for (final s in ['confirmed', 'declined', 'cancelled']) {
                  for (final farmer in [true, false]) {
                    labels.add(CoopOfferStatusView.of(c, offer(row(status: s)), forFarmer: farmer).label);
                  }
                }
                return const SizedBox();
              },
            ),
          ),
        );
        expect(labels, ['Accepted', 'Accepted', 'Declined', 'Declined', 'Cancelled', 'Cancelled']);
      });
    });

    testWidgets('Tagalog labels exist for every filter on both sides', (tester) async {
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
        for (final f in CoopOfferFilter.values) {
          expect(f.label(tl, forFarmer: true), isNotEmpty);
          expect(f.label(tl, forFarmer: false), isNotEmpty);
        }
      });
    });
  });

  group('amount formatting', () {
    test('pesos and kilograms', () {
      expect(coopPeso(8000), '₱8,000.00');
      expect(coopPricePerKg(80), '₱80.00/kg');
      expect(coopKg(100), '100 kg');
      expect(coopKg(12.5), '12.50 kg');
    });
  });

  group('price summary card', () {
    testWidgets('open offer shows ask, latest proposal, who proposed and the total', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(
            CoopPriceSummary(
              offer: offer(row(current: 50, lastBy: 'cooperative', round: 2)),
              forFarmer: true,
            ),
          ),
        );
        await tester.pump();
        expect(find.text('100 kg'), findsOneWidget);
        expect(find.text('₱100.00/kg'), findsOneWidget); // asking
        expect(find.text('₱50.00/kg'), findsOneWidget); // latest
        expect(find.text('₱5,000.00'), findsOneWidget); // 50 x 100
        expect(find.textContaining('Proposed by Cooperative'), findsOneWidget);
        expect(find.textContaining('Round 2'), findsOneWidget);
      });
    });

    testWidgets('the Manager sees the Farmer\'s proposal as the Farmer\'s', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(CoopPriceSummary(offer: offer(row()), forFarmer: false)),
        );
        await tester.pump();
        expect(find.textContaining('Proposed by Farmer'), findsOneWidget);
      });
    });

    testWidgets('an accepted offer shows the agreed price and the settled total', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(
            CoopPriceSummary(
              offer: offer(
                row(status: 'confirmed', current: 80, lastBy: 'cooperative', round: 4, agreed: 80, confirmedAmount: 8000),
              ),
              forFarmer: false,
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Agreed price'), findsOneWidget);
        expect(find.text('₱80.00/kg'), findsOneWidget);
        expect(find.text('₱8,000.00'), findsOneWidget);
        expect(find.textContaining('Proposed by'), findsNothing);
      });
    });

    testWidgets('an offer with no price yet says so', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(CoopPriceSummary(offer: offer(row(asking: null, current: null)), forFarmer: false)),
        );
        await tester.pump();
        expect(find.text('No price yet'), findsOneWidget);
      });
    });
  });

  group('history timeline', () {
    testWidgets('shows each step, who took it and the price, in order', (tester) async {
      await runIgnoringFontErrors(() async {
        CooperativeOfferEvent ev(int i, String action, String role, double? price, {String? note}) =>
            CooperativeOfferEvent(
              id: 'e$i',
              offerId: 'o1',
              round: i,
              action: action,
              actorRole: role,
              pricePerKg: price,
              note: note,
              createdAt: DateTime(2026, 10, 1, 8 + i),
            );
        await tester.pumpWidget(
          host(
            CoopNegotiationTimeline(
              forFarmer: false,
              events: [
                ev(1, 'offered', 'farmer', 100),
                ev(2, 'countered', 'cooperative', 50, note: 'Too high this week'),
                ev(3, 'countered', 'farmer', 100),
                ev(4, 'countered', 'cooperative', 80),
                ev(5, 'accepted', 'farmer', 80),
              ],
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Offer submitted'), findsOneWidget);
        expect(find.text('Counteroffer'), findsNWidgets(3));
        expect(find.text('Price accepted'), findsOneWidget);
        expect(find.text('₱100.00/kg'), findsNWidgets(2));
        expect(find.text('₱50.00/kg'), findsOneWidget);
        expect(find.text('₱80.00/kg'), findsNWidgets(2));
        expect(find.textContaining('Too high this week'), findsOneWidget);
        expect(find.textContaining('Farmer ·'), findsNWidgets(3));
        expect(find.textContaining('Cooperative ·'), findsNWidgets(2));
      });
    });
  });
}
