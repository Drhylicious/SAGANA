import 'farmer_crop_model.dart' show marketTypeLabelFor;

class BuyerOrderModel {
  final String id;
  final String listingId;
  final String cropName;
  final String? variety;
  final String? listingPhotoUrl;
  final double quantityKg;
  final double pricePerKg;
  final double totalPrice;
  final String status; // pending | approved | completed | cancelled
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Detail-screen-only — populated by fetchOrderById(), left null by the
  // lighter-weight fetchMyOrders() list query to avoid an N+1 join cost
  // the list view has no use for.
  final String? batchNumber;
  final DateTime? harvestDate;
  final String? category;
  final String?
  marketType; // sp3_cooperative | da_amad_market | open_market — from inventory_batches.crop_type
  final String? description;

  // Fulfillment — set via set_order_fulfillment() once the order is
  // approved (Listing Tab redesign, Phase 6). All null until the buyer
  // makes a choice; delivery_* fields stay null for a pickup order.
  final String? fulfillmentMethod; // 'pickup' | 'delivery' | null
  final String? deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String? deliveryContactNumber;
  final String? deliveryNotes;
  final String? deliveryRecipientName;
  final String? deliveryLabel;

  const BuyerOrderModel({
    required this.id,
    required this.listingId,
    required this.cropName,
    this.variety,
    this.listingPhotoUrl,
    required this.quantityKg,
    required this.pricePerKg,
    required this.totalPrice,
    required this.status,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.batchNumber,
    this.harvestDate,
    this.category,
    this.marketType,
    this.description,
    this.fulfillmentMethod,
    this.deliveryAddress,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.deliveryContactNumber,
    this.deliveryNotes,
    this.deliveryRecipientName,
    this.deliveryLabel,
  });

  bool get hasFulfillmentChoice => fulfillmentMethod != null;
  bool get isDelivery => fulfillmentMethod == 'delivery';
  bool get isPickupChoice => fulfillmentMethod == 'pickup';

  String get displayName {
    final v = variety?.trim();
    if (v == null || v.isEmpty) return cropName;
    if (cropName.toLowerCase().contains(v.toLowerCase())) return cropName;
    return '$cropName ($v)';
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  /// Same display-label-vs-stored-value pattern as MarketplaceListingModel's
  /// pending_review → "Pending" convention — 'pending' is stored,
  /// "Pending Review" is what the buyer sees.
  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Pending Review';
      case 'approved':
        return 'Approved';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  /// Matches the LOAN-XXXXXXXX convention already established for
  /// farmer_loans.loan_reference — same auto-generated-reference idiom,
  /// applied to orders since orders has no equivalent stored column.
  String get orderReference => 'ORD-${id.substring(0, 8).toUpperCase()}';

  /// Relative "Harvested X days ago" label for the detail screen's
  /// freshness field. Empty when no harvest date is available (list view,
  /// or a listing with no linked inventory batch).
  String get harvestedLabel {
    if (harvestDate == null) return '';
    final diff = DateTime.now().difference(harvestDate!);
    if (diff.inDays <= 0) return 'Harvested today';
    if (diff.inDays == 1) return 'Harvested yesterday';
    return 'Harvested ${diff.inDays} days ago';
  }

  String get marketTypeLabel => marketTypeLabelFor(marketType);

  factory BuyerOrderModel.fromMap(Map<String, dynamic> map) {
    return BuyerOrderModel(
      id: map['id'] as String,
      listingId: map['listing_id'] as String,
      cropName: map['crop_name'] as String? ?? 'Produce',
      variety: map['variety'] as String?,
      listingPhotoUrl: map['photo_url'] as String?,
      quantityKg: (map['quantity_kg'] as num).toDouble(),
      pricePerKg: (map['price_per_kg'] as num).toDouble(),
      totalPrice: (map['total_price'] as num).toDouble(),
      status: map['status'] as String? ?? 'pending',
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      batchNumber: map['batch_number'] as String?,
      harvestDate: map['harvest_date'] != null
          ? DateTime.parse(map['harvest_date'] as String)
          : null,
      category: map['category'] as String?,
      marketType: map['market_type'] as String?,
      description: map['description'] as String?,
      fulfillmentMethod: map['fulfillment_method'] as String?,
      deliveryAddress: map['delivery_address'] as String?,
      deliveryLatitude: (map['delivery_latitude'] as num?)?.toDouble(),
      deliveryLongitude: (map['delivery_longitude'] as num?)?.toDouble(),
      deliveryContactNumber: map['delivery_contact_number'] as String?,
      deliveryNotes: map['delivery_notes'] as String?,
      deliveryRecipientName: map['delivery_recipient_name'] as String?,
      deliveryLabel: map['delivery_label'] as String?,
    );
  }
}