import 'program_model.dart' show memberUnitPrice;

/// One Cooperative Product (a product of a Product Sales program) as a Farmer sees it in the
/// Marketplace: the product, its program, and the price THIS Farmer pays.
///
/// Only Farmers can see these (the database hides them from Buyers). The price shown here is
/// a preview: the database works out the real price when the order is placed.
class CooperativeProduct {
  final String productId;
  final String programId;
  final String programName;
  final String itemName;
  final String category;
  final String unit;
  final String? imageUrl;

  /// The program's price list price per unit.
  final double regularPrice;

  /// The discount enrolled members pay (0 = none).
  final double memberDiscountPercent;

  /// Whether this Farmer is an enrolled (active) member of the program.
  final bool isMember;

  /// What can still be ordered: the stock set aside for the program minus what open orders reserved.
  final double availableToSell;

  final int buyers;
  final double soldQuantity;

  const CooperativeProduct({
    required this.productId,
    required this.programId,
    required this.programName,
    required this.itemName,
    this.category = '',
    required this.unit,
    this.imageUrl,
    required this.regularPrice,
    this.memberDiscountPercent = 0,
    this.isMember = false,
    required this.availableToSell,
    this.buyers = 0,
    this.soldQuantity = 0,
  });

  /// The program has a member discount.
  bool get hasMemberDiscount => memberDiscountPercent > 0;

  /// The member price applies to this Farmer (enrolled, and the program has a discount).
  bool get memberPriceApplies => isMember && hasMemberDiscount;

  /// The member price per unit (what an enrolled member pays).
  double get memberPrice =>
      memberUnitPrice(regularPrice, memberDiscountPercent);

  /// What this Farmer pays per unit.
  double get payPrice => memberPriceApplies ? memberPrice : regularPrice;

  bool get isOutOfStock => availableToSell <= 0;

  CooperativeProduct copyWith({int? buyers, double? soldQuantity}) =>
      CooperativeProduct(
        productId: productId,
        programId: programId,
        programName: programName,
        itemName: itemName,
        category: category,
        unit: unit,
        imageUrl: imageUrl,
        regularPrice: regularPrice,
        memberDiscountPercent: memberDiscountPercent,
        isMember: isMember,
        availableToSell: availableToSell,
        buyers: buyers ?? this.buyers,
        soldQuantity: soldQuantity ?? this.soldQuantity,
      );

  /// [row] is a program_products row with its `cooperative_inventory` and
  /// `cooperative_programs` joined in. Null when it is not a product that can be bought now
  /// (switched off, or the program is not an active Product Sales program).
  static CooperativeProduct? fromRow(
    Map<String, dynamic> row, {
    required bool isMember,
  }) {
    if (row['is_available'] != true) return null;
    final program = row['cooperative_programs'] as Map<String, dynamic>?;
    if (program == null ||
        program['status'] != 'active' ||
        program['program_purpose'] != 'sales')
      return null;
    final inv = row['cooperative_inventory'] as Map<String, dynamic>?;
    final allocated = (row['stock_allocated'] as num?)?.toDouble() ?? 0;
    final reserved = (row['stock_reserved'] as num?)?.toDouble() ?? 0;
    return CooperativeProduct(
      productId: row['id'] as String,
      programId: row['program_id'] as String,
      programName: (program['program_name'] as String?) ?? '',
      itemName: (inv?['item_name'] as String?) ?? '',
      category: (inv?['category'] as String?) ?? '',
      unit: (inv?['unit'] as String?) ?? '',
      imageUrl: inv?['image_url'] as String?,
      regularPrice: (row['unit_price'] as num).toDouble(),
      memberDiscountPercent:
          (program['member_discount_percent'] as num?)?.toDouble() ?? 0,
      isMember: isMember,
      availableToSell: (allocated - reserved)
          .clamp(0, double.infinity)
          .toDouble(),
    );
  }
}

/// Why a saved Cooperative cart line can no longer be bought. [none] means it can.
enum CooperativeCartIssue { none, unavailable, soldOut }

/// Decides whether one saved Cooperative cart line can still be checked out. [row] is the live
/// program_products row (with its program) or null when it is gone or hidden from this account.
/// The database still decides at checkout; this only says so first, with a reason.
CooperativeCartIssue evaluateCooperativeCartLine(Map<String, dynamic>? row) {
  if (row == null) return CooperativeCartIssue.unavailable;
  final product = CooperativeProduct.fromRow(row, isMember: false);
  if (product == null) return CooperativeCartIssue.unavailable;
  if (product.isOutOfStock) return CooperativeCartIssue.soldOut;
  return CooperativeCartIssue.none;
}
