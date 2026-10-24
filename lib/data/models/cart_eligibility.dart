import 'cart_item_model.dart';

/// Why a saved cart line can no longer be bought. [none] means it can.
enum CartIssue {
  none,

  /// The listing is in a market this account may not buy from (a Buyer's cart
  /// holding a farmer-only market item, from before the rule applied).
  restricted,

  /// The listing is gone, withdrawn, rejected or otherwise not for sale.
  unavailable,

  /// Approved, but nothing is left.
  soldOut,

  /// A Farmer's own listing: nobody may buy their own listing.
  ownListing,
}

/// Decides whether one saved cart line can still be checked out.
///
/// [listing] is the live row for the line's listing as this account can read
/// it (`id, status, remaining_kg, crop_type, farmer_id`), or null when no row
/// came back: the listing was removed, or the database hides it from this
/// account. [canSeeMarket] answers "may this account see items of that market
/// type?" (MarketTypes.visibleToCurrentUser in the app).
///
/// The database is still the final authority: place_order() and the order
/// trigger refuse the same cases. This only lets the app say so BEFORE a
/// buyer tries, with a clear reason.
CartIssue evaluateCartItem({
  required CartItemModel item,
  required Map<String, dynamic>? listing,
  required String? currentUserId,
  required bool Function(String? marketType) canSeeMarket,
}) {
  if (listing == null) {
    // Hidden by the database or removed: a hidden one is told apart by the
    // market type the cart line was saved with.
    return canSeeMarket(item.marketType)
        ? CartIssue.unavailable
        : CartIssue.restricted;
  }

  if (!canSeeMarket(listing['crop_type'] as String?)) {
    return CartIssue.restricted;
  }
  if ((listing['status'] as String?) != 'approved') {
    return CartIssue.unavailable;
  }
  if (currentUserId != null && listing['farmer_id'] == currentUserId) {
    return CartIssue.ownListing;
  }
  final remaining = (listing['remaining_kg'] as num?)?.toDouble() ?? 0;
  if (remaining <= 0) return CartIssue.soldOut;
  return CartIssue.none;
}
