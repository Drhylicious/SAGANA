import '../../core/l10n/localized_labels.dart';
import '../../core/utils/quantity_utils.dart';
import 'shelf_life_model.dart';

class HarvestModel {
  final String id;
  final String farmerId;
  final String cropId;
  final String cropName;
  final String cropCategory;
  final double quantityKg;

  /// The unit [quantityKg] is measured in (the field keeps its old name).
  final String unit;
  final String? variety;
  final String? batchNumber;
  final String? storageLocation;
  final DateTime harvestDate;
  final bool isSynced;
  final DateTime createdAt;

  /// 'self' (the Farmer recorded their own harvest) or 'program_received' (a cooperative program gave
  /// them this produce). A received record is not the Farmer's own production.
  final String sourceType;
  final String? sourceProgramId;

  /// The shelf life this harvest was given (days), from its own batch. Null
  /// when the crop had none, or the harvest has not synced yet.
  final int? shelfLifeDays;

  /// Quantity of this harvest reported as rotten (a loss), in [unit].
  final double spoiledKg;

  /// Everything that was left of this harvest was reported as rotten.
  final bool isLost;

  const HarvestModel({
    required this.id,
    required this.farmerId,
    required this.cropId,
    required this.cropName,
    required this.cropCategory,
    required this.quantityKg,
    this.unit = kDefaultUnit,
    this.variety,
    this.batchNumber,
    this.storageLocation,
    required this.harvestDate,
    required this.isSynced,
    required this.createdAt,
    this.sourceType = 'self',
    this.sourceProgramId,
    this.shelfLifeDays,
    this.spoiledKg = 0,
    this.isLost = false,
  });

  bool get isPending => !isSynced;
  bool get isReceivedFromProgram => sourceType == 'program_received';

  /// The batch number with its leading #, or a note when the database has not
  /// issued one yet (a harvest saved offline is numbered when it syncs).
  String get displayBatch => formatBatchNumber(batchNumber).isEmpty
      ? currentL10n().dlBatchWhenSynced
      : formatBatchNumber(batchNumber);

  String get displayQty {
    if (unit == kDefaultUnit && quantityKg >= 1000) {
      return '${formatQuantity(quantityKg / 1000)}t';
    }
    return formatQuantityUnit(quantityKg, unit);
  }

  factory HarvestModel.fromMap(Map<String, dynamic> map) {
    // The harvest's own batch and its shelf-life row, when the query embedded
    // them (inventory_batches(available_kg, reserved_kg, batch_shelf_life(*))).
    final batches = map['inventory_batches'];
    final batch = batches is List && batches.isNotEmpty
        ? batches.first
        : batches is Map
        ? batches
        : null;
    final shelf = batch is Map
        ? BatchShelfLife.fromEmbed(batch['batch_shelf_life'])
        : null;
    final left = batch is Map
        ? ((batch['available_kg'] as num?)?.toDouble() ?? 0) +
              ((batch['reserved_kg'] as num?)?.toDouble() ?? 0)
        : 0.0;
    final spoiled = shelf?.spoiledKg ?? 0;
    return HarvestModel(
      shelfLifeDays: shelf?.defaultDays ?? shelf?.days,
      spoiledKg: spoiled,
      isLost: spoiled > 0 && left <= 0,
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      cropId: map['crop_id'] as String,
      cropName: map['crop_name'] as String,
      cropCategory: map['crop_category'] as String? ?? 'Other',
      quantityKg: (map['quantity_kg'] as num).toDouble(),
      unit: unitOrDefault(map['unit'] as String?),
      variety: map['variety'] as String?,
      batchNumber: map['batch_number'] as String?,
      storageLocation: map['storage_location'] as String?,
      harvestDate: DateTime.parse(map['harvest_date'] as String),
      isSynced: map['is_synced'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
      sourceType: map['source_type'] as String? ?? 'self',
      sourceProgramId: map['source_program_id'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'farmer_id': farmerId,
      'crop_id': cropId,
      'crop_name': cropName,
      'crop_category': cropCategory,
      'quantity_kg': quantityKg,
      'unit': unit,
      'variety': variety,
      'batch_number': batchNumber,
      'storage_location': storageLocation,
      'harvest_date': harvestDate.toIso8601String(),
      'is_synced': isSynced,
      'created_at': createdAt.toIso8601String(),
      'source_type': sourceType,
      'source_program_id': sourceProgramId,
    };
  }
}

// ─── Harvest Stats ────────────────────────────────────────────────────────────

class HarvestStats {
  final int seasonCount;
  final int unsyncedCount;

  const HarvestStats({required this.seasonCount, required this.unsyncedCount});

  static const HarvestStats empty = HarvestStats(
    seasonCount: 0,
    unsyncedCount: 0,
  );
}

// ─── Harvest Filter ───────────────────────────────────────────────────────────

enum HarvestFilter { all, synced, pending, thisMonth }

extension HarvestFilterExt on HarvestFilter {
  String get label {
    switch (this) {
      case HarvestFilter.all:
        return 'All';
      case HarvestFilter.synced:
        return 'Synced';
      case HarvestFilter.pending:
        return 'Pending';
      case HarvestFilter.thisMonth:
        return 'This Month';
    }
  }

  bool matches(HarvestModel h) {
    switch (this) {
      case HarvestFilter.all:
        return true;
      case HarvestFilter.synced:
        return h.isSynced;
      case HarvestFilter.pending:
        return !h.isSynced;
      case HarvestFilter.thisMonth:
        final now = DateTime.now();
        return h.harvestDate.year == now.year &&
            h.harvestDate.month == now.month;
    }
  }
}
