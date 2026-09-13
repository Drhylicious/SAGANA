import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_dashboard_model.dart';
import '../repositories/admin_loan_repository.dart';
import '../../core/utils/bod_schedule_utils.dart';
import '../../routes/app_routes.dart';
import 'farmer_lookup.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminDashboardRepository
//
// Two distinct inventory domains are queried in this file — not
// interchangeable, and neither is a migration target for the other:
//   - cooperative_inventory: coop-owned agricultural inputs (fertilizer,
//     feeds, etc.), used by fetchKpiSummary(), fetchDashboardPriorities(),
//     and fetchManagementModuleBadges().
//   - inventory_batches: farmer-owned harvest stock, used by
//     fetchInventoryAlerts().
// ─────────────────────────────────────────────────────────────────────────────

class AdminDashboardRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // Consolidated low-stock threshold — single source of truth for the three
  // sites below (fetchKpiSummary, fetchDashboardPriorities,
  // fetchManagementModuleBadges). Uses the more inclusive of the two
  // conditions previously duplicated across the file. Fixed per Phase 5,
  // item 5.2.
  bool _isLowStock(num onHand, num? reorderLevel) {
    final reorder = reorderLevel?.toDouble() ?? 0;
    return onHand.toDouble() <= reorder || onHand.toDouble() <= 0;
  }

  // ─── Phase 5, item 5.1 — shared per-load-cycle query cache ────────────────
  // fetchKpiSummary(), fetchDashboardPriorities(), fetchManagementModuleBadges(),
  // and fetchCoopPerformance() are all called concurrently via Future.wait in
  // admin_dashboard_screen.dart's _loadAll(), and several of them previously
  // queried cooperative_inventory, marketplace_listings (pending_review), and
  // user_roles (role=farmer) independently for identical filters. These three
  // cached Futures ensure exactly one round-trip per table per load cycle.
  // Caching the Future itself (not just the resolved value) is required for
  // correctness under Future.wait's concurrent execution: Dart's `??=` is a
  // single synchronous expression, so whichever method reaches it first
  // populates the field before any other method can race it — every other
  // caller then awaits that same in-flight Future rather than starting a
  // second query.
  //
  // clearDashboardCache() must be called once at the very start of every
  // fresh load cycle (see admin_dashboard_screen.dart's _loadAll()) —
  // otherwise a pull-to-refresh would silently reuse stale data.
  Future<List<Map<String, dynamic>>>? _inventoryRowsCache;
  Future<List<Map<String, dynamic>>>? _pendingListingRowsCache;
  Future<List<Map<String, dynamic>>>? _farmerRoleRowsCache;

  void clearDashboardCache() {
    _inventoryRowsCache = null;
    _pendingListingRowsCache = null;
    _farmerRoleRowsCache = null;
  }

  Future<List<Map<String, dynamic>>> _fetchActiveInventoryRows() {
    return _inventoryRowsCache ??= _client
        .from('cooperative_inventory')
        .select('id, item_name, category, unit, quantity_on_hand, reorder_level')
        .eq('is_active', true);
  }

  Future<List<Map<String, dynamic>>> _fetchPendingListingRows() {
    return _pendingListingRowsCache ??= _client
        .from('marketplace_listings')
        .select('id')
        .eq('status', 'pending_review');
  }

  Future<List<Map<String, dynamic>>> _fetchFarmerRoleRows() {
    return _farmerRoleRowsCache ??= _client
        .from('user_roles')
        .select('user_id, status')
        .eq('role', 'farmer');
  }

  // ─── KPI Summary ──────────────────────────────────────────────────────────

  Future<AdminKpiSummary> fetchKpiSummary() async {
    int activeMembers = 0;
    int pendingMembers = 0;
    int totalMembers = 0;
    bool membersQueryFailed = false;
    double totalStockKg = 0;
    int pendingListings = 0;
    double totalRevenue = 0;
    int overdueLoans = 0;

    try {
      // Consolidated per Phase 5, item 5.1 — all farmer user_roles rows
      // fetched once via _fetchFarmerRoleRows() and shared with
      // fetchDashboardPriorities()/fetchCoopPerformance(). Same derivation
      // logic as before, just computed from the shared row set.
      final allFarmerRows = await _fetchFarmerRoleRows();
      totalMembers = allFarmerRows.length;
      pendingMembers = allFarmerRows.where((r) => r['status'] == 'pending').length;

      final activeIds = allFarmerRows
          .where((r) => r['status'] == 'active')
          .map((r) => r['user_id'] as String)
          .toList();
      if (activeIds.isNotEmpty) {
        final profileRows = await _client
            .from('farmer_profiles')
            .select('user_id')
            .inFilter('user_id', activeIds)
            .eq('is_verified', true);
        activeMembers = profileRows.length;
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchKpiSummary/members: $e');
      membersQueryFailed = true;
    }

    int activeInventoryItems = 0;
    int lowStockAlertCount = 0;
    try {
      final rows = await _fetchActiveInventoryRows();
      activeInventoryItems = rows.length;
      totalStockKg = rows.fold<double>(
        0,
        (sum, r) => sum + (r['quantity_on_hand'] as num).toDouble(),
      );
      lowStockAlertCount = rows.where((r) => _isLowStock(
        r['quantity_on_hand'] as num,
        r['reorder_level'] as num?,
      )).length;
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchKpiSummary/inventory: $e');
    }

    try {
      final rows = await _fetchPendingListingRows();
      pendingListings = rows.length;
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchKpiSummary/listings: $e');
    }

    // (pendingOrders query removed — pendingOrders was never rendered
    //  anywhere in admin_dashboard_screen.dart; confirmed via repo-wide
    //  search, no other consumer found. See Phase 1, item 1.2.)

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
        (s, r) => s + (r['total_price'] as num).toDouble(),
      );
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchKpiSummary/revenue: $e');
    }

    DateTime? loanDataAsOf;
    try {
      // Single source of truth for loan counts — see AdminLoanRepository's
      // own fetchDashboardStats() for the Loan module's dashboard, which
      // this delegates to instead of re-querying farmer_loans independently.
      // Only overdueLoans is consumed by this Dashboard's KPI strip;
      // activeLoansCount is intentionally not read here — see Phase 1, item 1.2.
      final loanStats = await AdminLoanRepository().fetchDashboardStats();
      overdueLoans = loanStats.overdueLoansCount;
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchKpiSummary/loans: $e');
    }

    try {
      // Phase 2, item 2.1 — when the nightly run_daily_loan_maintenance()
      // job last confirmed a run, so the UI can flag a stale Overdue figure
      // instead of presenting it as always-current with no way to check.
      // RLS-restricted to admins; an Officer session gets a caught exception
      // here and loanDataAsOf stays null, which the UI treats as "no
      // staleness warning" rather than a false positive.
      final row = await _client
          .from('loan_policy_settings')
          .select('last_maintenance_run_at')
          .eq('id', 1)
          .maybeSingle();
      final raw = row?['last_maintenance_run_at'] as String?;
      loanDataAsOf = raw != null ? DateTime.parse(raw) : null;
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchKpiSummary/loanDataAsOf: $e');
    }

    return AdminKpiSummary(
      activeMembers: activeMembers,
      totalMembersTarget: membersQueryFailed ? 52 : totalMembers, // fallback only when the query itself threw — a genuine zero-member result is reported as 0, not masked
      pendingMembers: pendingMembers,
      totalStockKg: totalStockKg,
      activeInventoryItems: activeInventoryItems,
      lowStockAlertCount: lowStockAlertCount,
      pendingListings: pendingListings,
      totalRevenueThisMonth: totalRevenue,
      overdueLoans: overdueLoans,
      loanDataAsOf: loanDataAsOf,
    );
  }

  // ─── Dashboard Priorities (Dynamic Hero Card) ──────────────────────────────
  // Returns ordered list of items for the "Today's Priorities" hero card.
  // Items are sorted: critical first, then warning, then info.
  // BOD countdown is included only when meeting is ≤ 7 days away.

  Future<List<DashboardPriority>> fetchDashboardPriorities() async {
    final List<DashboardPriority> priorities = [];
    final now = DateTime.now();
    final bodDate = BodSchedule.upcoming();
    final daysUntilBod = bodDate.difference(now).inDays;

    // BOD countdown — only when within 7 days
    if (daysUntilBod <= 7) {
      int farmersWithLoans = 0;
      try {
        // Single source of truth — see AdminLoanRepository.fetchDashboardStats().
        farmersWithLoans =
            (await AdminLoanRepository().fetchDashboardStats()).farmersOutstandingCount;
      } catch (e) {
        debugPrint('[AdminDashboardRepository] fetchDashboardPriorities/bodLoans: $e');
      }

      priorities.add(
        DashboardPriority(
          id: 'bod',
          level: DashboardPriorityLevel.warning,
          label: daysUntilBod == 0
              ? 'BOD Meeting — TODAY'
              : 'BOD Meeting in $daysUntilBod day${daysUntilBod == 1 ? '' : 's'}',
          value: '$farmersWithLoans farmers with outstanding loans',
          route: AppRoutes.loanDashboard,
          useGo: true, // switch to Loans tab
        ),
      );
    }

    // Overdue loans — always critical
    try {
      final rows = await _client
          .from('farmer_loans')
          .select('id')
          .eq('status', 'overdue');
      if (rows.isNotEmpty) {
        priorities.add(
          DashboardPriority(
            id: 'overdue_loans',
            level: DashboardPriorityLevel.critical,
            label: '${rows.length} Overdue Loan${rows.length == 1 ? '' : 's'}',
            value: 'Immediate attention required',
            route: AppRoutes.loanDashboard,
            useGo: true,
          ),
        );
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchDashboardPriorities/overdueLoans: $e');
    }

    // Pending listings
    try {
      final rows = await _fetchPendingListingRows();
      if (rows.isNotEmpty) {
        priorities.add(
          DashboardPriority(
            id: 'pending_listings',
            level: DashboardPriorityLevel.warning,
            label:
                '${rows.length} Listing${rows.length == 1 ? '' : 's'} Awaiting Approval',
            value: 'Farmers waiting for review',
            route: AppRoutes.pendingApprovals,
            // AppRoutes.pendingApprovals is a root-navigator push route, not a
            // shell branch — MarketplaceDashboardScreen already pushes this same
            // route for its own "Pending Review" action. useGo:true previously
            // navigated outside the shell, dropping the bottom nav. Fixed per
            // Phase 1, item 1.2.
            useGo: false, // push above shell
          ),
        );
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchDashboardPriorities/pendingListings: $e');
    }

    // Low stock — cooperative-owned stock only, per the Inventory
    // architecture decision (inventory_batches is farmer-owned, a
    // different domain — this priority is specifically about the
    // co-op's own input stock running low).
    try {
      final rows = await _fetchActiveInventoryRows();
      final lowItems = rows.where((r) => _isLowStock(
        r['quantity_on_hand'] as num,
        r['reorder_level'] as num?,
      )).toList();
      if (lowItems.isNotEmpty) {
        final names =
            lowItems.map((r) => r['item_name'] as String).take(2).join(', ');
        priorities.add(
          DashboardPriority(
            id: 'low_stock',
            level: DashboardPriorityLevel.warning,
            label:
                '${lowItems.length} Item${lowItems.length == 1 ? '' : 's'} Low on Stock',
            value: names,
            route: AppRoutes.adminInventory,
            useGo: false, // push above shell
          ),
        );
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchDashboardPriorities/lowStock: $e');
    }

    // Crop requests awaiting review
    try {
      final rows = await _client
          .from('crop_requests')
          .select('id')
          .eq('status', 'pending');
      if (rows.isNotEmpty) {
        priorities.add(
          DashboardPriority(
            id: 'crop_requests',
            level: DashboardPriorityLevel.warning,
            label:
                '${rows.length} Crop Request${rows.length == 1 ? '' : 's'} Pending',
            value: 'Farmers waiting for catalog review',
            route: AppRoutes.cropRequestApproval,
            useGo: false, // push above shell
          ),
        );
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchDashboardPriorities/cropRequests: $e');
    }

    // Pending members
    try {
      final allFarmerRows = await _fetchFarmerRoleRows();
      final rows = allFarmerRows.where((r) => r['status'] == 'pending').toList();
      if (rows.isNotEmpty) {
        priorities.add(
          DashboardPriority(
            id: 'pending_members',
            level: DashboardPriorityLevel.info,
            label:
                '${rows.length} Member${rows.length == 1 ? '' : 's'} Pending Verification',
            value: 'New registrations to review',
            route: AppRoutes.farmerManagement,
            useGo: true, // switch to Members tab
          ),
        );
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchDashboardPriorities/pendingMembers: $e');
    }

    // Sort: critical → warning → info
    priorities.sort((a, b) => a.level.index.compareTo(b.level.index));
    return priorities;
  }

  // ─── Inventory Alerts ──────────────────────────────────────────────────────
  // Farmer-owned harvest stock (inventory_batches) — intentionally distinct
  // from cooperative_inventory. See file header.

  // Phase 2: reworked to source from cooperative_inventory — the table
  // Inventory Management actually manages — instead of inventory_batches
  // (farmer harvest stock, a different table entirely). Shares the same
  // cached row set as fetchKpiSummary()/fetchManagementModuleBadges() via
  // _fetchActiveInventoryRows(), so this adds no extra round-trip, and the
  // low-stock definition stays identical to the KPI/badge low-stock counts
  // via the shared _isLowStock() helper.
  Future<List<InventoryAlertItem>> fetchInventoryAlerts() async {
    try {
      final rows = await _fetchActiveInventoryRows();
      final alerts = rows.where((r) => _isLowStock(
        r['quantity_on_hand'] as num,
        r['reorder_level'] as num?,
      )).map((r) {
        final onHand = (r['quantity_on_hand'] as num).toDouble();
        return InventoryAlertItem(
          id: r['id'] as String,
          itemName: r['item_name'] as String,
          category: r['category'] as String? ?? 'Agricultural Supplies',
          quantityOnHand: onHand,
          unit: r['unit'] as String? ?? 'kg',
          reorderLevel: (r['reorder_level'] as num?)?.toDouble() ?? 0,
          alertLevel: onHand <= 0
              ? InventoryAlertLevel.depleted
              : InventoryAlertLevel.low,
        );
      }).toList();
      alerts.sort((a, b) => a.quantityOnHand.compareTo(b.quantityOnHand));
      return alerts.take(5).toList();
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchInventoryAlerts: $e');
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
    final bodDate = BodSchedule.firstSaturdayOf(year, month);
    events.add(
      CalendarEvent(
        id: 'bod-$year-$month',
        type: CalendarEventType.bodMeeting,
        date: bodDate,
        title: 'BOD Meeting',
        subtitle: 'Board of Directors Monthly Meeting',
        sourceModule: 'system',
      ),
    );

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
        // Consolidated per Phase 5, item 5.1 — was a private inline lookup,
        // now uses the shared farmer_lookup.dart utility already relied on
        // by AdminLoanRepository/AdminReportsRepository.
        final infoMap = await fetchFarmerInfoMap(_client, farmerIds);
        for (final r in loanRows) {
          final dt = DateTime.parse(r['next_payment_date'] as String);
          final name = infoMap[r['farmer_id'] as String]?.fullName ?? 'Farmer';
          events.add(
            CalendarEvent(
              id: 'loan-${r['id']}',
              type: CalendarEventType.loanDue,
              date: dt,
              title: 'Loan Payment Due',
              subtitle: name,
              referenceId: r['id'] as String,
              sourceModule: 'loans',
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchCalendarEvents/loanDueDates: $e');
    }

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
        events.add(
          CalendarEvent(
            id: 'harvest-${entry.key}',
            type: CalendarEventType.harvest,
            date: dt,
            title: '$count Harvest${count == 1 ? '' : 's'} Recorded',
            subtitle: crops,
            sourceModule: 'harvest',
          ),
        );
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchCalendarEvents/harvest: $e');
    }

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
        events.add(
          CalendarEvent(
            id: 'broadcast-${r['id']}',
            type: CalendarEventType.announcement,
            date: dt,
            title: r['title'] as String,
            subtitle: (r['category'] as String?)?.toUpperCase(),
            referenceId: r['id'] as String,
            sourceModule: 'broadcast',
          ),
        );
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchCalendarEvents/broadcasts: $e');
    }

    // Program activities
    try {
      final start = DateTime(year, month, 1);
      final end = DateTime(year, month + 1, 1);
      final rows = await _client
          .from('program_activities')
          .select('id, title, description, activity_date, location, program_id, '
              'cooperative_programs(program_name)')
          .gte('activity_date', start.toIso8601String().split('T').first)
          .lt('activity_date', end.toIso8601String().split('T').first);
      for (final r in rows) {
        final dt = DateTime.parse(r['activity_date'] as String);
        final program = r['cooperative_programs'] as Map<String, dynamic>?;
        final programName = program?['program_name'] as String?;
        events.add(
          CalendarEvent(
            id: 'program-${r['id']}',
            type: CalendarEventType.program,
            date: dt,
            title: r['title'] as String,
            subtitle: (r['location'] as String?) ?? programName,
            referenceId: r['program_id'] as String,
            sourceModule: 'programs',
          ),
        );
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchCalendarEvents/programs: $e');
    }

    events.sort((a, b) => a.date.compareTo(b.date));
    return events;
  }

  // ─── BOD Meeting Info ──────────────────────────────────────────────────────

  Future<BodMeetingInfo> fetchBodMeetingInfo() async {
    int farmersWithLoans = 0;
    try {
      // Single source of truth — see AdminLoanRepository.fetchDashboardStats().
      farmersWithLoans =
          (await AdminLoanRepository().fetchDashboardStats()).farmersOutstandingCount;
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchBodMeetingInfo: $e');
    }

    return BodMeetingInfo(
      nextMeetingDate: BodSchedule.upcoming(),
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
    String programsBadge = '—';

    // Reads from cooperative_inventory (admin-managed) — NOT inventory_batches
    try {
      final rows = await _fetchActiveInventoryRows();
      final total = rows.length;
      final lowOrDepleted = rows.where((r) => _isLowStock(
        r['quantity_on_hand'] as num,
        r['reorder_level'] as num?,
      )).length;

      inventoryBadge = total == 0
          ? 'No items'
          : lowOrDepleted > 0
          ? '$lowOrDepleted low / $total items'
          : '$total items';
      inventoryAlert = lowOrDepleted > 0;
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchManagementModuleBadges/inventory: $e');
      inventoryBadge = 'No items';
    }

    try {
      final rows = await _client
          .from('crop_master')
          .select('id')
          .eq('is_active', true);
      cropsBadge = rows.isEmpty ? 'No crops' : '${rows.length} crops';
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchManagementModuleBadges/crops: $e');
    }

    try {
      final rows = await _client
          .from('loan_items_master')
          .select('id')
          .eq('is_active', true);
      loanItemsBadge = rows.isEmpty ? 'No items' : '${rows.length} items';
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchManagementModuleBadges/loanItems: $e');
    }

    try {
      final mapped = await _client
          .from('farmer_profiles')
          .select('user_id')
          .not('farm_latitude', 'is', null);
      supplyChainBadge = mapped.isEmpty
          ? '0 mapped'
          : '${mapped.length} mapped';
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchManagementModuleBadges/supplyChain: $e');
    }

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
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchManagementModuleBadges/prices: $e');
    }

    try {
      final rows = await _client
          .from('cooperative_programs')
          .select('id')
          .eq('status', 'active');
      programsBadge = rows.isEmpty ? 'No programs' : '${rows.length} active';
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchManagementModuleBadges/programs: $e');
    }

    return [
      ManagementModuleCard(
        id: 'inventory',
        title: 'Inventory Management',
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
      ManagementModuleCard(
        id: 'programs',
        title: 'Program Management',
        subtitle: 'Cooperative programs',
        badgeLabel: programsBadge,
        hasBadgeAlert: false,
        route: AppRoutes.programManagement,
        useGo: false,
      ),
      ManagementModuleCard(
        id: 'loan-items',
        title: 'Loan Item Catalog',
        subtitle: 'Seeds, fertilizers & supplies',
        badgeLabel: loanItemsBadge,
        hasBadgeAlert: false,
        route: AppRoutes.loanItemManagement,
        useGo: false,
      ),
      ManagementModuleCard(
        id: 'supply-chain',
        title: 'Supply Chain Management',
        subtitle: 'Cooperative workflow & flow',
        badgeLabel: supplyChainBadge,
        hasBadgeAlert: false,
        route: AppRoutes.supplyChainMap,
        useGo: false,
      ),
      ManagementModuleCard(
        id: 'prices',
        title: 'Price Management',
        subtitle: 'Cooperative & public market prices',
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

    // Local fetchNames() closure removed per Phase 5, item 5.1 — replaced by
    // the shared fetchFarmerInfoMap() utility at each call site below.

    try {
      final rows = await _client
          .from('harvest_records')
          .select('id, crop_name, quantity_kg, created_at, farmer_id')
          .order('created_at', ascending: false)
          .limit(15); // raised from 3 per Phase 1, item 1.5
      if (rows.isNotEmpty) {
        final infoMap = await fetchFarmerInfoMap(
          _client,
          rows.map((r) => r['farmer_id'] as String).toList(),
        );
        for (final r in rows) {
          final name = infoMap[r['farmer_id'] as String]?.fullName ?? 'Farmer';
          final qty = r['quantity_kg'];
          final crop = r['crop_name'] as String;
          final ts = DateTime.parse(r['created_at'] as String);
          items.add(
            AdminActivityItem(
              id: r['id'] as String,
              type: AdminActivityType.harvest,
              description: 'New harvest: $name — ${qty}kg $crop',
              highlightedName: name,
              timeLabel: _timeLabel(ts, now),
              timestamp: ts,
              isPrimary: true,
              sourceModule: 'harvest',
              referenceId: r['farmer_id'] as String,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchRecentActivity/harvest: $e');
    }

    try {
      final rows = await _client
          .from('marketplace_listings')
          .select('id, crop_name, status, submitted_at, farmer_id')
          .order('submitted_at', ascending: false)
          .limit(15); // raised from 3 per Phase 1, item 1.5
      if (rows.isNotEmpty) {
        final infoMap = await fetchFarmerInfoMap(
          _client,
          rows.map((r) => r['farmer_id'] as String).toList(),
        );
        for (final r in rows) {
          final name = infoMap[r['farmer_id'] as String]?.fullName ?? 'Farmer';
          final crop = r['crop_name'] as String;
          final status = r['status'] as String;
          final ts = DateTime.parse(r['submitted_at'] as String);
          final isApproved = status == 'approved';
          items.add(
            AdminActivityItem(
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
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchRecentActivity/listing: $e');
    }

    try {
      final rows = await _client
          .from('orders')
          .select('id, total_price, created_at')
          .order('created_at', ascending: false)
          .limit(10); // raised from 2 per Phase 1, item 1.5
      for (final r in rows) {
        final price = (r['total_price'] as num).toStringAsFixed(2);
        final ts = DateTime.parse(r['created_at'] as String);
        items.add(
          AdminActivityItem(
            id: r['id'] as String,
            type: AdminActivityType.order,
            description: 'Order placed: ₱$price',
            timeLabel: _timeLabel(ts, now),
            timestamp: ts,
            isPrimary: false,
            sourceModule: 'listings',
            referenceId: r['id'] as String,
          ),
        );
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchRecentActivity/order: $e');
    }

    try {
      final rows = await _client
          .from('price_records')
          .select('id, crop_name, price, recorded_at')
          .order('recorded_at', ascending: false)
          .limit(10); // raised from 2 per Phase 1, item 1.5
      for (final r in rows) {
        final crop = r['crop_name'] as String;
        final price = (r['price'] as num).toStringAsFixed(2);
        final ts = DateTime.parse(r['recorded_at'] as String);
        items.add(
          AdminActivityItem(
            id: r['id'] as String,
            type: AdminActivityType.price,
            description: 'Price updated: $crop — ₱$price/kg',
            highlightedName: crop,
            timeLabel: _timeLabel(ts, now),
            timestamp: ts,
            isPrimary: false,
            sourceModule: 'prices',
          ),
        );
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchRecentActivity/price: $e');
    }

    try {
      final rows = await _client
          .from('user_roles')
          .select('user_id, created_at')
          .eq('role', 'farmer')
          .order('created_at', ascending: false)
          .limit(10); // raised from 2 per Phase 1, item 1.5
      if (rows.isNotEmpty) {
        final infoMap = await fetchFarmerInfoMap(
          _client,
          rows.map((r) => r['user_id'] as String).toList(),
        );
        for (final r in rows) {
          final name = infoMap[r['user_id'] as String]?.fullName ?? 'New Member';
          final ts = DateTime.parse(r['created_at'] as String);
          items.add(
            AdminActivityItem(
              id: r['user_id'] as String,
              type: AdminActivityType.member,
              description: 'New member: $name',
              highlightedName: name,
              timeLabel: _timeLabel(ts, now),
              timestamp: ts,
              isPrimary: true,
              sourceModule: 'members',
              referenceId: r['user_id'] as String,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchRecentActivity/member: $e');
    }

    try {
      final rows = await _client
          .from('crop_requests')
          .select('id, requested_name, farmer_id, created_at')
          .order('created_at', ascending: false)
          .limit(10); // raised from 2 per Phase 1, item 1.5
      if (rows.isNotEmpty) {
        final infoMap = await fetchFarmerInfoMap(
          _client,
          rows.map((r) => r['farmer_id'] as String).toList(),
        );
        for (final r in rows) {
          final name = infoMap[r['farmer_id'] as String]?.fullName ?? 'Farmer';
          final crop = r['requested_name'] as String;
          final ts = DateTime.parse(r['created_at'] as String);
          items.add(
            AdminActivityItem(
              id: r['id'] as String,
              type: AdminActivityType.cropRequest,
              description: 'Crop requested: $name — $crop',
              highlightedName: crop,
              timeLabel: _timeLabel(ts, now),
              timestamp: ts,
              isPrimary: false,
              sourceModule: 'crops',
              referenceId: r['id'] as String,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchRecentActivity/cropRequest: $e');
    }

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final filtered = typeFilter == null
        ? items
        : items.where((item) => item.type == typeFilter).toList();

    return filtered.skip(offset).take(limit).toList();
  }

  // ─── Cooperative Performance ───────────────────────────────────────────────

  Future<CoopPerformanceSummary> fetchCoopPerformance() async {
    int totalHarvests = 0;
    int activeListings = 0;
    int completedSales = 0;
    int activeMembersThisSeason = 0;

    try {
      final rows = await _client.from('harvest_records').select('id');
      totalHarvests = rows.length;
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchCoopPerformance/harvests: $e');
    }

    double farmerAvailableStockKg = 0;
    try {
      final rows = await _client
          .from('inventory_batches')
          .select('available_kg');
      farmerAvailableStockKg = rows.fold<double>(
        0,
        (s, r) => s + (r['available_kg'] as num).toDouble(),
      );
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchCoopPerformance/farmerStock: $e');
    }

    try {
      final rows = await _client
          .from('marketplace_listings')
          .select('id')
          .eq('status', 'approved');
      activeListings = rows.length;
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchCoopPerformance/listings: $e');
    }

    try {
      final rows = await _client
          .from('orders')
          .select('id')
          .eq('status', 'completed');
      completedSales = rows.length;
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchCoopPerformance/sales: $e');
    }

    try {
      final seasonStart = DateTime(DateTime.now().year, 1, 1).toIso8601String();
      final rows = await _client
          .from('harvest_records')
          .select('farmer_id')
          .gte('harvest_date', seasonStart);
      activeMembersThisSeason = rows
          .map((r) => r['farmer_id'] as String)
          .toSet()
          .length;
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchCoopPerformance/activeMembers: $e');
    }

    int totalMembers = 0;
    bool totalMembersQueryFailed = false;
    try {
      // Total registered membership, replacing the hardcoded constant of 52.
      // See Phase 2, item 2.5. Consolidated per Phase 5, item 5.1 — shares
      // the same farmer user_roles row set as fetchKpiSummary()/
      // fetchDashboardPriorities() via _fetchFarmerRoleRows().
      final rows = await _fetchFarmerRoleRows();
      totalMembers = rows.length;
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchCoopPerformance/totalMembers: $e');
      totalMembersQueryFailed = true;
    }

    return CoopPerformanceSummary(
      totalHarvests: totalHarvests,
      farmerAvailableStockKg: farmerAvailableStockKg,
      activeListings: activeListings,
      completedSales: completedSales,
      activeMembersThisSeason: activeMembersThisSeason,
      totalMembers: totalMembersQueryFailed ? 52 : totalMembers, // fallback only when the query itself threw — a genuine zero-member result is reported as 0, not masked
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
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchUnreadCount: $e');
      return 0;
    }
  }

  // ─── Admin Display Name ─────────────────────────────────────────────────────

  Future<String?> fetchAdminFirstName() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return null;
      final row = await _client
          .from('user_information')
          .select('full_name')
          .eq('user_id', userId)
          .maybeSingle();
      final name = row?['full_name'] as String?;
      if (name == null || name.isEmpty) return null;
      return name.split(' ').first; // first name only, matches prior behavior
    } catch (e) {
      debugPrint('[AdminDashboardRepository] fetchAdminFirstName: $e');
      return null;
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  // BOD-Saturday math now lives solely in core/utils/bod_schedule_utils.dart
  // — see BodSchedule.upcoming() and BodSchedule.firstSaturdayOf(). The two
  // private methods formerly here computed the "next" case incorrectly on
  // the BOD Saturday itself (always rolled to next month instead of showing
  // today), which made the "BOD Meeting — TODAY" label above unreachable in
  // practice — using the shared, already-correct utility fixes that as a
  // side effect of this consolidation.

  String _timeLabel(DateTime dt, DateTime now) {
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }
}