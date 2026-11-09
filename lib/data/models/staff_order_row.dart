import '../../core/utils/listing_order.dart' show oldestFirst;
import '../../core/utils/order_status.dart';
import '../../core/utils/quantity_utils.dart';
import '../repositories/admin_order_repository.dart';
import 'program_model.dart';

/// One line of the staff order list. Marketplace orders and Cooperative Product orders are
/// different records in the database (and stay different there), but staff see one list.
class StaffOrderRow {
  /// kOrderSourceMarketplace | kOrderSourceCooperative
  final String source;
  final String id;
  final String reference;
  final String customerName;
  final String itemLabel;
  final String quantityLabel;
  final double total;

  /// The stored status. `delivered` is filed under Out for Delivery ([displayStatus]).
  final String status;
  final String fulfillmentMethod;
  final String paymentStatus;
  final DateTime createdAt;
  final String? programName;

  const StaffOrderRow({
    required this.source,
    required this.id,
    required this.reference,
    required this.customerName,
    required this.itemLabel,
    required this.quantityLabel,
    required this.total,
    required this.status,
    required this.fulfillmentMethod,
    required this.paymentStatus,
    required this.createdAt,
    this.programName,
  });

  bool get isCooperative => source == kOrderSourceCooperative;
  bool get isDelivery => fulfillmentMethod == 'delivery';

  /// The six staff statuses: a handed-over delivery counts as Out for Delivery.
  String get displayStatus => orderDisplayStatus(status);
  bool get awaitingConfirmation => isHandedOverAwaitingConfirmation(status);
  bool get needsAction =>
      orderNeedsStaffAction(status, paymentStatus: paymentStatus);

  factory StaffOrderRow.fromMarketplace(AdminOrderModel o) => StaffOrderRow(
    source: kOrderSourceMarketplace,
    id: o.id,
    reference: o.orderReference,
    customerName: o.buyerName,
    itemLabel: o.displayName,
    quantityLabel: formatQuantityUnit(o.quantityKg, o.unit),
    total: o.totalPrice,
    status: o.status,
    fulfillmentMethod: o.fulfillmentMethod ?? 'pickup',
    paymentStatus: o.paymentStatus,
    createdAt: o.createdAt,
  );

  factory StaffOrderRow.fromCooperative(ProgramPurchase p) => StaffOrderRow(
    source: kOrderSourceCooperative,
    id: p.id,
    reference: p.reference,
    customerName: p.farmerName,
    itemLabel: p.itemName,
    quantityLabel: formatQuantityUnit(p.quantity, p.unit),
    total: p.totalAmount,
    status: p.status,
    fulfillmentMethod: p.fulfillmentMethod,
    paymentStatus: p.paymentStatus,
    createdAt: p.requestedAt,
    programName: p.programName,
  );
}

/// Merges both engines into one list, newest first.
List<StaffOrderRow> mergeStaffOrders(
  Iterable<AdminOrderModel> marketplace,
  Iterable<ProgramPurchase> cooperative,
) {
  final rows = [
    for (final o in marketplace) StaffOrderRow.fromMarketplace(o),
    for (final p in cooperative) StaffOrderRow.fromCooperative(p),
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return rows;
}

/// Source filter for the list: null = both.
List<StaffOrderRow> filterStaffOrders(
  List<StaffOrderRow> rows, {
  String? source,
  String? status,
  String query = '',
}) {
  Iterable<StaffOrderRow> list = rows;
  if (source != null) list = list.where((r) => r.source == source);
  if (status == kOrderNeedsActionFilter) {
    list = list.where((r) => r.needsAction);
  } else if (status != null) {
    list = list.where((r) => r.displayStatus == status);
  }
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    list = list.where(
      (r) =>
          r.customerName.toLowerCase().contains(q) ||
          r.itemLabel.toLowerCase().contains(q) ||
          r.reference.toLowerCase().contains(q) ||
          (r.programName?.toLowerCase().contains(q) ?? false),
    );
  }
  final result = list.toList();
  // The two work queues (Pending, Needs Action) are oldest first: what has waited longest is
  // handled first. Every other view is newest first.
  if (status == kOrderNeedsActionFilter || status == 'pending') {
    return oldestFirst(result, (r) => r.createdAt);
  }
  return result;
}
