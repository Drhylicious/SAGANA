// ─── Program completion ──────────────────────────────────────────────────────
// What still stands between a program and "Completed", from
// get_programs_completion_status(). All counts zero = ready.

class ProgramCompletionStatus {
  final String programId;
  final int awaitingOutcome;
  final int openReturns;

  /// Failed outcomes whose latest cooperative decision is still "Pending Cooperative Decision".
  final int pendingDecisions;

  /// Failed outcomes marked "Eligible for Reassessment" whose second distribution has not started.
  final int openReassessments;

  /// Assistance requests from a Referred case that nobody has decided yet.
  final int pendingAssistanceRequests;

  /// Product Sales: orders still open (Pending, Approved, Ready for Pickup, Out for Delivery,
  /// or handed over and waiting for the member's confirmation).
  final int openOrders;

  /// Product Sales: products that still have stock set aside for the program.
  final int allocatedStock;

  const ProgramCompletionStatus({
    required this.programId,
    this.awaitingOutcome = 0,
    this.openReturns = 0,
    this.pendingDecisions = 0,
    this.openReassessments = 0,
    this.pendingAssistanceRequests = 0,
    this.openOrders = 0,
    this.allocatedStock = 0,
  });

  bool get isReady =>
      awaitingOutcome == 0 &&
      openReturns == 0 &&
      pendingDecisions == 0 &&
      openReassessments == 0 &&
      pendingAssistanceRequests == 0 &&
      openOrders == 0 &&
      allocatedStock == 0;

  factory ProgramCompletionStatus.fromMap(Map<String, dynamic> m) {
    final b = (m['blockers'] as Map?)?.cast<String, dynamic>() ?? const {};
    int n(String k) => (b[k] as num?)?.toInt() ?? 0;
    return ProgramCompletionStatus(
      programId: m['program_id'] as String,
      awaitingOutcome: n('awaiting_outcome'),
      openReturns: n('open_returns'),
      pendingDecisions: n('pending_decisions'),
      openReassessments: n('open_reassessments'),
      pendingAssistanceRequests: n('pending_assistance_requests'),
      openOrders: n('open_orders'),
      allocatedStock: n('allocated_stock'),
    );
  }
}

class CooperativeProgram {
  final String id;
  final String programName;
  final String programType;
  final String benefitType; // 'grant' | 'revenue_share'
  final String? description;
  final int seasonYear;
  final String status;
  final double? budget;
  final int memberCount;
  final double? expectedReturnPercent;
  // Which cooperative_inventory.category this program distributes from —
  // decoupled from programType (a free-text display label like "Peanut" or
  // "Livestock" that doesn't necessarily match an inventory category name).
  // Null for programs created before this field existed, or for programs
  // that intentionally distribute across any category.
  final String? distributionCategory;
  // 'distribution' (default — the existing benefit/loan-ROI workflow) or
  // 'sales' (the cooperative sells its own inventory products to enrolled
  // members via program_products/program_product_purchases — see
  // supabase_schema_program_product_sales.sql). Orthogonal to benefitType,
  // which answers "how does the member owe the coop back" — a question
  // that doesn't apply to a sale.
  final String programPurpose;
  final String? imageUrl;
  // The ONE inventory item a Distribution program hands out (Phase 5A).
  // Null on a legacy program = Incomplete: new distributions are blocked
  // (enforced in distribute_program_benefit(), not only in the UI).
  final String? distributionItemId;
  final String? distributionItemName;
  final String? distributionItemUnit;
  final double? distributionItemStock;
  // Harvest Return programs: what the cooperative expects back, set per
  // program by the cooperative — never a fixed quantity or a percentage.
  final String? returnCropId;
  final String? returnCropName;
  final double? returnQuantity;
  final String? returnUnit;
  // The DEFAULT Inventory item a Harvest Return Farmer returns (null = the item they were given). Each
  // member's own agreed return can differ; see [ProgramMember.returnItemId].
  final String? returnItemId;
  final String? returnItemName;
  final String? returnItemUnit;
  // Product Sales programs: percent off the regular price an ENROLLED member
  // pays (Balik-Tangkilik at the point of sale). Set per program; 0 = none.
  final double memberDiscountPercent;
  // Product Sales programs: the inventory categories products may be added from.
  final List<String> sourceCategories;
  // When the program was created (shown on the Program card as MM/DD/YY). Who created
  // it is kept in the Accountability Log, written by the database.
  final DateTime? createdAt;

  const CooperativeProgram({
    required this.id,
    required this.programName,
    required this.programType,
    required this.benefitType,
    this.description,
    required this.seasonYear,
    required this.status,
    this.budget,
    required this.memberCount,
    this.expectedReturnPercent,
    this.distributionCategory,
    this.programPurpose = 'distribution',
    this.imageUrl,
    this.distributionItemId,
    this.distributionItemName,
    this.distributionItemUnit,
    this.distributionItemStock,
    this.returnCropId,
    this.returnCropName,
    this.returnQuantity,
    this.returnUnit,
    this.returnItemId,
    this.returnItemName,
    this.returnItemUnit,
    this.memberDiscountPercent = 0,
    this.sourceCategories = const [],
    this.createdAt,
  });

  factory CooperativeProgram.fromMap(Map<String, dynamic> m) {
    final item = m['distribution_item'] as Map<String, dynamic>?;
    final crop = m['return_crop'] as Map<String, dynamic>?;
    return CooperativeProgram(
        id: m['id'] as String,
        programName: m['program_name'] as String,
        programType: m['program_type'] as String? ?? 'other',
        benefitType: m['benefit_type'] as String? ?? 'grant',
        description: m['description'] as String?,
        seasonYear: m['season_year'] as int? ?? DateTime.now().year,
        status: m['status'] as String? ?? 'active',
        budget: m['budget'] != null ? (m['budget'] as num).toDouble() : null,
        memberCount: m['member_count'] as int? ?? 0,
        expectedReturnPercent: m['expected_return_percent'] != null
            ? (m['expected_return_percent'] as num).toDouble()
            : null,
        distributionCategory: m['distribution_category'] as String?,
        programPurpose: m['program_purpose'] as String? ?? 'distribution',
        imageUrl: m['image_url'] as String?,
        distributionItemId: m['distribution_item_id'] as String?,
        distributionItemName: item?['item_name'] as String?,
        distributionItemUnit: item?['unit'] as String?,
        distributionItemStock: (item?['quantity_on_hand'] as num?)?.toDouble(),
        returnCropId: m['return_crop_id'] as String?,
        returnCropName: crop?['crop_name'] as String?,
        returnQuantity: (m['return_quantity'] as num?)?.toDouble(),
        returnUnit: m['return_unit'] as String?,
        returnItemId: m['return_item_id'] as String?,
        returnItemName: (m['return_item'] as Map?)?['item_name'] as String?,
        returnItemUnit: (m['return_item'] as Map?)?['unit'] as String?,
        memberDiscountPercent:
            (m['member_discount_percent'] as num?)?.toDouble() ?? 0,
        sourceCategories: ((m['source_categories'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(),
        createdAt: m['created_at'] != null
            ? DateTime.tryParse('${m['created_at']}')?.toLocal()
            : null,
      );
  }

  bool get isActive => status == 'active';
  // 'revenue_share' is the stored value; it now means a HARVEST RETURN (the
  // farmer returns harvested produce). The old money-percentage meaning is
  // retired — the stored value is kept so existing rows and RPCs still work.
  bool get isRevenueShare => benefitType == 'revenue_share';
  bool get isHarvestReturn => isRevenueShare;
  bool get isSalesProgram => programPurpose == 'sales';
  bool get hasMemberDiscount => isSalesProgram && memberDiscountPercent > 0;

  /// Required fields this program still lacks (Distribution and Product Sales).
  /// Mirrors program_missing_fields() in the database (keep the two in step).
  /// An Incomplete program is only labelled: a Sales program keeps selling.
  List<String> get missingFields => programMissingFields(
        purpose: programPurpose,
        name: programName,
        type: programType,
        imageUrl: imageUrl,
        description: description,
        budget: budget,
        distributionItemId: distributionItemId,
        isHarvestReturn: isHarvestReturn,
        returnQuantity: returnQuantity,
        sourceCount: sourceCategories.length,
      );

  bool get isIncomplete => missingFields.isNotEmpty;

  /// New distributions need a source: the program's categories (or, for an older
  /// program, its single configured item). Blocked until one is set.
  bool get canDistribute =>
      !isSalesProgram && (distributionItemId != null || sourceCategories.isNotEmpty);
}

/// The name each item shows in a pick list. Normally just the name ("Tomato").
/// Only when two or more items in the SAME list share a name (for example Tomato
/// from two different Farmers) is where it came from added in brackets, so they
/// can be told apart: "Tomato (Jhon Drhy M.)". A name that is unique stays plain.
/// When the same name is both Seeds & Seedlings and Harvested Produce (a crop item takes the crop's name),
/// the Item Type is what tells them apart: "Tomato · Seeds & Seedlings" ([typeLabel] words it).
Map<String, String> itemPickerNames(
  Iterable<DistributionItem> items, {
  String Function(String itemType)? typeLabel,
}) {
  String key(DistributionItem i) => i.itemName.trim().toLowerCase();
  final counts = <String, int>{};
  for (final i in items) {
    counts[key(i)] = (counts[key(i)] ?? 0) + 1;
  }
  String shortSource(String? s) {
    final t = (s ?? '').trim();
    return t.length > 18 ? '${t.substring(0, 17)}…' : t;
  }

  final typesByName = <String, Set<String>>{};
  for (final i in items) {
    (typesByName[key(i)] ??= <String>{}).add(i.itemType);
  }
  String name(DistributionItem i) {
    final shared = (counts[key(i)] ?? 0) > 1;
    final mixedTypes = (typesByName[key(i)]?.length ?? 0) > 1;
    final base = shared && shortSource(i.source).isNotEmpty
        ? '${i.itemName} (${shortSource(i.source)})'
        : i.displayName;
    return shared && mixedTypes && typeLabel != null
        ? '${i.itemName} · ${typeLabel(i.itemType)}'
        : base;
  }

  return {for (final i in items) i.id: name(i)};
}

/// The items a Product Sales program may sell: only those in a category the
/// program distributes from (none chosen = none). Case and spaces do not matter.
List<DistributionItem> itemsInSources(
  Iterable<DistributionItem> items,
  Iterable<String> sourceCategories,
) {
  final allowed = sourceCategories.map((c) => c.trim().toLowerCase()).toSet();
  if (allowed.isEmpty) return [];
  return items.where((i) => allowed.contains(i.category.trim().toLowerCase())).toList();
}

/// What an enrolled member pays per unit: the regular price less the program's
/// member discount, rounded to centavos. The database computes the real price
/// the same way when the purchase is requested; this lets the app show it first.
double memberUnitPrice(double regularPrice, double discountPercent) {
  final pct = discountPercent.clamp(0, 100).toDouble();
  return double.parse((regularPrice * (1 - pct / 100)).toStringAsFixed(2));
}

/// Whole calendar days since an item was received (0 = today). Counted from the date
/// alone, so it grows by one each day without anyone doing anything.
int daysSinceReceived(DateTime received, [DateTime? now]) {
  final n = now ?? DateTime.now();
  // The calendar day on the phone, not in UTC: a timestamp from the database is UTC, so near
  // midnight (Philippines, UTC+8) its UTC date is still yesterday and the count was a day short.
  final r = received.toLocal();
  final a = DateTime(r.year, r.month, r.day);
  final b = DateTime(n.year, n.month, n.day);
  final d = b.difference(a).inDays;
  return d < 0 ? 0 : d;
}

/// The latest reminder sent to a member to submit their outcome report (staff view only).
class ProgramReportReminder {
  final String programMemberId;
  final DateTime sentAt;
  final String? sentByRole; // admin | officer
  const ProgramReportReminder({required this.programMemberId, required this.sentAt, this.sentByRole});

  /// True when the reminder was sent today (local calendar day).
  bool isToday([DateTime? now]) {
    final n = now ?? DateTime.now();
    return sentAt.year == n.year && sentAt.month == n.month && sentAt.day == n.day;
  }

  /// The newest reminder per member from rows (program_member_id, created_at, sent_by_role).
  static Map<String, ProgramReportReminder> latest(Iterable<Map<String, dynamic>> rows) {
    final out = <String, ProgramReportReminder>{};
    for (final r in rows) {
      final id = r['program_member_id'] as String?;
      final at = DateTime.tryParse('${r['created_at']}')?.toLocal();
      if (id == null || at == null) continue;
      final cur = out[id];
      if (cur == null || at.isAfter(cur.sentAt)) {
        out[id] = ProgramReportReminder(programMemberId: id, sentAt: at, sentByRole: r['sent_by_role'] as String?);
      }
    }
    return out;
  }
}

/// One member's purchases in one Product Sales program, for the member card.
/// Orders are the ones not cancelled; spent and saved count paid purchases only (the
/// same rule patronage and reports use); pending are those still awaiting confirmation.
class MemberPurchaseSummary {
  final int orders;
  final double spent;
  final double saved;
  final int pending;
  const MemberPurchaseSummary({this.orders = 0, this.spent = 0, this.saved = 0, this.pending = 0});

  /// Groups purchase rows (farmer_id, status, total_amount, discount_amount) by Farmer.
  static Map<String, MemberPurchaseSummary> group(Iterable<Map<String, dynamic>> rows) {
    final out = <String, MemberPurchaseSummary>{};
    for (final r in rows) {
      final id = r['farmer_id'] as String?;
      if (id == null) continue;
      final status = r['status'] as String? ?? 'pending';
      final cur = out[id] ?? const MemberPurchaseSummary();
      final total = (r['total_amount'] as num?)?.toDouble() ?? 0;
      final disc = (r['discount_amount'] as num?)?.toDouble() ?? 0;
      out[id] = MemberPurchaseSummary(
        orders: cur.orders + (status == 'cancelled' ? 0 : 1),
        spent: cur.spent + (status == 'completed' ? total : 0),
        saved: cur.saved + (status == 'completed' ? disc : 0),
        pending: cur.pending + (status == 'pending' ? 1 : 0),
      );
    }
    return out;
  }
}

/// When a member asked to join a program and who approved it (the Member details view).
class MemberJoinInfo {
  final DateTime? requestedAt;
  final DateTime? reviewedAt;
  final String? reviewerName;
  final String? reviewerRole; // admin | officer

  const MemberJoinInfo({
    this.requestedAt,
    this.reviewedAt,
    this.reviewerName,
    this.reviewerRole,
  });
}

/// Pure so it can be unit-tested and shared by the form and the model.
List<String> programMissingFields({
  required String purpose,
  required String name,
  required String type,
  required String? imageUrl,
  required String? description,
  required double? budget,
  required String? distributionItemId,
  required bool isHarvestReturn,
  required double? returnQuantity,
  int sourceCount = 0,
}) {
  bool blank(String? v) => v == null || v.trim().isEmpty;
  return [
    if (blank(name)) 'name',
    if (blank(type)) 'type',
    if (blank(imageUrl)) 'photo',
    if (blank(description)) 'description',
    if (budget == null || budget <= 0) 'budget',
    // A Harvest Return quantity is agreed per Farmer when the item is distributed, not on the program.
    // Where it distributes from (inventory categories). An older Distribution
    // program that still has its single configured item counts until it is edited.
    if (sourceCount == 0 && (purpose == 'sales' || distributionItemId == null))
      'sources',
  ];
}

// ─── Program history (staff-only) ────────────────────────────────────────
// One row of get_program_history(): who did what, when. Worded in the app
// (English / Tagalog), not in the database.

class ProgramHistoryEntry {
  final DateTime at;
  final String type;
  final String? actorName;
  final String? actorRole; // admin | officer | farmer
  final String? subjectName;
  final Map<String, dynamic> details;

  const ProgramHistoryEntry({
    required this.at,
    required this.type,
    this.actorName,
    this.actorRole,
    this.subjectName,
    this.details = const {},
  });

  factory ProgramHistoryEntry.fromMap(Map<String, dynamic> m) =>
      ProgramHistoryEntry(
        at: DateTime.parse(m['out_at'] as String).toLocal(),
        type: m['out_type'] as String,
        actorName: m['out_actor'] as String?,
        actorRole: m['out_role'] as String?,
        subjectName: m['out_subject'] as String?,
        details:
            (m['out_details'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

// ─── Program Product (Cooperative Product Sales Program) ─────────────────
// A cooperative_inventory item made available for purchase through a
// 'sales'-purpose program — see program_products in
// supabase_schema_program_product_sales.sql. Thin join, same shape as
// DistributionItem below, plus the price/availability program_products
// itself owns.

class ProgramProduct {
  final String id;
  final String programId;
  final String inventoryItemId;
  final String itemName;
  final String category;
  final String unit;
  final double quantityOnHand;
  final double unitPrice;
  final bool isAvailable;
  final String? imageUrl;

  /// Stock set aside for this program ("stock for this program"). Protected: nothing else in
  /// the cooperative can take it, and a Farmer can only order from it.
  final double stockAllocated;

  /// Part of the allocation that open orders have already reserved.
  final double stockReserved;

  const ProgramProduct({
    required this.id,
    required this.programId,
    required this.inventoryItemId,
    required this.itemName,
    required this.category,
    required this.unit,
    required this.quantityOnHand,
    required this.unitPrice,
    required this.isAvailable,
    this.imageUrl,
    this.stockAllocated = 0,
    this.stockReserved = 0,
  });

  /// What a member can still order: the allocation not yet reserved by open orders.
  double get availableToSell => (stockAllocated - stockReserved).clamp(0, double.infinity).toDouble();

  factory ProgramProduct.fromMap(Map<String, dynamic> m) => ProgramProduct(
        id: m['id'] as String,
        programId: m['program_id'] as String,
        inventoryItemId: m['inventory_item_id'] as String,
        itemName: m['item_name'] as String? ?? '',
        category: m['category'] as String? ?? '',
        unit: m['unit'] as String? ?? '',
        quantityOnHand: (m['quantity_on_hand'] as num?)?.toDouble() ?? 0,
        unitPrice: (m['unit_price'] as num).toDouble(),
        isAvailable: m['is_available'] as bool? ?? true,
        imageUrl: m['image_url'] as String?,
        stockAllocated: (m['stock_allocated'] as num?)?.toDouble() ?? 0,
        stockReserved: (m['stock_reserved'] as num?)?.toDouble() ?? 0,
      );
}

// ─── Manage Products: state, order, filters and the sales figures ─────────

enum ProductFilter { all, onSale, outOfStock, off }

extension ProgramProductState on ProgramProduct {
  /// Nothing left to sell (whether or not it is switched on): no allocated stock is left
  /// for new orders.
  bool get isOutOfStock => availableToSell <= 0;
}

/// A product can be On Sale and Out of Stock at once, so these are filters, not stages.
bool productMatchesFilter(ProgramProduct p, ProductFilter f) => switch (f) {
      ProductFilter.all => true,
      ProductFilter.onSale => p.isAvailable,
      ProductFilter.outOfStock => p.isOutOfStock,
      ProductFilter.off => !p.isAvailable,
    };

/// 0 = on sale and in stock, 1 = on sale but out of stock, 2 = turned off.
int productSortRank(ProgramProduct p) => !p.isAvailable ? 2 : (p.isOutOfStock ? 1 : 0);

/// On sale first, then out of stock, then turned off; by name inside each.
List<ProgramProduct> sortProductsForDisplay(Iterable<ProgramProduct> products) {
  final list = products.toList();
  list.sort((a, b) {
    final r = productSortRank(a).compareTo(productSortRank(b));
    return r != 0 ? r : a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase());
  });
  return list;
}

/// The categories the products come from, A to Z. Used to group the list only when there
/// is more than one.
List<String> productCategories(Iterable<ProgramProduct> products) {
  final seen = <String, String>{};
  for (final p in products) {
    final c = p.category.trim();
    seen.putIfAbsent(c.toLowerCase(), () => c);
  }
  final out = seen.values.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return out;
}

/// What one product has sold (paid purchases only).
class ProductSales {
  final int buyers;
  final double sold;
  const ProductSales({this.buyers = 0, this.sold = 0});
}

/// The program's sales figures for the Manage Products cards, from one read of its
/// purchases. Paid purchases are the sales; pending ones are only counted.
class ProgramSalesSummary {
  final double totalSales;
  final double savings;
  final int buyers;
  final int pending;
  final Map<String, ProductSales> byProduct;
  const ProgramSalesSummary({
    this.totalSales = 0,
    this.savings = 0,
    this.buyers = 0,
    this.pending = 0,
    this.byProduct = const {},
  });

  /// Rows carry product_id, farmer_id, status, quantity, total_amount, discount_amount.
  static ProgramSalesSummary fromRows(Iterable<Map<String, dynamic>> rows) {
    var sales = 0.0;
    var saved = 0.0;
    var pending = 0;
    final buyers = <String>{};
    final soldBy = <String, double>{};
    final buyersBy = <String, Set<String>>{};
    for (final r in rows) {
      final status = r['status'] as String? ?? 'pending';
      if (status == 'pending') pending++;
      if (status != 'completed') continue;
      final farmer = r['farmer_id'] as String? ?? '';
      final product = r['product_id'] as String? ?? '';
      sales += (r['total_amount'] as num?)?.toDouble() ?? 0;
      saved += (r['discount_amount'] as num?)?.toDouble() ?? 0;
      buyers.add(farmer);
      soldBy[product] = (soldBy[product] ?? 0) + ((r['quantity'] as num?)?.toDouble() ?? 0);
      (buyersBy[product] ??= <String>{}).add(farmer);
    }
    return ProgramSalesSummary(
      totalSales: sales,
      savings: saved,
      buyers: buyers.length,
      pending: pending,
      byProduct: {
        for (final id in soldBy.keys)
          id: ProductSales(buyers: buyersBy[id]?.length ?? 0, sold: soldBy[id] ?? 0),
      },
    );
  }
}

/// What has been sold of a product in a Product Sales program: how many different
/// people bought it and the total quantity (paid purchases only).
class ProgramProductStats {
  final int buyers;
  final double quantitySold;
  const ProgramProductStats({this.buyers = 0, this.quantitySold = 0});

  factory ProgramProductStats.fromMap(Map<String, dynamic> m) => ProgramProductStats(
        buyers: (m['buyers'] as num?)?.toInt() ?? 0,
        quantitySold: (m['quantity_sold'] as num?)?.toDouble() ?? 0,
      );
}

/// A Farmer's request for another distribution after "Eligible for Reassessment" (staff can only approve it).
class RedistributionRequest {
  final String id;
  final String memberId;
  final String note;
  final DateTime? requestedAt;
  const RedistributionRequest({
    required this.id,
    required this.memberId,
    required this.note,
    this.requestedAt,
  });
}

/// An earlier, failed distribution of a Farmer who was then given another one (kept as history).
class EarlierRound {
  final String? itemName;
  final String? unit;
  final double? quantity;
  final DateTime? distributedAt;
  const EarlierRound({
    this.itemName,
    this.unit,
    this.quantity,
    this.distributedAt,
  });
}

class ProgramMember {
  final String id;
  final String programId;
  final String farmerId;
  final String farmerName;
  final String status;
  final DateTime enrolledAt;
  final String? inventoryItemId;
  final double? quantityGiven;
  final DateTime? distributedAt;
  // The item's name and unit at the moment it was given (the Inventory item's unit).
  final String? distributedItemName;
  final String? distributedUnit;
  // The agreed return for this member's item (set at distribution; Harvest Return programs only).
  final String? returnItemId;
  final double? returnQuantity;
  final double? amountReturned;
  final DateTime? settledAt;
  // Phase 8 / Issue 3's Loan/ROI workflow — the outcome check-in recorded
  // on a distributed benefit. Null/'pending' until an admin records it.
  final String? distributionOutcome; // null | 'pending' | 'thriving' | 'failed'
  final DateTime? outcomeRecordedAt;
  final String? convertedLoanId;
  // 1 for the first distribution; 2, 3... when the cooperative gave another item after a failed outcome.
  final int roundNo;
  // For a second (or later) round: the item the Farmer asked for again (the failed round's item).
  final String? requestedItemId;

  const ProgramMember({
    required this.id,
    required this.programId,
    required this.farmerId,
    required this.farmerName,
    required this.status,
    required this.enrolledAt,
    this.inventoryItemId,
    this.quantityGiven,
    this.distributedAt,
    this.distributedItemName,
    this.distributedUnit,
    this.returnItemId,
    this.returnQuantity,
    this.amountReturned,
    this.settledAt,
    this.distributionOutcome,
    this.outcomeRecordedAt,
    this.convertedLoanId,
    this.roundNo = 1,
    this.requestedItemId,
  });

  bool get isDistributed => distributedAt != null;
  bool get isSettled => settledAt != null;
  bool get isOutcomeRecorded => distributionOutcome == 'thriving' || distributionOutcome == 'failed';
  bool get isThriving => distributionOutcome == 'thriving';
  bool get isFailed => distributionOutcome == 'failed';

  factory ProgramMember.fromMap(Map<String, dynamic> m) => ProgramMember(
    id: m['id'] as String,
    programId: m['program_id'] as String,
    farmerId: m['farmer_id'] as String,
    farmerName: m['user_information']?['full_name'] as String? ?? 'Unknown',
    status: m['status'] as String? ?? 'active',
    enrolledAt: DateTime.parse(m['enrolled_at'] as String),
    inventoryItemId: m['inventory_item_id'] as String?,
    quantityGiven: m['quantity_given'] != null
        ? (m['quantity_given'] as num).toDouble()
        : null,
    distributedAt: m['distributed_at'] != null
        ? DateTime.parse(m['distributed_at'] as String)
        : null,
    distributedItemName: m['distributed_item_name'] as String?,
    distributedUnit: m['distributed_unit'] as String?,
    returnItemId: m['return_item_id'] as String?,
    returnQuantity: (m['return_quantity'] as num?)?.toDouble(),
    amountReturned: m['amount_returned'] != null
        ? (m['amount_returned'] as num).toDouble()
        : null,
    settledAt: m['settled_at'] != null
        ? DateTime.parse(m['settled_at'] as String)
        : null,
    distributionOutcome: m['distribution_outcome'] as String?,
    outcomeRecordedAt: m['outcome_recorded_at'] != null
        ? DateTime.parse(m['outcome_recorded_at'] as String)
        : null,
    convertedLoanId: m['converted_loan_id'] as String?,
    roundNo: (m['round_no'] as num?)?.toInt() ?? 1,
    requestedItemId: m['requested_item_id'] as String?,
  );
}

class DistributionItem {
  final String id;
  final String itemName;
  final String category;
  final String unit;
  final double quantityOnHand;
  // Phase 2: Farmer harvest items share a crop name across Farmers, so the
  // Farmer's name (stored in `source`) is what tells them apart.
  final String? source;
  final String? sourceFarmerId;
  // The item's type and (crop types) its Crop Master crop, from Inventory Management.
  final String itemType;
  final String? cropMasterId;
  // What comes back when a Farmer returns this item (Inventory's "When returned, it comes back as").
  final String? returnItemId;

  const DistributionItem({
    required this.id,
    required this.itemName,
    required this.category,
    required this.unit,
    required this.quantityOnHand,
    this.source,
    this.sourceFarmerId,
    this.itemType = 'non_crop',
    this.cropMasterId,
    this.returnItemId,
  });

  /// Just the item's name ("Tomato"), like every other inventory card. Where it
  /// came from is already recorded in Inventory, so it is not repeated here.
  String get displayName => itemName;

  factory DistributionItem.fromMap(Map<String, dynamic> m) => DistributionItem(
        id: m['id'] as String,
        itemName: m['item_name'] as String,
        category: m['category'] as String? ?? 'Agricultural Supplies',
        unit: m['unit'] as String,
        quantityOnHand: (m['quantity_on_hand'] as num).toDouble(),
        source: m['source'] as String?,
        sourceFarmerId: m['source_farmer_id'] as String?,
        itemType: m['item_type'] as String? ?? 'non_crop',
        cropMasterId: m['crop_master_id'] as String?,
        returnItemId: m['return_item_id'] as String?,
      );
}

// ─── Program Purchase (Cooperative Product Sales Program) ────────────────
// One farmer's purchase request for a program_product — see
// program_product_purchases in supabase_schema_program_product_sales.sql.
// status: pending | approved | ready_for_pickup | out_for_delivery | delivered | completed | cancelled.

class ProgramPurchase {
  final String id;
  final String programId;
  final String programName;
  final String productId;
  final String itemName;
  final String unit;
  final String farmerId;
  final String farmerName;
  final double quantity;
  final double unitPrice;
  final double totalAmount;
  final String status;
  final DateTime requestedAt;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final String? imageUrl;
  // Price snapshot taken when the purchase was requested (Phase 4). A purchase
  // made before member pricing existed has no snapshot: regularUnitPrice is
  // null and the price paid is simply unitPrice, with no discount.
  final double? regularUnitPrice;
  final double discountPercent;
  final double discountAmount;
  final bool isMemberPrice;

  // ── Order tracking (the unified Marketplace / Cooperative order flow) ──
  /// PSO-YYYYMMDD-A001. Null only for a row the database has not numbered.
  final String? orderNumber;
  final String fulfillmentMethod; // 'pickup' | 'delivery'
  final String? deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String? deliveryContact;
  final String? deliveryRecipient;
  final String? deliveryLabel;
  final String? deliveryNotes;
  final String? checkoutGroupId;
  final double deliveryFeeCollected;
  final String paymentStatus; // 'unpaid' | 'paid' | 'not_recorded'
  final DateTime? paidAt;
  final String? paymentRecordedByName;
  final String? paymentRecordedByRole;
  final double? amountCollected;
  final String? paymentNote;
  final String? completionMethod; // 'consumer' | 'staff' | null (older rows)
  final DateTime? approvedAt;
  final DateTime? readyAt;
  final DateTime? outForDeliveryAt;
  final DateTime? deliveredAt;
  final DateTime? completedAt;
  final String? handoverPhotoUrl;
  final String? handoverNote;
  final String? staffCompletionReason;
  final String? staffCompletionPhotoUrl;
  final String? staffCompletedByName;
  final String? staffCompletedByRole;
  final DateTime? staffCompletedAt;
  final String? cancelledByRole;
  final bool legacyMigrated;

  const ProgramPurchase({
    required this.id,
    required this.programId,
    required this.programName,
    required this.productId,
    required this.itemName,
    required this.unit,
    required this.farmerId,
    required this.farmerName,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    required this.status,
    required this.requestedAt,
    this.confirmedAt,
    this.cancelledAt,
    this.cancelReason,
    this.imageUrl,
    this.regularUnitPrice,
    this.discountPercent = 0,
    this.discountAmount = 0,
    this.isMemberPrice = false,
    this.orderNumber,
    this.fulfillmentMethod = 'pickup',
    this.deliveryAddress,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.deliveryContact,
    this.deliveryRecipient,
    this.deliveryLabel,
    this.deliveryNotes,
    this.checkoutGroupId,
    this.deliveryFeeCollected = 0,
    this.paymentStatus = 'unpaid',
    this.paidAt,
    this.paymentRecordedByName,
    this.paymentRecordedByRole,
    this.amountCollected,
    this.paymentNote,
    this.completionMethod,
    this.approvedAt,
    this.readyAt,
    this.outForDeliveryAt,
    this.deliveredAt,
    this.completedAt,
    this.handoverPhotoUrl,
    this.handoverNote,
    this.staffCompletionReason,
    this.staffCompletionPhotoUrl,
    this.staffCompletedByName,
    this.staffCompletedByRole,
    this.staffCompletedAt,
    this.cancelledByRole,
    this.legacyMigrated = false,
  });

  bool get isPending => status == 'pending';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  bool get isDelivery => fulfillmentMethod == 'delivery';
  bool get isPaymentRecorded => paymentStatus == 'paid';

  /// The reference shown to people: the PSO number, or a short id for an unnumbered row.
  String get reference =>
      orderNumber ?? 'PSO-${id.replaceAll('-', '').substring(0, 8).toUpperCase()}';

  /// Everything the consumer paid in cash: the items plus any delivery fee collected.
  double get cashCollected => amountCollected ?? totalAmount + deliveryFeeCollected;

  /// What the purchase would have cost at the regular price.
  double get regularTotal => (regularUnitPrice ?? unitPrice) * quantity;

  /// What was actually charged: regular total minus the member discount.
  double get netAmount => totalAmount;

  bool get hasDiscount => discountAmount > 0;

  factory ProgramPurchase.fromMap(Map<String, dynamic> m) => ProgramPurchase(
        id: m['id'] as String,
        programId: m['program_id'] as String,
        programName: m['program_name'] as String? ?? '',
        productId: m['product_id'] as String,
        itemName: m['item_name'] as String? ?? '',
        unit: m['unit'] as String? ?? '',
        farmerId: m['farmer_id'] as String,
        farmerName: m['farmer_name'] as String? ?? 'Unknown',
        quantity: (m['quantity'] as num).toDouble(),
        unitPrice: (m['unit_price'] as num).toDouble(),
        totalAmount: (m['total_amount'] as num).toDouble(),
        status: m['status'] as String? ?? 'pending',
        requestedAt: DateTime.parse(m['requested_at'] as String),
        confirmedAt: m['confirmed_at'] != null
            ? DateTime.parse(m['confirmed_at'] as String)
            : null,
        cancelledAt: m['cancelled_at'] != null
            ? DateTime.parse(m['cancelled_at'] as String)
            : null,
        cancelReason: m['cancel_reason'] as String?,
        imageUrl: m['image_url'] as String?,
        regularUnitPrice: (m['regular_unit_price'] as num?)?.toDouble(),
        discountPercent: (m['discount_percent'] as num?)?.toDouble() ?? 0,
        discountAmount: (m['discount_amount'] as num?)?.toDouble() ?? 0,
        isMemberPrice: m['is_member_price'] as bool? ?? false,
        orderNumber: m['order_number'] as String?,
        fulfillmentMethod: m['fulfillment_method'] as String? ?? 'pickup',
        deliveryAddress: m['delivery_address'] as String?,
        deliveryLatitude: (m['delivery_latitude'] as num?)?.toDouble(),
        deliveryLongitude: (m['delivery_longitude'] as num?)?.toDouble(),
        deliveryContact: m['delivery_contact'] as String?,
        deliveryRecipient: m['delivery_recipient'] as String?,
        deliveryLabel: m['delivery_label'] as String?,
        deliveryNotes: m['delivery_notes'] as String?,
        checkoutGroupId: m['checkout_group_id'] as String?,
        deliveryFeeCollected: (m['delivery_fee_collected'] as num?)?.toDouble() ?? 0,
        paymentStatus: m['payment_status'] as String? ?? 'unpaid',
        paidAt: _ppDate(m['paid_at']),
        paymentRecordedByName: m['payment_recorded_by_name'] as String?,
        paymentRecordedByRole: m['payment_recorded_by_role'] as String?,
        amountCollected: (m['amount_collected'] as num?)?.toDouble(),
        paymentNote: m['payment_note'] as String?,
        completionMethod: m['completion_method'] as String?,
        approvedAt: _ppDate(m['approved_at']),
        readyAt: _ppDate(m['ready_at']),
        outForDeliveryAt: _ppDate(m['out_for_delivery_at']),
        deliveredAt: _ppDate(m['delivered_at']),
        completedAt: _ppDate(m['completed_at']),
        handoverPhotoUrl: m['handover_photo_url'] as String?,
        handoverNote: m['handover_note'] as String?,
        staffCompletionReason: m['staff_completion_reason'] as String?,
        staffCompletionPhotoUrl: m['staff_completion_photo_url'] as String?,
        staffCompletedByName: m['staff_completed_by_name'] as String?,
        staffCompletedByRole: m['staff_completed_by_role'] as String?,
        staffCompletedAt: _ppDate(m['staff_completed_at']),
        cancelledByRole: m['cancelled_by_role'] as String?,
        legacyMigrated: m['legacy_migrated'] as bool? ?? false,
      );
}

DateTime? _ppDate(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
