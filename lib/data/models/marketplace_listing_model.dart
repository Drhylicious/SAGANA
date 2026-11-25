import '../../core/utils/quantity_utils.dart';
import 'shelf_life_model.dart';

class MarketplaceListingModel {
  final String id;
  final String farmerId;
  final String? inventoryBatchId;
  final String cropName;
  final String? variety;
  final double pricePerKg;
  final double volumeKg;
  final double remainingKg;

  /// The unit [volumeKg], [remainingKg] and [pricePerKg] are measured in. The
  /// fields keep their old names; the database copies it from the batch.
  final String unit;
  final String
  status; // pending_review | approved | withdrawn | sold | rejected
  final String? photoUrl;
  final String? description;
  final String? adminNotes;

  /// Canonical crop_master.crop_name, resolved server-side via crop_id —
  /// mirrors AdminListingModel's own field exactly. Null for a listing
  /// whose crop_id didn't resolve (e.g. a row predating the crop_id
  /// population fix, or a crop still pending admin approval at the time
  /// this listing was created) — displayName falls back to the raw
  /// cropName in that case.
  final String? canonicalCropName;
  final DateTime createdAt;
  final DateTime? submittedAt;
  final DateTime? updatedAt;

  /// Shelf-life state of this listing (unavailable / discounted). Only the
  /// owning Farmer's and the staff's queries carry it.
  final ListingShelfLife? shelfLife;

  /// Set when the cooperative changed the Reference Price Range and this open
  /// listing's price is now outside it: the range the Farmer must move into
  /// (through an edit submitted for approval). The listing stays available
  /// meanwhile. Null otherwise.
  final ListingPriceRule? priceUpdateRule;
  bool get priceUpdateRequired => priceUpdateRule != null;

  /// True when the cooperative's Reference Price Range changed and this
  /// listing's price was automatically adjusted to the new lower boundary,
  /// awaiting the Farmer's confirmation (accept or edit within the new range).
  final bool priceConfirmationRequired;
  final double? priceAdjustedFrom;

  const MarketplaceListingModel({
    required this.id,
    required this.farmerId,
    this.inventoryBatchId,
    required this.cropName,
    this.variety,
    required this.pricePerKg,
    required this.volumeKg,
    required this.remainingKg,
    this.unit = kDefaultUnit,
    required this.status,
    this.photoUrl,
    this.description,
    this.adminNotes,
    this.canonicalCropName,
    required this.createdAt,
    this.submittedAt,
    this.updatedAt,
    this.shelfLife,
    this.priceUpdateRule,
    this.priceConfirmationRequired = false,
    this.priceAdjustedFrom,
  });

  bool get isPending => status == 'pending_review';
  bool get isLive => status == 'approved';
  bool get isWithdrawn => status == 'withdrawn';
  bool get isRejected => status == 'rejected';
  bool get isSold => status == 'sold';

  /// Approved and still open for purchase (Available). An approved listing
  /// with nothing left is Sold Out instead; see [isSoldOut].
  bool get isAvailable =>
      status == 'approved' && remainingKg > 0 && !isShelfUnavailable;

  /// Published, but past its shelf life and not confirmed: hidden from Buyers
  /// until the Farmer confirms the produce and the cooperative approves.
  bool get isShelfUnavailable =>
      status == 'approved' &&
      remainingKg > 0 &&
      (shelfLife?.unavailable ?? false);

  /// Carries the automatic expiry-day discount while stock remains for sale.
  bool get isShelfDiscounted =>
      status == 'approved' &&
      remainingKg > 0 &&
      (shelfLife?.isDiscounted ?? false);

  /// Closed or marked rotten/lost when its harvest batch was reported rotten.
  bool get isShelfRotten => shelfLife?.isRotten ?? false;

  /// Visually disabled because the underlying harvest was recorded rotten/lost.
  bool get isUnavailableDueToRotten => isShelfRotten && remainingKg <= 0;

  /// Nothing left to buy: stored as sold, or approved with 0 kg remaining.
  bool get isSoldOut => status == 'sold' || (status == 'approved' && remainingKg <= 0);

  String get displayName {
    final name = canonicalCropName ?? cropName;
    final v = variety?.trim();
    if (v == null || v.isEmpty) return name;
    if (name.toLowerCase().contains(v.toLowerCase())) return name;
    return '$name ($v)';
  }

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
      remainingKg:
          (map['remaining_kg'] as num?)?.toDouble() ??
          (map['volume_kg'] as num).toDouble(),
      unit: unitOrDefault(map['unit'] as String?),
      status: map['status'] as String? ?? 'pending_review',
      photoUrl: map['photo_url'] as String?,
      description: map['description'] as String?,
      adminNotes: map['admin_notes'] as String?,
      canonicalCropName: map['canonical_crop_name'] as String?,
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
      submittedAt: _parseDateTime(map['submitted_at']),
      updatedAt: _parseDateTime(map['updated_at']),
      shelfLife: ListingShelfLife.fromEmbed(map['listing_shelf_life']),
      priceUpdateRule: ListingPriceRule.fromMap(map['price_update_rule']),
      priceConfirmationRequired:
          map['price_confirmation_required'] as bool? ??
          ((map['price_update_rule'] as Map?)?['price_confirmation_required']
                  as bool? ??
              false),
      priceAdjustedFrom:
          (map['price_adjusted_from'] as num?)?.toDouble() ??
          ((map['price_update_rule'] as Map?)?['price_adjusted_from'] as num?)
              ?.toDouble(),
    );
  }
}

// ─── Listing Filter ───────────────────────────────────────────────────────────

/// Farmer-side filter for My Listings. The chip names follow the shared
/// listing terminology (see listing_status_badge.dart): Pending Approval,
/// Available, Sold Out, Disapproved, Withdrawn.
enum ListingFilter {
  all,
  pending,
  available,

  /// Published but past its shelf life and not confirmed: hidden from Buyers.
  unavailable,
  soldOut,
  disapproved,
  withdrawn,
}

extension ListingFilterExt on ListingFilter {
  /// English fallback only; screens use listingFilterLabel() for the
  /// localized text.
  String get label {
    switch (this) {
      case ListingFilter.all:
        return 'All';
      case ListingFilter.pending:
        return 'Pending Approval';
      case ListingFilter.available:
        return 'Available';
      case ListingFilter.unavailable:
        return 'Unavailable';
      case ListingFilter.soldOut:
        return 'Sold Out';
      case ListingFilter.disapproved:
        return 'Disapproved';
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
      case ListingFilter.available:
        return listing.isAvailable;
      case ListingFilter.unavailable:
        return listing.isShelfUnavailable;
      case ListingFilter.soldOut:
        return listing.isSoldOut;
      case ListingFilter.disapproved:
        return listing.isRejected;
      case ListingFilter.withdrawn:
        return listing.isWithdrawn;
    }
  }
}
