/// Dedicated model for cooperative_purchase_offers, replacing the raw
/// Map<String, dynamic> the repository and screen both passed around before.
/// Status values in the database stay 'pending' / 'confirmed' / 'declined'
/// (matching the RPCs) — statusLabel below is purely a UI-wording layer,
/// per the explicit instruction to never say "Confirmed" or "Declined"
/// on screen. Keep that distinction: filter/query logic should always use
/// .status (the real value), never .statusLabel.
class CooperativeOfferModel {
  final String id;
  final String farmerId;
  final String farmerName;
  final String cropName;
  final double offeredQuantityKg;
  final DateTime offeredAt;
  final String? inventoryBatchId;
  final String status; // pending | confirmed | declined
  final double? confirmedQuantityKg;
  final double? confirmedAmount;
  final String? adminNotes;
  final DateTime? confirmedAt;

  // Detail-screen-only, same convention as AdminOrderModel — left null by
  // fetchOffers()'s list query, populated only by fetchOfferById().
  final String? farmerPhone;
  final String? farmerPhotoUrl;
  final String? batchNumber;
  final DateTime? harvestDate;
  final String? category;

  const CooperativeOfferModel({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    required this.cropName,
    required this.offeredQuantityKg,
    required this.offeredAt,
    this.inventoryBatchId,
    required this.status,
    this.confirmedQuantityKg,
    this.confirmedAmount,
    this.adminNotes,
    this.confirmedAt,
    this.farmerPhone,
    this.farmerPhotoUrl,
    this.batchNumber,
    this.harvestDate,
    this.category,
  });

  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed';
  bool get isDeclined => status == 'declined';

  /// UI-facing label only — matches Pending Review's wording exactly.
  /// Never use this for filtering or comparisons; use .status instead.
  String get statusLabel {
    switch (status) {
      case 'pending': return 'Pending';
      case 'confirmed': return 'Approved';
      case 'declined': return 'Rejected';
      default: return status;
    }
  }

  String get offeredLabel {
    final diff = DateTime.now().difference(offeredAt);
    if (diff.inDays <= 0) return 'Offered today';
    if (diff.inDays == 1) return 'Offered yesterday';
    return 'Offered ${diff.inDays} days ago';
  }

  String get harvestedLabel {
    if (harvestDate == null) return '';
    final diff = DateTime.now().difference(harvestDate!);
    if (diff.inDays <= 0) return 'Harvested today';
    if (diff.inDays == 1) return 'Harvested yesterday';
    return 'Harvested ${diff.inDays} days ago';
  }

  factory CooperativeOfferModel.fromMap(Map<String, dynamic> map) {
    return CooperativeOfferModel(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      farmerName: map['farmer_name'] as String? ?? 'Farmer',
      cropName: map['crop_name'] as String? ?? 'Produce',
      offeredQuantityKg: (map['offered_quantity_kg'] as num).toDouble(),
      offeredAt: DateTime.parse(map['offered_at'] as String),
      inventoryBatchId: map['inventory_batch_id'] as String?,
      status: map['status'] as String? ?? 'pending',
      confirmedQuantityKg: map['confirmed_quantity_kg'] != null
          ? (map['confirmed_quantity_kg'] as num).toDouble()
          : null,
      confirmedAmount: map['confirmed_amount'] != null
          ? (map['confirmed_amount'] as num).toDouble()
          : null,
      adminNotes: map['admin_notes'] as String?,
      confirmedAt: map['confirmed_at'] != null
          ? DateTime.parse(map['confirmed_at'] as String)
          : null,
      farmerPhone: map['farmer_phone'] as String?,
      farmerPhotoUrl: map['farmer_photo_url'] as String?,
      batchNumber: map['batch_number'] as String?,
      harvestDate: map['harvest_date'] != null
          ? DateTime.parse(map['harvest_date'] as String)
          : null,
      category: map['category'] as String?,
    );
  }
}
