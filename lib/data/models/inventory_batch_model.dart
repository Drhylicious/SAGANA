import '../../core/utils/quantity_utils.dart';
import 'shelf_life_model.dart';

class InventoryBatchModel {
  final String id;
  final String farmerId;
  final String harvestRecordId;
  final String cropId;
  final String cropName;
  final String batchNumber;
  final double quantityKg;
  final double availableKg;
  final double reservedKg;
  final double soldKg;

  /// Quantity the Farmer took out with Update Quantity. available + reserved +
  /// sold + adjusted = quantityKg.
  final double adjustedKg;

  /// The unit every quantity on this batch is measured in (the *Kg fields keep
  /// their old names). Chosen at harvest and never changed.
  final String unit;
  final String
  status; // available | reserved | sold_out | withdrawn | low_stock
  final bool isCoopEligible;
  final String? cropType; // a market_types.code (Public or Cooperative)

  /// The one selling channel this batch's crop is reserved for, if any
  /// (inventory_batches.exclusive_channel, copied from the crop). Null for an
  /// ordinary crop, which can use Marketplace, Offer to Cooperative and
  /// Informal Sale. Set (DA-AMAD Market Linking) for Ginger only.
  final String? exclusiveChannel;
  /// The Farmer's own camera photo of this batch's crop, or null if they have
  /// not taken one (the Crop Master image is never used). Resolved by the
  /// repository via fetchFarmerCropImageMap(), since it needs a batched
  /// cross-table lookup this model has no access to on its own.
  final String? displayImageUrl;
  // From crop_master via crop_lookup.dart's fetchFarmerCropCategoryMap()
  // (Phase 11) — inventory_batches has no category column of its own.
  final String? category;
  final DateTime createdAt;
  final DateTime? harvestDate;
  // True only for produce a Cooperative Program gave the Farmer (its harvest entry is 'program_received').
  // A later harvest of the same crop is a separate batch and is never marked.
  final bool fromProgram;

  /// This batch's own shelf-life tracking (null when the crop has no shelf
  /// life set and no loss was reported). Farmer and staff only.
  final BatchShelfLife? shelfLife;

  const InventoryBatchModel({
    required this.id,
    required this.farmerId,
    required this.harvestRecordId,
    required this.cropId,
    required this.cropName,
    required this.batchNumber,
    required this.quantityKg,
    required this.availableKg,
    required this.reservedKg,
    required this.soldKg,
    this.adjustedKg = 0,
    this.unit = kDefaultUnit,
    required this.status,
    this.isCoopEligible = false,
    this.cropType,
    this.exclusiveChannel,
    this.displayImageUrl,
    this.category,
    required this.createdAt,
    this.harvestDate,
    this.fromProgram = false,
    this.shelfLife,
  });

  double get stockPercent =>
      quantityKg > 0 ? (availableKg / quantityKg).clamp(0.0, 1.0) : 0.0;

  /// Marketplace, Offer to Cooperative and Market Linking need this photo;
  /// an Informal Sale does not.
  bool get hasPhoto => displayImageUrl != null && displayImageUrl!.isNotEmpty;

  /// The same batch once its crop has a photo (after the Farmer takes one).
  InventoryBatchModel withPhoto(String url) => InventoryBatchModel(
    id: id,
    farmerId: farmerId,
    harvestRecordId: harvestRecordId,
    cropId: cropId,
    cropName: cropName,
    batchNumber: batchNumber,
    quantityKg: quantityKg,
    availableKg: availableKg,
    reservedKg: reservedKg,
    soldKg: soldKg,
    adjustedKg: adjustedKg,
    unit: unit,
    status: status,
    isCoopEligible: isCoopEligible,
    cropType: cropType,
    exclusiveChannel: exclusiveChannel,
    displayImageUrl: url,
    category: category,
    createdAt: createdAt,
    harvestDate: harvestDate,
    fromProgram: fromProgram,
    shelfLife: shelfLife,
  );

  bool get isAvailable => status == 'available' || status == 'low_stock';

  bool get isReserved => status == 'reserved';
  bool get isSoldOut => status == 'sold_out';
  bool get isWithdrawn => status == 'withdrawn';

  /// Part or all of this batch was reported as rotten (a loss).
  bool get hasLoss => (shelfLife?.spoiledKg ?? 0) > 0;

  /// Everything that was left was reported as rotten: nothing can be sold.
  bool get isLost => hasLoss && availableKg <= 0 && reservedKg <= 0;

  /// Recorded past its shelf life and not confirmed yet: no selling channel
  /// accepts it until the Farmer confirms the produce.
  bool get isOnShelfLifeHold => shelfLife?.hold ?? false;

  factory InventoryBatchModel.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String) return DateTime.parse(value);
      return null;
    }

    DateTime? harvestDate;
    var fromProgram = false;
    final harvestRecords = map['harvest_records'];
    if (harvestRecords is List && harvestRecords.isNotEmpty) {
      final first = harvestRecords.first;
      if (first is Map) {
        harvestDate = parseDate(first['harvest_date']);
        fromProgram = first['source_type'] == 'program_received';
      }
    } else if (harvestRecords is Map) {
      harvestDate = parseDate(harvestRecords['harvest_date']);
      fromProgram = harvestRecords['source_type'] == 'program_received';
    }

    return InventoryBatchModel(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      harvestRecordId: map['harvest_record_id'] as String,
      cropId: map['crop_id'] as String,
      cropName: map['crop_name'] as String,
      batchNumber: map['batch_number'] as String,
      quantityKg: (map['quantity_kg'] as num).toDouble(),
      availableKg: (map['available_kg'] as num).toDouble(),
      reservedKg: (map['reserved_kg'] as num).toDouble(),
      soldKg: (map['sold_kg'] as num).toDouble(),
      adjustedKg: (map['adjusted_kg'] as num?)?.toDouble() ?? 0,
      unit: unitOrDefault(map['unit'] as String?),
      status: map['status'] as String? ?? 'available',
      isCoopEligible: map['is_coop_eligible'] as bool? ?? false,
      cropType: map['crop_type'] as String?,
      exclusiveChannel: map['exclusive_channel'] as String?,
      displayImageUrl: map['display_image_url'] as String?,
      category: map['category'] as String?,
      createdAt: parseDate(map['created_at']) ?? DateTime.now(),
      harvestDate: harvestDate,
      fromProgram: fromProgram,
      shelfLife: BatchShelfLife.fromEmbed(map['batch_shelf_life']),
    );
  }
}