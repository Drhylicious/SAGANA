import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/data/models/cart_eligibility.dart';
import 'package:sagana/data/models/cart_item_model.dart';
import 'package:sagana/data/services/market_types_service.dart';
import 'package:sagana/data/services/offline_cache.dart';

/// The two market types as the database holds them (market_types table), and
/// the DA-AMAD channel (selling_channels).
const _public = MarketType(
  code: 'open_market',
  name: 'Public Market',
  nameTl: 'Pampublikong Market',
  buyerVisible: true,
  managerSetsPrice: false,
  sortOrder: 1,
  isActive: true,
);
const _coop = MarketType(
  code: 'sp3_cooperative',
  name: 'Cooperative Market',
  nameTl: 'Market ng Kooperatiba',
  buyerVisible: false,
  managerSetsPrice: true,
  sortOrder: 2,
  isActive: true,
);
const _daAmad = SellingChannel(
  code: 'da_amad_market_linking',
  name: 'DA-AMAD Market Linking',
  requiresExclusiveCrop: true,
);

CartItemModel _line({String? marketType}) => CartItemModel(
  listingId: 'l1',
  cropName: 'Palay',
  pricePerKg: 20,
  marketType: marketType,
  availableKgSnapshot: 10,
  quantityKg: 2,
);

void main() {
  final types = MarketTypes.instance;

  setUp(() => types.debugSet(types: [_public, _coop], channels: [_daAmad]));
  tearDown(() => types.debugSet());

  group('market types are read from data, not from code', () {
    test('names, short names and the default come from the rows', () {
      expect(types.label('open_market'), 'Public Market');
      expect(types.label('sp3_cooperative'), 'Cooperative Market');
      expect(types.shortLabel('open_market'), 'Public');
      expect(types.shortLabel('sp3_cooperative'), 'Cooperative');
      expect(types.defaultCode, 'open_market');
      expect(types.activeTypes.map((t) => t.code), [
        'open_market',
        'sp3_cooperative',
      ]);
    });

    test('a market type added later needs no code change', () {
      types.debugSet(
        types: [
          _public,
          _coop,
          const MarketType(
            code: 'wholesale',
            name: 'Wholesale Market',
            buyerVisible: false,
            managerSetsPrice: false,
            sortOrder: 3,
            isActive: true,
          ),
        ],
      );
      expect(types.label('wholesale'), 'Wholesale Market');
      expect(types.isBuyerVisible('wholesale'), isFalse);
      expect(types.activeTypes.length, 3);
    });

    test('an inactive market type is not offered', () {
      types.debugSet(
        types: [
          _public,
          const MarketType(
            code: 'sp3_cooperative',
            name: 'Cooperative Market',
            buyerVisible: false,
            managerSetsPrice: true,
            sortOrder: 2,
            isActive: false,
          ),
        ],
      );
      expect(types.activeTypes.map((t) => t.code), ['open_market']);
    });

    test('an unknown code is shown readably, never as a raw code', () {
      expect(types.label('some_new_market'), 'Some New Market');
      expect(types.label(null), 'Not yet assigned');
    });

    test('the DA-AMAD channel is a selling channel, not a market type', () {
      expect(types.byCode('da_amad_market_linking'), isNull);
      expect(
        types.channelLabel('da_amad_market_linking'),
        'DA-AMAD Market Linking',
      );
      expect(types.channelByCode('da_amad_market_linking')?.requiresExclusiveCrop,
          isTrue);
    });
  });

  group('who can see which market (Buyer vs Farmer)', () {
    bool see(String? code, String? role, {bool approved = true}) =>
        types.visibleTo(code, role: role, approvedFarmer: approved);

    test('Buyers see Public Market only', () {
      expect(see('open_market', 'buyer'), isTrue);
      expect(see('sp3_cooperative', 'buyer'), isFalse);
    });

    test('approved Farmers see both markets', () {
      expect(see('open_market', 'farmer'), isTrue);
      expect(see('sp3_cooperative', 'farmer'), isTrue);
    });

    test('a Farmer who is not yet approved sees Public Market only', () {
      expect(see('sp3_cooperative', 'farmer', approved: false), isFalse);
      expect(see('open_market', 'farmer', approved: false), isTrue);
    });

    test('Managers and Officers see both markets', () {
      expect(see('sp3_cooperative', 'admin'), isTrue);
      expect(see('sp3_cooperative', 'officer'), isTrue);
    });

    test('nothing is hidden while the markets have not loaded', () {
      types.debugSet();
      expect(see('sp3_cooperative', 'buyer'), isTrue); // the database decides
    });

    test('a row with no market type is shown', () {
      expect(see(null, 'buyer'), isTrue);
    });
  });

  group('saved (offline) data follows the current rules', () {
    test('a snapshot from an older release is not trusted', () {
      expect(OfflineCache.snapshotIsCurrent(null), isFalse);
      expect(OfflineCache.snapshotIsCurrent({'rows': []}), isFalse);
      expect(OfflineCache.snapshotIsCurrent({'v': 1, 'rows': []}), isFalse);
    });

    test('a snapshot written by this release is trusted', () {
      expect(
        OfflineCache.snapshotIsCurrent({
          'v': OfflineCache.schemaVersion,
          'rows': [],
        }),
        isTrue,
      );
    });
  });

  group('a saved cart line is checked before checkout', () {
    CartIssue check(
      Map<String, dynamic>? listing, {
      String role = 'buyer',
      String? userId = 'me',
      String? savedMarket = 'open_market',
    }) => evaluateCartItem(
      item: _line(marketType: savedMarket),
      listing: listing,
      currentUserId: userId,
      canSeeMarket: (code) =>
          types.visibleTo(code, role: role, approvedFarmer: true),
    );

    Map<String, dynamic> live({
      String status = 'approved',
      num remaining = 5,
      String crop = 'open_market',
      String farmer = 'someone-else',
    }) => {
      'id': 'l1',
      'status': status,
      'remaining_kg': remaining,
      'crop_type': crop,
      'farmer_id': farmer,
    };

    test('a normal Public Market line can be bought', () {
      expect(check(live()), CartIssue.none);
    });

    test('a Buyer cannot buy a Cooperative Market line', () {
      expect(check(live(crop: 'sp3_cooperative')), CartIssue.restricted);
    });

    test('a Farmer can buy a Cooperative Market line from another Farmer', () {
      expect(
        check(live(crop: 'sp3_cooperative'), role: 'farmer'),
        CartIssue.none,
      );
    });

    test('a Farmer cannot buy their own listing', () {
      expect(
        check(live(farmer: 'me'), role: 'farmer'),
        CartIssue.ownListing,
      );
    });

    test('a hidden listing is told apart from a removed one', () {
      // The database hides a farmer-only listing from a Buyer: no row.
      expect(
        check(null, savedMarket: 'sp3_cooperative'),
        CartIssue.restricted,
      );
      // A Public Market listing that has no row was removed.
      expect(check(null), CartIssue.unavailable);
    });

    test('withdrawn, rejected and sold-out listings are not purchasable', () {
      expect(check(live(status: 'withdrawn')), CartIssue.unavailable);
      expect(check(live(status: 'rejected')), CartIssue.unavailable);
      expect(check(live(remaining: 0)), CartIssue.soldOut);
    });
  });
}
