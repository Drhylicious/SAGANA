import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dashboard_summary_model.dart';
import '../models/price_record_model.dart';
import '../services/hive_service.dart';

class DashboardRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  // ─── KPI Summary ─────────────────────────────────────────────────────────────

  Future<DashboardSummaryModel> fetchSummary() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startOfLastMonth = DateTime(now.year, now.month - 1, 1);
    final endOfLastMonth = DateTime(now.year, now.month, 0);

    double totalYield = 0;
    double lastMonthYield = 0;
    double totalEarnings = 0;

    // Total yield this month
    try {
      final yieldResponse = await _client
          .from('harvest_records')
          .select('quantity_kg')
          .eq('farmer_id', _userId)
          .gte('harvest_date', startOfMonth.toIso8601String());
      totalYield = yieldResponse.fold<double>(
        0,
        (sum, row) => sum + (row['quantity_kg'] as num).toDouble(),
      );
    } catch (_) {}

    // Yield last month for trend
    try {
      final lastMonthYieldResponse = await _client
          .from('harvest_records')
          .select('quantity_kg')
          .eq('farmer_id', _userId)
          .gte('harvest_date', startOfLastMonth.toIso8601String())
          .lte('harvest_date', endOfLastMonth.toIso8601String());
      lastMonthYield = lastMonthYieldResponse.fold<double>(
        0,
        (sum, row) => sum + (row['quantity_kg'] as num).toDouble(),
      );
    } catch (_) {}

    // Total earnings from completed orders this month.
    // No fallback to approved-listing value: that would substitute a
    // fundamentally different metric (total listed value, whether or
    // not anything sold) for a farmer's actual earnings — worse than
    // showing 0, since it looks like a real number. Every other read
    // path in this app already fails toward "show less," never toward
    // "show a plausible but wrong bigger number" — this now matches
    // that convention instead of being the one exception.
    try {
      final earningsResponse = await _client
          .from('orders')
          .select('total_price')
          .eq('farmer_id', _userId)
          .eq('status', 'completed')
          .gte('created_at', startOfMonth.toIso8601String());
      totalEarnings = earningsResponse.fold<double>(
        0,
        (sum, row) => sum + (row['total_price'] as num).toDouble(),
      );
    } catch (_) {
      totalEarnings = 0;
    }

    final unsyncedCount = HiveService.getUnsyncedCount();

    return DashboardSummaryModel(
      totalYieldKg: totalYield,
      previousMonthYieldKg: lastMonthYield,
      totalEarnings: totalEarnings,
      earningsGoal: 60000,
      unsyncedCount: unsyncedCount,
    );
  }

  // ─── Market Prices (ticker) ───────────────────────────────────────────────────

  Future<List<PriceRecordModel>> fetchLatestPrices() async {
    try {
      final response = await _client
          .from('price_records')
          .select()
          .order('recorded_at', ascending: false)
          .limit(20);

      final List<PriceRecordModel> prices = [];
      final Set<String> seen = {};
      for (final row in response) {
        final key = '${row['crop_id']}_${row['price_type']}';
        if (!seen.contains(key)) {
          seen.add(key);
          prices.add(PriceRecordModel.fromMap(row));
        }
      }

      if (prices.isNotEmpty) {
        await HiveService.cachePrices(
          {for (var p in prices) '${p.cropId}_${p.priceType}': p.toMap()},
        );
      }
      return prices;
    } catch (_) {
      return _getCachedPrices();
    }
  }

  List<PriceRecordModel> _getCachedPrices() {
    final cached = HiveService.getCachedPrices();
    if (cached == null) return [];
    return cached.values
        .map((v) =>
            PriceRecordModel.fromMap(Map<String, dynamic>.from(v as Map)))
        .toList();
  }

  // ─── Recent Activity ──────────────────────────────────────────────────────────

  Future<List<ActivityItem>> fetchRecentActivity({int limit = 5}) async {
    final List<ActivityItem> items = [];

    // Recent harvests
    try {
      final harvests = await _client
          .from('harvest_records')
          .select(
              'id, crop_name, quantity_kg, batch_number, created_at, is_synced')
          .eq('farmer_id', _userId)
          .order('created_at', ascending: false)
          .limit(3);
      for (final h in harvests) {
        items.add(ActivityItem(
          id: h['id'] as String,
          type: ActivityType.harvest,
          title: '${h['crop_name']} Harvest',
          subtitle:
              'Batch #${h['batch_number'] ?? '—'} • ${_formatRelative(DateTime.parse(h['created_at'] as String))}',
          valueLabel: '${h['quantity_kg']} kg',
          statusLabel:
              (h['is_synced'] as bool? ?? false) ? 'Synced' : 'Pending Sync',
          timestamp: DateTime.parse(h['created_at'] as String),
        ));
      }
    } catch (_) {}

    // Recent orders — now safe, orders table exists
    try {
      final orders = await _client
          .from('orders')
          .select(
              'id, quantity_kg, total_price, status, created_at, marketplace_listings(crop_name)')
          .eq('farmer_id', _userId)
          .order('created_at', ascending: false)
          .limit(2);
      for (final o in orders) {
        final cropName =
            (o['marketplace_listings'] as Map?)?['crop_name'] as String? ??
                'Produce';
        items.add(ActivityItem(
          id: o['id'] as String,
          type: ActivityType.order,
          title: 'Order Received',
          subtitle:
              '${o['quantity_kg']}kg $cropName • ${_formatRelative(DateTime.parse(o['created_at'] as String))}',
          valueLabel:
              '₱${(o['total_price'] as num).toStringAsFixed(0)}',
          statusLabel: _orderStatusLabel(o['status'] as String),
          timestamp: DateTime.parse(o['created_at'] as String),
        ));
      }
    } catch (_) {}

    // Upcoming loan payments — uses corrected column names
    try {
      final loans = await _client
          .from('farmer_loans')
          .select('id, next_payment_date, monthly_payment')
          .eq('farmer_id', _userId)
          .eq('status', 'active')
          .not('next_payment_date', 'is', null)
          .order('next_payment_date', ascending: true)
          .limit(1);
      for (final l in loans) {
        if (l['next_payment_date'] != null) {
          items.add(ActivityItem(
            id: l['id'] as String,
            type: ActivityType.loan,
            title: 'Loan Payment Due',
            subtitle:
                'Next installment • ${_formatDate(DateTime.parse(l['next_payment_date'] as String))}',
            valueLabel:
                '₱${(l['monthly_payment'] as num? ?? 0).toStringAsFixed(0)}',
            statusLabel: 'Upcoming',
            isAlert: true,
            timestamp: DateTime.parse(l['next_payment_date'] as String),
          ));
        }
      }
    } catch (_) {}

    // Recent crop request activity
    items.addAll(await _fetchCropRequestActivity(userId: _userId, limit: 3));

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items.take(limit).toList();
  }

  // ─── Notification Count ───────────────────────────────────────────────────────
  // FIX: was querying non-existent 'admin_notifications' table.
  // Now correctly queries the 'notifications' table built in supabase_schema_notifications.sql

  Future<int> fetchUnreadNotificationCount() async {
    try {
      final response = await _client
          .from('notifications')
          .select('id')
          .eq('user_id', _userId)
          .eq('is_read', false);
      return response.length;
    } catch (_) {
      return 0;
    }
  }

  // ─── Crop Request Activity (submission + outcome) ─────────────────────────
  // A single crop_requests row can produce up to two ActivityItems: the
  // submission itself, and — once reviewed — the approval/rejection outcome.

  Future<List<ActivityItem>> _fetchCropRequestActivity({
    required String userId,
    String? searchQuery,
    int limit = 50,
  }) async {
    final List<ActivityItem> items = [];
    try {
      final requests = await _client
          .from('crop_requests')
          .select('id, requested_name, status, created_at, reviewed_at')
          .eq('farmer_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);

      for (final r in requests) {
        final name = r['requested_name'] as String;
        if (searchQuery != null &&
            searchQuery.isNotEmpty &&
            !name.toLowerCase().contains(searchQuery.toLowerCase())) {
          continue;
        }

        final status = r['status'] as String;
        final createdAt = DateTime.parse(r['created_at'] as String);

        items.add(ActivityItem(
          id: '${r['id']}_submitted',
          type: ActivityType.cropRequest,
          title: 'Crop Request Submitted',
          subtitle: name,
          statusLabel: status == 'pending' ? 'Pending Review' : 'Submitted',
          timestamp: createdAt,
        ));

        if (status != 'pending' && r['reviewed_at'] != null) {
          final reviewedAt = DateTime.parse(r['reviewed_at'] as String);
          final isRejected = status == 'rejected';
          items.add(ActivityItem(
            id: '${r['id']}_reviewed',
            type: ActivityType.cropRequest,
            title: isRejected ? 'Crop Request Declined' : 'Crop Request Approved',
            subtitle: name,
            statusLabel: isRejected ? 'Declined' : 'Approved',
            isAlert: isRejected,
            timestamp: reviewedAt,
          ));
        }
      }
    } catch (_) {}
    return items;
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  String _formatRelative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 0) return 'Today';
    return '${diff.inDays}d ago';
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  String _orderStatusLabel(String status) {
    switch (status) {
      case 'pending':   return 'Processing';
      case 'approved':  return 'Approved';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      default:          return status;
    }
  }
}

// ─── Full Activity Fetch Extension ───────────────────────────────────────────

extension FullActivityFetch on DashboardRepository {
  Future<List<ActivityItem>> fetchAllActivity({
    String? searchQuery,
    int limit = 50,
  }) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;
    final List<ActivityItem> items = [];

    // Harvests
    try {
      final harvests = await client
          .from('harvest_records')
          .select(
              'id, crop_name, quantity_kg, batch_number, harvest_date, created_at, is_synced, quality_grade')
          .eq('farmer_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      for (final h in harvests) {
        final cropName = h['crop_name'] as String;
        final batchNo = h['batch_number'] as String? ?? '—';
        final qty = h['quantity_kg'];
        final isSynced = h['is_synced'] as bool? ?? false;
        final grade = h['quality_grade'] as String?;
        if (searchQuery != null && searchQuery.isNotEmpty) {
          final q = searchQuery.toLowerCase();
          if (!cropName.toLowerCase().contains(q) &&
              !batchNo.toLowerCase().contains(q)) {
            continue;
          }
        }
        items.add(ActivityItem(
          id: h['id'] as String,
          type: ActivityType.harvest,
          title: '$cropName Harvest Logged',
          subtitle: 'Batch #$batchNo • $qty kg',
          statusLabel: isSynced
              ? (grade != null ? _gradeStatus(grade) : 'Verified')
              : 'Pending Sync',
          timestamp: DateTime.parse(h['created_at'] as String),
        ));
      }
    } catch (_) {}

    // Orders
    try {
      final orders = await client
          .from('orders')
          .select(
              'id, quantity_kg, total_price, status, created_at, marketplace_listings(crop_name)')
          .eq('farmer_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      for (final o in orders) {
        final cropName =
            (o['marketplace_listings'] as Map?)?['crop_name'] as String? ??
                'Produce';
        if (searchQuery != null && searchQuery.isNotEmpty) {
          if (!cropName.toLowerCase().contains(searchQuery.toLowerCase())) {
            continue;
          }
        }
        items.add(ActivityItem(
          id: o['id'] as String,
          type: ActivityType.order,
          title: 'New Order Received',
          subtitle: cropName,
          valueLabel:
              '₱${(o['total_price'] as num).toStringAsFixed(2)}',
          statusLabel: _orderStatusLabel(o['status'] as String),
          timestamp: DateTime.parse(o['created_at'] as String),
        ));
      }
    } catch (_) {}

    // Listings with status updates
    try {
      final listings = await client
          .from('marketplace_listings')
          .select(
              'id, crop_name, variety, status, admin_notes, updated_at, created_at')
          .eq('farmer_id', userId)
          .inFilter('status', ['approved', 'changes_required'])
          .order('updated_at', ascending: false)
          .limit(limit);
      for (final l in listings) {
        final cropName = l['crop_name'] as String;
        final variety = l['variety'] as String? ?? '';
        final status = l['status'] as String;
        if (searchQuery != null && searchQuery.isNotEmpty) {
          if (!cropName.toLowerCase().contains(searchQuery.toLowerCase())) {
            continue;
          }
        }
        items.add(ActivityItem(
          id: l['id'] as String,
          type: ActivityType.listing,
          title: _listingStatusTitle(status, cropName),
          subtitle: variety.isNotEmpty ? variety : cropName,
          statusLabel: _listingStatusLabel(status),
          isAlert: status == 'changes_required',
          timestamp: DateTime.parse(l['updated_at'] as String),
        ));
      }
    } catch (_) {}

    // Loan payment reminders — uses corrected column names
    try {
      final loans = await client
          .from('farmer_loans')
          .select(
              'id, loan_reference, next_payment_date, monthly_payment, status')
          .eq('farmer_id', userId)
          .not('next_payment_date', 'is', null)
          .order('next_payment_date', ascending: true)
          .limit(10);
      for (final l in loans) {
        if (l['next_payment_date'] == null) continue;
        final ref = l['loan_reference'] as String? ??
            'LOAN-${l['id'].toString().substring(0, 8).toUpperCase()}';
        items.add(ActivityItem(
          id: l['id'] as String,
          type: ActivityType.loan,
          title: 'Loan Payment Due',
          subtitle: ref,
          valueLabel:
              '₱${(l['monthly_payment'] as num? ?? 0).toStringAsFixed(2)}',
          statusLabel: 'Reminder',
          isAlert: true,
          timestamp: DateTime.parse(l['next_payment_date'] as String),
        ));
      }
    } catch (_) {}

    // Crop requests (submission + outcome), search-aware
    items.addAll(await DashboardRepository()._fetchCropRequestActivity(
      userId: userId,
      searchQuery: searchQuery,
      limit: limit,
    ));

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items.take(limit).toList();
  }

  String _gradeStatus(String grade) {
    switch (grade.toUpperCase()) {
      case 'A':
      case 'B':
        return 'Verified';
      default:
        return 'Pending Quality Check';
    }
  }

  String _orderStatusLabel(String status) {
    switch (status) {
      case 'pending':   return 'Processing';
      case 'approved':  return 'Approved';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      default:          return status;
    }
  }

  String _listingStatusTitle(String status, String crop) {
    switch (status) {
      case 'approved':         return '$crop Listing Approved';
      case 'changes_required': return 'Changes Requested';
      default:                 return '$crop Listing Updated';
    }
  }

  String _listingStatusLabel(String status) {
    switch (status) {
      case 'approved':         return 'Active on Marketplace';
      case 'changes_required': return 'Needs Changes';
      default:                 return status;
    }
  }
}

// ─── Latest price for a specific crop (Create Listing reference) ──────────────

extension CropPriceFetch on DashboardRepository {
  Future<double?> fetchLatestPriceForCrop(String cropName) async {
    final client = Supabase.instance.client;
    try {
      final response = await client
          .from('price_records')
          .select('price')
          .ilike('crop_name', cropName)
          .order('recorded_at', ascending: false)
          .limit(1);
      if (response.isEmpty) return null;
      return (response.first['price'] as num).toDouble();
    } catch (_) {
      return null;
    }
  }
}