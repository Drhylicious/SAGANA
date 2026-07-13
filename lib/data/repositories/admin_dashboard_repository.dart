import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_dashboard_model.dart';
import '../../routes/app_routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminDashboardRepository
//
// [INVENTORY-AWARE] markers indicate queries that will switch from
// inventory_batches → cooperative_inventory once that module is live.
// Method signatures remain stable; only the table name changes.
// ─────────────────────────────────────────────────────────────────────────────

class AdminDashboardRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── KPI Summary ──────────────────────────────────────────────────────────

  Future<AdminKpiSummary> fetchKpiSummary() async {
    int activeMembers = 0;
    int pendingMembers = 0;
    double totalStockKg = 0;
    int pendingListings = 0;
    int pendingOrders = 0;
    double totalRevenue = 0;
    int activeLoans = 0;
    int overdueLoans = 0;

    try {
      // Only count farmers who are both status=active AND is_verified=true
      final roleRows = await _client
          .from('user_roles')
          .select('user_id, status')
          .eq('role', 'farmer')
          .eq('status', 'active');

      if (roleRows.isNotEmpty) {
        final activeIds = roleRows.map((r) => r['user_id'] as String).toList();
        final profileRows = await _client
            .from('farmer_profiles')
            .select('user_id')
            .inFilter('user_id', activeIds)
            .eq('is_verified', true);
        activeMembers = profileRows.length;
      }

      final pendingRows = await _client
          .from('user_roles')
          .select('user_id')
          .eq('role', 'farmer')
          .eq('status', 'pending');
      pendingMembers = pendingRows.length;
    } catch (_) {}

    // [INVENTORY-AWARE]
    try {
      final coopRows = await _client
          .from('cooperative_inventory')
          .select('quantity_on_hand')
          .eq('is_active', true);
      if (coopRows.isNotEmpty) {
        totalStockKg = coopRows.fold<double>(
            0, (s, r) => s + (r['quantity_on_hand'] as num).toDouble());
      } else {
        final batchRows = await _client
            .from('inventory_batches')
            .select('available_kg')
            .inFilter('status', ['available', 'low_stock']);
        totalStockKg = batchRows.fold<double>(
            0, (s, r) => s + (r['available_kg'] as num).toDouble());
      }
    } catch (_) {}

    try {
      final rows = await _client
          .from('marketplace_listings')
          .select('id')
          .eq('status', 'pending_review');
      pendingListings = rows.length;
    } catch (_) {}

    try {
      final rows = await _client
          .from('orders')
          .select('id')
          .eq('status', 'pending');
      pendingOrders = rows.length;
    } catch (_) {}

    try {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final rows = await _client
          .from('orders')
          .select('total_price')
          .eq('status', 'completed')
          .gte('created_at', monthStart.toIso8601String());
      totalRevenue = rows.fold<double>(
          0, (s, r) => s + (r['total_price'] as num).toDouble());
    } catch (_) {}

    try {
      final active = await _client
          .from('farmer_loans')
          .select('id')
          .eq('status', 'active');
      activeLoans = active.length;
      final overdue = await _client
          .from('farmer_loans')
          .select('id')
          .eq('status', 'overdue');
      overdueLoans = overdue.length;
    } catch (_) {}

    return AdminKpiSummary(
      activeMembers: activeMembers,
      totalMembersTarget: 52,
      pendingMembers: pendingMembers,
      totalStockKg: totalStockKg,
      pendingListings: pendingListings,
      pendingOrders: pendingOrders,
      totalRevenueThisMonth: totalRevenue,
      activeLoans: activeLoans,
      overdueLoans: overdueLoans,
    );
  }

  // ─── Dashboard Priorities (Dynamic Hero Card) ──────────────────────────────
  // Returns ordered list of items for the "Today's Priorities" hero card.
  // Items are sorted: critical first, then warning, then info.
  // BOD countdown is included only when meeting is ≤ 7 days away.

  Future<List<DashboardPriority>> fetchDashboardPriorities() async {
    final List<DashboardPriority> priorities = [];
    final now = DateTime.now();
    final bodDate = _nextFirstSaturday();
    final daysUntilBod = bodDate.difference(now).inDays;

    // BOD countdown — only when within 7 days
    if (daysUntilBod <= 7) {
      int farmersWithLoans = 0;
      try {
        final rows = await _client
            .from('farmer_loans')
            .select('farmer_id')
            .neq('status', 'paid');
        farmersWithLoans =
            rows.map((r) => r['farmer_id'] as String).toSet().length;
      } catch (_) {}

      priorities.add(DashboardPriority(
        id: 'bod',
        level: DashboardPriorityLevel.warning,
        label: daysUntilBod == 0
            ? 'BOD Meeting — TODAY'
            : 'BOD Meeting in $daysUntilBod day${daysUntilBod == 1 ? '' : 's'}',
        value: '$farmersWithLoans farmers with outstanding loans',
        route: AppRoutes.loanDashboard,
        useGo: true, // switch to Loans tab
      ));
    }

    // Overdue loans — always critical
    try {
      final rows = await _client
          .from('farmer_loans')
          .select('id')
          .eq('status', 'overdue');
      if (rows.isNotEmpty) {
        priorities.add(DashboardPriority(
          id: 'overdue_loans',
          level: DashboardPriorityLevel.critical,
          label: '${rows.length} Overdue Loan${rows.length == 1 ? '' : 's'}',
          value: 'Immediate attention required',
          route: AppRoutes.loanDashboard,
          useGo: true,
        ));
      }
    } catch (_) {}

    // Pending listings
    try {
      final rows = await _client
          .from('marketplace_listings')
          .select('id')
          .eq('status', 'pending_review');
      if (rows.isNotEmpty) {
        priorities.add(DashboardPriority(
          id: 'pending_listings',
          level: DashboardPriorityLevel.warning,
          label: '${rows.length} Listing${rows.length == 1 ? '' : 's'} Awaiting Approval',
          value: 'Farmers waiting for review',
          route: AppRoutes.pendingApprovals,
          useGo: true, // switch to Listings tab
        ));
      }
    } catch (_) {}

    // Low stock — [INVENTORY-AWARE]
    try {
      final rows = await _client
          .from('inventory_batches')
          .select('crop_name')
          .eq('status', 'low_stock');
      if (rows.isNotEmpty) {
        final crops =
            rows.map((r) => r['crop_name'] as String).toSet().take(2).join(', ');
        priorities.add(DashboardPriority(
          id: 'low_stock',
          level: DashboardPriorityLevel.warning,
          label: '${rows.length} Batch${rows.length == 1 ? '' : 'es'} Low on Stock',
          value: crops,
          route: AppRoutes.adminInventory,
          useGo: false, // push above shell
        ));
      }
    } catch (_) {}

    // Pending members
    try {
      final rows = await _client
          .from('user_roles')
          .select('user_id')
          .eq('role', 'farmer')
          .eq('status', 'pending');
      if (rows.isNotEmpty) {
        priorities.add(DashboardPriority(
          id: 'pending_members',
          level: DashboardPriorityLevel.info,
          label: '${rows.length} Member${rows.length == 1 ? '' : 's'} Pending Verification',
          value: 'New registrations to review',
          route: AppRoutes.farmerManagement,
          useGo: true, // switch to Members tab
        ));
      }
    } catch (_) {}

    // Sort: critical → warning → info
    priorities.sort((a, b) => a.level.index.compareTo(b.level.index));
    return priorities;
  }

  // ─── Inventory Alerts ──────────────────────────────────────────────────────
  // [INVENTORY-AWARE]: will query cooperative_inventory once module is live.

  Future<List<InventoryAlertItem>> fetchInventoryAlerts() async {
    try {
      final rows = await _client
          .from('inventory_batches')
          .select('id, crop_name, batch_number, available_kg, status')
          .inFilter('status', ['low_stock', 'depleted'])
          .order('available_kg', ascending: true)
          .limit(5);
      return rows.map((r) {
        final status = r['status'] as String;
        return InventoryAlertItem(
          id: r['id'] as String,
          cropName: r['crop_name'] as String,
          batchNumber: r['batch_number'] as String? ?? '—',
          availableKg: (r['available_kg'] as num).toDouble(),
          alertLevel: status == 'depleted'
              ? InventoryAlertLevel.depleted
              : InventoryAlertLevel.low,
          lastMovementSource: 'harvest',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Calendar Events ───────────────────────────────────────────────────────

  Future<List<CalendarEvent>> fetchCalendarEvents({
    required int year,
    required int month,
  }) async {
    final List<CalendarEvent> events = [];

    // BOD Meeting — auto-generated
    final bodDate = _firstSaturdayOf(year, month);
    events.add(CalendarEvent(
      id: 'bod-$year-$month',
      type: CalendarEventType.bodMeeting,
      date: bodDate,
      title: 'BOD Meeting',
      subtitle: 'Board of Directors Monthly Meeting',
      sourceModule: 'system',
    ));

    // Loan due dates
    try {
      final start = DateTime(year, month, 1);
      final end = DateTime(year, month + 1, 1);
      final loanRows = await _client
          .from('farmer_loans')
          .select('id, farmer_id, next_payment_date')
          .gte('next_payment_date', start.toIso8601String())
          .lt('next_payment_date', end.toIso8601String())
          .neq('status', 'paid');

      if (loanRows.isNotEmpty) {
        final farmerIds = loanRows
            .map((r) => r['farmer_id'] as String)
            .toSet()
            .toList();
        final infoRows = await _client
            .from('user_information')
            .select('user_id, full_name')
            .inFilter('user_id', farmerIds);
        final nameMap = {
          for (final r in infoRows)
            r['user_id'] as String: r['full_name'] as String? ?? 'Farmer'
        };
        for (final r in loanRows) {
          final dt = DateTime.parse(r['next_payment_date'] as String);
          final name = nameMap[r['farmer_id'] as String] ?? 'Farmer';
          events.add(CalendarEvent(
            id: 'loan-${r['id']}',
            type: CalendarEventType.loanDue,
            date: dt,
            title: 'Loan Payment Due',
            subtitle: name,
            referenceId: r['id'] as String,
            sourceModule: 'loans',
          ));
        }
      }
    } catch (_) {}

    // Harvests grouped by date
    try {
      final start = DateTime(year, month, 1);
      final end = DateTime(year, month + 1, 1);
      final rows = await _client
          .from('harvest_records')
          .select('id, crop_name, harvest_date, farmer_id')
          .gte('harvest_date', start.toIso8601String())
          .lt('harvest_date', end.toIso8601String());

      final Map<String, List<Map<String, dynamic>>> byDate = {};
      for (final r in rows) {
        final dateKey = (r['harvest_date'] as String).substring(0, 10);
        byDate.putIfAbsent(dateKey, () => []).add(r);
      }
      for (final entry in byDate.entries) {
        final dt = DateTime.parse(entry.key);
        final count = entry.value.length;
        final crops = entry.value
            .map((r) => r['crop_name'] as String)
            .toSet()
            .take(2)
            .join(', ');
        events.add(CalendarEvent(
          id: 'harvest-${entry.key}',
          type: CalendarEventType.harvest,
          date: dt,
          title: '$count Harvest${count == 1 ? '' : 's'} Recorded',
          subtitle: crops,
          sourceModule: 'harvest',
        ));
      }
    } catch (_) {}

    // Broadcasts
    try {
      final start = DateTime(year, month, 1);
      final end = DateTime(year, month + 1, 1);
      final rows = await _client
          .from('broadcast_logs')
          .select('id, title, sent_at, category')
          .gte('sent_at', start.toIso8601String())
          .lt('sent_at', end.toIso8601String())
          .not('sent_at', 'is', null);
      for (final r in rows) {
        final dt = DateTime.parse(r['sent_at'] as String);
        events.add(CalendarEvent(
          id: 'broadcast-${r['id']}',
          type: CalendarEventType.announcement,
          date: dt,
          title: r['title'] as String,
          subtitle: (r['category'] as String?)?.toUpperCase(),
          referenceId: r['id'] as String,
          sourceModule: 'broadcast',
        ));
      }
    } catch (_) {}

    // Programs placeholder — insert point for program_activities table
    events.sort((a, b) => a.date.compareTo(b.date));
    return events;
  }

  // ─── BOD Meeting Info ──────────────────────────────────────────────────────

  Future<BodMeetingInfo> fetchBodMeetingInfo() async {
    int farmersWithLoans = 0;
    try {
      final rows = await _client
          .from('farmer_loans')
          .select('farmer_id')
          .neq('status', 'paid');
      farmersWithLoans =
          rows.map((r) => r['farmer_id'] as String).toSet().length;
    } catch (_) {}

    return BodMeetingInfo(
      nextMeetingDate: _nextFirstSaturday(),
      farmersWithOutstandingLoans: farmersWithLoans,
    );
  }

  // ─── Management Module Badges ──────────────────────────────────────────────

  Future<List<ManagementModuleCard>> fetchManagementModuleBadges() async {
    String inventoryBadge = '—';
    bool inventoryAlert = false;
    String cropsBadge = '—';
    String loanItemsBadge = '—';
    String supplyChainBadge = '—';
    String pricesBadge = '—';

    // Reads from cooperative_inventory (admin-managed) — NOT inventory_batches
    try {
      final rows = await _client
          .from('cooperative_inventory')
          .select('quantity_on_hand, reorder_level, is_active')
          .eq('is_active', true);
      final total = rows.length;
      final lowOrDepleted = rows.where((r) {
        final onHand = (r['quantity_on_hand'] as num).toDouble();
        final reorder = (r['reorder_level'] as num?)?.toDouble() ?? 0;
        return onHand <= reorder || onHand <= 0;
      }).length;

      inventoryBadge = total == 0
          ? 'No items'
          : lowOrDepleted > 0
              ? '$lowOrDepleted low / $total items'
              : '$total items';
      inventoryAlert = lowOrDepleted > 0;
    } catch (_) {
      inventoryBadge = 'No items';
    }

    try {
      final rows = await _client
          .from('crop_master')
          .select('id')
          .eq('is_active', true);
      cropsBadge = rows.isEmpty ? 'No crops' : '${rows.length} crops';
    } catch (_) {}

    try {
      final rows = await _client
          .from('loan_items_master')
          .select('id')
          .eq('is_active', true);
      loanItemsBadge = rows.isEmpty ? 'No items' : '${rows.length} items';
    } catch (_) {}

    try {
      final mapped = await _client
          .from('farmer_profiles')
          .select('user_id')
          .not('farm_latitude', 'is', null);
      supplyChainBadge = mapped.isEmpty ? '0 mapped' : '${mapped.length} mapped';
    } catch (_) {}

    try {
      final rows = await _client
          .from('price_records')
          .select('crop_name, recorded_at')
          .order('recorded_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        final crop = rows.first['crop_name'] as String;
        final ts = DateTime.parse(rows.first['recorded_at'] as String);
        pricesBadge = '$crop · ${_timeLabel(ts, DateTime.now())}';
      } else {
        pricesBadge = 'No entries';
      }
    } catch (_) {}

    return [
      ManagementModuleCard(
        id: 'inventory',
        title: 'Inventory',
        subtitle: 'Cooperative stock levels',
        badgeLabel: inventoryBadge,
        hasBadgeAlert: inventoryAlert,
        route: AppRoutes.adminInventory,
        useGo: false,
      ),
      ManagementModuleCard(
        id: 'crops',
        title: 'Crop Management',
        subtitle: 'Available crops & categories',
        badgeLabel: cropsBadge,
        hasBadgeAlert: false,
        route: AppRoutes.cropManagement,
        useGo: false,
      ),
      const ManagementModuleCard(
        id: 'programs',
        title: 'Program Management',
        subtitle: 'Cooperative programs',
        badgeLabel: 'Manage',
        hasBadgeAlert: false,
        route: AppRoutes.programManagement,
        useGo: false,
      ),
      ManagementModuleCard(
        id: 'loan-items',
        title: 'Loan Items',
        subtitle: 'Seeds, fertilizers & supplies',
        badgeLabel: loanItemsBadge,
        hasBadgeAlert: false,
        route: AppRoutes.loanItemManagement,
        useGo: false,
      ),
      ManagementModuleCard(
        id: 'supply-chain',
        title: 'Supply Chain',
        subtitle: 'Cooperative workflow & flow',
        badgeLabel: supplyChainBadge,
        hasBadgeAlert: false,
        route: AppRoutes.supplyChainMap,
        useGo: false,
      ),
      ManagementModuleCard(
        id: 'prices',
        title: 'Price Management',
        subtitle: 'SP3, DA-AMAD & market prices',
        badgeLabel: pricesBadge,
        hasBadgeAlert: false,
        route: AppRoutes.priceManagement,
        useGo: false,
      ),
    ];
  }

  // ─── Recent Activity ───────────────────────────────────────────────────────

  Future<List<AdminActivityItem>> fetchRecentActivity({
    int limit = 10,
    int offset = 0,
    AdminActivityType? typeFilter,
  }) async {
    final List<AdminActivityItem> items = [];
    final now = DateTime.now();

    Future<Map<String, String>> fetchNames(List<String> ids) async {
      if (ids.isEmpty) return {};
      try {
        final rows = await _client
            .from('user_information')
            .select('user_id, full_name')
            .inFilter('user_id', ids);
        return {
          for (final r in rows)
            r['user_id'] as String: r['full_name'] as String? ?? 'Unknown'
        };
      } catch (_) {
        return {};
      }
    }

    try {
      final rows = await _client
          .from('harvest_records')
          .select('id, crop_name, quantity_kg, created_at, farmer_id')
          .order('created_at', ascending: false)
          .limit(3);
      if (rows.isNotEmpty) {
        final names = await fetchNames(
          rows.map((r) => r['farmer_id'] as String).toList(),
        );
        for (final r in rows) {
          final name = names[r['farmer_id'] as String] ?? 'Farmer';
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
            sourceModule: 'harvest',
            referenceId: r['farmer_id'] as String,
          ));
        }
      }
    } catch (_) {}

    try {
      final rows = await _client
          .from('marketplace_listings')
          .select('id, crop_name, status, submitted_at, farmer_id')
          .order('submitted_at', ascending: false)
          .limit(3);
      if (rows.isNotEmpty) {
        final names = await fetchNames(
          rows.map((r) => r['farmer_id'] as String).toList(),
        );
        for (final r in rows) {
          final name = names[r['farmer_id'] as String] ?? 'Farmer';
          final crop = r['crop_name'] as String;
          final status = r['status'] as String;
          final ts = DateTime.parse(r['submitted_at'] as String);
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
            sourceModule: 'listings',
            referenceId: r['id'] as String,
          ));
        }
      }
    } catch (_) {}

    try {
      final rows = await _client
          .from('orders')
          .select('id, total_price, created_at')
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
          sourceModule: 'listings',
          referenceId: r['id'] as String,
        ));
      }
    } catch (_) {}

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
          sourceModule: 'prices',
        ));
      }
    } catch (_) {}

    try {
      final rows = await _client
          .from('user_roles')
          .select('user_id, created_at')
          .eq('role', 'farmer')
          .order('created_at', ascending: false)
          .limit(2);
      if (rows.isNotEmpty) {
        final names = await fetchNames(
          rows.map((r) => r['user_id'] as String).toList(),
        );
        for (final r in rows) {
          final name = names[r['user_id'] as String] ?? 'New Member';
          final ts = DateTime.parse(r['created_at'] as String);
          items.add(AdminActivityItem(
            id: r['user_id'] as String,
            type: AdminActivityType.member,
            description: 'New member: $name',
            highlightedName: name,
            timeLabel: _timeLabel(ts, now),
            timestamp: ts,
            isPrimary: true,
            sourceModule: 'members',
            referenceId: r['user_id'] as String,
          ));
        }
      }
    } catch (_) {}

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final filtered = typeFilter == null
        ? items
        : items.where((item) => item.type == typeFilter).toList();

    return filtered.skip(offset).take(limit).toList();
  }

  // ─── Cooperative Performance ───────────────────────────────────────────────

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

    // Cooperative-managed inventory stock (admin_inventory_screen source of truth)
    // Falls back to inventory_batches sum if cooperative_inventory is empty
    try {
      final coopRows = await _client
          .from('cooperative_inventory')
          .select('quantity_on_hand')
          .eq('is_active', true);
      if (coopRows.isNotEmpty) {
        totalStock = coopRows.fold<double>(
            0, (s, r) => s + (r['quantity_on_hand'] as num).toDouble());
      } else {
        // Fallback: sum farmer batches until cooperative_inventory is populated
        final batchRows = await _client
            .from('inventory_batches')
            .select('available_kg');
        totalStock = batchRows.fold<double>(
            0, (s, r) => s + (r['available_kg'] as num).toDouble());
      }
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

  // ─── Unread count ──────────────────────────────────────────────────────────

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

  // ─── Helpers ──────────────────────────────────────────────────────────────

  DateTime _nextFirstSaturday() {
    final now = DateTime.now();
    DateTime firstSat = _firstSaturdayOf(now.year, now.month);
    if (!firstSat.isAfter(now)) {
      final nm = now.month == 12
          ? DateTime(now.year + 1, 1, 1)
          : DateTime(now.year, now.month + 1, 1);
      firstSat = _firstSaturdayOf(nm.year, nm.month);
    }
    return firstSat;
  }

  DateTime _firstSaturdayOf(int year, int month) {
    DateTime d = DateTime(year, month, 1);
    while (d.weekday != DateTime.saturday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  String _timeLabel(DateTime dt, DateTime now) {
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }
}