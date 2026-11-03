/// The one way a stored order status becomes the status the app works with.
///
/// SAGANA orders end in exactly one of two ways: a Buyer or Farmer **cancels**
/// their own pending order, or the Manager / Officer **approves** it and later
/// **completes** it. The Manager no longer disapproves ("rejects") an order.
///
/// Orders that were disapproved before that was removed still carry the stored
/// status `rejected`. Until they are converted (see
/// supabase_schema_remove_order_rejection.sql) every screen reads them as
/// `cancelled`, so no screen has a Disapproved state, chip or wording and no
/// old order disappears from a list. Their stock was already returned when they
/// were rejected, which is what cancelling does too.
String canonicalOrderStatus(String? stored) {
  if (stored == null || stored.isEmpty) return 'pending';
  return stored == 'rejected' ? 'cancelled' : stored;
}

/// Every stored order status, in the order a filter row lists them. An order
/// moves through these by fulfillment method:
///   pickup    pending -> approved -> ready_for_pickup -> completed
///   delivery  pending -> approved -> out_for_delivery -> delivered -> completed
/// (or cancelled by its consumer while still pending). There is no "preparing".
const List<String> kOrderStatuses = [
  'pending',
  'approved',
  'ready_for_pickup',
  'out_for_delivery',
  'delivered',
  'completed',
  'cancelled',
];

/// The statuses after approval and before completion: the order is committed
/// and being handed over.
bool isFulfillmentStatus(String status) =>
    status == 'approved' ||
    status == 'ready_for_pickup' ||
    status == 'out_for_delivery' ||
    status == 'delivered';

/// The consumer can confirm receipt only once the order is Ready for Pickup
/// (a pickup order) or Delivered (a delivery order). A missing method is pickup,
/// as in the database.
bool canConfirmReceiptFor(String status, String? fulfillmentMethod) {
  final method = fulfillmentMethod ?? 'pickup';
  return method == 'delivery'
      ? status == 'delivered'
      : status == 'ready_for_pickup';
}

/// What the Manager / Officer does next on an order, or null when nothing is
/// theirs to do (pending is approved elsewhere; ready / delivered wait for the
/// consumer; finished orders are done).
enum StaffOrderAction { readyForPickup, outForDelivery, markDelivered }

StaffOrderAction? nextStaffOrderAction(String status, String? fulfillmentMethod) {
  final method = fulfillmentMethod ?? 'pickup';
  if (status == 'approved') {
    return method == 'delivery'
        ? StaffOrderAction.outForDelivery
        : StaffOrderAction.readyForPickup;
  }
  if (status == 'out_for_delivery') return StaffOrderAction.markDelivered;
  return null;
}

/// The steps of an order's journey for a fulfillment method (stored statuses).
List<String> orderJourney(String? fulfillmentMethod) =>
    (fulfillmentMethod ?? 'pickup') == 'delivery'
    ? const ['pending', 'approved', 'out_for_delivery', 'delivered', 'completed']
    : const ['pending', 'approved', 'ready_for_pickup', 'completed'];

/// The Manager / Officer's "Needs Action" orders: Pending (to approve), Approved
/// (to mark Ready for Pickup or Out for Delivery) and Out for Delivery (to mark
/// Delivered with a photo). Orders that wait only for the consumer to confirm
/// receipt (Ready for Pickup, Delivered) are NOT included.
const List<String> kOrderNeedsActionStatuses = [
  'pending',
  'approved',
  'out_for_delivery',
];

/// The filter value the order list uses for the Needs Action group.
const String kOrderNeedsActionFilter = 'needs_action';

bool orderNeedsStaffAction(String status) =>
    kOrderNeedsActionStatuses.contains(status);
