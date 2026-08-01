/// Buyer-facing view of a marketplace listing. Deliberately separate from
/// AdminListingModel — that model carries moderation-only fields
/// (adminNotes, farmer approval history, outstanding loan) that have no
/// business reaching buyer-facing UI. Same underlying `marketplace_listings`
/// row, different consuming context, genuinely different shape.
class BuyerListingModel {
  final String id;
  final String cropName;
  final String? variety;
  final String? category; // from crop_master, looked up client-side
  final double volumeKg; // quantity as listed by the farmer
  final double remainingKg; // real-time unclaimed balance, per-order source of truth
  final double pricePerKg;
  final String? listingPhotoUrl;
  final DateTime createdAt;

  // From the linked inventory_batches row (nullable — a listing can
  // exist without a linked batch).
  final String? qualityGrade;
  final double? availableKg; // real-time stock, independent of listing status
  final String? batchStatus; // available | low_stock | reserved | sold_out | withdrawn
  final String? batchNumber; // detail screen only
  final DateTime? harvestDate; // detail screen only

  // From price_records — used for the market-range comparison badge.
  final double? marketRefPricePerKg;

  const BuyerListingModel({
    required this.id,
    required this.cropName,
    this.variety,
    this.category,
    required this.volumeKg,
    required this.remainingKg,
    required this.pricePerKg,
    this.listingPhotoUrl,
    required this.createdAt,
    this.qualityGrade,
    this.availableKg,
    this.batchStatus,
    this.batchNumber,
    this.harvestDate,
    this.marketRefPricePerKg,
  });

  // ─── Computed helpers ─────────────────────────────────────────────────────

  String get displayName =>
      variety != null && variety!.isNotEmpty ? '$cropName ($variety)' : cropName;

  /// No linked batch at all — fall back to the listed volume as the
  /// orderable quantity, no grade/stock badge to show.
  bool get hasBatchInfo => batchStatus != null;

  /// remainingKg is the live per-listing balance that place_order() checks
  /// and decrements — it reflects real-time order activity in a way the
  /// batch-level availableKg/batchStatus no longer do now that ordering
  /// operates purely on the listing. Those batch fields stay on the model
  /// for context (quality grade, a withdrawn/rejected batch) but are no
  /// longer the source of truth for whether this listing can be ordered.
  bool get isOrderable => remainingKg > 0;

  bool get isSoldOut => remainingKg <= 0;

  bool get isLowStock => remainingKg > 0 && remainingKg < volumeKg * 0.15;

  /// Quantity to actually display/order against.
  double get displayAvailableKg => remainingKg;

  double? get priceDiffPercent =>
      marketRefPricePerKg != null && marketRefPricePerKg! > 0
          ? ((pricePerKg - marketRefPricePerKg!) / marketRefPricePerKg!) * 100
          : null;

  /// Same ±20% convention as AdminListingModel.isPriceWithinMarketRange —
  /// duplicated rather than shared, matching this codebase's existing
  /// tolerance for small label/getter duplication between role-specific
  /// models (see AdminListingModel's own displayName comment).
  bool get isPriceWithinMarketRange {
    final pct = priceDiffPercent;
    if (pct == null) return true; // no market ref — can't judge, don't warn
    return pct.abs() <= 20.0;
  }

  double get totalValueAtFullStock => remainingKg * pricePerKg;

  String get harvestedLabel {
    if (harvestDate == null) return '';
    final diff = DateTime.now().difference(harvestDate!);
    if (diff.inDays <= 0) return 'Harvested today';
    if (diff.inDays == 1) return 'Harvested yesterday';
    return 'Harvested ${diff.inDays} days ago';
  }

  factory BuyerListingModel.fromMap(Map<String, dynamic> map) {
    return BuyerListingModel(
      id: map['id'] as String,
      cropName: map['crop_name'] as String,
      variety: map['variety'] as String?,
      category: map['category'] as String?,
      volumeKg: (map['volume_kg'] as num).toDouble(),
      remainingKg: (map['remaining_kg'] as num?)?.toDouble() ??
          (map['volume_kg'] as num).toDouble(),
      pricePerKg: (map['price_per_kg'] as num).toDouble(),
      listingPhotoUrl: map['photo_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      qualityGrade: map['quality_grade'] as String?,
      availableKg: map['available_kg'] != null
          ? (map['available_kg'] as num).toDouble()
          : null,
      batchStatus: map['batch_status'] as String?,
      batchNumber: map['batch_number'] as String?,
      harvestDate: map['harvest_date'] != null
          ? DateTime.parse(map['harvest_date'] as String)
          : null,
      marketRefPricePerKg: map['market_ref_price'] != null
          ? (map['market_ref_price'] as num).toDouble()
          : null,
    );
  }
}