class PriceRecordModel {
  final String id;
  final String cropId;
  final String cropName;
  final double price;
  final String unit;
  final String priceType; // 'sp3_cooperative' | 'open_market'
  final double? previousPrice;
  final DateTime recordedAt;
  final String? recordedBy;
  final String? source; // Reference document: Board Resolution, DA Bulletin, etc.
  // Referenced from crop_master via crop_id — Price Management never owns
  // or uploads this, only displays it. Null until the admin sets an image
  // on the crop in Crop Management.
  final String? cropImageUrl;

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
  });

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  bool get isUp => previousPrice != null && price > previousPrice!;
  bool get isDown => previousPrice != null && price < previousPrice!;

  double? get priceDifference =>
      previousPrice != null ? price - previousPrice! : null;

  String get formattedPrice => '₱${price.toStringAsFixed(2)}/$unit';

  String get priceTypeLabel {
    switch (priceType) {
      case 'sp3_cooperative':
        return 'Cooperative Market Price';
      case 'da_amad_market':
        return 'DA-AMAD Market Price';
      default:
        return 'Public Market Price';
    }
  }

  // ─── Serialization ───────────────────────────────────────────────────────────

  factory PriceRecordModel.fromMap(Map<String, dynamic> map) {
    return PriceRecordModel(
      id:            map['id'] as String,
      cropId:        map['crop_id'] as String? ?? '',
      cropName:      map['crop_name'] as String,
      price:         (map['price'] as num).toDouble(),
      unit:          map['unit'] as String? ?? 'kg',
      priceType:     map['price_type'] as String? ?? 'open_market',
      previousPrice: map['previous_price'] != null
          ? (map['previous_price'] as num).toDouble()
          : null,
      recordedAt:    DateTime.parse(map['recorded_at'] as String),
      recordedBy:    map['recorded_by'] as String?,
      source:        map['source'] as String?,
      // Present only when fetched via a query that embeds crop_master
      // (fetchLatestPricePerCrop) — absent (null) elsewhere, e.g. history.
      cropImageUrl:  (map['crop_master'] as Map<String, dynamic>?)?['image_url'] as String?,
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
    };
  }
}
