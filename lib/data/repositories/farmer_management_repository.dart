import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_member_model.dart';

class FarmerManagementRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Fetch all farmer members ─────────────────────────────────────────────
  // Joins user_roles + user_information + farmer_profiles + crops + loans

  Future<List<FarmerMemberModel>> fetchFarmers() async {
    try {
      // 1. All farmer user IDs with role status
      final roleRows = await _client
          .from('user_roles')
          .select('user_id, status, created_at')
          .eq('role', 'farmer');

      if (roleRows.isEmpty) return [];

      final userIds =
          roleRows.map((r) => r['user_id'] as String).toList();

      final roleMap = {
        for (final r in roleRows)
          r['user_id'] as String: {
            'status':     r['status'] as String? ?? 'pending',
            'created_at': r['created_at'] as String?,
          }
      };

      // 2. user_information
      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name, sitio, profile_photo_url')
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
          'sitio':              info['sitio'] as String?,
          'profile_photo_url':  info['profile_photo_url'] as String?,
          'member_status':      role['status'],
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

      int active  = 0;
      int pending = 0;
      for (final r in roleRows) {
        final uid    = r['user_id'] as String;
        final status = r['status'] as String? ?? 'pending';
        // Active = status active AND is_verified true
        if (status == 'active' && verifiedSet.contains(uid)) active++;
        // Pending = everything else that isn't inactive/rejected
        if (status == 'pending') pending++;
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
        totalMembers:    roleRows.length,
        activeMembers:   active,
        pendingMembers:  pending,
        withActiveLoans: withActive,
        withOverdueLoans: withOverdue,
      );
    } catch (_) {
      return MemberSummaryStats.empty;
    }
  }

  // ─── Verify a pending farmer (legacy — prefer approveMember) ──────────────
  //
  // Kept for backward compatibility with any existing call sites, but this
  // only sets member_id + is_verified. It does NOT activate user_roles.status,
  // assign a proper SP3 username, register in sp3_member_registry, or notify
  // the farmer. New approval actions should call approveMember() instead.

  Future<void> verifyFarmer({
    required String userId,
    required String memberId,
  }) async {
    await _client.from('user_roles').update({
      'status': 'active',
    }).eq('user_id', userId);

    await _client.from('farmer_profiles').update({
      'member_id':   memberId,
      'is_verified': true,
    }).eq('user_id', userId);
  }

  // ─── Approve a pending member (full workflow) ─────────────────────────────
  //
  // 1. Generates a member ID (SP3-<year>-<sequence>)
  // 2. Assigns a proper SP3-XXXX username if the farmer doesn't have one yet
  //    (self-registered farmers may have a placeholder/custom username)
  // 3. Activates user_roles.status
  // 4. Marks farmer_profiles.is_verified + sets member_id
  // 5. Adds/updates the sp3_member_registry entry
  // 6. Sends an in-app notification to the farmer

  Future<ApproveMemberResult> approveMember({
    required String userId,
    required String fullName,
  }) async {
    try {
      // 1. Generate member ID
      final year = DateTime.now().year;
      final existingRows = await _client
          .from('farmer_profiles')
          .select('member_id')
          .not('member_id', 'is', null);
      final count = existingRows.length + 1;
      final memberId = 'SP3-$year-${count.toString().padLeft(3, '0')}';

      // 2. Generate username (SP3-XXXX) if not yet assigned
      final infoRow = await _client
          .from('user_information')
          .select('username')
          .eq('user_id', userId)
          .maybeSingle();
      final existingUsername = infoRow?['username'] as String?;

      String username = existingUsername ?? '';
      if (username.isEmpty || !username.startsWith('sp3-')) {
        // Assign proper SP3 username
        final usernameResult = await _client.rpc(
            'suggest_next_username', params: {'p_prefix': 'SP3'});
        username = usernameResult as String;

        // Update user_information username
        await _client.from('user_information').update({
          'username': username,
        }).eq('user_id', userId);

        // Update auth.users email to match
        // Note: this requires the migration SQL function
        await _client.rpc('update_user_email_to_username', params: {
          'p_user_id': userId,
          'p_username': username,
        });
      }

      // 3. Activate user_roles
      await _client.from('user_roles').update({
        'status': 'active',
      }).eq('user_id', userId);

      // 4. Update farmer_profiles
      await _client.from('farmer_profiles').update({
        'member_id':   memberId,
        'is_verified': true,
      }).eq('user_id', userId);

      // 5. Add to sp3_member_registry if not already there
      final registryRow = await _client
          .from('sp3_member_registry')
          .select('id')
          .eq('registered_user_id', userId)
          .maybeSingle();

      if (registryRow == null) {
        await _client.from('sp3_member_registry').upsert({
          'full_name':            fullName,
          'is_registered':        true,
          'registered_user_id':   userId,
        }, onConflict: 'registered_user_id');
      } else {
        await _client.from('sp3_member_registry').update({
          'is_registered':      true,
          'registered_user_id': userId,
        }).eq('id', registryRow['id'] as String);
      }

      // 6. Send in-app notification to farmer
      await _client.from('notifications').insert({
        'user_id': userId,
        'type':    'member_approved',
        'title':   'Membership Approved!',
        'body':    'Congratulations! Your SP3 cooperative membership has been '
                   'approved. You now have full access to all farmer features. '
                   'Your Member ID is $memberId.',
        'is_read': false,
      });

      return ApproveMemberResult(
        success:  true,
        memberId: memberId,
        username: username,
      );
    } catch (e) {
      return ApproveMemberResult(
        success:  false,
        error:    e.toString(),
      );
    }
  }

  // ─── Reject a pending member ───────────────────────────────────────────────
  //
  // Sets status to 'inactive' — account exists but cannot log in to features.
  // Admin can re-evaluate later; we don't delete accounts.

  Future<void> rejectMember({required String userId}) async {
    await _client.from('user_roles').update({
      'status': 'inactive',
    }).eq('user_id', userId);

    // Notify farmer
    try {
      await _client.from('notifications').insert({
        'user_id': userId,
        'type':    'member_rejected',
        'title':   'Membership Status Update',
        'body':    'Your SP3 cooperative membership application was not approved '
                   'at this time. Please contact the SP3 office for more information.',
        'is_read': false,
      });
    } catch (_) {}
  }

  // ─── Set farmer status ────────────────────────────────────────────────────

  Future<void> setFarmerStatus({
    required String userId,
    required String status, // 'active' | 'inactive'
  }) async {
    await _client.from('user_roles').update({
      'status': status,
    }).eq('user_id', userId);
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
              (f.sitio?.toLowerCase().contains(q) ?? false))
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

    // Sort
    switch (filter.sortBy) {
      case FarmerSortOption.nameAZ:
        list.sort((a, b) => a.fullName.compareTo(b.fullName));
        break;
      case FarmerSortOption.recentHarvest:
        list.sort((a, b) {
          if (a.lastHarvestDate == null && b.lastHarvestDate == null) {
            return 0;
          }
          if (a.lastHarvestDate == null) return 1;
          if (b.lastHarvestDate == null) return -1;
          return b.lastHarvestDate!.compareTo(a.lastHarvestDate!);
        });
        break;
      case FarmerSortOption.memberId:
        list.sort((a, b) =>
            (a.memberId ?? '').compareTo(b.memberId ?? ''));
        break;
      case FarmerSortOption.loanBalance:
        list.sort((a, b) => b.outstandingLoanBalance
            .compareTo(a.outstandingLoanBalance));
        break;
    }

    return list;
  }
}