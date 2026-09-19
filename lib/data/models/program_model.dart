// ─── Program Delete Impact ────────────────────────────────────────────────
// What deleting a program would cascade-delete, so the confirmation UI can
// warn with real numbers rather than a generic "are you sure?" — same
// pattern as CropDeleteImpact in crop_repository.dart.

class ProgramDeleteImpact {
  final int memberCount;
  final int distributedCount;
  /// True if the impact check itself failed — the UI should treat this as
  /// "assume there's data at risk" rather than "safe".
  final bool checkFailed;

  const ProgramDeleteImpact({
    required this.memberCount,
    required this.distributedCount,
    this.checkFailed = false,
  });

  bool get isRisky => checkFailed || memberCount > 0;
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
  });

  factory CooperativeProgram.fromMap(Map<String, dynamic> m) =>
      CooperativeProgram(
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
      );

  bool get isActive => status == 'active';
  bool get isRevenueShare => benefitType == 'revenue_share';
  bool get isSalesProgram => programPurpose == 'sales';
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
  });

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
      );
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
  final double? amountReturned;
  final DateTime? settledAt;
  // Phase 8 / Issue 3's Loan/ROI workflow — the outcome check-in recorded
  // on a distributed benefit. Null/'pending' until an admin records it.
  final String? distributionOutcome; // null | 'pending' | 'thriving' | 'failed'
  final DateTime? outcomeRecordedAt;
  final String? convertedLoanId;

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
    this.amountReturned,
    this.settledAt,
    this.distributionOutcome,
    this.outcomeRecordedAt,
    this.convertedLoanId,
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
        quantityGiven: m['quantity_given'] != null ? (m['quantity_given'] as num).toDouble() : null,
        distributedAt: m['distributed_at'] != null ? DateTime.parse(m['distributed_at'] as String) : null,
        amountReturned: m['amount_returned'] != null ? (m['amount_returned'] as num).toDouble() : null,
        settledAt: m['settled_at'] != null ? DateTime.parse(m['settled_at'] as String) : null,
        distributionOutcome: m['distribution_outcome'] as String?,
        outcomeRecordedAt: m['outcome_recorded_at'] != null
            ? DateTime.parse(m['outcome_recorded_at'] as String)
            : null,
        convertedLoanId: m['converted_loan_id'] as String?,
      );
}

class DistributionItem {
  final String id;
  final String itemName;
  final String category;
  final String unit;
  final double quantityOnHand;

  const DistributionItem({
    required this.id,
    required this.itemName,
    required this.category,
    required this.unit,
    required this.quantityOnHand,
  });

  factory DistributionItem.fromMap(Map<String, dynamic> m) => DistributionItem(
        id: m['id'] as String,
        itemName: m['item_name'] as String,
        category: m['category'] as String? ?? 'Agricultural Supplies',
        unit: m['unit'] as String,
        quantityOnHand: (m['quantity_on_hand'] as num).toDouble(),
      );
}

// ─── Program Purchase (Cooperative Product Sales Program) ────────────────
// One farmer's purchase request for a program_product — see
// program_product_purchases in supabase_schema_program_product_sales.sql.
// status: 'pending' (awaiting admin payment confirmation) | 'paid' | 'cancelled'.

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
  });

  bool get isPending => status == 'pending';

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
      );
}

class ProgramActivity {
  final String id;
  final String programId;
  final String title;
  final String? description;
  final DateTime activityDate;
  final String? location;

  const ProgramActivity({
    required this.id,
    required this.programId,
    required this.title,
    this.description,
    required this.activityDate,
    this.location,
  });

  factory ProgramActivity.fromMap(Map<String, dynamic> m) => ProgramActivity(
        id: m['id'] as String,
        programId: m['program_id'] as String,
        title: m['title'] as String,
        description: m['description'] as String?,
        activityDate: DateTime.parse(m['activity_date'] as String),
        location: m['location'] as String?,
      );
}
