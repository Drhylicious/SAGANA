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
  VoidCallback? onAccept,
  VoidCallback? onCounter,
}) {
  return CoopOfferActionBar(
    offer: o,
    forFarmer: forFarmer,
    busy: busy,
    online: online,
    onAccept: onAccept ?? () {},
    onCounter: onCounter ?? () {},
    onEnd: onEnd ?? () {},
  );
}

Finder button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is OutlinedButton || w is ElevatedButton));

void main() {
  group('Manager, on the Cooperative\'s turn', () {
    testWidgets('has Accept Offer | Decline Offer on one row and a full-width Submit Counteroffer below', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        await tester.pumpWidget(host(bar(offer())));
        await tester.pump();

        expect(find.text('Submit Counteroffer'), findsOneWidget);
        expect(find.text('Accept Offer'), findsOneWidget);
        expect(find.text('Decline Offer'), findsOneWidget);

        final decline = button('Decline Offer');
        expect(tester.widget(decline), isA<OutlinedButton>(), reason: 'Decline is a bordered button, not a text link');
        expect(tester.widget(button('Accept Offer')), isA<ElevatedButton>());
        expect(find.byType(TextButton), findsNothing);

        // Accept Offer | Decline Offer share one row; Submit Counteroffer is
        // full width on its own row below it.
        final acceptRect = tester.getRect(button('Accept Offer'));
        final declineRect = tester.getRect(decline);
        final counterRect = tester.getRect(button('Submit Counteroffer'));
        expect(acceptRect.top, declineRect.top, reason: 'same row');
        expect(acceptRect.right, lessThan(declineRect.left));
        expect(acceptRect.height, declineRect.height);
        expect(acceptRect.left, counterRect.left);
        expect(declineRect.right, counterRect.right);
        expect(counterRect.width, 400 - 40); // the bar pads 20 on each side
        expect(counterRect.top, greaterThan(acceptRect.bottom));
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

    testWidgets('Accept Offer approves the original offer directly, without a counteroffer', (tester) async {
      await runIgnoringFontErrors(() async {
        var accepted = 0, countered = 0;
        await tester.pumpWidget(host(bar(offer(), onAccept: () => accepted++, onCounter: () => countered++)));
        await tester.pump();
        await tester.tap(find.text('Accept Offer'));
        expect(accepted, 1);
        expect(countered, 0);
        await tester.tap(find.text('Submit Counteroffer'));
        expect(countered, 1);
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
    testWidgets('Manager who just sent a counteroffer: no buttons until the Farmer answers', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(host(bar(offer(lastBy: 'cooperative', price: 50))));
        await tester.pump();
        expect(find.text('Submit Counteroffer'), findsNothing);
        expect(find.textContaining('Accept'), findsNothing);
        expect(find.text('Decline Offer'), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
        expect(find.byType(ElevatedButton), findsNothing);
        // The Farmer answers with a counteroffer: the buttons are back.
        await tester.pumpWidget(host(bar(offer(lastBy: 'farmer', price: 70))));
        await tester.pump();
        expect(find.text('Decline Offer'), findsOneWidget);
        expect(find.text('Accept Offer'), findsOneWidget);
        expect(find.text('Submit Counteroffer'), findsOneWidget);
      });
    });

    testWidgets('Farmer on a counteroffer: the same layout as the Manager', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        await tester.pumpWidget(host(bar(offer(lastBy: 'cooperative', price: 50), forFarmer: true)));
        await tester.pump();
        expect(find.text('Accept Offer'), findsOneWidget);
        expect(find.text('Decline Offer'), findsOneWidget);
        expect(find.text('Submit Counteroffer'), findsOneWidget);
        expect(find.text('Cancel Offer'), findsNothing, reason: 'Decline Offer replaces it when the Farmer answers');
        expect(tester.widget(button('Accept Offer')), isA<ElevatedButton>());
        expect(tester.widget(button('Decline Offer')), isA<OutlinedButton>());

        final accept = tester.getRect(button('Accept Offer'));
        final decline = tester.getRect(button('Decline Offer'));
        final counter = tester.getRect(button('Submit Counteroffer'));
        expect(accept.top, decline.top, reason: 'same row');
        expect(accept.width, decline.width, reason: 'equal widths');
        expect(accept.height, decline.height);
        expect(accept.left, counter.left);
        expect(decline.right, counter.right);
        expect(counter.top, greaterThan(accept.bottom));
        await tester.binding.setSurfaceSize(null);
      });
    });

    testWidgets('Farmer and Manager get identical button geometry', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        await tester.pumpWidget(host(bar(offer(lastBy: 'cooperative', price: 50), forFarmer: true)));
        await tester.pump();
        final farmer = [for (final l in ['Accept Offer', 'Decline Offer', 'Submit Counteroffer']) tester.getRect(button(l))];
        await tester.pumpWidget(host(bar(offer())));
        await tester.pump();
        final manager = [for (final l in ['Accept Offer', 'Decline Offer', 'Submit Counteroffer']) tester.getRect(button(l))];
        for (var i = 0; i < 3; i++) {
          expect(farmer[i].size, manager[i].size);
          expect(farmer[i].left, manager[i].left);
        }
        await tester.binding.setSurfaceSize(null);
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
        for (final label in ['Submit Counteroffer', 'Accept Offer', 'Decline Offer']) {
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
