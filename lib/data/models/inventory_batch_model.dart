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
  final String status; // available | reserved | sold_out | withdrawn | low_stock
  final bool isCoopEligible;
  final DateTime createdAt;
  final DateTime? harvestDate;

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
    required this.status,
    this.isCoopEligible = false,
    required this.createdAt,
    this.harvestDate,
  });

  double get stockPercent =>
      quantityKg > 0 ? (availableKg / quantityKg).clamp(0.0, 1.0) : 0.0;

  bool get isAvailable => status == 'available' || status == 'low_stock';
  bool get isReserved => status == 'reserved';
  bool get isSoldOut => status == 'sold_out';
  bool get isWithdrawn => status == 'withdrawn';

  factory InventoryBatchModel.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String) return DateTime.parse(value);
      return null;
    }

    DateTime? harvestDate;
    final harvestRecords = map['harvest_records'];
    if (harvestRecords is List && harvestRecords.isNotEmpty) {
      final first = harvestRecords.first;
      if (first is Map) {
        harvestDate = parseDate(first['harvest_date']);
      }
    } else if (harvestRecords is Map) {
      harvestDate = parseDate(harvestRecords['harvest_date']);
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
      status: map['status'] as String? ?? 'available',
      isCoopEligible: map['is_coop_eligible'] as bool? ?? false,
      createdAt: parseDate(map['created_at']) ?? DateTime.now(),
      harvestDate: harvestDate,
    );
  }
}