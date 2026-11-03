import 'quantity_utils.dart';

/// What is wrong with an edited listing, in the order the form checks it.
enum ListingEditProblem {
  /// Empty, not a number, zero, more than 2 decimals, or more than the stock
  /// the listing can grow to ([ListingEditResult] has no number then).
  quantity,

  /// A valid number, but not above what buyers have already ordered. The
  /// database refuses it too: an edit is never a way to close a listing.
  quantityNotAboveOrdered,

  /// Empty, not a number, zero, or more than 2 decimals.
  price,

  /// Blank. A listing always needs its description.
  description,
}

/// The checked values of an edit form, or the first [problem] found.
class ListingEditResult {
  final double? quantity;
  final double? price;
  final String? description;
  final ListingEditProblem? problem;

  const ListingEditResult._({
    this.quantity,
    this.price,
    this.description,
    this.problem,
  });

  bool get isValid => problem == null;
}

/// Checks the quantity, asking price and description typed in the edit form.
///
/// [orderedQuantity] is what buyers have already ordered (volume minus what is
/// left): the new quantity must stay above it. [maxQuantity] is the largest the
/// listing can become: its current quantity plus what its batch still has free.
/// Quantities and prices are decimals with at most 2 places, in the listing's
/// own unit: nothing is converted or rounded.
ListingEditResult checkListingEdit({
  required String? quantityText,
  required String? priceText,
  required String? description,
  required double orderedQuantity,
  double? maxQuantity,
}) {
  final quantity = parseDecimal(quantityText, max: maxQuantity ?? kMaxQuantity);
  if (quantity == null) {
    return const ListingEditResult._(problem: ListingEditProblem.quantity);
  }
  if (quantity <= orderedQuantity + 1e-9) {
    return const ListingEditResult._(
      problem: ListingEditProblem.quantityNotAboveOrdered,
    );
  }
  final price = parseDecimal(priceText);
  if (price == null) {
    return const ListingEditResult._(problem: ListingEditProblem.price);
  }
  final text = description?.trim() ?? '';
  if (text.isEmpty) {
    return const ListingEditResult._(problem: ListingEditProblem.description);
  }
  return ListingEditResult._(quantity: quantity, price: price, description: text);
}

/// True when the form holds something different from the listing as it is now.
/// Compared as centavos / hundredths so 12.5 and 12.50 are the same value.
bool listingEditChanged({
  required double quantity,
  required double price,
  required String description,
  required double currentQuantity,
  required double currentPrice,
  required String? currentDescription,
  bool newPhoto = false,
}) {
  int hundredths(double v) => (v * 100).round();
  return newPhoto ||
      hundredths(quantity) != hundredths(currentQuantity) ||
      hundredths(price) != hundredths(currentPrice) ||
      description.trim() != (currentDescription ?? '').trim();
}
