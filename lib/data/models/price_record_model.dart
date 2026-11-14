import '../services/market_types_service.dart';

class PriceRecordModel {
  final String id;
  final String cropId;
  final String cropName;
  final double price;
  final String unit;
  final String priceType; // a market_types.code (Public or Cooperative)
  final double? previousPrice;
  final DateTime recordedAt;
  final String? recordedBy;
  final String?
  source; // Reference document: Board Resolution, DA Bulletin, etc.
  // Referenced from crop_master via crop_id — Price Management never owns
  // or uploads this, only displays it. Null until the admin sets an image
  // on the crop in Crop Management.
  final String? cropImageUrl;
  // Also referenced from crop_master via crop_id — read-only display only,
  // same as cropImageUrl. Null when fetched via a query that doesn't embed
  // crop_master (e.g. history), or for a very old crop_id-less row.
  final String? cropCategory;

  /// How the Reference Price is configured: [modeFixed] (one Fixed Price, in
  /// [price]) or [modeRange] ([price] is the Minimum Reference Price and
  /// [priceMax] the Maximum). Records made before ranges existed are fixed.
  final String priceMode;
  final double? priceMax;

  static const String modeFixed = 'fixed';
  static const String modeRange = 'range';

  const PriceRecordModel({
    required this.id,
    required this.cropId,
    required this.cropName,
    required this.price,
    required this.unit,
    required this.priceType,
    this.previousPrice,
    required this.recordedAt,
    this.recordedBy,
    this.source,
    this.cropImageUrl,
    this.cropCategory,
    this.priceMode = modeFixed,
    this.priceMax,
  });

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  bool get isUp => previousPrice != null && price > previousPrice!;
  bool get isDown => previousPrice != null && price < previousPrice!;

  double? get priceDifference =>
      previousPrice != null ? price - previousPrice! : null;

  /// A Reference Price Range (a minimum and a maximum), not one Fixed Price.
  bool get isRange =>
      priceMode == modeRange && priceMax != null && priceMax! > price;

  /// The amount alone: "₱50.00", or "₱50.00–₱80.00" for a range.
  String get priceText => isRange
      ? '₱${price.toStringAsFixed(2)}–₱${priceMax!.toStringAsFixed(2)}'
      : '₱${price.toStringAsFixed(2)}';

  /// "₱50.00/kg", or "₱50.00–₱80.00/kg" for a range.
  String get formattedPrice => '$priceText/$unit';

  String get priceTypeLabel => '${MarketTypes.instance.label(priceType)} Price';

  // ─── Serialization ───────────────────────────────────────────────────────────

  factory PriceRecordModel.fromMap(Map<String, dynamic> map) {
    return PriceRecordModel(
      id:            map['id'] as String,
      cropId:        map['crop_id'] as String? ?? '',
      cropName:      map['crop_name'] as String,
      price:         (map['price'] as num).toDouble(),
      unit:          map['unit'] as String? ?? 'kg',
      priceType:     map['price_type'] as String? ?? (MarketTypes.instance.defaultCode ?? ''),
      previousPrice: map['previous_price'] != null
          ? (map['previous_price'] as num).toDouble()
          : null,
      recordedAt:    DateTime.parse(map['recorded_at'] as String),
      recordedBy:    map['recorded_by'] as String?,
      source:        map['source'] as String?,
      // Present only when fetched via a query that embeds crop_master
      // (fetchLatestPricePerCrop) — absent (null) elsewhere, e.g. history.
      cropImageUrl:
          (map['crop_master'] as Map<String, dynamic>?)?['image_url']
              as String?,
      cropCategory:
          (map['crop_master'] as Map<String, dynamic>?)?['category'] as String?,
      priceMode:     map['price_mode'] as String? ?? modeFixed,
      priceMax:      (map['price_max'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id':             id,
      'crop_id':        cropId,
      'crop_name':      cropName,
      'price':          price,
      'unit':           unit,
      'price_type':     priceType,
      'previous_price': previousPrice,
      'recorded_at':    recordedAt.toIso8601String(),
      'recorded_by':    recordedBy,
      'source':         source,
      'price_mode':     priceMode,
      'price_max':      priceMax,
    };
  }
}
