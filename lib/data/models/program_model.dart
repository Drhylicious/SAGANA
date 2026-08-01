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
      );

  bool get isActive => status == 'active';
  bool get isRevenueShare => benefitType == 'revenue_share';
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
  });

  bool get isDistributed => distributedAt != null;
  bool get isSettled => settledAt != null;

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
      );
}

class DistributionItem {
  final String id;
  final String itemName;
  final String unit;
  final double quantityOnHand;

  const DistributionItem({
    required this.id,
    required this.itemName,
    required this.unit,
    required this.quantityOnHand,
  });

  factory DistributionItem.fromMap(Map<String, dynamic> m) => DistributionItem(
        id: m['id'] as String,
        itemName: m['item_name'] as String,
        unit: m['unit'] as String,
        quantityOnHand: (m['quantity_on_hand'] as num).toDouble(),
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
