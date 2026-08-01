class MarketplaceListingModel {
  final String id;
  final String farmerId;
  final String? inventoryBatchId;
  final String cropName;
  final String? variety;
  final double pricePerKg;
  final double volumeKg;
  final double remainingKg;
  final String
  status; // pending_review | approved | changes_required | withdrawn | sold | rejected
  final String? photoUrl;
  final String? adminNotes;
  final DateTime createdAt;
  final DateTime? submittedAt;
  final DateTime? updatedAt;

  const MarketplaceListingModel({
    required this.id,
    required this.farmerId,
    this.inventoryBatchId,
    required this.cropName,
    this.variety,
    required this.pricePerKg,
    required this.volumeKg,
    required this.remainingKg,
    required this.status,
    this.photoUrl,
    this.adminNotes,
    required this.createdAt,
    this.submittedAt,
    this.updatedAt,
  });

  bool get isPending => status == 'pending_review';
  bool get isLive => status == 'approved';
  bool get needsChanges => status == 'changes_required';
  bool get isWithdrawn => status == 'withdrawn';
  bool get isRejected => status == 'rejected';

  String get displayName => variety != null && variety!.isNotEmpty
      ? '$cropName ($variety)'
      : cropName;

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    return null;
  }

  factory MarketplaceListingModel.fromMap(Map<String, dynamic> map) {
    return MarketplaceListingModel(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      inventoryBatchId: map['inventory_batch_id'] as String?,
      cropName: map['crop_name'] as String,
      variety: map['variety'] as String?,
      pricePerKg: (map['price_per_kg'] as num).toDouble(),
      volumeKg: (map['volume_kg'] as num).toDouble(),
      // remaining_kg is the new single source of truth for buyer-order
      // availability (see supabase_schema_marketplace_order_reservation_fix.sql).
      // Falls back to volume_kg for any row/response that hasn't been
      // backfilled or doesn't select the column, so this stays safe even
      // before every call site is updated.
      remainingKg: (map['remaining_kg'] as num?)?.toDouble() ??
          (map['volume_kg'] as num).toDouble(),
      status: map['status'] as String? ?? 'pending_review',
      photoUrl: map['photo_url'] as String?,
      adminNotes: map['admin_notes'] as String?,
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
      submittedAt: _parseDateTime(map['submitted_at']),
      updatedAt: _parseDateTime(map['updated_at']),
    );
  }
}

// ─── Listing Filter ───────────────────────────────────────────────────────────

enum ListingFilter { all, pending, live, changesRequired, withdrawn }

extension ListingFilterExt on ListingFilter {
  String get label {
    switch (this) {
      case ListingFilter.all:
        return 'All';
      case ListingFilter.pending:
        return 'Pending Review';
      case ListingFilter.live:
        return 'Live on Market';
      case ListingFilter.changesRequired:
        return 'Changes Required';
      case ListingFilter.withdrawn:
        return 'Withdrawn';
    }
  }

  bool matches(MarketplaceListingModel listing) {
    switch (this) {
      case ListingFilter.all:
        return true;
      case ListingFilter.pending:
        return listing.isPending;
      case ListingFilter.live:
        return listing.isLive;
      case ListingFilter.changesRequired:
        return listing.needsChanges;
      case ListingFilter.withdrawn:
        return listing.isWithdrawn;
    }
  }
}