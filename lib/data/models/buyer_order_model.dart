import '../../core/utils/order_reference.dart';
import '../../core/utils/order_status.dart';
import '../../core/utils/quantity_utils.dart';
import 'farmer_crop_model.dart' show marketTypeLabelFor;

class BuyerOrderModel {
  final String id;

  /// The database-issued ORD-YYYYMMDD-XXXX number. Null for an order placed
  /// before order numbers existed (it keeps its old reference).
  final String? orderNumber;
  final String listingId;
  final String cropName;
  final String? variety;
  final String? listingPhotoUrl;
  final double quantityKg;
  final double pricePerKg;

  /// The unit quantityKg and pricePerKg are measured in (copied from the
  /// listing by the database; the fields keep their old names).
  final String unit;
  final double totalPrice;
  final String status; // pending | approved | ready_for_pickup | out_for_delivery | delivered | completed | cancelled
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

  // Fulfillment progress recorded by the Manager / Officer (null until it
  // happens). The delivery photo is the evidence uploaded with "Mark as Delivered".
  final DateTime? readyAt;
  final DateTime? outForDeliveryAt;
  final DateTime? deliveredAt;
  final String? deliveryPhotoUrl;
  final String? deliveryEvidenceNote;

  const BuyerOrderModel({
    required this.id,
    required this.listingId,
    required this.cropName,
    this.variety,
    this.orderNumber,
    this.listingPhotoUrl,
    required this.quantityKg,
    required this.pricePerKg,
    this.unit = kDefaultUnit,
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
    this.readyAt,
    this.outForDeliveryAt,
    this.deliveredAt,
    this.deliveryPhotoUrl,
    this.deliveryEvidenceNote,
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
  bool get isReadyForPickup => status == 'ready_for_pickup';
  bool get isOutForDelivery => status == 'out_for_delivery';
  bool get isDelivered => status == 'delivered';
  bool get isCompleted => status == 'completed';

  /// Receipt can be confirmed only when Ready for Pickup (pickup) or Delivered
  /// (delivery); the database refuses it at any other point.
  bool get canConfirmReceipt => canConfirmReceiptFor(status, fulfillmentMethod);
  bool get isCancelled => status == 'cancelled';

  /// The stored 'pending' is read as "Pending Order". There is no Disapproved
  /// state: an old stored 'rejected' arrives here already as 'cancelled'
  /// (see canonicalOrderStatus).
  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Pending Order';
      case 'approved':
        return 'Approved';
      case 'ready_for_pickup':
        return 'Ready for Pickup';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  /// What every screen shows: the stored order number, or for an older order
  /// the ORD-xxxxxxxx reference it always had (see order_reference.dart).
  String get orderReference => orderReferenceOf(id, orderNumber);

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

  static DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  factory BuyerOrderModel.fromMap(Map<String, dynamic> map) {
    return BuyerOrderModel(
      id: map['id'] as String,
      orderNumber: map['order_number'] as String?,
      listingId: map['listing_id'] as String,
      cropName: map['crop_name'] as String? ?? 'Produce',
      variety: map['variety'] as String?,
      listingPhotoUrl: map['photo_url'] as String?,
      quantityKg: (map['quantity_kg'] as num).toDouble(),
      pricePerKg: (map['price_per_kg'] as num).toDouble(),
      unit: unitOrDefault(map['unit'] as String?),
      totalPrice: (map['total_price'] as num).toDouble(),
      status: canonicalOrderStatus(map['status'] as String?),
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
      readyAt: _dt(map['ready_at']),
      outForDeliveryAt: _dt(map['out_for_delivery_at']),
      deliveredAt: _dt(map['delivered_at']),
      deliveryPhotoUrl: map['delivery_photo_url'] as String?,
      deliveryEvidenceNote: map['delivery_evidence_note'] as String?,
    );
  }
}