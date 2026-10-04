import 'farmer_crop_model.dart' show marketTypeLabelFor;

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
  final double
  remainingKg; // real-time unclaimed balance, per-order source of truth
  final double pricePerKg;
  final String? listingPhotoUrl;
  final String? description;
  final DateTime createdAt;

  // From the linked inventory_batches row (nullable — a listing can
  // exist without a linked batch).
  final double? availableKg; // real-time stock, independent of listing status
  final String? batchNumber; // detail screen only
  final DateTime? harvestDate; // detail screen only
  final String?
  marketType; // sp3_cooperative | da_amad_market | open_market — from inventory_batches.crop_type

  // From price_records — used for the market-range comparison badge.
  final double? marketRefPricePerKg;

  // From crop_master via crop_id (Phase D) — merges historical name
  // variants (e.g. "Rice (Palay)" vs "Palay") under one display name for
  // dedup/grouping contexts. Null when crop_id is missing or unresolved,
  // in which case callers should fall back to cropName (see
  // canonicalDisplayCropName below) rather than null-check everywhere.
  final String? canonicalCropName;

  // Owning farmer's user id — unused by the Buyer flow, added for the
  // Farmer-as-buyer Marketplace tab (Phase 9), which needs it for the
  // self-purchase guard (a farmer can see but not buy their own listing).
  final String? farmerId;

  // Cumulative completed kg sold for this specific listing, from the
  // marketplace_listing_units_sold view — not to be confused with
  // inventory_batches.sold_kg (a batch-wide counter shared across every
  // disposal channel) or volumeKg - remainingKg (includes pending/approved
  // orders, not just completed ones). Defaults to 0 when the view lookup
  // is unavailable or the listing has no completed orders yet.
  final double soldKg;

  const BuyerListingModel({
    required this.id,
    required this.cropName,
    this.variety,
    this.category,
    required this.volumeKg,
    required this.remainingKg,
    required this.pricePerKg,
    this.listingPhotoUrl,
    this.description,
    required this.createdAt,
    this.availableKg,
    this.batchNumber,
    this.harvestDate,
    this.marketType,
    this.marketRefPricePerKg,
    this.canonicalCropName,
    this.farmerId,
    this.soldKg = 0,
  });

  // ─── Computed helpers ─────────────────────────────────────────────────────

  String get displayName {
    // Previously built from the raw cropName directly, never consulting
    // canonicalCropName at all — so a listing under a merged/duplicate
    // catalog entry (e.g. "Rice (Palay)" instead of "Palay") displayed
    // the fragmented raw text everywhere this getter is used (this
    // screen's title, the order confirmation dialog, etc.), even though
    // canonicalDisplayCropName already existed and was correctly used
    // elsewhere (the price ticker). Same fix already applied to
    // MarketplaceListingModel's own displayName on the Farmer side.
    final name = canonicalDisplayCropName;
    final v = variety?.trim();
    if (v == null || v.isEmpty) return name;
    if (name.toLowerCase().contains(v.toLowerCase())) return name;
    return '$name ($v)';
  }

  /// Canonical crop name for dedup/grouping contexts (e.g. the price
  /// ticker), falling back to the listing's own cropName when no
  /// canonical mapping was resolved.
  String get canonicalDisplayCropName => canonicalCropName ?? cropName;

  /// remainingKg is the live per-listing balance that place_order() checks
  /// and decrements — it reflects real-time order activity in a way the
  /// batch-level availableKg no longer does now that ordering
  /// operates purely on the listing.
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

  String get marketTypeLabel => marketTypeLabelFor(marketType);

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
      remainingKg:
          (map['remaining_kg'] as num?)?.toDouble() ??
          (map['volume_kg'] as num).toDouble(),
      pricePerKg: (map['price_per_kg'] as num).toDouble(),
      listingPhotoUrl: map['photo_url'] as String?,
      description: map['description'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      availableKg: map['available_kg'] != null
          ? (map['available_kg'] as num).toDouble()
          : null,
      batchNumber: map['batch_number'] as String?,
      harvestDate: map['harvest_date'] != null
          ? DateTime.parse(map['harvest_date'] as String)
          : null,
      marketType: map['market_type'] as String?,
      marketRefPricePerKg: map['market_ref_price'] != null
          ? (map['market_ref_price'] as num).toDouble()
          : null,
      canonicalCropName: map['canonical_crop_name'] as String?,
      farmerId: map['farmer_id'] as String?,
      soldKg: (map['sold_kg'] as num?)?.toDouble() ?? 0,
    );
  }
}