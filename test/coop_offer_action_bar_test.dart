import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/cooperative_offer_model.dart';
import 'package:sagana/presentation/screens/shared/coop_offer_negotiation_screen.dart';

import 'support/ignore_font_errors.dart';

CooperativeOfferModel offer({String lastBy = 'farmer', double? price = 100, String status = 'pending'}) {
  return CooperativeOfferModel.fromMap({
    'id': 'o1',
    'farmer_id': 'f1',
    'farmer_name': 'Juan',
    'crop_name': 'Potato',
    'offered_quantity_kg': 100,
    'offered_at': DateTime(2026, 10, 1).toIso8601String(),
    'status': status,
    'asking_price_per_kg': price,
    'current_price_per_kg': price,
    'last_proposed_by': lastBy,
    'negotiation_round': 1,
  });
}

Widget host(Widget bar, {double width = 400}) => MaterialApp(
  theme: AppTheme.lightTheme,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: MediaQuery(
    data: MediaQueryData(size: Size(width, 800)),
    child: Scaffold(
      body: const SizedBox.shrink(),
      bottomNavigationBar: SizedBox(width: width, child: bar),
    ),
  ),
);

CoopOfferActionBar bar(
  CooperativeOfferModel o, {
  bool forFarmer = false,
  bool busy = false,
  bool online = true,
  VoidCallback? onEnd,
}) {
  return CoopOfferActionBar(
    offer: o,
    forFarmer: forFarmer,
    busy: busy,
    online: online,
    onAccept: () {},
    onCounter: () {},
    onEnd: onEnd ?? () {},
  );
}

Finder button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is OutlinedButton || w is ElevatedButton));

void main() {
  group('Manager, on the Cooperative\'s turn', () {
    testWidgets('has Counteroffer, Accept and a full-width Decline Offer button', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        await tester.pumpWidget(host(bar(offer())));
        await tester.pump();

        expect(find.text('Counteroffer'), findsOneWidget);
        expect(find.text('Accept ₱100.00/kg'), findsOneWidget);
        expect(find.text('Decline Offer'), findsOneWidget);

        final decline = button('Decline Offer');
        expect(tester.widget(decline), isA<OutlinedButton>(), reason: 'Decline is a bordered button, not a text link');
        expect(find.byType(TextButton), findsNothing);

        // Same height as Counteroffer, and as wide as the bar's content.
        final counterSize = tester.getSize(button('Counteroffer'));
        final declineSize = tester.getSize(decline);
        expect(declineSize.height, counterSize.height);
        expect(declineSize.width, 400 - 40); // the bar pads 20 on each side

        // Sits below the other actions, left-aligned with them.
        final counterRect = tester.getRect(button('Counteroffer'));
        final declineRect = tester.getRect(decline);
        expect(declineRect.top, greaterThan(counterRect.bottom));
        expect(declineRect.left, counterRect.left);
        await tester.binding.setSurfaceSize(null);
      });
    });

    testWidgets('does not overflow on a 320px screen', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.binding.setSurfaceSize(const Size(320, 700));
        await tester.pumpWidget(host(bar(offer()), width: 320));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Decline Offer'), findsOneWidget);
        await tester.binding.setSurfaceSize(null);
      });
    });

    testWidgets('Decline calls onEnd', (tester) async {
      await runIgnoringFontErrors(() async {
        var ended = 0;
        await tester.pumpWidget(host(bar(offer(), onEnd: () => ended++)));
        await tester.pump();
        await tester.tap(find.text('Decline Offer'));
        expect(ended, 1);
      });
    });
  });

  group('turn rules in the bar', () {
    testWidgets('Manager waiting for the Farmer: only Decline Offer is offered', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(host(bar(offer(lastBy: 'cooperative', price: 50))));
        await tester.pump();
        expect(find.text('Counteroffer'), findsNothing);
        expect(find.textContaining('Accept'), findsNothing);
        expect(find.text('Decline Offer'), findsOneWidget);
      });
    });

    testWidgets('Farmer on a counteroffer: Counteroffer, Accept and Cancel Offer', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(host(bar(offer(lastBy: 'cooperative', price: 50), forFarmer: true)));
        await tester.pump();
        expect(find.text('Counteroffer'), findsOneWidget);
        expect(find.text('Accept ₱50.00/kg'), findsOneWidget);
        expect(find.text('Cancel Offer'), findsOneWidget);
        expect(find.text('Decline Offer'), findsNothing);
        expect(tester.widget(button('Cancel Offer')), isA<OutlinedButton>());
      });
    });

    testWidgets('Farmer waiting for the Cooperative: only Cancel Offer', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(host(bar(offer(), forFarmer: true)));
        await tester.pump();
        expect(find.text('Counteroffer'), findsNothing);
        expect(find.textContaining('Accept'), findsNothing);
        expect(find.text('Cancel Offer'), findsOneWidget);
      });
    });

    testWidgets('an offer with no price yet offers Propose a Price and no Accept', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(host(bar(offer(price: null))));
        await tester.pump();
        expect(find.text('Propose a Price'), findsOneWidget);
        expect(find.textContaining('Accept'), findsNothing);
        expect(find.text('Decline Offer'), findsOneWidget);
      });
    });
  });

  group('offline and busy', () {
    testWidgets('every action is disabled offline, with a notice', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(host(bar(offer(), online: false)));
        await tester.pump();
        expect(find.textContaining('offline'), findsOneWidget);
        for (final label in ['Counteroffer', 'Accept ₱100.00/kg', 'Decline Offer']) {
          final w = tester.widget(button(label));
          final enabled = w is OutlinedButton ? w.onPressed != null : (w as ElevatedButton).onPressed != null;
          expect(enabled, isFalse, reason: label);
        }
      });
    });

    testWidgets('actions are disabled while one is running', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(host(bar(offer(), busy: true)));
        await tester.pump();
        final w = tester.widget<OutlinedButton>(button('Decline Offer'));
        expect(w.onPressed, isNull);
      });
    });
  });
}
