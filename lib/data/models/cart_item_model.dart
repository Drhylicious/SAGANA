/// Local-only cart line item — lives in Hive, never in Supabase. A cart
/// is a pre-purchase scratchpad, not business data; the only thing that
/// needs to be correct and durable is the moment of checkout, which
/// place_order() already guarantees atomically per item.
class CartItemModel {
  final String listingId;
  final String cropName;
  final String? variety;
  final double pricePerKg;
  final String? photoUrl;

  /// Stock at the moment this was added — a display hint only.
  /// place_order() re-checks real stock at checkout regardless.
  final double availableKgSnapshot;

  double quantityKg;

  CartItemModel({
    required this.listingId,
    required this.cropName,
    this.variety,
    required this.pricePerKg,
    this.photoUrl,
    required this.availableKgSnapshot,
    required this.quantityKg,
  });

  String get displayName {
    final v = variety?.trim();
    if (v == null || v.isEmpty) return cropName;
    if (cropName.toLowerCase().contains(v.toLowerCase())) return cropName;
    return '$cropName ($v)';
  }

  double get subtotal => quantityKg * pricePerKg;

  Map<String, dynamic> toMap() => {
        'listing_id': listingId,
        'crop_name': cropName,
        'variety': variety,
        'price_per_kg': pricePerKg,
        'photo_url': photoUrl,
        'available_kg_snapshot': availableKgSnapshot,
        'quantity_kg': quantityKg,
      };

  factory CartItemModel.fromMap(Map<dynamic, dynamic> map) {
    return CartItemModel(
      listingId: map['listing_id'] as String,
      cropName: map['crop_name'] as String,
      variety: map['variety'] as String?,
      pricePerKg: (map['price_per_kg'] as num).toDouble(),
      photoUrl: map['photo_url'] as String?,
      availableKgSnapshot: (map['available_kg_snapshot'] as num).toDouble(),
      quantityKg: (map['quantity_kg'] as num).toDouble(),
    );
  }
}
