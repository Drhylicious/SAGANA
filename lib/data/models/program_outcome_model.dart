// Outcome reports (Proposal 11): a Farmer reports a Successful or Failed
// outcome with evidence; staff review it, an Officer verifies it in the field,
// and it is finalized. See supabase_schema_program_rework_p3_outcome_workflow.sql.

/// A database refusal (or any failure) of an outcome action, with the reason
/// the database gave, so the screen can show it instead of a vague "failed".
class OutcomeActionException implements Exception {
  final String message;

  /// True when the action could not even start because there is no connection.
  final bool offline;
  const OutcomeActionException(this.message, {this.offline = false});

  @override
  String toString() => message;
}

class OutcomePhoto {
  final String id;
  final String path;

  /// 'farmer' (the Farmer's evidence) or 'staff' (the Officer's field photos).
  final String by;
  const OutcomePhoto({required this.id, required this.path, required this.by});

  factory OutcomePhoto.fromMap(Map<String, dynamic> m) => OutcomePhoto(
    id: m['id'] as String,
    path: m['path'] as String,
    by: m['by'] as String? ?? 'farmer',
  );
}

/// Where a report is in the process, from the staff point of view.
enum OutcomeStage {
  /// Closed by staff: no longer required (a Free Distribution has no outcome). Kept as history.
  closed,

  /// Neither the evidence review nor the field verification is done.
  awaitingBoth,

  /// The evidence is validated; an Officer still has to verify in the field.
  awaitingVerification,

  /// An Officer verified; the evidence still has to be reviewed.
  awaitingReview,

  /// Both are done; ready for the final decision.
  readyToFinalize,

  /// Staff asked the Farmer for better evidence (a new report is needed).
  returned,

  /// Successful or Failed, final.
  finalized,
}

/// A report as staff see it (names and all), from get_program_outcome_reports().
class OutcomeReport {
  final String id;
  final String programMemberId;
  final String programId;
  final String programName;
  // A Harvest Return program asks the reviewer for the quantity to return.
  final bool isHarvestReturn;
  // The item the Farmer was given, which they return, and its unit.
  final String? returnItemName;
  final String? itemUnit;
  // What was agreed for this Farmer's return (member, else program default): pre-fills the final step.
  final double? agreedReturnQuantity;
  final String farmerId;
  final String farmerName;
  final String? itemName;
  final double? quantityGiven;
  final DateTime? distributedAt;

  final String reportedOutcome; // 'successful' | 'failed'
  final String explanation;
  final DateTime? plantedDate;
  final DateTime? harvestDate;
  final double? quantityHarvested;
  final String? quantityUnit;
  final double? areaPlanted;
  final String? areaUnit;
  final String? failureCause;
  final DateTime? failureDate;
  final String status; // 'pending_validation' | 'returned' | 'finalized'
  final DateTime submittedAt;

  final String? reviewDecision; // 'validated' | 'returned'
  final String? reviewedBy;
  final String? reviewedByName;
  final String? reviewedByRole;
  final DateTime? reviewedAt;
  final String? reviewNote;

  final String? verificationFinding; // 'confirms' | 'disputes'
  final String? verifiedBy;
  final String? verifiedByName;
  final DateTime? verifiedAt;
  final DateTime? fieldVisitDate;
  final double? verifiedQuantity;
  final String? verifiedUnit;
  final String? verificationNote;

  final String? finalOutcome;
  final String? finalizedByName;
  final String? finalizedByRole;
  final DateTime? finalizedAt;
  final String? finalNote;

  final List<OutcomePhoto> photos;

  const OutcomeReport({
    required this.id,
    required this.programMemberId,
    required this.programId,
    required this.programName,
    this.isHarvestReturn = false,
    this.returnItemName,
    this.itemUnit,
    this.agreedReturnQuantity,
    required this.farmerId,
    required this.farmerName,
    this.itemName,
    this.quantityGiven,
    this.distributedAt,
    required this.reportedOutcome,
    required this.explanation,
    this.plantedDate,
    this.harvestDate,
    this.quantityHarvested,
    this.quantityUnit,
    this.areaPlanted,
    this.areaUnit,
    this.failureCause,
    this.failureDate,
    required this.status,
    required this.submittedAt,
    this.reviewDecision,
    this.reviewedBy,
    this.reviewedByName,
    this.reviewedByRole,
    this.reviewedAt,
    this.reviewNote,
    this.verificationFinding,
    this.verifiedBy,
    this.verifiedByName,
    this.verifiedAt,
    this.fieldVisitDate,
    this.verifiedQuantity,
    this.verifiedUnit,
    this.verificationNote,
    this.finalOutcome,
    this.finalizedByName,
    this.finalizedByRole,
    this.finalizedAt,
    this.finalNote,
    this.photos = const [],
  });

  bool get isSuccessfulReport => reportedOutcome == 'successful';
  bool get isFinalized => status == 'finalized';
  bool get isReturned => status == 'returned';
  bool get isPending => status == 'pending_validation';
  bool get isClosed => status == 'closed';
  bool get isReviewed => reviewDecision == 'validated';
  bool get isVerified => verifiedBy != null || verifiedAt != null;
  bool get disputed => verificationFinding == 'disputes';

  List<OutcomePhoto> get farmerPhotos =>
      photos.where((p) => p.by == 'farmer').toList();
  List<OutcomePhoto> get fieldPhotos =>
      photos.where((p) => p.by == 'staff').toList();

  OutcomeStage get stage {
    if (isClosed) return OutcomeStage.closed;
    if (isFinalized) return OutcomeStage.finalized;
    if (isReturned) return OutcomeStage.returned;
    if (isReviewed && isVerified) return OutcomeStage.readyToFinalize;
    if (isReviewed) return OutcomeStage.awaitingVerification;
    if (isVerified) return OutcomeStage.awaitingReview;
    return OutcomeStage.awaitingBoth;
  }

  static DateTime? _d(Object? v) => v == null ? null : DateTime.parse('$v');
  static double? _n(Object? v) => v == null ? null : (v as num).toDouble();

  factory OutcomeReport.fromMap(Map<String, dynamic> m) => OutcomeReport(
    id: m['id'] as String,
    programMemberId: m['program_member_id'] as String,
    programId: m['program_id'] as String,
    programName: m['program_name'] as String? ?? 'Program',
    isHarvestReturn: m['is_harvest_return'] as bool? ?? false,
    returnItemName: m['return_item_name'] as String?,
    itemUnit: m['item_unit'] as String?,
    agreedReturnQuantity: _n(m['agreed_return_quantity']),
    farmerId: m['farmer_id'] as String,
    farmerName: m['farmer_name'] as String? ?? 'Farmer',
    itemName: m['item_name'] as String?,
    quantityGiven: _n(m['quantity_given']),
    distributedAt: _d(m['distributed_at'])?.toLocal(),
    reportedOutcome: m['reported_outcome'] as String,
    explanation: m['explanation'] as String? ?? '',
    plantedDate: _d(m['planted_date']),
    harvestDate: _d(m['harvest_date']),
    quantityHarvested: _n(m['quantity_harvested']),
    quantityUnit: m['quantity_unit'] as String?,
    areaPlanted: _n(m['area_planted']),
    areaUnit: m['area_unit'] as String?,
    failureCause: m['failure_cause'] as String?,
    failureDate: _d(m['failure_date']),
    status: m['status'] as String? ?? 'pending_validation',
    submittedAt: DateTime.parse(m['submitted_at'] as String).toLocal(),
    reviewDecision: m['review_decision'] as String?,
    reviewedBy: m['reviewed_by'] as String?,
    reviewedByName: m['reviewed_by_name'] as String?,
    reviewedByRole: m['reviewed_by_role'] as String?,
    reviewedAt: _d(m['reviewed_at'])?.toLocal(),
    reviewNote: m['review_note'] as String?,
    verificationFinding: m['verification_finding'] as String?,
    verifiedBy: m['verified_by'] as String?,
    verifiedByName: m['verified_by_name'] as String?,
    verifiedAt: _d(m['verified_at'])?.toLocal(),
    fieldVisitDate: _d(m['field_visit_date']),
    verifiedQuantity: _n(m['verified_quantity']),
    verifiedUnit: m['verified_unit'] as String?,
    verificationNote: m['verification_note'] as String?,
    finalOutcome: m['final_outcome'] as String?,
    finalizedByName: m['finalized_by_name'] as String?,
    finalizedByRole: m['finalized_by_role'] as String?,
    finalizedAt: _d(m['finalized_at'])?.toLocal(),
    finalNote: m['final_note'] as String?,
    photos: [
      for (final p in (m['photos'] as List? ?? const []))
        OutcomePhoto.fromMap(Map<String, dynamic>.from(p as Map)),
    ],
  );
}

/// A Farmer's own report, from get_my_outcome_reports(): no reviewer,
/// verifier or any other staff identity.
class MyOutcomeReport {
  final String id;
  final String programMemberId;
  final String programId;
  final String reportedOutcome;
  final String status; // 'pending_validation' | 'returned' | 'finalized'
  final DateTime submittedAt;
  final String? returnNote;
  final String? finalOutcome;
  final DateTime? finalizedAt;
  final bool reviewDone;
  final bool verificationDone;
  final int photoCount;

  const MyOutcomeReport({
    required this.id,
    required this.programMemberId,
    required this.programId,
    required this.reportedOutcome,
    required this.status,
    required this.submittedAt,
    this.returnNote,
    this.finalOutcome,
    this.finalizedAt,
    this.reviewDone = false,
    this.verificationDone = false,
    this.photoCount = 0,
  });

  bool get isPending => status == 'pending_validation';
  bool get isReturned => status == 'returned';
  bool get isFinalized => status == 'finalized';

  factory MyOutcomeReport.fromMap(Map<String, dynamic> m) => MyOutcomeReport(
    id: m['id'] as String,
    programMemberId: m['program_member_id'] as String,
    programId: m['program_id'] as String,
    reportedOutcome: m['reported_outcome'] as String,
    status: m['status'] as String? ?? 'pending_validation',
    submittedAt: DateTime.parse(m['submitted_at'] as String).toLocal(),
    returnNote: m['return_note'] as String?,
    finalOutcome: m['final_outcome'] as String?,
    finalizedAt: m['finalized_at'] != null
        ? DateTime.parse(m['finalized_at'] as String).toLocal()
        : null,
    reviewDone: m['review_done'] as bool? ?? false,
    verificationDone: m['verification_done'] as bool? ?? false,
    photoCount: (m['photo_count'] as num?)?.toInt() ?? 0,
  );
}

/// Picks the report that represents a member right now: the one in progress or
/// finished, else the most recent returned one. [reports] is newest first.
T? currentReportFor<T>(
  Iterable<T> reports,
  String memberId, {
  required String Function(T) memberOf,
  required bool Function(T) isReturned,
}) {
  T? returned;
  for (final r in reports) {
    if (memberOf(r) != memberId) continue;
    if (!isReturned(r)) return r;
    returned ??= r;
  }
  return returned;
}
