// ─── Member Status ────────────────────────────────────────────────────────────

enum MemberStatus { active, inactive, pending }

extension MemberStatusExt on MemberStatus {
  String get value {
    switch (this) {
      case MemberStatus.active:   return 'active';
      case MemberStatus.inactive: return 'inactive';
      case MemberStatus.pending:  return 'pending';
    }
  }

  String get label {
    switch (this) {
      case MemberStatus.active:   return 'Active';
      case MemberStatus.inactive: return 'Inactive';
      case MemberStatus.pending:  return 'Pending';
    }
  }

  static MemberStatus fromString(String? v) {
    switch (v) {
      case 'active':   return MemberStatus.active;
      case 'inactive': return MemberStatus.inactive;
      default:         return MemberStatus.pending;
    }
  }
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
  final String? sitio;
  final String? profilePhotoUrl;
  final MemberStatus memberStatus;
  final bool isVerified;
  final List<String> primaryCrops;
  final DateTime? lastHarvestDate;
  final double outstandingLoanBalance;
  final LoanStatusSummary loanStatus;
  final bool isSynced;
  final DateTime? joinedAt;

  const FarmerMemberModel({
    required this.userId,
    required this.fullName,
    this.memberId,
    this.sitio,
    this.profilePhotoUrl,
    required this.memberStatus,
    required this.isVerified,
    required this.primaryCrops,
    this.lastHarvestDate,
    required this.outstandingLoanBalance,
    required this.loanStatus,
    required this.isSynced,
    this.joinedAt,
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

    return FarmerMemberModel(
      userId:                 map['user_id'] as String,
      fullName:               map['full_name'] as String? ?? 'Farmer',
      memberId:               map['member_id'] as String?,
      sitio:                  map['sitio'] as String?,
      profilePhotoUrl:        map['profile_photo_url'] as String?,
      memberStatus:           MemberStatusExt.fromString(
                                  map['member_status'] as String?),
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

// ─── Member Summary Stats ─────────────────────────────────────────────────────

class MemberSummaryStats {
  final int totalMembers;
  final int activeMembers;
  final int pendingMembers;
  final int withActiveLoans;
  final int withOverdueLoans;

  const MemberSummaryStats({
    required this.totalMembers,
    required this.activeMembers,
    required this.pendingMembers,
    required this.withActiveLoans,
    required this.withOverdueLoans,
  });

  static const empty = MemberSummaryStats(
    totalMembers:   0,
    activeMembers:  0,
    pendingMembers: 0,
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
