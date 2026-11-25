// Shelf-life data of a harvest batch and of a Marketplace listing.
//
// Both come from tables only the owning Farmer and the staff can read
// (batch_shelf_life / listing_shelf_life, see
// supabase_schema_shelf_life_s01_foundation.sql). A Buyer's queries never
// return them, so nothing here can reach a Buyer screen.

/// Where a tracked batch stands against its shelf life.
enum ShelfLifeStage {
  /// The crop has no shelf life set, so the batch is not monitored.
  untracked,

  /// More than one day left.
  fresh,

  /// One day left: the Farmer is asked to check the produce.
  nearExpiry,

  /// The shelf life ends today.
  expiresToday,

  /// Past its shelf life and not confirmed again.
  expired,

  /// Recorded when its shelf life had already passed: it cannot be sold through
  /// any channel until the Farmer confirms it.
  hold,
}

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

/// PostgREST returns a one-to-one embed as an object, and as a list on older
/// schema caches. Either way this is the one row (or null).
Map<String, dynamic>? _embedded(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is List && v.isNotEmpty && v.first is Map) {
    return Map<String, dynamic>.from(v.first as Map);
  }
  return null;
}

class BatchShelfLife {
  /// The crop's default when the harvest was recorded.
  final int? defaultDays;

  /// The duration now in effect, counted from [startsOn] (the harvest date, or
  /// the day the Farmer last confirmed the produce).
  final int? days;
  final DateTime? startsOn;
  final DateTime? expiresOn;
  final bool hold;
  final DateTime? confirmedAt;

  /// Quantity the Farmer reported as rotten (a loss), in the batch's unit.
  final double spoiledKg;
  final DateTime? spoiledAt;

  const BatchShelfLife({
    this.defaultDays,
    this.days,
    this.startsOn,
    this.expiresOn,
    this.hold = false,
    this.confirmedAt,
    this.spoiledKg = 0,
    this.spoiledAt,
  });

  bool get isTracked => expiresOn != null;
  bool get hasLoss => spoiledKg > 0;

  /// The Farmer changed the duration after checking the produce.
  bool get isAdjusted => confirmedAt != null && days != null && days != defaultDays;

  /// Whole days until the expiry date (0 = today, negative = past). Null when
  /// the batch is not tracked.
  int? get daysLeft {
    final e = expiresOn;
    if (e == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(e.year, e.month, e.day).difference(today).inDays;
  }

  ShelfLifeStage get stage {
    final left = daysLeft;
    if (left == null) return ShelfLifeStage.untracked;
    if (hold) return ShelfLifeStage.hold;
    if (left < 0) return ShelfLifeStage.expired;
    if (left == 0) return ShelfLifeStage.expiresToday;
    if (left == 1) return ShelfLifeStage.nearExpiry;
    return ShelfLifeStage.fresh;
  }

  /// The Farmer should check this batch now.
  bool get needsCheck =>
      stage == ShelfLifeStage.hold ||
      stage == ShelfLifeStage.expired ||
      stage == ShelfLifeStage.expiresToday ||
      stage == ShelfLifeStage.nearExpiry;

  /// Reads the `batch_shelf_life` embed of an inventory_batches row.
  static BatchShelfLife? fromEmbed(dynamic value) {
    final m = _embedded(value);
    if (m == null) return null;
    return BatchShelfLife(
      defaultDays: (m['default_days'] as num?)?.toInt(),
      days: (m['shelf_life_days'] as num?)?.toInt(),
      startsOn: _date(m['starts_on']),
      expiresOn: _date(m['expires_on']),
      hold: m['hold'] as bool? ?? false,
      confirmedAt: _date(m['confirmed_at']),
      spoiledKg: (m['spoiled_kg'] as num?)?.toDouble() ?? 0,
      spoiledAt: _date(m['spoiled_at']),
    );
  }
}

class ListingShelfLife {
  /// Past its shelf life and not confirmed: Buyers cannot see or buy it.
  final bool unavailable;

  /// The expiry date the automatic discount was applied for (null = none).
  final DateTime? discountAppliedOn;
  final double? discountPercent;
  final double? preDiscountPrice;

  /// Set when the batch behind this listing was finalized as Rotten/Lost.
  final DateTime? rottenAt;
  final double rottenKg;

  const ListingShelfLife({
    this.unavailable = false,
    this.discountAppliedOn,
    this.discountPercent,
    this.preDiscountPrice,
    this.rottenAt,
    this.rottenKg = 0,
  });

  bool get isDiscounted => discountAppliedOn != null;
  bool get isRotten => rottenAt != null;

  /// Reads the `listing_shelf_life` embed of a marketplace_listings row.
  static ListingShelfLife? fromEmbed(dynamic value) {
    final m = _embedded(value);
    if (m == null) return null;
    return ListingShelfLife(
      unavailable: m['unavailable'] as bool? ?? false,
      discountAppliedOn: _date(m['discount_applied_on']),
      discountPercent: (m['discount_percent'] as num?)?.toDouble(),
      preDiscountPrice: (m['pre_discount_price'] as num?)?.toDouble(),
      rottenAt: _date(m['rotten_at']),
      rottenKg: (m['rotten_kg'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// The Marketplace price rule of one harvest batch, from Price Management
/// (get_listing_price_rule). Null wherever there is no rule for the crop, or
/// the Reference Price is in another unit than the batch.
class ListingPriceRule {
  final bool isFixed;
  final double min;
  final double max;
  final String unit;

  /// Set while the listing carries the automatic shelf-life discount: the
  /// lowest price the Farmer may then keep (below the usual minimum).
  final double? discountedFloor;

  const ListingPriceRule({
    required this.isFixed,
    required this.min,
    required this.max,
    required this.unit,
    this.discountedFloor,
  });

  /// The lowest price accepted right now.
  double get lowest => discountedFloor != null && discountedFloor! < min
      ? discountedFloor!
      : min;

  /// The Farmer cannot type a price at all: it is the Fixed Price.
  bool get isLocked => isFixed && lowest == max;

  bool allows(double price) {
    final cents = (price * 100).round();
    return cents >= (lowest * 100).round() && cents <= (max * 100).round();
  }

  static ListingPriceRule? fromMap(dynamic value) {
    if (value is! Map) return null;
    final min = (value['price_min'] as num?)?.toDouble();
    final max = (value['price_max'] as num?)?.toDouble();
    if (min == null || max == null) return null;
    return ListingPriceRule(
      isFixed: value['mode'] != 'range',
      min: min,
      max: max,
      unit: value['unit'] as String? ?? 'kg',
      discountedFloor: (value['discounted_floor'] as num?)?.toDouble(),
    );
  }
}

/// One row of the shelf-life history (shelf_life_events), for the reports.
class ShelfLifeEvent {
  final String id;
  final String batchId;
  final String farmerId;
  final String eventType;
  final String cropName;
  final String batchNumber;
  final double quantity;
  final String unit;
  final int? days;
  final double? priceFrom;
  final double? priceTo;
  final String? note;
  final DateTime createdAt;

  const ShelfLifeEvent({
    required this.id,
    required this.batchId,
    required this.farmerId,
    required this.eventType,
    required this.cropName,
    required this.batchNumber,
    required this.quantity,
    required this.unit,
    this.days,
    this.priceFrom,
    this.priceTo,
    this.note,
    required this.createdAt,
  });

  bool get isLoss => eventType == 'reported_rotten';

  factory ShelfLifeEvent.fromMap(Map<String, dynamic> m) => ShelfLifeEvent(
    id: m['id'] as String,
    batchId: m['batch_id'] as String,
    farmerId: m['farmer_id'] as String,
    eventType: m['event_type'] as String? ?? '',
    cropName: m['crop_name'] as String? ?? '',
    batchNumber: m['batch_number'] as String? ?? '',
    quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
    unit: m['unit'] as String? ?? 'kg',
    days: (m['days'] as num?)?.toInt(),
    priceFrom: (m['price_from'] as num?)?.toDouble(),
    priceTo: (m['price_to'] as num?)?.toDouble(),
    note: m['note'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
  );
}
