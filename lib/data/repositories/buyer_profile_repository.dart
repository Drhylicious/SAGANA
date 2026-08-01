import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/buyer_profile_model.dart';

class BuyerProfileRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  Future<BuyerProfileModel?> fetchProfile() async {
    try {
      final info = await _client
          .from('user_information')
          .select('full_name, phone_number, profile_photo_url')
          .eq('user_id', _userId)
          .maybeSingle();

      DateTime memberSince = DateTime.now();
      try {
        final buyerRow = await _client
            .from('buyer_profiles')
            .select('created_at')
            .eq('user_id', _userId)
            .maybeSingle();
        if (buyerRow?['created_at'] != null) {
          memberSince = DateTime.parse(buyerRow!['created_at'] as String);
        }
      } catch (_) {}

      // Purchase stats — summed client-side, same convention as
      // InventoryRepository.fetchSummary().
      int totalOrders = 0, completedOrders = 0;
      double totalSpent = 0;
      try {
        final orders = await _client
            .from('orders')
            .select('status, total_price')
            .eq('buyer_id', _userId);
        totalOrders = orders.length;
        for (final o in orders) {
          if (o['status'] == 'completed') {
            completedOrders++;
            totalSpent += (o['total_price'] as num).toDouble();
          }
        }
      } catch (_) {}

      return BuyerProfileModel(
        userId: _userId,
        fullName: info?['full_name'] as String? ?? 'Buyer',
        phoneNumber: info?['phone_number'] as String?,
        profilePhotoUrl: info?['profile_photo_url'] as String?,
        email: _client.auth.currentUser?.email ?? '',
        memberSince: memberSince,
        totalOrders: totalOrders,
        completedOrders: completedOrders,
        totalSpent: totalSpent,
      );
    } catch (_) {
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
  }) async {
    await _client.from('user_information').update({
      'full_name': fullName.trim(),
      if (phoneNumber != null) 'phone_number': phoneNumber.trim(),
      if (photoUrl != null) 'profile_photo_url': photoUrl,
    }).eq('user_id', _userId);
  }

  // ─── Admin: fetch any buyer's profile by ID ────────────────────────────────
  // Separate from fetchProfile() above, which is scoped to the signed-in
  // user via auth.currentUser — this is for BuyerDetailsScreen, where an
  // admin looks up an arbitrary buyer, not their own account.

  Future<BuyerProfileModel?> fetchAdminView(String buyerId) async {
    try {
      final info = await _client
          .from('user_information')
          .select('full_name, phone_number, profile_photo_url, sitio')
          .eq('user_id', buyerId)
          .maybeSingle();
      if (info == null) return null;

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
      } catch (_) {}

      int totalOrders = 0, completedOrders = 0;
      double totalSpent = 0;
      try {
        final orders = await _client
            .from('orders')
            .select('status, total_price')
            .eq('buyer_id', buyerId);
        totalOrders = orders.length;
        for (final o in orders) {
          if (o['status'] == 'completed') {
            completedOrders++;
            totalSpent += (o['total_price'] as num).toDouble();
          }
        }
      } catch (_) {}

      return BuyerProfileModel(
        userId: buyerId,
        fullName: info['full_name'] as String? ?? 'Buyer',
        phoneNumber: info['phone_number'] as String?,
        sitio: info['sitio'] as String?,
        profilePhotoUrl: info['profile_photo_url'] as String?,
        email: '', // not fetched here — BuyerDetailsScreen never shows it
        accountStatus: status,
        memberSince: joinedAt,
        totalOrders: totalOrders,
        completedOrders: completedOrders,
        totalSpent: totalSpent,
      );
    } catch (_) {
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
          .select('user_id, full_name, phone_number, sitio, profile_photo_url')
          .inFilter('user_id', userIds);
      final infoMap = {for (final r in infoRows) r['user_id'] as String: r};

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
          orderSpentMap[id] = (orderSpentMap[id] ?? 0) + (r['total_price'] as num).toDouble();
        }
      }

      return userIds.map((uid) {
        final role = roleMap[uid]!;
        final info = infoMap[uid] ?? {};
        return BuyerProfileModel(
          userId: uid,
          fullName: info['full_name'] as String? ?? 'Buyer',
          phoneNumber: info['phone_number'] as String?,
          sitio: info['sitio'] as String?,
          profilePhotoUrl: info['profile_photo_url'] as String?,
          email: '', // not fetched for the list view — no card shows it
          accountStatus: role['status'] as String? ?? 'active',
          totalOrders: orderCountMap[uid] ?? 0,
          completedOrders: completedCountMap[uid] ?? 0,
          totalSpent: orderSpentMap[uid] ?? 0,
          memberSince: DateTime.parse(role['created_at'] as String),
        );
      }).toList()
        ..sort((a, b) => b.totalOrders.compareTo(a.totalOrders));
    } catch (_) {
      return [];
    }
  }

  Future<void> setBuyerStatus({
    required String buyerId,
    required String status,
  }) async {
    await _client
        .from('user_roles')
        .update({'status': status})
        .eq('user_id', buyerId)
        .eq('role', 'buyer');
  }

  // ─── Admin: total buyer count for dashboard KPI ────────────────────────────
  // Deliberately just a count. The full buyer list — with order stats, sitio,
  // status — is still fetched separately inside BuyerManagementScreen's own
  // local repository; that duplication is tracked to be resolved when we
  // redesign Buyer Management itself, not smuggled in here.
  Future<int> fetchBuyerCount() async {
    try {
      final rows = await _client
          .from('user_roles')
          .select('user_id')
          .eq('role', 'buyer');
      return rows.length;
    } catch (_) {
      return 0;
    }
  }
}