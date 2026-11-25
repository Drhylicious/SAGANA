import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/data/models/marketplace_listing_model.dart';
import 'package:sagana/data/models/price_record_model.dart';
import 'package:sagana/data/models/shelf_life_model.dart';

void main() {
  group('ListingPriceRule switching Fixed <-> Range', () {
    test('Fixed price locks editing and only allows exact price', () {
      final rule = ListingPriceRule.fromMap({
        'mode': 'fixed',
        'price_min': 50.0,
        'price_max': 50.0,
        'unit': 'kg',
      });

      expect(rule, isNotNull);
      expect(rule!.isFixed, isTrue);
      expect(rule.isLocked, isTrue);
      expect(rule.allows(50.0), isTrue);
      expect(rule.allows(49.99), isFalse);
      expect(rule.allows(50.01), isFalse);
    });

    test('Range price unlocks editing and enforces min..max', () {
      final rule = ListingPriceRule.fromMap({
        'mode': 'range',
        'price_min': 50.0,
        'price_max': 60.0,
        'unit': 'kg',
      });

      expect(rule, isNotNull);
      expect(rule!.isFixed, isFalse);
      expect(rule.isLocked, isFalse);
      expect(rule.allows(50.0), isTrue);
      expect(rule.allows(55.5), isTrue);
      expect(rule.allows(60.0), isTrue);
      expect(rule.allows(49.99), isFalse);
      expect(rule.allows(60.01), isFalse);
    });
  });

  group('PriceRecordModel Fixed vs Range formatting', () {
    test('Fixed price record reports isRange = false', () {
      final record = PriceRecordModel.fromMap({
        'id': 'pr-1',
        'crop_id': 'crop-1',
        'crop_name': 'Potato',
        'price': 50,
        'unit': 'kg',
        'price_type': 'open_market',
        'recorded_at': '2026-11-25T10:00:00.000Z',
        'price_mode': 'fixed',
        'price_max': null,
      });

      expect(record.isRange, isFalse);
      expect(record.formattedPrice, '₱50.00/kg');
    });

    test('Range price record reports isRange = true and range text', () {
      final record = PriceRecordModel.fromMap({
        'id': 'pr-2',
        'crop_id': 'crop-1',
        'crop_name': 'Potato',
        'price': 50,
        'unit': 'kg',
        'price_type': 'open_market',
        'recorded_at': '2026-11-25T10:00:00.000Z',
        'price_mode': 'range',
        'price_max': 60,
      });

      expect(record.isRange, isTrue);
      expect(record.formattedPrice, '₱50.00–₱60.00/kg');
    });
  });

  group('MarketplaceListingModel auto-adjusted range confirmation', () {
    test('parses price_confirmation_required and price_adjusted_from', () {
      final listing = MarketplaceListingModel.fromMap({
        'id': 'listing-1',
        'farmer_id': 'farmer-1',
        'crop_name': 'Potato',
        'price_per_kg': 50.0,
        'volume_kg': 10.0,
        'remaining_kg': 10.0,
        'unit': 'kg',
        'status': 'approved',
        'created_at': '2026-11-25T08:00:00.000Z',
        'price_confirmation_required': true,
        'price_adjusted_from': 40.0,
        'price_update_rule': {
          'mode': 'range',
          'price_min': 50.0,
          'price_max': 60.0,
          'unit': 'kg',
        },
      });

      expect(listing.priceConfirmationRequired, isTrue);
      expect(listing.priceAdjustedFrom, 40.0);
      expect(listing.pricePerKg, 50.0);
      expect(listing.priceUpdateRequired, isTrue);
      expect(listing.priceUpdateRule!.isLocked, isFalse);
      expect(listing.priceUpdateRule!.allows(55.0), isTrue);
    });
  });
}
