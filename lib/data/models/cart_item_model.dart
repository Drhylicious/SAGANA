import '../../core/utils/client_id.dart';
import '../../core/utils/quantity_utils.dart';

/// Where a cart line is bought from. One cart, two sources: each line is placed through its
/// own source (a Marketplace listing through place_order, a Cooperative Product through
/// place_program_order).
const String kCartSourceMarketplace = 'marketplace';
const String kCartSourceCooperative = 'cooperative';

/// Local-only cart line item — lives in Hive, never in Supabase. A cart
/// is a pre-purchase scratchpad, not business data; the only thing that
/// needs to be correct and durable is the moment of checkout, which
/// place_order() already guarantees atomically per item.
class CartItemModel {
  final String listingId;
  final String cropName;
  final String? variety;
  final double pricePerKg;

  /// The unit this line is sold in; pricePerKg is the price of one of them.
  final String unit;
  final String? photoUrl;
  // Display-only, same as the rest of this snapshot — shown on the cart
  // tile so a buyer/farmer sees the same listing details there as on
  // Listing Details, without a second network round-trip.
  final String? category;
  final String? marketType;

  /// Stock at the moment this was added — a display hint only.
  /// place_order() re-checks real stock at checkout regardless.
  final double availableKgSnapshot;

  double quantityKg;

  /// 'marketplace' (default, every line saved before Cooperative Products) or 'cooperative'.
  /// For a Cooperative line [listingId] holds the PRODUCT id (program_products.id).
  final String source;

  /// Cooperative lines only: the program the product belongs to.
  final String? programId;
  final String? programName;

  /// Cooperative lines only: the regular price, shown struck through when the member price applies.
  final double? regularPrice;

  /// Sent with the order so a retry of this same line never places it twice. Created once, when
  /// the line is first built, and kept with the saved line.
  final String requestId;

  CartItemModel({
    required this.listingId,
    required this.cropName,
    this.variety,
    required this.pricePerKg,
    this.unit = kDefaultUnit,
    this.photoUrl,
    this.category,
    this.marketType,
    required this.availableKgSnapshot,
    required this.quantityKg,
    this.source = kCartSourceMarketplace,
    this.programId,
    this.programName,
    this.regularPrice,
    String? requestId,
  }) : requestId = requestId ?? newClientId();

  bool get isCooperative => source == kCartSourceCooperative;

  String get displayName {
    final v = variety?.trim();
    if (v == null || v.isEmpty) return cropName;
    if (cropName.toLowerCase().contains(v.toLowerCase())) return cropName;
    return '$cropName ($v)';
  }

  double get subtotal => moneyOf(quantityKg, pricePerKg);

  Map<String, dynamic> toMap() => {
        'listing_id': listingId,
        'crop_name': cropName,
        'variety': variety,
        'price_per_kg': pricePerKg,
        'unit': unit,
        'photo_url': photoUrl,
    'category': category,
    'market_type': marketType,
        'available_kg_snapshot': availableKgSnapshot,
        'quantity_kg': quantityKg,
        'source': source,
        'program_id': programId,
        'program_name': programName,
        'regular_price': regularPrice,
        'request_id': requestId,
      };

  factory CartItemModel.fromMap(Map<dynamic, dynamic> map) {
    return CartItemModel(
      listingId: map['listing_id'] as String,
      cropName: map['crop_name'] as String,
      variety: map['variety'] as String?,
      pricePerKg: (map['price_per_kg'] as num).toDouble(),
      unit: unitOrDefault(map['unit'] as String?),
      photoUrl: map['photo_url'] as String?,
      category: map['category'] as String?,
      marketType: map['market_type'] as String?,
      availableKgSnapshot: (map['available_kg_snapshot'] as num).toDouble(),
      quantityKg: (map['quantity_kg'] as num).toDouble(),
      // A line saved before Cooperative Products has none of these: it is a Marketplace line.
      source: (map['source'] as String?) ?? kCartSourceMarketplace,
      programId: map['program_id'] as String?,
      programName: map['program_name'] as String?,
      regularPrice: (map['regular_price'] as num?)?.toDouble(),
      requestId: map['request_id'] as String?,
    );
  }
}
