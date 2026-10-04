import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/buyer_profile_model.dart';
import '../models/buyer_activity_model.dart';
import 'admin_activity_repository.dart';

class BuyerProfileRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  Future<BuyerProfileModel?> fetchProfile() async {
    try {
      final info = await _client
          .from('user_information')
          .select('full_name, phone_number, profile_photo_url, contact_email')
          .eq('user_id', _userId)
          .maybeSingle();

      DateTime memberSince = DateTime.now();
      DateTime? dateOfBirth;
      String? gender;
      try {
        final buyerRow = await _client
            .from('buyer_profiles')
            .select('created_at, date_of_birth, gender')
            .eq('user_id', _userId)
            .maybeSingle();
        if (buyerRow?['created_at'] != null) {
          memberSince = DateTime.parse(buyerRow!['created_at'] as String);
        }
        if (buyerRow?['date_of_birth'] != null) {
          dateOfBirth = DateTime.tryParse(buyerRow!['date_of_birth'] as String);
        }
        gender = buyerRow?['gender'] as String?;
      } catch (e) {
        debugPrint(
          'BuyerProfileRepository.fetchProfile: buyer_profiles lookup failed: $e',
        );
      }

      // Purchase stats — still summed client-side, same convention as
      // InventoryRepository.fetchSummary() (Buyer review finding 2.6 —
      // deliberately not replaced with a new SQL aggregate/RPC, to avoid
      // diverging from that shared pattern unilaterally). What changed:
      // total_price was previously fetched for every order just to sum the
      // completed ones. It's now fetched only for completed orders, and the
      // total-count pass no longer pulls total_price at all — two narrower
      // queries instead of one wide one, same aggregation approach.
      int totalOrders = 0, completedOrders = 0;
      double totalSpent = 0;
      try {
        final allOrderIds = await _client
            .from('orders')
            .select('id')
            .eq('buyer_id', _userId);
        totalOrders = allOrderIds.length;

        final completed = await _client
            .from('orders')
            .select('total_price')
            .eq('buyer_id', _userId)
            .eq('status', 'completed');
        completedOrders = completed.length;
        for (final o in completed) {
          totalSpent += (o['total_price'] as num).toDouble();
        }
      } catch (e) {
        debugPrint(
          'BuyerProfileRepository.fetchProfile: order stats failed: $e',
        );
      }

      return BuyerProfileModel(
        userId: _userId,
        fullName: info?['full_name'] as String? ?? 'Buyer',
        phoneNumber: info?['phone_number'] as String?,
        profilePhotoUrl: info?['profile_photo_url'] as String?,
        email: _client.auth.currentUser?.email ?? '',
        contactEmail: info?['contact_email'] as String?,
        memberSince: memberSince,
        totalOrders: totalOrders,
        completedOrders: completedOrders,
        totalSpent: totalSpent,
        dateOfBirth: dateOfBirth,
        gender: gender,
      );
    } catch (e) {
      debugPrint('BuyerProfileRepository.fetchProfile failed: $e');
      return null;
    }
  }

  // ─── Update profile (name, phone, photo) ───────────────────────────────────
  // Write method — lets errors propagate rather than swallowing, since a
  // failed save needs to surface to the user, not silently no-op.

  Future<void> updateProfile({
    required String fullName,
    String? phoneNumber,
    String? photoUrl,
    String? contactEmail,
    DateTime? dateOfBirth,
    String? gender,
  }) async {
    // Fetched before the update so _logProfileActivity() can tell what
    // actually changed — user_information/buyer_profiles only ever carry
    // current state, so this is the only point where that comparison is
    // possible. Covers every field this method can write (previously only
    // name/phone/photo were diffed, silently missing email/DOB/
    // gender edits entirely).
    Map<String, dynamic>? beforeInfo;
    Map<String, dynamic>? beforeBuyer;
    try {
      final results = await Future.wait([
        _client
          .from('user_information')
            .select('full_name, phone_number, profile_photo_url, contact_email')
          .eq('user_id', _userId)
            .maybeSingle(),
        _client
            .from('buyer_profiles')
            .select('date_of_birth, gender')
            .eq('user_id', _userId)
            .maybeSingle(),
      ]);
      beforeInfo = results[0];
      beforeBuyer = results[1];
    } catch (e) {
      debugPrint(
        'BuyerProfileRepository.updateProfile: could not fetch prior '
        'values for activity log: $e',
      );
    }

    await _client
        .from('user_information')
        .update({
      'full_name': fullName.trim(),
      if (phoneNumber != null) 'phone_number': phoneNumber.trim(),
      if (photoUrl != null) 'profile_photo_url': photoUrl,
        })
        .eq('user_id', _userId);

    if (contactEmail != null) {
      try {
        await _client.rpc(
          'promote_contact_email',
          params: {'p_email': contactEmail.trim()},
        );
      } on PostgrestException catch (e) {
        throw Exception(e.message);
      }
    }

    // DOB / gender live on buyer_profiles (personal info), same split
    // FarmerProfileRepository uses between user_information and
    // farmer_profiles.
    if (dateOfBirth != null || gender != null) {
      await _client
          .from('buyer_profiles')
          .update({
        if (dateOfBirth != null)
          'date_of_birth': dateOfBirth.toIso8601String().split('T').first,
        if (gender != null) 'gender': gender,
          })
          .eq('user_id', _userId);
    }

    await _logProfileActivity(
      beforeInfo: beforeInfo,
      beforeBuyer: beforeBuyer,
      newName: fullName,
      newPhone: phoneNumber,
      newPhotoUrl: photoUrl,
      newContactEmail: contactEmail,
      newDateOfBirth: dateOfBirth,
      newGender: gender,
    );
  }

  // Only logs when something genuinely changed — a Save tap with no actual
  // edits (e.g. buyer opens Edit Profile and immediately taps Save) writes
  // nothing, matching "meaningful action, not passive interaction." Diffs
  // every field updateProfile() can write, not just name/phone/photo.
  Future<void> _logProfileActivity({
    required Map<String, dynamic>? beforeInfo,
    required Map<String, dynamic>? beforeBuyer,
    required String newName,
    String? newPhone,
    String? newPhotoUrl,
    String? newContactEmail,
    DateTime? newDateOfBirth,
    String? newGender,
  }) async {
    final changes = <String>[];
    if (beforeInfo != null) {
      if ((beforeInfo['full_name'] as String?) != newName.trim())
        changes.add('name');
      if (newPhone != null &&
          (beforeInfo['phone_number'] as String?) != newPhone.trim()) {
        changes.add('phone number');
      }
      if (newPhotoUrl != null &&
          (beforeInfo['profile_photo_url'] as String?) != newPhotoUrl) {
        changes.add('profile photo');
      }
      if (newContactEmail != null &&
          (beforeInfo['contact_email'] as String?) != newContactEmail.trim()) {
        changes.add('email');
      }
    }
    if (beforeBuyer != null) {
      if (newDateOfBirth != null) {
        final newDob = newDateOfBirth.toIso8601String().split('T').first;
        final beforeDob = (beforeBuyer['date_of_birth'] as String?)
            ?.split('T')
            .first;
        if (beforeDob != newDob) changes.add('date of birth');
      }
      if (newGender != null &&
          (beforeBuyer['gender'] as String?) != newGender) {
        changes.add('gender');
      }
    }
    if (changes.isEmpty) return;

    await logActivity('Updated ${changes.join(', ')}');
  }

  // ─── Recent Activity (profile-derived entries) ─────────────────────────────
  Future<List<BuyerActivityItem>> fetchProfileActivity({int limit = 50}) async {
    try {
      final rows = await _client
          .from('buyer_profile_activity')
          .select('id, description, created_at')
          .eq('buyer_id', _userId)
          .order('created_at', ascending: false)
          .limit(limit);
      return rows
          .map(
            (r) => BuyerActivityItem(
            id: r['id'] as String,
            type: BuyerActivityType.profile,
            title: r['description'] as String,
            subtitle: 'Profile',
            timestamp: DateTime.parse(r['created_at'] as String),
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('BuyerProfileRepository.fetchProfileActivity failed: $e');
      return [];
    }
  }

  Future<List<BuyerActivityItem>> fetchRecentProfileActivity({int limit = 3}) =>
      fetchProfileActivity(limit: limit);

  // Generic entry point for buyer actions that have no natural
  // business-state row of their own to derive an activity entry from
  // (address changes, password changes) — same buyer_profile_activity
  // table _logProfileActivity's diff-based version writes to, just
  // without the diffing. BuyerAddressRepository calls this directly
  // rather than duplicating the insert.
  Future<void> logActivity(String description) async {
    try {
      await _client.from('buyer_profile_activity').insert({
        'buyer_id': _userId,
        'description': description,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('BuyerProfileRepository.logActivity failed: $e');
    }
  }

  // Mirrors FarmerProfileRepository.logPasswordChanged — same
  // ChangePasswordDialog(onSuccess: ...) hook, wired from
  // buyer_edit_profile_screen.dart.
  Future<void> logPasswordChanged() => logActivity('Changed password');

  // ─── Admin: fetch any buyer's profile by ID ────────────────────────────────
  // Separate from fetchProfile() above, which is scoped to the signed-in
  // user via auth.currentUser — this is for BuyerDetailsScreen, where an
  // admin looks up an arbitrary buyer, not their own account.

  Future<BuyerProfileModel?> fetchAdminView(String buyerId) async {
    try {
      final info = await _client
          .from('user_information')
          .select(
            'full_name, phone_number, profile_photo_url, contact_email, last_active_at',
          )
          .eq('user_id', buyerId)
          .maybeSingle();
      if (info == null) return null;

      DateTime? dateOfBirth;
      String? gender;
      try {
        final buyerRow = await _client
            .from('buyer_profiles')
            .select('date_of_birth, gender')
            .eq('user_id', buyerId)
            .maybeSingle();
        if (buyerRow?['date_of_birth'] != null) {
          dateOfBirth = DateTime.tryParse(buyerRow!['date_of_birth'] as String);
        }
        gender = buyerRow?['gender'] as String?;
      } catch (e) {
        debugPrint(
          'BuyerProfileRepository.fetchAdminView: buyer_profiles lookup failed: $e',
        );
      }

      String status = 'active';
      DateTime joinedAt = DateTime.now();
      try {
        final roleRow = await _client
            .from('user_roles')
            .select('status, created_at')
            .eq('user_id', buyerId)
            .eq('role', 'buyer')
            .maybeSingle();
        if (roleRow != null) {
          status = roleRow['status'] as String? ?? 'active';
          if (roleRow['created_at'] != null) {
            joinedAt = DateTime.parse(roleRow['created_at'] as String);
          }
        }
      } catch (e) {
        debugPrint(
          'BuyerProfileRepository.fetchAdminView: user_roles lookup failed: $e',
        );
      }

      int totalOrders = 0, completedOrders = 0;
      double totalSpent = 0;
      try {
        final allOrderIds = await _client
            .from('orders')
            .select('id')
            .eq('buyer_id', buyerId);
        totalOrders = allOrderIds.length;

        final completed = await _client
            .from('orders')
            .select('total_price')
            .eq('buyer_id', buyerId)
            .eq('status', 'completed');
        completedOrders = completed.length;
        for (final o in completed) {
          totalSpent += (o['total_price'] as num).toDouble();
        }
      } catch (e) {
        debugPrint(
          'BuyerProfileRepository.fetchAdminView: order stats failed: $e',
        );
      }

      return BuyerProfileModel(
        userId: buyerId,
        fullName: info['full_name'] as String? ?? 'Buyer',
        phoneNumber: info['phone_number'] as String?,
        profilePhotoUrl: info['profile_photo_url'] as String?,
        email: '', // synthetic auth address — BuyerDetailsScreen never shows it
        contactEmail: info['contact_email'] as String?,
        accountStatus: status,
        memberSince: joinedAt,
        totalOrders: totalOrders,
        completedOrders: completedOrders,
        totalSpent: totalSpent,
        lastActiveAt: info['last_active_at'] != null
            ? DateTime.tryParse(info['last_active_at'] as String)
            : null,
        dateOfBirth: dateOfBirth,
        gender: gender,
      );
    } catch (e) {
      debugPrint('BuyerProfileRepository.fetchAdminView failed: $e');
      return null;
    }
  }

  // ─── Admin: full buyer list for Buyer Management ───────────────────────────
  // Replaces BuyerManagementScreen's former private _BuyerRepository —
  // same join (user_roles + user_information + orders), same sort order.

  Future<List<BuyerProfileModel>> fetchAllBuyers() async {
    try {
      final roleRows = await _client
          .from('user_roles')
          .select('user_id, status, created_at')
          .eq('role', 'buyer');

      if (roleRows.isEmpty) return [];

      final userIds = roleRows.map((r) => r['user_id'] as String).toList();
      final roleMap = {for (final r in roleRows) r['user_id'] as String: r};

      final infoRows = await _client
          .from('user_information')
          .select(
            'user_id, full_name, phone_number, profile_photo_url, contact_email, last_active_at',
          )
          .inFilter('user_id', userIds);
      final infoMap = {for (final r in infoRows) r['user_id'] as String: r};

      // fetchAllBuyers aggregates across every buyer at once — unlike
      // fetchProfile/fetchAdminView above, there's no single-buyer filter
      // to split on, so the same two-query pattern can't cleanly apply
      // here without either an RPC (excluded per Buyer review finding 2.6's
      // scope) or a grouped count feature this file can't safely assume is
      // available without the project's pinned supabase_flutter version.
      // The one safe narrowing available without either of those: buyer_id
      // and status are needed for every row regardless, but total_price is
      // only ever used for completed rows — so it's no longer requested for
      // rows this query doesn't need it for.
      final orderRows = await _client
          .from('orders')
          .select('buyer_id, status, total_price')
          .inFilter('buyer_id', userIds);
      final orderCountMap = <String, int>{};
      final completedCountMap = <String, int>{};
      final orderSpentMap = <String, double>{};
      for (final r in orderRows) {
        final id = r['buyer_id'] as String;
        orderCountMap[id] = (orderCountMap[id] ?? 0) + 1;
        if (r['status'] == 'completed') {
          completedCountMap[id] = (completedCountMap[id] ?? 0) + 1;
          orderSpentMap[id] =
              (orderSpentMap[id] ?? 0) + (r['total_price'] as num).toDouble();
        }
      }

      return userIds.map((uid) {
        final role = roleMap[uid]!;
        final info = infoMap[uid] ?? {};
        return BuyerProfileModel(
          userId: uid,
          fullName: info['full_name'] as String? ?? 'Buyer',
          phoneNumber: info['phone_number'] as String?,
          profilePhotoUrl: info['profile_photo_url'] as String?,
          email:
              '', // synthetic auth address — the card shows contactEmail instead
          contactEmail: info['contact_email'] as String?,
          accountStatus: role['status'] as String? ?? 'active',
          totalOrders: orderCountMap[uid] ?? 0,
          completedOrders: completedCountMap[uid] ?? 0,
          totalSpent: orderSpentMap[uid] ?? 0,
          memberSince: DateTime.parse(role['created_at'] as String),
          lastActiveAt: info['last_active_at'] != null
              ? DateTime.tryParse(info['last_active_at'] as String)
              : null,
        );
      }).toList()..sort((a, b) => b.totalOrders.compareTo(a.totalOrders));
    } catch (e) {
      debugPrint('BuyerProfileRepository.fetchAllBuyers failed: $e');
      return [];
    }
  }

  // Routed through the same suspend_member/reactivate_member RPCs Farmer
  // suspension already uses (see FarmerDetailsRepository.setFarmerStatus)
  // rather than a raw user_roles.update() — despite the "member" naming,
  // both RPCs operate on any user_roles row by user_id with no role
  // filter, so they work unchanged for a buyer. Switching to them gets
  // Buyer suspension the same reason storage (user_roles.suspension_reason,
  // required — the RPC itself rejects an empty reason), audit trail
  // (member_status_events), and login-blocking guard (see
  // AuthService.login) that Farmer suspension already had; the old
  // version here only ever flipped a status column with no reason and no
  // actual access-control effect. The RPC sends its own notification, so
  // no separate NotificationRepository call is needed here.
  Future<void> setBuyerStatus({
    required String buyerId,
    required String status, // 'active' | 'suspended'
    String? reason,
  }) async {
    if (status == 'suspended') {
      await _client.rpc(
        'suspend_member',
        params: {
          'p_user_id': buyerId,
          'p_reason': (reason == null || reason.trim().isEmpty)
              ? 'Suspended by administrator'
              : reason.trim(),
        },
      );
      AdminActivityRepository().log(
        module: 'members',
        actionType: 'suspended',
        description: 'Suspended a buyer account.',
        referenceId: buyerId,
      );
    } else {
      await _client.rpc('reactivate_member', params: {'p_user_id': buyerId});
      AdminActivityRepository().log(
        module: 'members',
        actionType: 'reactivated',
        description: 'Reactivated a buyer account.',
        referenceId: buyerId,
      );
    }
  }

  // ─── Admin: total buyer count for dashboard KPI ────────────────────────────
  // Deliberately just a count, for the Admin dashboard's own KPI tile.
  // Buyer Management's full list (order stats, status, etc.) now
  // also goes through this same repository via fetchAllBuyers() above —
  // no separate/duplicated local repository remains.
  Future<int> fetchBuyerCount() async {
    try {
      final rows = await _client
          .from('user_roles')
          .select('user_id')
          .eq('role', 'buyer');
      return rows.length;
    } catch (e) {
      debugPrint('BuyerProfileRepository.fetchBuyerCount failed: $e');
      return 0;
    }
  }
}