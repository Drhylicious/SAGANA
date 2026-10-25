/// The reference people see for an order.
///
/// New orders carry a database-issued number, `ORD-YYYYMMDD-XXXX` (for example
/// `ORD-20261024-A001`), stored in `orders.order_number`. Orders placed before
/// that existed have no number and keep the reference they always had, `ORD-`
/// plus the first 8 characters of the order id. Every screen that shows an
/// order reference goes through here, so they cannot disagree.
String orderReferenceOf(String orderId, String? orderNumber) {
  final number = orderNumber?.trim();
  if (number != null && number.isNotEmpty) return number;
  return legacyOrderReference(orderId);
}

/// The reference orders had before order numbers were stored.
String legacyOrderReference(String orderId) {
  final short = orderId.length >= 8 ? orderId.substring(0, 8) : orderId;
  return 'ORD-${short.toUpperCase()}';
}
