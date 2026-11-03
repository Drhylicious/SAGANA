import '../../core/utils/quantity_utils.dart';

/// One request to change a published (approved) listing.
///
/// It holds the listing as it was when the request was made ([originalQuantity]
/// ...) and what the Farmer asks for ([proposedQuantity] ...). The listing itself
/// is untouched until a Manager / Officer approves. Quantities and prices are
/// decimals in the listing's own [unit] (the fields keep the database names).
///
/// The staff-only fields ([reviewedBy], [farmerName], [currentQuantity] ...) are
/// filled for the Manager / Officer; a Farmer's copy never carries the reviewer.
class ListingEditRequest {
  final String id;
  final String listingId;

  /// pending | approved | rejected | cancelled
  final String status;
  final String unit;

  final double originalQuantity;
  final double originalPrice;
  final String? originalDescription;
  final String? originalPhotoUrl;

  final double proposedQuantity;
  final double proposedPrice;
  final String proposedDescription;

  /// Null = the photo is not being changed.
  final String? proposedPhotoUrl;

  final String? reviewReason;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  // ── Staff only ──────────────────────────────────────────────────────────
  final String? reviewedBy;
  final String? reviewerName;
  final String farmerName;
  final String cropName;
  final String? variety;

  /// The listing as it is NOW (it may differ from the original if a Manager
  /// changed the price, or orders came in, since the request was made).
  final double? currentQuantity;
  final double? currentRemaining;
  final double? currentPrice;
  final String? currentDescription;
  final String? currentPhotoUrl;
  final String? listingStatus;

  /// Free quantity left on the listing's harvest batch.
  final double? batchAvailable;

  const ListingEditRequest({
    required this.id,
    required this.listingId,
    required this.status,
    this.unit = kDefaultUnit,
    required this.originalQuantity,
    required this.originalPrice,
    this.originalDescription,
    this.originalPhotoUrl,
    required this.proposedQuantity,
    required this.proposedPrice,
    required this.proposedDescription,
    this.proposedPhotoUrl,
    this.reviewReason,
    this.reviewedAt,
    required this.createdAt,
    this.reviewedBy,
    this.reviewerName,
    this.farmerName = '',
    this.cropName = '',
    this.variety,
    this.currentQuantity,
    this.currentRemaining,
    this.currentPrice,
    this.currentDescription,
    this.currentPhotoUrl,
    this.listingStatus,
    this.batchAvailable,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';

  /// What buyers have already ordered (current quantity minus what is left).
  double? get orderedSoFar => currentQuantity == null || currentRemaining == null
      ? null
      : roundQuantity(currentQuantity! - currentRemaining!);

  bool get changesQuantity => !_same(originalQuantity, proposedQuantity);
  bool get changesPrice => !_same(originalPrice, proposedPrice);
  bool get changesDescription =>
      (originalDescription ?? '').trim() != proposedDescription.trim();
  bool get changesPhoto => proposedPhotoUrl != null;

  /// The staff compare against what is published NOW; a Farmer-side copy has no
  /// current values and compares against the original.
  double get shownQuantity => currentQuantity ?? originalQuantity;
  double get shownPrice => currentPrice ?? originalPrice;
  String? get shownDescription => currentDescription ?? originalDescription;
  String? get shownPhotoUrl => currentPhotoUrl ?? originalPhotoUrl;

  static bool _same(double a, double b) => (a * 100).round() == (b * 100).round();

  static double _num(Object? v) => (v as num?)?.toDouble() ?? 0;
  static double? _numOrNull(Object? v) => (v as num?)?.toDouble();

  /// [map] is a listing_edit_requests row (staff), or one element of
  /// get_my_listing_edit_requests() (Farmer). [extra] adds the staff context.
  factory ListingEditRequest.fromMap(Map<String, dynamic> map, {Map<String, dynamic> extra = const {}}) {
    final m = {...map, ...extra};
    return ListingEditRequest(
      id: m['id'] as String,
      listingId: m['listing_id'] as String,
      status: m['status'] as String? ?? 'pending',
      unit: unitOrDefault(m['unit'] as String?),
      originalQuantity: _num(m['original_quantity']),
      originalPrice: _num(m['original_price']),
      originalDescription: m['original_description'] as String?,
      originalPhotoUrl: m['original_photo_url'] as String?,
      proposedQuantity: _num(m['proposed_quantity']),
      proposedPrice: _num(m['proposed_price']),
      proposedDescription: m['proposed_description'] as String? ?? '',
      proposedPhotoUrl: m['proposed_photo_url'] as String?,
      reviewReason: m['review_reason'] as String?,
      reviewedAt: m['reviewed_at'] == null
          ? null
          : DateTime.parse(m['reviewed_at'] as String).toLocal(),
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      reviewedBy: m['reviewed_by'] as String?,
      reviewerName: m['reviewer_name'] as String?,
      farmerName: m['farmer_name'] as String? ?? '',
      cropName: m['crop_name'] as String? ?? '',
      variety: m['variety'] as String?,
      currentQuantity: _numOrNull(m['current_quantity']),
      currentRemaining: _numOrNull(m['current_remaining']),
      currentPrice: _numOrNull(m['current_price']),
      currentDescription: m['current_description'] as String?,
      currentPhotoUrl: m['current_photo_url'] as String?,
      listingStatus: m['listing_status'] as String?,
      batchAvailable: _numOrNull(m['batch_available']),
    );
  }
}
