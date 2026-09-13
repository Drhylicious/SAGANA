// ─── Member Status (Issue 5 — 5-status model) ─────────────────────────────────
//
// Active     — normal member.
// Inactive   — DERIVED, not a stored user_roles.status. status='active' AND
//              user_information.last_active_at older than 30 days. Indicator
//              only; never blocks login (Decision D11).
// Suspended  — manual admin action, blocks login, reason recorded.
// Pending    — application submitted, awaiting admin review.
// Rejected   — application rejected; account stays listed, no farmer access.
// Draft      — account created but application NOT yet submitted. Hidden from
//              the Admin Members list until submit_application() (Decision D5).

enum MemberStatus { active, inactive, suspended, pending, rejected, draft }

extension MemberStatusExt on MemberStatus {
  /// The value written to user_roles.status. `inactive` is derived, never
  /// stored — it maps to `active` so an accidental write path stays sane.
  String get value {
    switch (this) {
      case MemberStatus.active:    return 'active';
      case MemberStatus.inactive:  return 'active';
      case MemberStatus.suspended: return 'suspended';
      case MemberStatus.pending:   return 'pending';
      case MemberStatus.rejected:  return 'rejected';
      case MemberStatus.draft:     return 'draft';
    }
  }

  String get label {
    switch (this) {
      case MemberStatus.active:    return 'Active';
      case MemberStatus.inactive:  return 'Inactive';
      case MemberStatus.suspended: return 'Suspended';
      case MemberStatus.pending:   return 'Pending';
      case MemberStatus.rejected:  return 'Rejected';
      case MemberStatus.draft:     return 'Draft';
    }
  }

  static MemberStatus fromString(String? v) {
    switch (v) {
      case 'active':    return MemberStatus.active;
      case 'inactive':  return MemberStatus.inactive;
      case 'suspended': return MemberStatus.suspended;
      case 'rejected':  return MemberStatus.rejected;
      case 'draft':     return MemberStatus.draft;
      default:          return MemberStatus.pending;
    }
  }

  /// Resolves the effective status for display: an `active` member whose
  /// last activity is older than [inactivityThreshold] shows as Inactive.
  /// A member who has never logged in ([lastActiveAt] == null) stays Active.
  static MemberStatus derive(String? dbStatus, DateTime? lastActiveAt) {
    final base = fromString(dbStatus);
    if (base == MemberStatus.active &&
        lastActiveAt != null &&
        DateTime.now().difference(lastActiveAt) > inactivityThreshold) {
      return MemberStatus.inactive;
    }
    return base;
  }

  static const Duration inactivityThreshold = Duration(days: 30);

  /// Statuses offered as filter chips on the Members tab — Draft is
  /// deliberately excluded (those rows are not listed at all).
  static const List<MemberStatus> filterable = [
    MemberStatus.active,
    MemberStatus.inactive,
    MemberStatus.suspended,
    MemberStatus.pending,
    MemberStatus.rejected,
  ];

  /// Whether the plain Active⇄Suspended toggle (Members list + detail
  /// actions menu) applies to this status. Pending has its own dedicated
  /// Approve/Reject actions; Rejected and Draft have no status toggle at
  /// all — a rejected application is not "reactivated", it is reviewed
  /// again only through resubmission (verification finding, bugfix round).
  bool get supportsSuspendToggle =>
      this == MemberStatus.active ||
      this == MemberStatus.inactive ||
      this == MemberStatus.suspended;

  /// For a status where [supportsSuspendToggle] is true: whether the member
  /// is currently on the "active side" of the toggle (Active or the derived
  /// Inactive both count — under the hood both are `user_roles.status =
  /// 'active'`, so both offer "Set Suspended" as the next action, never a
  /// no-op "Set Active"). Only meaningful when [supportsSuspendToggle].
  bool get isEffectivelyActive =>
      this == MemberStatus.active || this == MemberStatus.inactive;
}

// ─── Loan Summary ─────────────────────────────────────────────────────────────

enum LoanStatusSummary { none, active, overdue }

extension LoanStatusSummaryExt on LoanStatusSummary {
  String get label {
    switch (this) {
      case LoanStatusSummary.none:    return 'No Loans';
      case LoanStatusSummary.active:  return 'Active Loan';
      case LoanStatusSummary.overdue: return 'Overdue';
    }
  }
}

// ─── Farmer Member Model ──────────────────────────────────────────────────────

class FarmerMemberModel {
  final String userId;
  final String fullName;
  final String? memberId;
  final String? purok;
  final String? profilePhotoUrl;
  final MemberStatus memberStatus;
  final bool isVerified;
  final List<String> primaryCrops;
  final DateTime? lastHarvestDate;
  final double outstandingLoanBalance;
  final LoanStatusSummary loanStatus;
  final bool isSynced;
  final DateTime? joinedAt;
  final DateTime? lastActiveAt;
  final String? rejectionReason;
  final String? suspensionReason;
  final int applicationAttempts;

  const FarmerMemberModel({
    required this.userId,
    required this.fullName,
    this.memberId,
    this.purok,
    this.profilePhotoUrl,
    required this.memberStatus,
    required this.isVerified,
    required this.primaryCrops,
    this.lastHarvestDate,
    required this.outstandingLoanBalance,
    required this.loanStatus,
    required this.isSynced,
    this.joinedAt,
    this.lastActiveAt,
    this.rejectionReason,
    this.suspensionReason,
    this.applicationAttempts = 0,
  });

  bool get hasPhoto =>
      profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty;

  bool get hasOutstandingLoan => outstandingLoanBalance > 0;

  bool get isOverdue => loanStatus == LoanStatusSummary.overdue;

  /// Two-letter initials for avatar fallback
  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }

  String get lastHarvestLabel {
    if (lastHarvestDate == null) return 'No records';
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    final d = lastHarvestDate!;
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  factory FarmerMemberModel.fromMap(Map<String, dynamic> map) {
    final loanStatusStr = map['loan_status'] as String? ?? 'none';
    LoanStatusSummary ls;
    switch (loanStatusStr) {
      case 'overdue': ls = LoanStatusSummary.overdue; break;
      case 'active':  ls = LoanStatusSummary.active;  break;
      default:        ls = LoanStatusSummary.none;
    }

    final lastActiveAt = map['last_active_at'] != null
        ? DateTime.tryParse(map['last_active_at'] as String)
        : null;

    return FarmerMemberModel(
      userId:                 map['user_id'] as String,
      fullName:               map['full_name'] as String? ?? 'Farmer',
      memberId:               map['member_id'] as String?,
      purok:                  map['purok'] as String?,
      profilePhotoUrl:        map['profile_photo_url'] as String?,
      memberStatus:           MemberStatusExt.derive(
                                  map['member_status'] as String?, lastActiveAt),
      lastActiveAt:           lastActiveAt,
      rejectionReason:        map['rejection_reason'] as String?,
      suspensionReason:       map['suspension_reason'] as String?,
      applicationAttempts:    (map['application_attempts'] as num?)?.toInt() ?? 0,
      isVerified:             map['is_verified'] as bool? ?? false,
      primaryCrops:           (map['crops'] as List<dynamic>?)
                                  ?.map((c) => c.toString())
                                  .toList() ??
                              [],
      lastHarvestDate:        map['last_harvest_date'] != null
                                  ? DateTime.tryParse(
                                      map['last_harvest_date'] as String)
                                  : null,
      outstandingLoanBalance: (map['outstanding_balance'] as num? ?? 0)
                                  .toDouble(),
      loanStatus:             ls,
      isSynced:               map['is_synced'] as bool? ?? true,
      joinedAt:               map['joined_at'] != null
                                  ? DateTime.tryParse(
                                      map['joined_at'] as String)
                                  : null,
    );
  }
}

// ─── Member Status Event (audit trail row) ───────────────────────────────────

class MemberStatusEvent {
  final String? fromStatus;
  final String toStatus;
  final String? reason;
  final DateTime createdAt;

  const MemberStatusEvent({
    required this.toStatus,
    required this.createdAt,
    this.fromStatus,
    this.reason,
  });

  factory MemberStatusEvent.fromMap(Map<String, dynamic> map) {
    return MemberStatusEvent(
      fromStatus: map['from_status'] as String?,
      toStatus: map['to_status'] as String? ?? 'unknown',
      reason: map['reason'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

// ─── Member Summary Stats ─────────────────────────────────────────────────────

class MemberSummaryStats {
  final int totalMembers;
  final int activeMembers;
  final int pendingMembers;
  final int rejectedMembers;
  final int withActiveLoans;
  final int withOverdueLoans;

  const MemberSummaryStats({
    required this.totalMembers,
    required this.activeMembers,
    required this.pendingMembers,
    this.rejectedMembers = 0,
    required this.withActiveLoans,
    required this.withOverdueLoans,
  });

  static const empty = MemberSummaryStats(
    totalMembers:   0,
    activeMembers:  0,
    pendingMembers: 0,
    rejectedMembers: 0,
    withActiveLoans: 0,
    withOverdueLoans: 0,
  );
}

// ─── Filter & Sort State ──────────────────────────────────────────────────────

enum FarmerSortOption {
  nameAZ,
  recentHarvest,
  memberId,
  loanBalance,
}

extension FarmerSortOptionExt on FarmerSortOption {
  String get label {
    switch (this) {
      case FarmerSortOption.nameAZ:         return 'Name (A–Z)';
      case FarmerSortOption.recentHarvest:  return 'Recent Harvest';
      case FarmerSortOption.memberId:       return 'Member ID';
      case FarmerSortOption.loanBalance:    return 'Loan Balance';
    }
  }
}

class FarmerFilterState {
  final MemberStatus? statusFilter;      // null = All
  final String? cropFilter;             // null = All
  final LoanStatusSummary? loanFilter;  // null = All
  final FarmerSortOption sortBy;

  const FarmerFilterState({
    this.statusFilter,
    this.cropFilter,
    this.loanFilter,
    this.sortBy = FarmerSortOption.nameAZ,
  });

  FarmerFilterState copyWith({
    Object? statusFilter = _sentinel,
    Object? cropFilter   = _sentinel,
    Object? loanFilter   = _sentinel,
    FarmerSortOption? sortBy,
  }) {
    return FarmerFilterState(
      statusFilter: statusFilter == _sentinel
          ? this.statusFilter
          : statusFilter as MemberStatus?,
      cropFilter: cropFilter == _sentinel
          ? this.cropFilter
          : cropFilter as String?,
      loanFilter: loanFilter == _sentinel
          ? this.loanFilter
          : loanFilter as LoanStatusSummary?,
      sortBy: sortBy ?? this.sortBy,
    );
  }

  bool get isDefault =>
      statusFilter == null &&
      cropFilter == null &&
      loanFilter == null &&
      sortBy == FarmerSortOption.nameAZ;
}

const _sentinel = Object();