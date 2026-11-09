// Harvest Return and Failed-outcome resolutions (Proposal 12).
//
// A Successful outcome in a Harvest Return program opens a return: what is due,
// what the cooperative has actually received (partial receipts allowed), and the
// full history. A Failed outcome carries a resolution that staff record; it never
// changes another record and never blocks an assistance request.

/// The four resolutions for a Failed outcome. Stored as these exact values.
class FailedResolution {
  static const closedNoFurtherObligation = 'closed_no_further_obligation';
  static const eligibleForReassessment = 'eligible_for_reassessment';
  static const referredForLoanAssessment = 'referred_for_loan_assessment';
  static const pendingCooperativeDecision = 'pending_cooperative_decision';

  /// In the order they are offered. Pending is the default, not a decision.
  static const all = [
    closedNoFurtherObligation,
    eligibleForReassessment,
    referredForLoanAssessment,
    pendingCooperativeDecision,
  ];

  final String programMemberId;
  final String programId;
  final String resolution;
  final String? note;
  final String? decidedByName;
  final String? decidedByRole;
  final DateTime? decidedAt;
  final int historyCount;

  const FailedResolution({
    required this.programMemberId,
    required this.programId,
    required this.resolution,
    this.note,
    this.decidedByName,
    this.decidedByRole,
    this.decidedAt,
    this.historyCount = 1,
  });

  bool get isPending => resolution == pendingCooperativeDecision;

  factory FailedResolution.fromMap(Map<String, dynamic> m) => FailedResolution(
        programMemberId: m['program_member_id'] as String,
        programId: m['program_id'] as String,
        resolution: m['resolution'] as String? ?? pendingCooperativeDecision,
        note: m['note'] as String?,
        decidedByName: m['decided_by_name'] as String?,
        decidedByRole: m['decided_by_role'] as String?,
        decidedAt: DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal(),
        historyCount: (m['history_count'] as num?)?.toInt() ?? 1,
      );
}

class ProgramReturnReceipt {
  final String id;
  final double quantity;
  final String? note;
  final DateTime receivedAt;
  final String? recordedByName;

  const ProgramReturnReceipt({
    required this.id,
    required this.quantity,
    required this.receivedAt,
    this.note,
    this.recordedByName,
  });

  factory ProgramReturnReceipt.fromMap(Map<String, dynamic> m) => ProgramReturnReceipt(
        id: m['id'] as String,
        quantity: (m['quantity'] as num).toDouble(),
        note: m['note'] as String?,
        receivedAt: DateTime.parse(m['received_at'] as String).toLocal(),
        recordedByName: m['recorded_by_name'] as String?,
      );
}

class ProgramReturnEvent {
  /// created | adjusted | receipt | closed
  final String type;
  final double? quantityBefore;
  final double? quantityAfter;
  final double? quantity;
  final String? reason;
  final String? actorName;
  final String? actorRole;
  final DateTime at;

  const ProgramReturnEvent({
    required this.type,
    required this.at,
    this.quantityBefore,
    this.quantityAfter,
    this.quantity,
    this.reason,
    this.actorName,
    this.actorRole,
  });

  factory ProgramReturnEvent.fromMap(Map<String, dynamic> m) {
    double? d(String k) => (m[k] as num?)?.toDouble();
    return ProgramReturnEvent(
      type: m['event_type'] as String? ?? '',
      quantityBefore: d('quantity_before'),
      quantityAfter: d('quantity_after'),
      quantity: d('quantity'),
      reason: m['reason'] as String?,
      actorName: m['actor_name'] as String?,
      actorRole: m['actor_role'] as String?,
      at: DateTime.parse(m['created_at'] as String).toLocal(),
    );
  }
}

class ProgramReturn {
  final String id;
  final String programId;
  final String programMemberId;
  final String? programName;
  final String? farmerName;
  final String cropName;
  final String unit;
  final double originalQuantity;
  final double dueQuantity;
  final double receivedQuantity;

  /// pending | partial | received | closed_short
  final String status;
  final double? reportedQuantity;
  final double? verifiedQuantity;
  final bool underreportFlag;
  final String? closedReason;
  final List<ProgramReturnReceipt> receipts;
  final List<ProgramReturnEvent> events;

  const ProgramReturn({
    required this.id,
    required this.programId,
    required this.programMemberId,
    required this.cropName,
    required this.unit,
    required this.originalQuantity,
    required this.dueQuantity,
    required this.receivedQuantity,
    required this.status,
    this.programName,
    this.farmerName,
    this.reportedQuantity,
    this.verifiedQuantity,
    this.underreportFlag = false,
    this.closedReason,
    this.receipts = const [],
    this.events = const [],
  });

  bool get isOpen => status == 'pending' || status == 'partial';
  bool get wasAdjusted => dueQuantity != originalQuantity;
  double get remaining => (dueQuantity - receivedQuantity).clamp(0, double.infinity);

  factory ProgramReturn.fromMap(Map<String, dynamic> m) {
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) =>
        ((m[k] as List?) ?? const [])
            .map((e) => f((e as Map).cast<String, dynamic>()))
            .toList();
    double? d(String k) => (m[k] as num?)?.toDouble();
    return ProgramReturn(
      id: m['id'] as String,
      programId: m['program_id'] as String,
      programMemberId: m['program_member_id'] as String,
      programName: m['program_name'] as String?,
      farmerName: m['farmer_name'] as String?,
      cropName: m['crop_name'] as String? ?? '',
      unit: m['unit'] as String? ?? '',
      originalQuantity: d('original_quantity') ?? 0,
      dueQuantity: d('due_quantity') ?? 0,
      receivedQuantity: d('received_quantity') ?? 0,
      status: m['status'] as String? ?? 'pending',
      reportedQuantity: d('reported_quantity'),
      verifiedQuantity: d('verified_quantity'),
      underreportFlag: m['underreport_flag'] as bool? ?? false,
      closedReason: m['closed_reason'] as String?,
      receipts: list('receipts', ProgramReturnReceipt.fromMap),
      events: list('events', ProgramReturnEvent.fromMap),
    );
  }
}

/// What a Farmer is allowed to see: the status and quantities, no staff names
/// and no internal reasons.
class MyReturnsSnapshot {
  final Map<String, ProgramReturnSummary> byMember; // program_member_id -> return
  final Map<String, String> resolutionByMember; // program_member_id -> resolution

  const MyReturnsSnapshot({
    this.byMember = const {},
    this.resolutionByMember = const {},
  });

  factory MyReturnsSnapshot.fromMap(Map<String, dynamic> m) {
    final returns = <String, ProgramReturnSummary>{};
    for (final e in (m['returns'] as List?) ?? const []) {
      final r = ProgramReturnSummary.fromMap((e as Map).cast<String, dynamic>());
      returns[r.programMemberId] = r;
    }
    final res = <String, String>{};
    for (final e in (m['resolutions'] as List?) ?? const []) {
      final x = (e as Map).cast<String, dynamic>();
      res[x['program_member_id'] as String] = x['resolution'] as String;
    }
    return MyReturnsSnapshot(byMember: returns, resolutionByMember: res);
  }
}

class ProgramReturnSummary {
  final String programMemberId;
  final String cropName;
  final String unit;
  final double dueQuantity;
  final double receivedQuantity;
  final String status;

  const ProgramReturnSummary({
    required this.programMemberId,
    required this.cropName,
    required this.unit,
    required this.dueQuantity,
    required this.receivedQuantity,
    required this.status,
  });

  factory ProgramReturnSummary.fromMap(Map<String, dynamic> m) => ProgramReturnSummary(
        programMemberId: m['program_member_id'] as String,
        cropName: m['crop_name'] as String? ?? '',
        unit: m['unit'] as String? ?? '',
        dueQuantity: (m['due_quantity'] as num?)?.toDouble() ?? 0,
        receivedQuantity: (m['received_quantity'] as num?)?.toDouble() ?? 0,
        status: m['status'] as String? ?? 'pending',
      );
}

/// Formats a quantity without trailing zeros: 5 -> "5", 2.5 -> "2.5".
String formatReturnQuantity(double v) {
  final s = v.toStringAsFixed(2);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}
