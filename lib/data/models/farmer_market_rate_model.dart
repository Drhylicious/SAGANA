import 'price_record_model.dart';

/// Farmer-facing wrapper around PriceRecordModel. Keeps PriceRecordModel
/// exactly as Admin already relies on it — the extra fields a farmer needs
/// (crop category, crop description, both sourced from crop_master) live
/// here instead, so no other screen that already depends on
/// PriceRecordModel's shape is affected by this addition.
class FarmerMarketRateModel {
  final PriceRecordModel price;
  final String cropCategory;   // crop_master.category — Grain/Legume/etc.
  final String? cropDescription; // crop_master.description — shown on Details only

  const FarmerMarketRateModel({
    required this.price,
    required this.cropCategory,
    this.cropDescription,
  });

  // Passthroughs so screens read `rate.cropName` / `rate.formattedPrice`
  // directly instead of reaching through `rate.price.x` everywhere — the
  // wrapper is plumbing, not something every call site should have to know.
  String get cropId => price.cropId;
  String get cropName => price.cropName;
  double get priceValue => price.price;
  String get unit => price.unit;
  String get priceType => price.priceType;
  String get priceTypeLabel => price.priceTypeLabel;
  DateTime get recordedAt => price.recordedAt;
  String? get source => price.source;
  bool get isUp => price.isUp;
  bool get isDown => price.isDown;
  String get formattedPrice => price.formattedPrice;

  factory FarmerMarketRateModel.fromMap(Map<String, dynamic> map) {
    // crop_master arrives as an embedded object under its own key since
    // price_records.crop_id -> crop_master.id is many-to-one.
    final cropMaster = map['crop_master'] as Map<String, dynamic>?;
    return FarmerMarketRateModel(
      price: PriceRecordModel.fromMap(map),
      cropCategory: cropMaster?['category'] as String? ?? 'Other',
      cropDescription: cropMaster?['description'] as String?,
    );
  }
}