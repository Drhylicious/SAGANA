// Failed-program assistance (Phase 6). NOT a loan: it has its own records and
// never touches loan payments, due dates, overdue logic or loan totals.

class AssistanceItem {
  final String itemName;
  final String unit;
  final double quantity;

  const AssistanceItem({
    required this.itemName,
    required this.unit,
    required this.quantity,
  });

  factory AssistanceItem.fromMap(Map<String, dynamic> m) => AssistanceItem(
        itemName: m['item_name'] as String? ?? '',
        unit: m['unit'] as String? ?? '',
        quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
      );
}

class AssistanceRequest {
  final String id;

  /// LQR-YYYYMMDD-… (assigned when the request is made).
  final String requestNumber;

  /// LRN-YYYYMMDD-… (assigned only when it is approved).
  final String? assistanceReference;
  final String programMemberId;

  /// Staff rows only (the Farmer's own copy does not carry it).
  final String? farmerId;
  final String? programName;
  final String? farmerName;

  /// pending | approved | rejected | cancelled
  final String status;
  final String? message;

  /// What the Farmer sees when rejected; staff also see the note on approval.
  final String? reviewNote;
  final String? reviewedByName;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final List<AssistanceItem> items;

  const AssistanceRequest({
    required this.id,
    required this.requestNumber,
    required this.programMemberId,
    required this.status,
    required this.createdAt,
    this.farmerId,
    this.assistanceReference,
    this.programName,
    this.farmerName,
    this.message,
    this.reviewNote,
    this.reviewedByName,
    this.reviewedAt,
    this.items = const [],
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory AssistanceRequest.fromMap(
    Map<String, dynamic> m,
  ) => AssistanceRequest(
    id: m['id'] as String,
    requestNumber: m['request_number'] as String? ?? '',
    assistanceReference: m['assistance_reference'] as String?,
    programMemberId: m['program_member_id'] as String? ?? '',
    farmerId: m['farmer_id'] as String?,
    programName: m['program_name'] as String?,
    farmerName: m['farmer_name'] as String?,
    status: m['status'] as String? ?? 'pending',
    message: m['message'] as String?,
    // The Farmer's function names it rejection_reason; staff rows hold review_note.
    reviewNote: (m['rejection_reason'] ?? m['review_note']) as String?,
    reviewedByName: m['reviewed_by_name'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    reviewedAt: DateTime.tryParse(m['reviewed_at'] as String? ?? '')?.toLocal(),
    items: ((m['items'] as List?) ?? const [])
        .map((e) => AssistanceItem.fromMap((e as Map).cast<String, dynamic>()))
        .toList(),
  );
}

/// One of the Farmer's failed outcomes and whether it may ask for assistance.
class AssistanceOption {
  final String programMemberId;
  final String programName;

  /// null = may ask. Otherwise: not_eligible | pending | limit.
  final String? blocker;

  const AssistanceOption({
    required this.programMemberId,
    required this.programName,
    this.blocker,
  });

  bool get canRequest => blocker == null;

  factory AssistanceOption.fromMap(Map<String, dynamic> m) => AssistanceOption(
        programMemberId: m['program_member_id'] as String,
        programName: m['program_name'] as String? ?? '',
        blocker: m['blocker'] as String?,
      );
}
