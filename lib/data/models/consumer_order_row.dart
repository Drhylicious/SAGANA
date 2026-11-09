import '../../core/utils/order_status.dart';
import '../../core/utils/quantity_utils.dart';
import 'buyer_order_model.dart';
import 'program_model.dart';

/// One line of a Farmer's My Orders list. A Farmer buys from the Marketplace (orders) and from
/// the cooperative's own products (Cooperative orders); both are shown in the same list with a
/// source label, but stay separate records.
class ConsumerOrderRow {
  /// kOrderSourceMarketplace | kOrderSourceCooperative
  final String source;
  final String id;
  final String reference;
  final String title;
  final String? photoUrl;
  final String quantityLabel;
  final double total;
  final String status;
  final String? fulfillmentMethod;
  final String paymentStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Marketplace rows: the listing, for "Order again".
  final String? listingId;

  const ConsumerOrderRow({
    required this.source,
    required this.id,
    required this.reference,
    required this.title,
    this.photoUrl,
    required this.quantityLabel,
    required this.total,
    required this.status,
    this.fulfillmentMethod,
    this.paymentStatus = 'unpaid',
    required this.createdAt,
    required this.updatedAt,
    this.listingId,
  });

  bool get isCooperative => source == kOrderSourceCooperative;
  bool get hasFulfillmentChoice => fulfillmentMethod != null;
  bool get isDelivery => fulfillmentMethod == 'delivery';
  bool get isPickup => fulfillmentMethod == 'pickup';
  bool get isCancelled => status == 'cancelled';
  bool get isPaymentRecorded => paymentStatus == 'paid';

  /// Ready / delivered, so receipt could be confirmed, once the cooperative has recorded the cash.
  bool get canConfirmReceipt => canConfirmReceiptFor(
    status,
    fulfillmentMethod,
    paymentRecorded: isPaymentRecorded,
  );

  bool get isWaitingForPayment =>
      !isPaymentRecorded && canConfirmReceiptFor(status, fulfillmentMethod);

  factory ConsumerOrderRow.fromMarketplace(BuyerOrderModel o) =>
      ConsumerOrderRow(
        source: kOrderSourceMarketplace,
        id: o.id,
        reference: o.orderReference,
        title: o.displayName,
        photoUrl: o.listingPhotoUrl,
        quantityLabel: formatQuantityUnit(o.quantityKg, o.unit),
        total: o.totalPrice,
        status: o.status,
        fulfillmentMethod: o.fulfillmentMethod,
        paymentStatus: o.paymentStatus,
        createdAt: o.createdAt,
        updatedAt: o.updatedAt,
        listingId: o.listingId,
      );

  factory ConsumerOrderRow.fromCooperative(ProgramPurchase p) =>
      ConsumerOrderRow(
        source: kOrderSourceCooperative,
        id: p.id,
        reference: p.reference,
        title: p.itemName,
        photoUrl: p.imageUrl,
        quantityLabel: formatQuantityUnit(p.quantity, p.unit),
        total: p.totalAmount,
        status: p.status,
        fulfillmentMethod: p.fulfillmentMethod,
        paymentStatus: p.paymentStatus,
        createdAt: p.requestedAt,
        updatedAt: p.completedAt ?? p.cancelledAt ?? p.requestedAt,
      );
}

/// Both engines in one list, newest first.
List<ConsumerOrderRow> mergeConsumerOrders(
  Iterable<BuyerOrderModel> marketplace,
  Iterable<ProgramPurchase> cooperative,
) => [
  for (final o in marketplace) ConsumerOrderRow.fromMarketplace(o),
  for (final p in cooperative) ConsumerOrderRow.fromCooperative(p),
]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
