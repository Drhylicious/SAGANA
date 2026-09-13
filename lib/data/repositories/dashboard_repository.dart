import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dashboard_summary_model.dart';
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

    // Total earnings this month — three farmer income channels:
    // Marketplace (orders), Confirmed Cooperative Sales
    // (member_sales_transactions), and Informal Sales (informal_sales).
    // No fallback to approved-listing value: that would substitute a
    // fundamentally different metric (total listed value, whether or
    // not anything sold) for a farmer's actual earnings — worse than
    // showing 0, since it looks like a real number. Every other read
    // path in this app already fails toward "show less," never toward
    // "show a plausible but wrong bigger number" — this matches that
    // convention. Each of the three sources below has its own
    // independent try/catch so one source failing can't blank out the
    // other two — same reasoning, applied per-source instead of once.
    final startOfNextMonth = DateTime(now.year, now.month + 1, 1);

    double marketplaceEarnings = 0;
    try {
      final earningsResponse = await _client
          .from('orders')
          .select('total_price')
          .eq('farmer_id', _userId)
          .eq('status', 'completed')
          .gte('created_at', startOfMonth.toIso8601String());
      marketplaceEarnings = earningsResponse.fold<double>(
        0,
        (sum, row) => sum + (row['total_price'] as num).toDouble(),
      );
    } catch (_) {
      marketplaceEarnings = 0;
    }

    // member_sales_transactions.sale_date is a plain DATE column (not a
    // timestamp), so it needs an explicit calendar-date upper bound rather
    // than relying on "now" as the implicit end the way the two
    // timestamp-based sources below do.
    double cooperativeEarnings = 0;
    try {
      String dateOnly(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      final coopResponse = await _client
          .from('member_sales_transactions')
          .select('amount')
          .eq('farmer_id', _userId)
          .gte('sale_date', dateOnly(startOfMonth))
          .lt('sale_date', dateOnly(startOfNextMonth));
      cooperativeEarnings = coopResponse.fold<double>(
        0,
        (sum, row) => sum + (row['amount'] as num).toDouble(),
      );
    } catch (_) {
      cooperativeEarnings = 0;
    }

    // informal_sales.sale_date is a TIMESTAMPTZ (same shape as
    // orders.created_at), so this mirrors the orders query above directly.
    // amount is nullable on this table — a NULL amount counts as 0
    // (confirmed product decision, not an oversight).
    double informalEarnings = 0;
    try {
      final informalResponse = await _client
          .from('informal_sales')
          .select('amount')
          .eq('farmer_id', _userId)
          .gte('sale_date', startOfMonth.toIso8601String());
      informalEarnings = informalResponse.fold<double>(
        0,
        (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
      );
    } catch (_) {
      informalEarnings = 0;
    }

    totalEarnings = marketplaceEarnings + cooperativeEarnings + informalEarnings;

    final unsyncedCount = HiveService.getUnsyncedCount();

    return DashboardSummaryModel(
      totalYieldKg: totalYield,
      previousMonthYieldKg: lastMonthYield,
      totalEarnings: totalEarnings,
      earningsGoal: 60000,
      unsyncedCount: unsyncedCount,
    );
  }

  // ─── Recent Activity ──────────────────────────────────────────────────────
  //
  // Single source of truth for both Home's 5-item preview and the full
  // Activity screen — replaces the old two-method split (fetchRecentActivity
  // + the FullActivityFetch.fetchAllActivity extension), which independently
  // duplicated most of their query logic and had silently diverged in
  // coverage (e.g. listings only appeared in one of the two). Mirrors
  // AdminDashboardRepository.fetchRecentActivity()'s pattern exactly: query
  // every source with a generous fixed limit regardless of typeFilter,
  // collect, sort once, then apply typeFilter and offset/limit in Dart.

  Future<List<ActivityItem>> fetchActivity({
    int limit = 50,
    int offset = 0,
    ActivityFilter? typeFilter,
    String? searchQuery,
  }) async {
    final List<ActivityItem> items = [];
    const sourceLimit = 15;

    bool matchesSearch(String text) =>
        searchQuery == null ||
        searchQuery.isEmpty ||
        text.toLowerCase().contains(searchQuery.toLowerCase());

    // Harvests
    try {
      final harvests = await _client
          .from('harvest_records')
          .select(
              'id, crop_name, quantity_kg, batch_number, created_at, is_synced')
          .eq('farmer_id', _userId)
          .order('created_at', ascending: false)
          .limit(sourceLimit);
      for (final h in harvests) {
        final cropName = h['crop_name'] as String;
        final batchNo = h['batch_number'] as String? ?? '—';
        if (!matchesSearch(cropName) && !matchesSearch(batchNo)) continue;
        final isSynced = h['is_synced'] as bool? ?? false;
        items.add(ActivityItem(
          id: h['id'] as String,
          type: ActivityType.harvest,
          title: '$cropName Harvest',
          subtitle:
              'Batch #$batchNo • ${_formatRelative(DateTime.parse(h['created_at'] as String))}',
          valueLabel: '${h['quantity_kg']} kg',
          statusLabel: isSynced ? 'Synced' : 'Pending Sync',
          timestamp: DateTime.parse(h['created_at'] as String),
        ));
      }
    } catch (_) {}

    // Orders — title now reflects actual status (pending/approved/completed/
    // cancelled) rather than always reading "New Order Received" regardless
    // of what actually happened (Phase 7 fix).
    try {
      final orders = await _client
          .from('orders')
          .select(
              'id, quantity_kg, total_price, status, created_at, marketplace_listings(crop_name)')
          .eq('farmer_id', _userId)
          .order('created_at', ascending: false)
          .limit(sourceLimit);
      for (final o in orders) {
        final cropName =
            (o['marketplace_listings'] as Map?)?['crop_name'] as String? ??
                'Produce';
        if (!matchesSearch(cropName)) continue;
        items.add(ActivityItem(
          id: o['id'] as String,
          type: ActivityType.order,
          title: _orderStatusTitle(o['status'] as String),
          subtitle:
              '${o['quantity_kg']}kg $cropName • ${_formatRelative(DateTime.parse(o['created_at'] as String))}',
          valueLabel: '₱${(o['total_price'] as num).toStringAsFixed(0)}',
          statusLabel: _orderStatusLabel(o['status'] as String),
          timestamp: DateTime.parse(o['created_at'] as String),
        ));
      }
    } catch (_) {}

    // Listings — widened to all five meaningful states (Phase 7 fix).
    // pending_review covers both original submission and resubmission
    // after changes_required; submitted_at (bumped on resubmit) is used
    // as the timestamp so it reflects the most recent submission.
    try {
      final listings = await _client
          .from('marketplace_listings')
          .select(
              'id, crop_name, variety, status, admin_notes, updated_at, submitted_at, created_at')
          .eq('farmer_id', _userId)
          .inFilter('status', [
            'pending_review',
            'approved',
            'changes_required',
            'rejected',
            'withdrawn',
          ])
          .order('updated_at', ascending: false)
          .limit(sourceLimit);
      for (final l in listings) {
        final cropName = l['crop_name'] as String;
        final variety = l['variety'] as String? ?? '';
        final status = l['status'] as String;
        if (!matchesSearch(cropName)) continue;
        final timestamp = status == 'pending_review'
            ? DateTime.parse((l['submitted_at'] ?? l['created_at']) as String)
            : DateTime.parse(l['updated_at'] as String);
        items.add(ActivityItem(
          id: l['id'] as String,
          type: ActivityType.listing,
          title: _listingStatusTitle(status, cropName),
          subtitle: variety.isNotEmpty ? variety : cropName,
          statusLabel: _listingStatusLabel(status),
          isAlert: status == 'changes_required' || status == 'rejected',
          timestamp: timestamp,
        ));
      }
    } catch (_) {}

    // Loan payment reminders
    try {
      final loans = await _client
          .from('farmer_loans')
          .select(
              'id, reference_no, next_payment_date, monthly_payment, status')
          .eq('farmer_id', _userId)
          .eq('status', 'active')
          .not('next_payment_date', 'is', null)
          .order('next_payment_date', ascending: true)
          .limit(sourceLimit);
      for (final l in loans) {
        if (l['next_payment_date'] == null) continue;
        final ref = l['reference_no'] as String? ??
            'LOAN-${l['id'].toString().substring(0, 8).toUpperCase()}';
        items.add(ActivityItem(
          id: l['id'] as String,
          type: ActivityType.loan,
          title: 'Loan Payment Due',
          subtitle:
              'Next installment • ${_formatDate(DateTime.parse(l['next_payment_date'] as String))} • $ref',
          valueLabel:
              '₱${(l['monthly_payment'] as num? ?? 0).toStringAsFixed(0)}',
          statusLabel: 'Upcoming',
          isAlert: true,
          timestamp: DateTime.parse(l['next_payment_date'] as String),
        ));
      }
    } catch (_) {}

    // Crop requests (submission + outcome)
    items.addAll(await _fetchCropRequestActivity(
      userId: _userId,
      searchQuery: searchQuery,
      limit: sourceLimit,
    ));

    // Crop added (instant catalog add)
    items.addAll(await _fetchCropAddedActivity(
      userId: _userId,
      searchQuery: searchQuery,
      limit: sourceLimit,
    ));

    // Informal sales
    items.addAll(await _fetchInformalSaleActivity(
      userId: _userId,
      searchQuery: searchQuery,
      limit: sourceLimit,
    ));

    // Cooperative offer sales
    items.addAll(await _fetchCooperativeSaleActivity(
      userId: _userId,
      searchQuery: searchQuery,
      limit: sourceLimit,
    ));

    // Account activity — not search-filtered, same reasoning as before:
    // descriptions are short generic status text, searching adds little.
    items.addAll(await _fetchProfileActivity(
      userId: _userId,
      limit: sourceLimit,
    ));

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final filtered =
        typeFilter == null ? items : items.where(typeFilter.matches).toList();

    return filtered.skip(offset).take(limit).toList();
  }

  // ─── Crop Request Activity ──────────────────────────────────────────────

  Future<List<ActivityItem>> _fetchCropRequestActivity({
    required String userId,
    String? searchQuery,
    int limit = 15,
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
        items.add(ActivityItem(
          id: '${r['id']}-submitted',
          type: ActivityType.cropRequest,
          title: 'Crop Request Submitted',
          subtitle: name,
          statusLabel: 'Pending Review',
          timestamp: DateTime.parse(r['created_at'] as String),
        ));
        if (status != 'pending' && r['reviewed_at'] != null) {
          final isRejected = status == 'rejected';
          final reviewedAt = DateTime.parse(r['reviewed_at'] as String);
          items.add(ActivityItem(
            id: '${r['id']}-reviewed',
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

  // ─── Crop Added Activity (instant catalog add) ─────────────────────────────

  Future<List<ActivityItem>> _fetchCropAddedActivity({
    required String userId,
    String? searchQuery,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
    try {
      final crops = await _client
          .from('farmer_crops')
          .select('id, crop_name, created_at')
          .eq('farmer_id', userId)
          .not('crop_master_id', 'is', null)
          .order('created_at', ascending: false)
          .limit(limit);
      for (final c in crops) {
        final name = c['crop_name'] as String;
        if (searchQuery != null &&
            searchQuery.isNotEmpty &&
            !name.toLowerCase().contains(searchQuery.toLowerCase())) {
          continue;
        }
        items.add(ActivityItem(
          id: c['id'] as String,
          type: ActivityType.cropAdded,
          title: 'Crop Added',
          subtitle: name,
          statusLabel: 'Added',
          timestamp: DateTime.parse(c['created_at'] as String),
        ));
      }
    } catch (_) {}
    return items;
  }

  // ─── Informal Sale Activity ────────────────────────────────────────────────

  Future<List<ActivityItem>> _fetchInformalSaleActivity({
    required String userId,
    String? searchQuery,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
    try {
      final sales = await _client
          .from('informal_sales')
          .select('id, crop_name, quantity_kg, amount, buyer_name, sale_date')
          .eq('farmer_id', userId)
          .order('sale_date', ascending: false)
          .limit(limit);
      for (final s in sales) {
        final cropName = s['crop_name'] as String;
        if (searchQuery != null &&
            searchQuery.isNotEmpty &&
            !cropName.toLowerCase().contains(searchQuery.toLowerCase())) {
          continue;
        }
        final buyer = s['buyer_name'] as String?;
        items.add(ActivityItem(
          id: s['id'] as String,
          type: ActivityType.informalSale,
          title: 'Informal Sale',
          subtitle: buyer != null && buyer.isNotEmpty
              ? '$cropName • Sold to $buyer'
              : cropName,
          valueLabel: s['amount'] != null
              ? '₱${(s['amount'] as num).toStringAsFixed(0)}'
              : null,
          statusLabel: '${s['quantity_kg']} kg',
          timestamp: DateTime.parse(s['sale_date'] as String),
        ));
      }
    } catch (_) {}
    return items;
  }

  // ─── Cooperative Offer Sale Activity ────────────────────────────────────────

  Future<List<ActivityItem>> _fetchCooperativeSaleActivity({
    required String userId,
    String? searchQuery,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
    try {
      final sales = await _client
          .from('member_sales_transactions')
          .select('id, crop_name, quantity_kg, amount, sale_date, created_at')
          .eq('farmer_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      for (final s in sales) {
        final cropName = s['crop_name'] as String;
        if (searchQuery != null &&
            searchQuery.isNotEmpty &&
            !cropName.toLowerCase().contains(searchQuery.toLowerCase())) {
          continue;
        }
        items.add(ActivityItem(
          id: s['id'] as String,
          type: ActivityType.cooperativeSale,
          title: 'Cooperative Sale',
          subtitle: cropName,
          valueLabel: '₱${(s['amount'] as num).toStringAsFixed(0)}',
          statusLabel: '${s['quantity_kg']} kg',
          timestamp: DateTime.parse(s['created_at'] as String),
        ));
      }
    } catch (_) {}
    return items;
  }

  // ─── Account Activity (password, photo, basic info, farm details) ─────────

  Future<List<ActivityItem>> _fetchProfileActivity({
    required String userId,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
    try {
      final rows = await _client
          .from('farmer_profile_activity')
          .select('id, description, created_at')
          .eq('farmer_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      for (final r in rows) {
        items.add(ActivityItem(
          id: r['id'] as String,
          type: ActivityType.profile,
          title: r['description'] as String,
          subtitle: 'Account',
          statusLabel: 'Updated',
          timestamp: DateTime.parse(r['created_at'] as String),
        ));
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

  String _orderStatusTitle(String status) {
    switch (status) {
      case 'pending':   return 'New Order Received';
      case 'approved':  return 'Order Approved';
      case 'completed': return 'Order Completed';
      case 'cancelled': return 'Order Cancelled';
      default:          return 'Order Updated';
    }
  }

  String _listingStatusTitle(String status, String crop) {
    switch (status) {
      case 'pending_review':   return '$crop Listing Submitted';
      case 'approved':         return '$crop Listing Approved';
      case 'changes_required': return 'Changes Requested';
      case 'rejected':         return '$crop Listing Rejected';
      case 'withdrawn':        return '$crop Listing Withdrawn';
      default:                 return '$crop Listing Updated';
    }
  }

  String _listingStatusLabel(String status) {
    switch (status) {
      case 'pending_review':   return 'Pending Review';
      case 'approved':         return 'Active on Marketplace';
      case 'changes_required': return 'Needs Changes';
      case 'rejected':         return 'Rejected';
      case 'withdrawn':        return 'Withdrawn';
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