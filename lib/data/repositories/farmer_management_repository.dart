import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_member_model.dart';

class FarmerManagementRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Fetch all farmer members ─────────────────────────────────────────────
  // Joins user_roles + user_information + farmer_profiles + crops + loans

  Future<List<FarmerMemberModel>> fetchFarmers() async {
    try {
      // 1. All farmer user IDs with role status.
      // 'draft' applicants (account created, application not yet submitted)
      // are deliberately excluded — they stay off the Members list until
      // they tap Submit Application (Issue 5 / Decision D5).
      final roleRows = await _client
          .from('user_roles')
          .select('user_id, status, created_at, application_attempts, '
              'rejection_reason, suspension_reason')
          .eq('role', 'farmer')
          .neq('status', 'draft');

      if (roleRows.isEmpty) return [];

      final userIds =
          roleRows.map((r) => r['user_id'] as String).toList();

      final roleMap = {
        for (final r in roleRows)
          r['user_id'] as String: {
            'status':               r['status'] as String? ?? 'pending',
            'created_at':           r['created_at'] as String?,
            'application_attempts': r['application_attempts'],
            'rejection_reason':     r['rejection_reason'] as String?,
            'suspension_reason':    r['suspension_reason'] as String?,
          }
      };

      // 2. user_information
      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name, purok, profile_photo_url, last_active_at')
          .inFilter('user_id', userIds);

      final infoMap = {
        for (final r in infoRows) r['user_id'] as String: r,
      };

      // 3. farmer_profiles (member_id, is_verified)
      final profileRows = await _client
          .from('farmer_profiles')
          .select('user_id, member_id, is_verified')
          .inFilter('user_id', userIds);

      final profileMap = {
        for (final r in profileRows) r['user_id'] as String: r,
      };

      // 4. Crops per farmer
      final cropRows = await _client
          .from('farmer_crops')
          .select('farmer_id, crop_name')
          .inFilter('farmer_id', userIds);

      final cropsMap = <String, List<String>>{};
      for (final r in cropRows) {
        final id = r['farmer_id'] as String;
        cropsMap.putIfAbsent(id, () => []).add(r['crop_name'] as String);
      }

      // 5. Loan summary per farmer
      final loanRows = await _client
          .from('farmer_loans')
          .select('farmer_id, total_value, amount_paid, status')
          .inFilter('farmer_id', userIds)
          .neq('status', 'paid');

      final loanMap = <String, Map<String, dynamic>>{};
      for (final r in loanRows) {
        final id  = r['farmer_id'] as String;
        final rem = ((r['total_value'] as num).toDouble() -
                (r['amount_paid'] as num? ?? 0).toDouble())
            .clamp(0.0, double.infinity);
        final existing = loanMap[id];
        final balance  = (existing?['balance'] as double? ?? 0) + rem;
        final paymentStatus = r['status'] as String? ?? 'active';
        final isOverdue = paymentStatus == 'overdue' ||
            ((existing?['status'] as String?) == 'overdue');
        loanMap[id] = {
          'balance': balance,
          'status':  isOverdue ? 'overdue' : 'active',
        };
      }

      // 6. Last harvest date per farmer
      final harvestRows = await _client
          .from('harvest_records')
          .select('farmer_id, harvest_date')
          .inFilter('farmer_id', userIds)
          .order('harvest_date', ascending: false);

      final harvestMap = <String, String>{};
      for (final r in harvestRows) {
        final id = r['farmer_id'] as String;
        harvestMap.putIfAbsent(id, () => r['harvest_date'] as String);
      }

      return userIds.map((uid) {
        final role    = roleMap[uid]!;
        final info    = infoMap[uid] ?? {};
        final profile = profileMap[uid] ?? {};
        final loan    = loanMap[uid];

        return FarmerMemberModel.fromMap({
          'user_id':            uid,
          'full_name':          info['full_name'] as String? ?? 'Farmer',
          'member_id':          profile['member_id'] as String?,
          'purok':              info['purok'] as String?,
          'profile_photo_url':  info['profile_photo_url'] as String?,
          'member_status':      role['status'],
          'last_active_at':     info['last_active_at'],
          'application_attempts': role['application_attempts'],
          'rejection_reason':   role['rejection_reason'],
          'suspension_reason':  role['suspension_reason'],
          'is_verified':        profile['is_verified'] as bool? ?? false,
          'crops':              cropsMap[uid] ?? [],
          'outstanding_balance': loan?['balance'] ?? 0.0,
          'loan_status':        loan != null
              ? loan['status']
              : 'none',
          'is_synced':          true,
          'last_harvest_date':  harvestMap[uid],
          'joined_at':          role['created_at'],
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Fetch summary stats ──────────────────────────────────────────────────

  Future<MemberSummaryStats> fetchSummaryStats() async {
    try {
      final roleRows = await _client
          .from('user_roles')
          .select('user_id, status')
          .eq('role', 'farmer');

      final userIds =
          roleRows.map((r) => r['user_id'] as String).toList();

      // Only count a member as "active" if their role status is active
      // AND their farmer_profiles.is_verified flag is true. This keeps the
      // KPI in sync with the approval workflow — a role can be flipped to
      // 'active' without going through approveMember(), but they shouldn't
      // show up as a verified SP3 member until is_verified is set.
      final profileRows = await _client
          .from('farmer_profiles')
          .select('user_id, is_verified')
          .inFilter('user_id', userIds);

      final verifiedSet = {
        for (final r in profileRows)
          if (r['is_verified'] == true) r['user_id'] as String
      };

      int active   = 0;
      int pending  = 0;
      int rejected = 0;
      int draft    = 0;
      for (final r in roleRows) {
        final uid    = r['user_id'] as String;
        final status = r['status'] as String? ?? 'pending';
        // Active = status active AND is_verified true
        if (status == 'active' && verifiedSet.contains(uid)) active++;
        if (status == 'pending')  pending++;
        if (status == 'rejected') rejected++;
        if (status == 'draft')    draft++;
      }

      int withActive  = 0;
      int withOverdue = 0;
      if (userIds.isNotEmpty) {
        final loanRows = await _client
            .from('farmer_loans')
            .select('farmer_id, status')
            .inFilter('farmer_id', userIds)
            .neq('status', 'paid');

        final seen = <String>{};
        for (final r in loanRows) {
          final id     = r['farmer_id'] as String;
          final status = r['status'] as String;
          if (status == 'overdue' && !seen.contains('$id-overdue')) {
            withOverdue++;
            seen.add('$id-overdue');
          } else if (status == 'active' && !seen.contains('$id-active')) {
            withActive++;
            seen.add('$id-active');
          }
        }
      }

      return MemberSummaryStats(
        // Draft applicants are not listed, so don't count them here either.
        totalMembers:    roleRows.length - draft,
        activeMembers:   active,
        pendingMembers:  pending,
        rejectedMembers: rejected,
        withActiveLoans: withActive,
        withOverdueLoans: withOverdue,
      );
    } catch (_) {
      return MemberSummaryStats.empty;
    }
  }

  // ─── Approve a pending member (Issue 5) ──────────────────────────────────
  //
  // One atomic RPC (approve_member): pending -> active with the
  // acknowledgement gate ON, Member ID minted via the shared generator if
  // missing, is_verified set, registry linked, 'member_approved'
  // notification sent, and a member_status_events audit row written. The
  // login username is NEVER changed by approval.

  Future<ApproveMemberResult> approveMember({
    required String userId,
    required String fullName,
  }) async {
    try {
      final memberId =
          await _client.rpc('approve_member', params: {'p_user_id': userId});

      final infoRow = await _client
          .from('user_information')
          .select('username')
          .eq('user_id', userId)
          .maybeSingle();

      return ApproveMemberResult(
        success:  true,
        memberId: memberId as String?,
        username: infoRow?['username'] as String? ?? '',
      );
    } catch (e) {
      return ApproveMemberResult(
        success:  false,
        error:    e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  // ─── Reject a pending application (Issue 5) ───────────────────────────────
  //
  // reject_member: pending -> 'rejected' (a distinct status — the account
  // stays listed but gains NO farmer access, unlike the old behaviour
  // which set 'suspended' and accidentally let them in). Reason is
  // required; it is shown to the applicant and recorded in the audit trail.
  // The applicant can review their details and resubmit (up to 3 total).

  Future<void> rejectMember({
    required String userId,
    required String reason,
  }) async {
    await _client.rpc('reject_member', params: {
      'p_user_id': userId,
      'p_reason':  reason.trim(),
    });
  }

  // ─── Suspend / reactivate (Issue 5, Decision D17) ────────────────────────

  Future<void> suspendMember({
    required String userId,
    required String reason,
  }) async {
    await _client.rpc('suspend_member', params: {
      'p_user_id': userId,
      'p_reason':  reason.trim(),
    });
  }

  Future<void> reactivateMember({required String userId}) async {
    await _client.rpc('reactivate_member', params: {'p_user_id': userId});
  }

  // ─── Status history (audit trail for the member record) ──────────────────

  Future<List<MemberStatusEvent>> fetchStatusHistory(String userId) async {
    try {
      final rows = await _client
          .from('member_status_events')
          .select('from_status, to_status, reason, created_at')
          .eq('member_id', userId)
          .order('created_at', ascending: false)
          .limit(20);
      return rows.map((r) => MemberStatusEvent.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Known crop names for filter chips ───────────────────────────────────

  Future<List<String>> fetchDistinctCrops() async {
    try {
      final rows = await _client
          .from('farmer_crops')
          .select('crop_name');
      return rows
          .map((r) => r['crop_name'] as String)
          .toSet()
          .toList()
        ..sort();
    } catch (_) {
      return ['Peanut', 'Ginger', 'Palay', 'Banana', 'Copra'];
    }
  }
}

// ─── Approve member result ────────────────────────────────────────────────────

class ApproveMemberResult {
  final bool success;
  final String? memberId;
  final String? username;
  final String? error;

  const ApproveMemberResult({
    required this.success,
    this.memberId,
    this.username,
    this.error,
  });
}

// ─── Client-side filter + sort helper ────────────────────────────────────────

extension FarmerListFilter on List<FarmerMemberModel> {
  List<FarmerMemberModel> applyFilter(
    FarmerFilterState filter,
    String searchQuery,
  ) {
    var list = this;

    // Search
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      list = list
          .where((f) =>
              f.fullName.toLowerCase().contains(q) ||
              (f.memberId?.toLowerCase().contains(q) ?? false) ||
              (f.purok?.toLowerCase().contains(q) ?? false))
          .toList();
    }

    // Status filter
    if (filter.statusFilter != null) {
      list = list
          .where((f) => f.memberStatus == filter.statusFilter)
          .toList();
    }

    // Crop filter
    if (filter.cropFilter != null) {
      final crop = filter.cropFilter!.toLowerCase();
      list = list
          .where((f) =>
              f.primaryCrops.any((c) => c.toLowerCase().contains(crop)))
          .toList();
    }

    // Loan filter
    if (filter.loanFilter != null) {
      list = list.where((f) => f.loanStatus == filter.loanFilter).toList();
    }

    // Sort — the chosen option is the tiebreaker; Rejected applicants
    // always sink to the bottom of the list regardless of sort option
    // (verification bugfix: a rejected record is archived-for-reference,
    // not a normal member row competing for name/loan/etc. ranking).
    int byOption(FarmerMemberModel a, FarmerMemberModel b) {
      switch (filter.sortBy) {
        case FarmerSortOption.nameAZ:
          return a.fullName.compareTo(b.fullName);
        case FarmerSortOption.recentHarvest:
          if (a.lastHarvestDate == null && b.lastHarvestDate == null) {
            return 0;
          }
          if (a.lastHarvestDate == null) return 1;
          if (b.lastHarvestDate == null) return -1;
          return b.lastHarvestDate!.compareTo(a.lastHarvestDate!);
        case FarmerSortOption.memberId:
          return (a.memberId ?? '').compareTo(b.memberId ?? '');
        case FarmerSortOption.loanBalance:
          return b.outstandingLoanBalance.compareTo(a.outstandingLoanBalance);
      }
    }

    list.sort((a, b) {
      final aRejected = a.memberStatus == MemberStatus.rejected;
      final bRejected = b.memberStatus == MemberStatus.rejected;
      if (aRejected != bRejected) return aRejected ? 1 : -1;
      return byOption(a, b);
    });

    return list;
  }
}