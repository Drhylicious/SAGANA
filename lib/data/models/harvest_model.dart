class HarvestModel {
  final String id;
  final String farmerId;
  final String cropId;
  final String cropName;
  final String cropCategory;
  final double quantityKg;
  final String? variety;
  final String? batchNumber;
  final String? storageLocation;
  final String? notes;
  final DateTime harvestDate;
  final bool isSynced;
  final bool submittedToCooperative;
  final DateTime createdAt;

  const HarvestModel({
    required this.id,
    required this.farmerId,
    required this.cropId,
    required this.cropName,
    required this.cropCategory,
    required this.quantityKg,
    this.variety,
    this.batchNumber,
    this.storageLocation,
    this.notes,
    required this.harvestDate,
    required this.isSynced,
    required this.submittedToCooperative,
    required this.createdAt,
  });

  bool get isPending => !isSynced;

  String get displayBatch => batchNumber ?? '—';

  String get displayQty {
    if (quantityKg >= 1000) {
      return '${(quantityKg / 1000).toStringAsFixed(1)}t';
    }
    return '${quantityKg.toStringAsFixed(0)}kg';
  }

  factory HarvestModel.fromMap(Map<String, dynamic> map) {
    return HarvestModel(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      cropId: map['crop_id'] as String,
      cropName: map['crop_name'] as String,
      cropCategory: map['crop_category'] as String? ?? 'Other',
      quantityKg: (map['quantity_kg'] as num).toDouble(),
      variety: map['variety'] as String?,
      batchNumber: map['batch_number'] as String?,
      storageLocation: map['storage_location'] as String?,
      notes: map['notes'] as String?,
      harvestDate: DateTime.parse(map['harvest_date'] as String),
      isSynced: map['is_synced'] as bool? ?? false,
      submittedToCooperative:
          map['submitted_to_cooperative'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
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
      'variety': variety,
      'batch_number': batchNumber,
      'storage_location': storageLocation,
      'notes': notes,
      'harvest_date': harvestDate.toIso8601String(),
      'is_synced': isSynced,
      'submitted_to_cooperative': submittedToCooperative,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

// ─── Harvest Stats ────────────────────────────────────────────────────────────

class HarvestStats {
  final int seasonCount;
  final double totalYieldKg;
  final int unsyncedCount;

  const HarvestStats({
    required this.seasonCount,
    required this.totalYieldKg,
    required this.unsyncedCount,
  });

  static const HarvestStats empty = HarvestStats(
    seasonCount: 0,
    totalYieldKg: 0,
    unsyncedCount: 0,
  );
}

// ─── Harvest Filter ───────────────────────────────────────────────────────────

enum HarvestFilter { all, synced, pending, thisMonth }

extension HarvestFilterExt on HarvestFilter {
  String get label {
    switch (this) {
      case HarvestFilter.all: return 'All';
      case HarvestFilter.synced: return 'Synced';
      case HarvestFilter.pending: return 'Pending';
      case HarvestFilter.thisMonth: return 'This Month';
    }
  }

  bool matches(HarvestModel h) {
    switch (this) {
      case HarvestFilter.all: return true;
      case HarvestFilter.synced: return h.isSynced;
      case HarvestFilter.pending: return !h.isSynced;
      case HarvestFilter.thisMonth:
        final now = DateTime.now();
        return h.harvestDate.year == now.year &&
            h.harvestDate.month == now.month;
    }
  }
}
