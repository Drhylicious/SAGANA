import '../../core/utils/quantity_utils.dart';

/// One item the Farmer can ask for: a loan-eligible item of the existing loan
/// catalog (loan_items_master -> cooperative_inventory), with the stock on hand
/// right now. Comes from the list_loanable_items() database function.
class LoanableItem {
  final String loanItemId;
  final String inventoryItemId;
  final String itemName;
  final String category;
  final String unit;
  final double unitPrice;
  final double quantityOnHand;
  final String? imageUrl;

  const LoanableItem({
    required this.loanItemId,
    required this.inventoryItemId,
    required this.itemName,
    required this.category,
    required this.unit,
    required this.unitPrice,
    required this.quantityOnHand,
    this.imageUrl,
  });

  /// Anything left to lend. An item with zero stock is shown but cannot be requested.
  bool get inStock => quantityOnHand > 0;

  /// More than the stock on hand is never allowed.
  bool allows(double quantity) => quantity > 0 && quantity <= quantityOnHand;

  factory LoanableItem.fromMap(Map<String, dynamic> map) => LoanableItem(
    loanItemId: map['loan_item_id'] as String,
    inventoryItemId: map['inventory_item_id'] as String,
    itemName: map['item_name'] as String,
    category: map['category'] as String? ?? '',
    unit: map['unit'] as String? ?? 'pc',
    unitPrice: (map['unit_price'] as num? ?? 0).toDouble(),
    quantityOnHand: (map['quantity_on_hand'] as num? ?? 0).toDouble(),
    imageUrl: map['image_url'] as String?,
  );
}

/// One line of a loan request (name, unit and price as they were when it was
/// made).
class LoanRequestItem {
  final String itemName;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double lineTotal;

  // Manager / Officer view only: the inventory item behind the line and the
  // stock on hand right now, so a decision is made against the real stock.
  final String? inventoryItemId;
  final double? stockOnHand;

  const LoanRequestItem({
    required this.itemName,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.inventoryItemId,
    this.stockOnHand,
  });

  String get label => '$itemName × ${formatQuantityUnit(quantity, unit)}';

  /// Stock on hand is known and is less than what was asked for.
  bool get shortOnStock => stockOnHand != null && stockOnHand! < quantity;

  LoanRequestItem withStock(double? stock) => LoanRequestItem(
    itemName: itemName,
    unit: unit,
    quantity: quantity,
    unitPrice: unitPrice,
    lineTotal: lineTotal,
    inventoryItemId: inventoryItemId,
    stockOnHand: stock,
  );

  factory LoanRequestItem.fromMap(Map<String, dynamic> map) => LoanRequestItem(
    itemName: map['item_name'] as String,
    unit: map['unit'] as String? ?? 'pc',
    quantity: (map['quantity'] as num).toDouble(),
    unitPrice: (map['unit_price'] as num? ?? 0).toDouble(),
    lineTotal: (map['line_total'] as num? ?? 0).toDouble(),
    inventoryItemId: map['inventory_item_id'] as String?,
  );
}

/// A Farmer's request for a loan of inputs, and what the Cooperative decided.
///
/// Stored statuses: `pending` (waiting for a Manager / Officer), `approved`
/// (the loan was issued; see [loanReference]), `disapproved` (a reason is
/// always given) and `cancelled` (the Farmer withdrew it).
///
/// A Farmer's copy never carries who decided (staff identities do not reach a
/// Farmer): [reviewerName] is filled only for Manager / Officer.
class LoanRequestModel {
  final String id;
  final String requestNo;
  final String status;
  final double totalValue;
  final String? notes;
  final DateTime requestedAt;
  final DateTime? decidedAt;
  final String? decisionNote;

  /// The reference (LRN-...) of the loan issued when the request was approved.
  final String? loanReference;
  final List<LoanRequestItem> items;

  // Manager / Officer view only.
  final String? farmerId;
  final String? farmerName;
  final String? farmerPhone;
  final String? reviewerName;
  final String? loanId;

  const LoanRequestModel({
    required this.id,
    required this.requestNo,
    required this.status,
    required this.totalValue,
    this.notes,
    required this.requestedAt,
    this.decidedAt,
    this.decisionNote,
    this.loanReference,
    this.items = const [],
    this.farmerId,
    this.farmerName,
    this.farmerPhone,
    this.reviewerName,
    this.loanId,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isDisapproved => status == 'disapproved';
  bool get isCancelled => status == 'cancelled';

  /// Manager / Officer view: at least one line asks for more than is in stock now.
  bool get hasStockShortage => items.any((i) => i.shortOnStock);

  /// The Farmer's copy, from get_my_loan_requests().
  factory LoanRequestModel.fromFarmerJson(Map<String, dynamic> map) {
    return LoanRequestModel(
      id: map['id'] as String,
      requestNo: map['request_no'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      totalValue: (map['total_value'] as num? ?? 0).toDouble(),
      notes: map['notes'] as String?,
      requestedAt: DateTime.parse(map['requested_at'] as String).toLocal(),
      decidedAt: map['decided_at'] != null
          ? DateTime.parse(map['decided_at'] as String).toLocal()
          : null,
      decisionNote: map['decision_note'] as String?,
      loanReference: map['loan_reference'] as String?,
      items: [
        for (final i in (map['items'] as List? ?? const []))
          LoanRequestItem.fromMap(Map<String, dynamic>.from(i as Map)),
      ],
    );
  }

  /// The Manager / Officer's copy: a loan_requests row with its
  /// loan_request_items, plus the names resolved by the repository.
  factory LoanRequestModel.fromStaffRow(
    Map<String, dynamic> row, {
    String? farmerName,
    String? farmerPhone,
    String? reviewerName,
    String? loanReference,
  }) {
    return LoanRequestModel(
      id: row['id'] as String,
      requestNo: row['request_no'] as String? ?? '',
      status: row['status'] as String? ?? 'pending',
      totalValue: (row['total_value'] as num? ?? 0).toDouble(),
      notes: row['notes'] as String?,
      requestedAt: DateTime.parse(row['requested_at'] as String).toLocal(),
      decidedAt: row['reviewed_at'] != null
          ? DateTime.parse(row['reviewed_at'] as String).toLocal()
          : null,
      decisionNote: row['decision_note'] as String?,
      loanReference: loanReference,
      items: [
        for (final i in (row['loan_request_items'] as List? ?? const []))
          LoanRequestItem.fromMap(Map<String, dynamic>.from(i as Map)),
      ],
      farmerId: row['farmer_id'] as String?,
      farmerName: farmerName,
      farmerPhone: farmerPhone,
      reviewerName: reviewerName,
      loanId: row['loan_id'] as String?,
    );
  }
}
