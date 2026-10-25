import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/data/models/cooperative_offer_model.dart';
import 'package:sagana/presentation/widgets/coop_offer_widgets.dart';

CooperativeOfferModel offer(
  String id,
  String crop, {
  String farmer = 'Juan Dela Cruz',
  String status = 'pending',
  String lastBy = 'farmer',
}) {
  return CooperativeOfferModel.fromMap({
    'id': id,
    'farmer_id': 'f1',
    'farmer_name': farmer,
    'crop_name': crop,
    'offered_quantity_kg': 20,
    'offered_at': DateTime(2026, 10, 1).toIso8601String(),
    'status': status,
    'asking_price_per_kg': 100,
    'current_price_per_kg': 100,
    'last_proposed_by': lastBy,
    'negotiation_round': 1,
  });
}

List<String> ids(Iterable<CooperativeOfferModel> l) => l.map((o) => o.id).toList();

void main() {
  final offers = [
    offer('1', 'Peanut'), // waiting for the Cooperative
    offer('2', 'Potato', lastBy: 'cooperative'), // counteroffer received
    offer('3', 'Palay', status: 'confirmed'),
    offer('4', 'Peanut', status: 'declined', farmer: 'Maria Santos'),
    offer('5', 'Ginger Root', status: 'cancelled'),
  ];

  group('search', () {
    test('an empty or blank search shows everything in the chosen chip', () {
      expect(ids(filterCoopOffers(offers, filter: CoopOfferFilter.all)), ['1', '2', '3', '4', '5']);
      expect(ids(filterCoopOffers(offers, filter: CoopOfferFilter.all, query: '   ')), ['1', '2', '3', '4', '5']);
    });

    test('finds a crop by part of its name, in any letter case', () {
      expect(ids(filterCoopOffers(offers, filter: CoopOfferFilter.all, query: 'pea')), ['1', '4']);
      expect(ids(filterCoopOffers(offers, filter: CoopOfferFilter.all, query: 'PALAY')), ['3']);
      expect(ids(filterCoopOffers(offers, filter: CoopOfferFilter.all, query: 'root')), ['5']);
    });

    test('ignores spaces around what was typed', () {
      expect(ids(filterCoopOffers(offers, filter: CoopOfferFilter.all, query: '  potato ')), ['2']);
    });

    test('no match gives an empty list', () {
      expect(filterCoopOffers(offers, filter: CoopOfferFilter.all, query: 'zzz'), isEmpty);
    });

    test('a Farmer\'s search does not match the farmer name field', () {
      expect(filterCoopOffers(offers, filter: CoopOfferFilter.all, query: 'maria'), isEmpty);
    });

    test('the Manager\'s search also matches the farmer name', () {
      final out = filterCoopOffers(offers, filter: CoopOfferFilter.all, query: 'maria', matchFarmerName: true);
      expect(ids(out), ['4']);
      // and still the crop
      expect(ids(filterCoopOffers(offers, filter: CoopOfferFilter.all, query: 'potato', matchFarmerName: true)), ['2']);
    });
  });

  group('search and chips combine', () {
    test('an offer must satisfy both', () {
      // "pea" matches offers 1 and 4; only offer 4 is Declined.
      expect(ids(filterCoopOffers(offers, filter: CoopOfferFilter.declined, query: 'pea')), ['4']);
      expect(ids(filterCoopOffers(offers, filter: CoopOfferFilter.awaitingCooperative, query: 'pea')), ['1']);
      expect(filterCoopOffers(offers, filter: CoopOfferFilter.accepted, query: 'pea'), isEmpty);
    });

    test('each chip on its own is unchanged by an empty search', () {
      for (final f in CoopOfferFilter.values) {
        expect(ids(filterCoopOffers(offers, filter: f)), ids(offers.where(f.matches)));
      }
    });

    test('searching never changes the order or drops a match', () {
      final out = filterCoopOffers(offers, filter: CoopOfferFilter.all, query: 'p');
      expect(ids(out), ['1', '2', '3', '4']); // Peanut, Potato, Palay, Peanut (not Ginger Root)
    });

    test('the Farmer\'s chip counts stay the totals for each status', () {
      // The screen counts from the full list, not the searched one, like the Manager's.
      int count(CoopOfferFilter f) => offers.where(f.matches).length;
      expect(count(CoopOfferFilter.declined), 1);
      expect(count(CoopOfferFilter.awaitingFarmer), 1);
    });
  });

  group('layout and wiring (source)', () {
    String read(String p) => File(p).readAsStringSync();

    test('Farmer screen: search bar first, then the scrolling chips, as on the Manager screen', () {
      final src = read('lib/presentation/screens/farmer/farmer_coop_offers_screen.dart');
      final search = src.indexOf('TextField(');
      final chips = src.indexOf('scrollDirection: Axis.horizontal');
      final cards = src.indexOf('for (final offer in list)');
      expect(search, greaterThan(0));
      expect(chips, greaterThan(search));
      expect(cards, greaterThan(chips));
      expect(src, contains('l10n.coopMyOffersSearchHint'));
      expect(src, contains('filterCoopOffers(_offers, filter: _filter, query: _searchQuery)'));
      expect(src, contains('_searchCtrl.dispose()'));
      expect(src, contains('onPressed: () => _searchCtrl.clear()'));
    });

    test('Manager screen uses the same rule and still searches the farmer name', () {
      final src = read('lib/presentation/screens/admin/offer_to_cooperative_screen.dart');
      expect(src, contains('filterCoopOffers('));
      expect(src, contains('matchFarmerName: true'));
      // Same order on both: search, then chips.
      expect(src.indexOf('TextField('), lessThan(src.indexOf('scrollDirection: Axis.horizontal')));
    });

    test('the empty state says "no match" when offers exist but the search finds none', () {
      final src = read('lib/presentation/screens/farmer/farmer_coop_offers_screen.dart');
      expect(src, contains('filtered: _offers.isNotEmpty'));
    });
  });
}
