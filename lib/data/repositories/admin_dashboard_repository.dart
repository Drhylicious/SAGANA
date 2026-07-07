import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_dashboard_model.dart';

class AdminDashboardRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── KPI Summary ─────────────────────────────────────────────────────────────

  Future<AdminKpiSummary> fetchKpiSummary() async {
    int activeMembers = 0;
    double totalStockKg = 0;
    int pendingOrders = 0;
    double totalRevenue = 0;

    // Active farmer members
    try {
      final rows = await _client
          .from('user_roles')
          .select('user_id')
          .eq('role', 'farmer')
          .eq('status', 'active');
      activeMembers = rows.length;
    } catch (_) {}

    // Total available stock across all farmers
    try {
      final rows = await _client
          .from('inventory_batches')
          .select('available_kg')
          .inFilter('status', ['available', 'low_stock']);
      totalStockKg = rows.fold<double>(
        0,
        (sum, r) => sum + (r['available_kg'] as num).toDouble(),
      );
    } catch (_) {}

    // Pending orders
    try {
      final rows = await _client
          .from('orders')
          .select('id')
          .eq('status', 'pending');
      pendingOrders = rows.length;
    } catch (_) {}

    // Revenue this month from completed orders
    try {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final rows = await _client
          .from('orders')
          .select('total_price')
          .eq('status', 'completed')
          .gte('created_at', monthStart.toIso8601String());
      totalRevenue = rows.fold<double>(
        0,
        (sum, r) => sum + (r['total_price'] as num).toDouble(),
      );
    } catch (_) {}

    return AdminKpiSummary(
      activeMembers: activeMembers,
      totalMembersTarget: 52,
      totalStockKg: totalStockKg,
      pendingOrders: pendingOrders,
      totalRevenueThisMonth: totalRevenue,
    );
  }

  // ─── Urgent Actions ───────────────────────────────────────────────────────────

  Future<List<UrgentAction>> fetchUrgentActions() async {
    // Pending listings
    int pendingListings = 0;
    try {
      final rows = await _client
          .from('marketplace_listings')
          .select('id')
          .eq('status', 'pending_review');
      pendingListings = rows.length;
    } catch (_) {}

    // Overdue loans + first overdue farmer name
    int overdueLoans = 0;
    String overdueSubtitle = 'Review required';
    try {
      final rows = await _client
          .from('farmer_loans')
          .select('id, farmer_id, user_information(full_name)')
          .eq('status', 'overdue');
      overdueLoans = rows.length;
      if (rows.isNotEmpty) {
        final userInfo = rows.first['user_information'];
        final firstName = userInfo is Map
            ? (userInfo['full_name'] as String? ?? 'Unknown')
            : 'Unknown';
        overdueSubtitle = overdueLoans > 1
            ? '$firstName +${overdueLoans - 1} more'
            : firstName;
      }
    } catch (_) {}

    // Low stock batches
    int lowStockBatches = 0;
    String lowStockCrops = '';
    try {
      final rows = await _client
          .from('inventory_batches')
          .select('crop_name')
          .eq('status', 'low_stock');
      lowStockBatches = rows.length;
      if (rows.isNotEmpty) {
        final crops = rows
            .map((r) => r['crop_name'] as String)
            .toSet()
            .take(3)
            .join(', ');
        lowStockCrops = crops;
      }
    } catch (_) {}

    return [
      UrgentAction(
        type: UrgentActionType.pendingListings,
        title: '$pendingListings Listing${pendingListings == 1 ? '' : 's'} Awaiting Approval',
        subtitle: 'Submitted by farmers, review required',
        count: pendingListings,
        isCritical: false,
      ),
      UrgentAction(
        type: UrgentActionType.overdueLoans,
        title: '$overdueLoans Overdue Loan Payment${overdueLoans == 1 ? '' : 's'}',
        subtitle: overdueSubtitle,
        count: overdueLoans,
        isCritical: true,
      ),
      UrgentAction(
        type: UrgentActionType.lowStock,
        title: '$lowStockBatches Batch${lowStockBatches == 1 ? '' : 'es'} Below Minimum Stock',
        subtitle: lowStockCrops.isEmpty ? 'Review inventory' : lowStockCrops,
        count: lowStockBatches,
        isCritical: false,
      ),
    ];
  }

  // ─── BOD Meeting Info ─────────────────────────────────────────────────────────

  Future<BodMeetingInfo> fetchBodMeetingInfo() async {
    int farmersWithLoans = 0;
    try {
      final rows = await _client
          .from('farmer_loans')
          .select('farmer_id')
          .neq('status', 'paid');
      // Count distinct farmers
      final distinct =
          rows.map((r) => r['farmer_id'] as String).toSet().length;
      farmersWithLoans = distinct;
    } catch (_) {}

    return BodMeetingInfo(
      nextMeetingDate: _nextFirstSaturday(),
      farmersWithOutstandingLoans: farmersWithLoans,
    );
  }

  /// Calculates the next 1st Saturday of the month (BOD meeting schedule)
  DateTime _nextFirstSaturday() {
    final now = DateTime.now();
    // Find the 1st Saturday of this month
    DateTime firstSat = DateTime(now.year, now.month, 1);
    while (firstSat.weekday != DateTime.saturday) {
      firstSat = firstSat.add(const Duration(days: 1));
    }
    // If it's already passed, go to next month
    if (firstSat.isBefore(now)) {
      final nextMonth = now.month == 12
          ? DateTime(now.year + 1, 1, 1)
          : DateTime(now.year, now.month + 1, 1);
      firstSat = nextMonth;
      while (firstSat.weekday != DateTime.saturday) {
        firstSat = firstSat.add(const Duration(days: 1));
      }
    }
    return firstSat;
  }

  // ─── Recent Activity ──────────────────────────────────────────────────────────

  Future<List<AdminActivityItem>> fetchRecentActivity({int limit = 10}) async {
    final List<AdminActivityItem> items = [];
    final now = DateTime.now();

    // Recent harvests (all farmers)
    try {
      final rows = await _client
          .from('harvest_records')
          .select(
              'id, crop_name, quantity_kg, created_at, farmer_id, user_information!inner(full_name)')
          .order('created_at', ascending: false)
          .limit(3);
      for (final r in rows) {
        final userInfo = r['user_information'];
        final name = userInfo is Map
            ? (userInfo['full_name'] as String? ?? 'Farmer')
            : 'Farmer';
        final qty = r['quantity_kg'];
        final crop = r['crop_name'] as String;
        final ts = DateTime.parse(r['created_at'] as String);
        items.add(AdminActivityItem(
          id: r['id'] as String,
          type: AdminActivityType.harvest,
          description: 'New harvest: $name — ${qty}kg $crop',
          highlightedName: name,
          timeLabel: _timeLabel(ts, now),
          timestamp: ts,
          isPrimary: true,
        ));
      }
    } catch (_) {}

    // Recent listings submitted
    try {
      final rows = await _client
          .from('marketplace_listings')
          .select(
              'id, crop_name, status, created_at, farmer_id, user_information!inner(full_name)')
          .order('created_at', ascending: false)
          .limit(3);
      for (final r in rows) {
        final userInfo = r['user_information'];
        final name = userInfo is Map
            ? (userInfo['full_name'] as String? ?? 'Farmer')
            : 'Farmer';
        final crop = r['crop_name'] as String;
        final status = r['status'] as String;
        final ts = DateTime.parse(r['created_at'] as String);
        final isApproved = status == 'approved';
        items.add(AdminActivityItem(
          id: r['id'] as String,
          type: AdminActivityType.listing,
          description: isApproved
              ? 'Listing approved: $crop — $name'
              : 'Listing submitted: $name — $crop',
          highlightedName: isApproved ? crop : name,
          timeLabel: _timeLabel(ts, now),
          timestamp: ts,
          isPrimary: isApproved,
        ));
      }
    } catch (_) {}

    // Recent orders
    try {
      final rows = await _client
          .from('orders')
          .select('id, total_price, created_at, buyer_id')
          .order('created_at', ascending: false)
          .limit(2);
      for (final r in rows) {
        final price = (r['total_price'] as num).toStringAsFixed(2);
        final ts = DateTime.parse(r['created_at'] as String);
        items.add(AdminActivityItem(
          id: r['id'] as String,
          type: AdminActivityType.order,
          description: 'Order placed: ₱$price',
          timeLabel: _timeLabel(ts, now),
          timestamp: ts,
          isPrimary: false,
        ));
      }
    } catch (_) {}

    // Recent price updates
    try {
      final rows = await _client
          .from('price_records')
          .select('id, crop_name, price, recorded_at')
          .order('recorded_at', ascending: false)
          .limit(2);
      for (final r in rows) {
        final crop = r['crop_name'] as String;
        final price = (r['price'] as num).toStringAsFixed(2);
        final ts = DateTime.parse(r['recorded_at'] as String);
        items.add(AdminActivityItem(
          id: r['id'] as String,
          type: AdminActivityType.price,
          description: 'Price updated: $crop — ₱$price/kg',
          highlightedName: crop,
          timeLabel: _timeLabel(ts, now),
          timestamp: ts,
          isPrimary: false,
        ));
      }
    } catch (_) {}

    // New members
    try {
      final rows = await _client
          .from('user_roles')
          .select('user_id, created_at, user_information!inner(full_name)')
          .eq('role', 'farmer')
          .order('created_at', ascending: false)
          .limit(2);
      for (final r in rows) {
        final userInfo = r['user_information'];
        final name = userInfo is Map
            ? (userInfo['full_name'] as String? ?? 'New Member')
            : 'New Member';
        final ts = DateTime.parse(r['created_at'] as String);
        items.add(AdminActivityItem(
          id: r['user_id'] as String,
          type: AdminActivityType.member,
          description: 'New member: $name',
          highlightedName: name,
          timeLabel: _timeLabel(ts, now),
          timestamp: ts,
          isPrimary: true,
        ));
      }
    } catch (_) {}

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items.take(limit).toList();
  }

  // ─── Cooperative Performance ──────────────────────────────────────────────────

  Future<CoopPerformanceSummary> fetchCoopPerformance() async {
    int totalHarvests = 0;
    double totalStock = 0;
    int activeListings = 0;
    int completedSales = 0;
    int activeMembersThisSeason = 0;

    try {
      final rows = await _client.from('harvest_records').select('id');
      totalHarvests = rows.length;
    } catch (_) {}

    try {
      final rows = await _client
          .from('inventory_batches')
          .select('available_kg');
      totalStock = rows.fold<double>(
          0, (s, r) => s + (r['available_kg'] as num).toDouble());
    } catch (_) {}

    try {
      final rows = await _client
          .from('marketplace_listings')
          .select('id')
          .eq('status', 'approved');
      activeListings = rows.length;
    } catch (_) {}

    try {
      final rows = await _client
          .from('orders')
          .select('id')
          .eq('status', 'completed');
      completedSales = rows.length;
    } catch (_) {}

    // Members who have recorded at least one harvest this season
    try {
      final seasonStart =
          DateTime(DateTime.now().year, 1, 1).toIso8601String();
      final rows = await _client
          .from('harvest_records')
          .select('farmer_id')
          .gte('harvest_date', seasonStart);
      activeMembersThisSeason =
          rows.map((r) => r['farmer_id'] as String).toSet().length;
    } catch (_) {}

    return CoopPerformanceSummary(
      totalHarvests: totalHarvests,
      totalStockKg: totalStock,
      activeListings: activeListings,
      completedSales: completedSales,
      activeMembersThisSeason: activeMembersThisSeason,
      totalMembers: 52,
    );
  }

  // ─── Unread notification count ────────────────────────────────────────────────

  Future<int> fetchUnreadCount() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return 0;
      final rows = await _client
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  // ─── Tools last-update labels ─────────────────────────────────────────────────

  Future<Map<String, String>> fetchToolsLastUpdated() async {
    final result = <String, String>{};

    // Last price update
    try {
      final rows = await _client
          .from('price_records')
          .select('crop_name, recorded_at')
          .order('recorded_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        final crop = rows.first['crop_name'] as String;
        final ts = DateTime.parse(rows.first['recorded_at'] as String);
        result['price'] = '$crop — ${_timeLabel(ts, DateTime.now())}';
      }
    } catch (_) {}

    // Last broadcast
    try {
      final rows = await _client
          .from('notifications')
          .select('title, created_at')
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        final title = rows.first['title'] as String;
        final ts = DateTime.parse(rows.first['created_at'] as String);
        result['broadcast'] = '$title — ${_timeLabel(ts, DateTime.now())}';
      }
    } catch (_) {}

    // Mapped farmers count
    try {
      final mapped = await _client
          .from('farmer_profiles')
          .select('user_id')
          .not('farm_latitude', 'is', null);
      final total = await _client.from('farmer_profiles').select('user_id');
      result['map'] =
          '${mapped.length} farmers mapped, ${total.length - mapped.length} not yet mapped';
    } catch (_) {}

    return result;
  }

  // ─── Time label helper ────────────────────────────────────────────────────────

  String _timeLabel(DateTime dt, DateTime now) {
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }
}
