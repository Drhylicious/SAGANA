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
    final startOfYear = DateTime(now.year, 1, 1);

    double monthlyYield = 0;
    double lastMonthYield = 0;

    // Monthly yield — this calendar month's harvest_records rows.
    try {
      final yieldResponse = await _client
          .from('harvest_records')
          .select('quantity_kg')
          .eq('farmer_id', _userId)
          .gte('harvest_date', startOfMonth.toIso8601String());
      monthlyYield = yieldResponse.fold<double>(
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

    // Annual yield — same harvest_records source, scoped to the whole
    // current calendar year. This is now the single source of truth for
    // "this year's total harvest" — the Harvest tab's own former "Total
    // Yield" stat computed this exact figure independently; it now reads
    // from here instead (see harvest_hub_screen.dart / HarvestRepository).
    double annualYield = 0;
    try {
      final annualYieldResponse = await _client
          .from('harvest_records')
          .select('quantity_kg')
          .eq('farmer_id', _userId)
          .gte('harvest_date', startOfYear.toIso8601String());
      annualYield = annualYieldResponse.fold<double>(
        0,
        (sum, row) => sum + (row['quantity_kg'] as num).toDouble(),
      );
    } catch (_) {}

    // Merge in Hive-queued offline harvests not yet synced to Supabase —
    // HarvestRepository.fetchStats() (Harvest Hub) already did this for
    // its season total; this KPI previously didn't, which is exactly why
    // a farmer with an unsynced harvest could see a lower figure here than
    // on the Harvest tab for the same underlying data.
    for (final entry in HiveService.getPendingHarvests()) {
      final payload = entry.value;
      final harvestDate = DateTime.tryParse(
        payload['harvest_date'] as String? ?? '',
      );
      final qty = (payload['quantity_kg'] as num?)?.toDouble() ?? 0;
      if (harvestDate == null) continue;
      if (!harvestDate.isBefore(startOfMonth)) {
        monthlyYield += qty;
      } else if (!harvestDate.isBefore(startOfLastMonth) &&
          !harvestDate.isAfter(endOfLastMonth)) {
        lastMonthYield += qty;
      }
      if (!harvestDate.isBefore(startOfYear)) {
        annualYield += qty;
      }
    }

    // Admin-configurable monthly earnings goal (farmer_dashboard_settings),
    // never hardcoded. Falls back to the table's own documented default if
    // the row is unreachable, matching the settings table's own DEFAULT —
    // not a business decision made here, just keeping this screen usable
    // if the read fails.
    double earningsGoal = 5000;
    try {
      final goalRow = await _client
          .from('farmer_dashboard_settings')
          .select('monthly_earnings_goal')
          .eq('id', 1)
          .single();
      earningsGoal = (goalRow['monthly_earnings_goal'] as num).toDouble();
    } catch (_) {}

    // Earnings — four farmer income channels: Marketplace (orders),
    // Confirmed Cooperative Sales (member_sales_transactions), Informal
    // Sales (informal_sales), and Market Linking
    // (market_linking_programs, completed rounds only). Each source is
    // queried once for the whole year, then split into this-month and
    // this-year sums from the same rows — avoids querying every channel
    // twice for two overlapping windows. Each source keeps its own
    // independent try/catch so one failing can't blank out the others —
    // matches the app-wide convention of failing toward "show less," never
    // toward a plausible-but-wrong bigger number.
    double marketplaceMonthly = 0, marketplaceAnnual = 0;
    try {
      final rows = await _client
          .from('orders')
          .select('total_price, created_at')
          .eq('farmer_id', _userId)
          .eq('status', 'completed')
          .gte('created_at', startOfYear.toIso8601String());
      for (final row in rows) {
        final amount = (row['total_price'] as num).toDouble();
        marketplaceAnnual += amount;
        final createdAt = DateTime.parse(row['created_at'] as String);
        if (!createdAt.isBefore(startOfMonth)) marketplaceMonthly += amount;
      }
    } catch (_) {}

    // member_sales_transactions.sale_date is a plain DATE column (not a
    // timestamp) — compared as calendar-date strings, same reasoning as
    // before this change.
    double cooperativeMonthly = 0, cooperativeAnnual = 0;
    try {
      String dateOnly(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      final rows = await _client
          .from('member_sales_transactions')
          .select('amount, sale_date')
          .eq('farmer_id', _userId)
          .gte('sale_date', dateOnly(startOfYear));
      for (final row in rows) {
        final amount = (row['amount'] as num).toDouble();
        cooperativeAnnual += amount;
        final saleDate = DateTime.parse(row['sale_date'] as String);
        if (!saleDate.isBefore(startOfMonth)) cooperativeMonthly += amount;
    }
    } catch (_) {}

    // informal_sales.sale_date is a TIMESTAMPTZ (same shape as
    // orders.created_at). amount is nullable — a NULL amount counts as 0
    // (confirmed product decision, not an oversight).
    double informalMonthly = 0, informalAnnual = 0;
    try {
      final rows = await _client
          .from('informal_sales')
          .select('amount, sale_date')
          .eq('farmer_id', _userId)
          .gte('sale_date', startOfYear.toIso8601String());
      for (final row in rows) {
        final amount = (row['amount'] as num?)?.toDouble() ?? 0;
        informalAnnual += amount;
        final saleDate = DateTime.parse(row['sale_date'] as String);
        if (!saleDate.isBefore(startOfMonth)) informalMonthly += amount;
      }
    } catch (_) {}

    // Market Linking — an admin-run institutional export program (Ginger
    // only), settled via the completed_market_linking RPC. A completed
    // round's confirmed_volume_kg is only guaranteed set when a batch was
    // attached at completion; requested_volume_kg (captured at Buyer
    // Found) and volume_kg (the farmer's originally committed amount) are
    // the next-best proxies in that order — same "prefer the most
    // final/authoritative figure available" reasoning the settlement RPC
    // itself already applies via COALESCE.
    double marketLinkingMonthly = 0, marketLinkingAnnual = 0;
    try {
      final rows = await _client
          .from('market_linking_programs')
          .select(
            'confirmed_volume_kg, requested_volume_kg, volume_kg, price_per_kg, completed_at',
          )
          .eq('farmer_id', _userId)
          .eq('status', 'completed')
          .gte('completed_at', startOfYear.toIso8601String());
      for (final row in rows) {
        final pricePerKg = (row['price_per_kg'] as num?)?.toDouble();
        if (pricePerKg == null) continue;
        final quantityKg =
            (row['confirmed_volume_kg'] as num?)?.toDouble() ??
            (row['requested_volume_kg'] as num?)?.toDouble() ??
            (row['volume_kg'] as num?)?.toDouble() ??
            0;
        final amount = quantityKg * pricePerKg;
        marketLinkingAnnual += amount;
        final completedAt = DateTime.parse(row['completed_at'] as String);
        if (!completedAt.isBefore(startOfMonth)) marketLinkingMonthly += amount;
    }
    } catch (_) {}

    final monthlyEarnings =
        marketplaceMonthly +
        cooperativeMonthly +
        informalMonthly +
        marketLinkingMonthly;
    final annualEarnings =
        marketplaceAnnual +
        cooperativeAnnual +
        informalAnnual +
        marketLinkingAnnual;

    final unsyncedCount = HiveService.getUnsyncedCount();
    final lastSyncedAt = HiveService.getLastSyncTime(userId: _userId);

    return DashboardSummaryModel(
      monthlyYieldKg: monthlyYield,
      previousMonthYieldKg: lastMonthYield,
      annualYieldKg: annualYield,
      monthlyEarnings: monthlyEarnings,
      annualEarnings: annualEarnings,
      earningsGoal: earningsGoal,
      unsyncedCount: unsyncedCount,
      lastSyncedAt: lastSyncedAt,
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
    // Applied before offset/limit, unlike typeFilter — lets a caller (Home's
    // 5-item preview) exclude a type from the ranking itself rather than
    // filtering it out of an already-capped result, which previously let a
    // farmer with several loan reminders in their top 5 see fewer than 5
    // items even when more real activity existed.
    Set<ActivityType>? excludeTypes,
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
            'id, crop_name, quantity_kg, batch_number, created_at, is_synced',
          )
          .eq('farmer_id', _userId)
          .order('created_at', ascending: false)
          .limit(sourceLimit);
      for (final h in harvests) {
        final cropName = h['crop_name'] as String;
        final batchNo = h['batch_number'] as String? ?? '—';
        if (!matchesSearch(cropName) && !matchesSearch(batchNo)) continue;
        final isSynced = h['is_synced'] as bool? ?? false;
        items.add(
          ActivityItem(
          id: h['id'] as String,
          type: ActivityType.harvest,
          title: '$cropName Harvest',
          subtitle:
              'Batch #$batchNo • ${_formatRelative(DateTime.parse(h['created_at'] as String))}',
          valueLabel: '${h['quantity_kg']} kg',
          statusLabel: isSynced ? 'Synced' : 'Pending Sync',
          timestamp: DateTime.parse(h['created_at'] as String),
          ),
        );
      }
    } catch (_) {}

    // Listings — the farmer's own submission is a permanent historical fact
    // and must always show, regardless of the row's CURRENT status. Fixed
    // after a live-testing report: the previous version filtered this query
    // by current status (`inFilter('status', ['pending_review','withdrawn'])`),
    // which meant a listing that got approved fell out of the query
    // entirely — losing not just the (correctly-excluded) approval event,
    // but the farmer's own original submission entry too, since a single
    // mutable row can't represent two historical events that way. Mirrors
    // _fetchCropRequestActivity's approach: select every row unconditionally,
    // always emit the submission entry, and additionally emit a second
    // entry only for a status that is itself a farmer-driven, terminal fact
    // (withdrawn). Approved/rejected/sold are still never surfaced — those
    // remain Admin's/the marketplace's own decision, not the farmer's action.
    try {
      final listings = await _client
          .from('marketplace_listings')
          .select(
            'id, crop_name, variety, status, updated_at, submitted_at, created_at',
          )
          .eq('farmer_id', _userId)
          .order('created_at', ascending: false)
          .limit(sourceLimit);
      for (final l in listings) {
        final cropName = l['crop_name'] as String;
        final variety = l['variety'] as String? ?? '';
        final status = l['status'] as String;
        if (!matchesSearch(cropName)) continue;
        final subtitle = variety.isNotEmpty ? variety : cropName;
        items.add(
          ActivityItem(
            id: '${l['id']}-submitted',
            type: ActivityType.listing,
            title: '$cropName Listing Submitted',
            subtitle: subtitle,
            statusLabel: 'Pending Review',
            timestamp: DateTime.parse(
              (l['submitted_at'] ?? l['created_at']) as String,
            ),
          ),
        );
        if (status == 'withdrawn') {
          items.add(
            ActivityItem(
              id: '${l['id']}-withdrawn',
          type: ActivityType.listing,
              title: '$cropName Listing Withdrawn',
              subtitle: subtitle,
              statusLabel: 'Withdrawn',
              timestamp: DateTime.parse(l['updated_at'] as String),
            ),
          );
        }
      }
    } catch (_) {}

    // Orders placed BY this farmer, as a buyer, in the Farmer-to-Farmer
    // Marketplace (orders.buyer_id = this farmer) — a genuine gap found
    // during a live-testing follow-up: orders.farmer_id (the SELLER side,
    // Admin/Buyer-driven, never the farmer's own action) was correctly
    // removed from Recent Activity, but orders.buyer_id — where THIS
    // farmer is the one who called place_order() against another farmer's
    // listing — was never queried at all, before or after that removal.
    // Only the placement moment is shown; subsequent status changes
    // (approved/completed/cancelled) are Admin's actions on the order, not
    // the farmer's, same reasoning as everywhere else.
    try {
      final orders = await _client
          .from('orders')
          .select(
            'id, quantity_kg, total_price, created_at, fulfillment_method, marketplace_listings(crop_name)',
          )
          .eq('buyer_id', _userId)
          .order('created_at', ascending: false)
          .limit(sourceLimit);
      for (final o in orders) {
        final cropName =
            (o['marketplace_listings'] as Map?)?['crop_name'] as String? ??
            'Produce';
        if (!matchesSearch(cropName)) continue;
        // Every checkout path (direct or from cart, pickup or delivery)
        // converges on this one place_order() insert — fulfillment_method
        // is the only thing that distinguishes them, so it's surfaced here
        // rather than needing a separate source per flow.
        final fulfillment = o['fulfillment_method'] as String?;
        final fulfillmentLabel = fulfillment == 'delivery'
            ? 'Delivery'
            : fulfillment == 'pickup'
            ? 'Pickup'
            : null;
        items.add(
          ActivityItem(
            id: o['id'] as String,
            type: ActivityType.orderPlaced,
            title: 'Placed an Order',
            subtitle: fulfillmentLabel != null
                ? '${o['quantity_kg']}kg $cropName • $fulfillmentLabel'
                : '${o['quantity_kg']}kg $cropName',
            valueLabel: '₱${(o['total_price'] as num).toStringAsFixed(0)}',
            statusLabel: fulfillmentLabel,
            timestamp: DateTime.parse(o['created_at'] as String),
          ),
        );
      }
    } catch (_) {}

    // Loan Payment Due was removed from here entirely (a later correction):
    // it's a passive reminder computed from Admin-issued loan data, not a
    // Farmer action — it never belonged in an "actions I performed" feed.
    // It's now communicated exclusively through Notifications instead (see
    // notify_upcoming_loan_payments() / supabase_schema_loan_due_soon_
    // notification.sql), alongside the pre-existing overdue-loan
    // notification. Loans remain entirely Admin-managed on the Farmer side
    // — no farmer-initiated loan action exists anywhere to record here.

    // Crop requests (submission only — see _fetchCropRequestActivity)
    items.addAll(
      await _fetchCropRequestActivity(
      userId: _userId,
      searchQuery: searchQuery,
      limit: sourceLimit,
      ),
    );

    // Crop added (instant catalog add)
    items.addAll(
      await _fetchCropAddedActivity(
      userId: _userId,
      searchQuery: searchQuery,
      limit: sourceLimit,
      ),
    );

    // Informal sales
    items.addAll(
      await _fetchInformalSaleActivity(
      userId: _userId,
      searchQuery: searchQuery,
      limit: sourceLimit,
      ),
    );

    // Crop photo updated — not search-filtered, same reasoning as Account
    // activity below: descriptions are short generic status text.
    items.addAll(
      await _fetchCropPhotoActivity(userId: _userId, limit: sourceLimit),
    );

    // Offer to Cooperative — the farmer's own offer action. Admin's later
    // confirmation of this offer is a separate, Admin-driven event and is
    // deliberately not surfaced here (see the removed
    // _fetchCooperativeSaleActivity, Phase 3).
    items.addAll(
      await _fetchCooperativeOfferActivity(
      userId: _userId,
      searchQuery: searchQuery,
      limit: sourceLimit,
      ),
    );

    // Market Linking Enrollment submission — not search-filtered, every
    // enrollment is the same Ginger/DA-AMAD program.
    items.addAll(
      await _fetchMarketLinkingEnrollmentActivity(
        userId: _userId,
        limit: sourceLimit,
      ),
    );

    // Ginger Batch submission for sale — not search-filtered, crop is
    // always Ginger.
    items.addAll(
      await _fetchGingerBatchSubmissionActivity(
        userId: _userId,
        limit: sourceLimit,
      ),
    );

    // Account activity — not search-filtered, same reasoning as before:
    // descriptions are short generic status text, searching adds little.
    items.addAll(
      await _fetchProfileActivity(userId: _userId, limit: sourceLimit),
    );

    // My Address changes — farmer-side "My Address" reuses the Buyer's
    // address book (buyer_addresses) and repository entirely (no
    // farmer-specific table), and its writes already log to
    // buyer_profile_activity via BuyerProfileRepository.logActivity().
    // That table is role-agnostic (scoped by buyer_id = auth.uid(), which
    // is just "whoever is logged in"), so this is a pure additional read,
    // not a change to the address feature itself.
    items.addAll(
      await _fetchAddressActivity(userId: _userId, limit: sourceLimit),
    );

    // Expense added — not search-filtered, same reasoning as Account
    // activity: names are short and searching adds little.
    items.addAll(
      await _fetchExpenseActivity(userId: _userId, limit: sourceLimit),
    );

    // Program Enrollment request — the farmer's own submission only.
    // Admin's later approve/reject is a separate, Admin-driven event and
    // is not surfaced here, same pattern as every other enrollment/request
    // source in this method.
    items.addAll(
      await _fetchProgramEnrollmentActivity(
        userId: _userId,
        limit: sourceLimit,
      ),
    );

    // Program Purchase request (Cooperative Product Sales) — the farmer's
    // own request only; Admin's confirm/cancel is not surfaced here.
    items.addAll(
      await _fetchProgramPurchaseActivity(userId: _userId, limit: sourceLimit),
    );

    // Capital Reinvestment ("Add to Capital") — filtered to
    // source = 'patronage_capital' only. capital_contribution_events also
    // carries 'member_payment' (membership renewal), 'manual_adjustment'
    // and 'opening_balance' rows, which are Admin/system-driven and out of
    // scope for this entry.
    items.addAll(
      await _fetchCapitalReinvestmentActivity(
      userId: _userId,
      limit: sourceLimit,
      ),
    );

    // Sync Now — only when a manual sync actually had something queued to
    // push (see the call site in FarmerDashboardScreen). Not search-filtered.
    items.addAll(await _fetchSyncActivity(userId: _userId, limit: sourceLimit));

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    var filtered = items;
    if (excludeTypes != null && excludeTypes.isNotEmpty) {
      filtered = filtered.where((i) => !excludeTypes.contains(i.type)).toList();
    }
    if (typeFilter != null) {
      filtered = filtered.where(typeFilter.matches).toList();
    }

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
      // Only the farmer's own submission is a farmer action — Admin's
      // approve/reject decision is not, so it no longer generates an
      // entry here (see recent_activity.md's farmer-actions-only scope
      // decision).
      final requests = await _client
          .from('crop_requests')
          .select('id, requested_name, created_at')
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
        items.add(
          ActivityItem(
          id: '${r['id']}-submitted',
          type: ActivityType.cropRequest,
          title: 'Crop Request Submitted',
          subtitle: name,
          statusLabel: 'Pending Review',
          timestamp: DateTime.parse(r['created_at'] as String),
          ),
        );
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
        items.add(
          ActivityItem(
          id: c['id'] as String,
          type: ActivityType.cropAdded,
          title: 'Crop Added',
          subtitle: name,
          statusLabel: 'Added',
          timestamp: DateTime.parse(c['created_at'] as String),
          ),
        );
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
        items.add(
          ActivityItem(
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
          ),
        );
      }
    } catch (_) {}
    return items;
  }

  // ─── Crop Photo Activity ────────────────────────────────────────────────────

  Future<List<ActivityItem>> _fetchCropPhotoActivity({
    required String userId,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
    try {
      final rows = await _client
          .from('farmer_crop_activity')
          .select('id, description, created_at')
          .eq('farmer_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      for (final r in rows) {
        items.add(
          ActivityItem(
            id: r['id'] as String,
            type: ActivityType.cropPhotoUpdated,
            title: r['description'] as String,
            subtitle: 'Crop Roster',
            statusLabel: 'Updated',
            timestamp: DateTime.parse(r['created_at'] as String),
          ),
        );
      }
    } catch (_) {}
    return items;
  }

  // ─── Offer to Cooperative Activity ──────────────────────────────────────────
  // The farmer's own offer action (offered_at) — not Admin's later
  // confirm/decline decision, which is a separate event owned by Admin.

  Future<List<ActivityItem>> _fetchCooperativeOfferActivity({
    required String userId,
    String? searchQuery,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
    try {
      final offers = await _client
          .from('cooperative_purchase_offers')
          .select('id, crop_name, offered_quantity_kg, offered_at')
          .eq('farmer_id', userId)
          .order('offered_at', ascending: false)
          .limit(limit);
      for (final o in offers) {
        final cropName = o['crop_name'] as String;
        if (searchQuery != null &&
            searchQuery.isNotEmpty &&
            !cropName.toLowerCase().contains(searchQuery.toLowerCase())) {
          continue;
        }
        items.add(
          ActivityItem(
            id: o['id'] as String,
            type: ActivityType.cooperativeOffer,
            title: 'Offered to Cooperative',
          subtitle: cropName,
            statusLabel: '${o['offered_quantity_kg']} kg',
            timestamp: DateTime.parse(o['offered_at'] as String),
          ),
        );
      }
    } catch (_) {}
    return items;
  }

  // ─── Market Linking Enrollment Activity ─────────────────────────────────────
  // The farmer's own enrollment submission (submitted_at) — Admin's later
  // approve/reject via respond_to_da_amad_enrollment() is a separate,
  // Admin-driven event and is not surfaced here.

  Future<List<ActivityItem>> _fetchMarketLinkingEnrollmentActivity({
    required String userId,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
    try {
      final rows = await _client
          .from('da_amad_enrollments')
          .select('id, submitted_at')
          .eq('farmer_id', userId)
          .order('submitted_at', ascending: false)
          .limit(limit);
      for (final r in rows) {
        items.add(
          ActivityItem(
            id: r['id'] as String,
            type: ActivityType.marketLinkingEnrollment,
            title: 'Submitted Market Linking Enrollment',
            subtitle: 'Ginger Market Linking (DA-AMAD)',
            statusLabel: 'Pending Review',
            timestamp: DateTime.parse(r['submitted_at'] as String),
          ),
        );
      }
    } catch (_) {}
    return items;
  }

  // ─── Ginger Batch Submission Activity ───────────────────────────────────────
  // The farmer's own submit_ginger_for_sale() call (submitted_at) — shown
  // regardless of the row's current status, since this entry represents the
  // moment the farmer submitted it, not how it was later settled.

  Future<List<ActivityItem>> _fetchGingerBatchSubmissionActivity({
    required String userId,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
    try {
      final rows = await _client
          .from('market_linking_programs')
          .select('id, volume_kg, submitted_at')
          .eq('farmer_id', userId)
          .not('submitted_at', 'is', null)
          .order('submitted_at', ascending: false)
          .limit(limit);
      for (final r in rows) {
        items.add(
          ActivityItem(
            id: r['id'] as String,
            type: ActivityType.gingerBatchSubmission,
            title: 'Submitted Ginger Batch for Sale',
            subtitle: 'Market Linking',
            statusLabel: '${r['volume_kg']} kg',
            timestamp: DateTime.parse(r['submitted_at'] as String),
          ),
        );
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
        items.add(
          ActivityItem(
          id: r['id'] as String,
          type: ActivityType.profile,
          title: r['description'] as String,
          subtitle: 'Account',
          statusLabel: 'Updated',
          timestamp: DateTime.parse(r['created_at'] as String),
          ),
        );
      }
    } catch (_) {}
    return items;
  }

  // ─── Address Activity (My Address) ──────────────────────────────────────────
  // My Address is a farmer-facing entry point into the Buyer's own address
  // book (buyer_addresses / BuyerAddressRepository) — no farmer-specific
  // table exists. Its writes already log into buyer_profile_activity via
  // BuyerProfileRepository.logActivity(); this just reads that table back,
  // scoped to this farmer's own auth.uid() the same way every other source
  // in this file scopes to _userId.

  Future<List<ActivityItem>> _fetchAddressActivity({
    required String userId,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
    try {
      final rows = await _client
          .from('buyer_profile_activity')
          .select('id, description, created_at')
          .eq('buyer_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      for (final r in rows) {
        items.add(
          ActivityItem(
            id: r['id'] as String,
            type: ActivityType.addressUpdated,
            title: r['description'] as String,
            subtitle: 'Address',
            statusLabel: 'Updated',
            timestamp: DateTime.parse(r['created_at'] as String),
          ),
        );
  }
    } catch (_) {}
    return items;
  }

  // ─── Expense Activity ───────────────────────────────────────────────────────
  // farmer_expenses is itself a pure insert-log (one row per expense, never
  // overwritten) — read directly, no separate logging table needed.

  Future<List<ActivityItem>> _fetchExpenseActivity({
    required String userId,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
    try {
      final rows = await _client
          .from('farmer_expenses')
          .select(
            'id, name, description, category, amount, is_subsidy, created_at',
          )
          .eq('farmer_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      for (final r in rows) {
        final isSubsidy = r['is_subsidy'] as bool? ?? false;
        // `name` is a nullable, later-added column — older rows (confirmed
        // via live DB check) predate it and have it null. `description` is
        // NOT NULL on this table, so it's the reliable fallback rather than
        // ever rendering the literal string "null" in the subtitle.
        final nameText = (r['name'] as String?)?.trim();
        final label = (nameText != null && nameText.isNotEmpty)
            ? nameText
            : r['description'] as String;
        items.add(
          ActivityItem(
            id: r['id'] as String,
            type: ActivityType.expenseAdded,
            title: 'Expense Added',
            subtitle: '$label • ${r['category']}',
            valueLabel: isSubsidy
                ? 'Subsidized'
                : '₱${(r['amount'] as num).toStringAsFixed(0)}',
            timestamp: DateTime.parse(r['created_at'] as String),
          ),
        );
      }
    } catch (_) {}
    return items;
  }

  // ─── Program Enrollment Activity ────────────────────────────────────────────
  // The farmer's own enrollment request only (submitted_at) — Admin's
  // approve/reject is a separate, Admin-driven event and is not surfaced
  // here, same pattern as every other request source in this file.

  Future<List<ActivityItem>> _fetchProgramEnrollmentActivity({
    required String userId,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
    try {
      final rows = await _client
          .from('program_enrollment_requests')
          .select('id, submitted_at, cooperative_programs(program_name)')
          .eq('farmer_id', userId)
          .order('submitted_at', ascending: false)
          .limit(limit);
      for (final r in rows) {
        final programName =
            (r['cooperative_programs'] as Map?)?['program_name'] as String? ??
            'Program';
        items.add(
          ActivityItem(
            id: r['id'] as String,
            type: ActivityType.programEnrollment,
            title: 'Requested Program Enrollment',
            subtitle: programName,
            statusLabel: 'Pending Review',
            timestamp: DateTime.parse(r['submitted_at'] as String),
          ),
        );
    }
    } catch (_) {}
    return items;
  }

  // ─── Program Purchase Activity ──────────────────────────────────────────────
  // The farmer's own purchase request only (requested_at) — Admin's
  // confirm/cancel is a separate, Admin-driven event and is not surfaced
  // here.

  Future<List<ActivityItem>> _fetchProgramPurchaseActivity({
    required String userId,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
    try {
      final rows = await _client
          .from('program_product_purchases')
          .select(
            'id, quantity, total_amount, requested_at, '
            'cooperative_programs(program_name), '
            'program_products(cooperative_inventory(item_name))',
          )
          .eq('farmer_id', userId)
          .order('requested_at', ascending: false)
          .limit(limit);
      for (final r in rows) {
        final programName =
            (r['cooperative_programs'] as Map?)?['program_name'] as String? ??
            'Program';
        final product = r['program_products'] as Map?;
        final itemName =
            (product?['cooperative_inventory'] as Map?)?['item_name']
                as String? ??
            programName;
        items.add(
          ActivityItem(
            id: r['id'] as String,
            type: ActivityType.programPurchase,
            title: 'Requested Program Purchase',
            subtitle: '${r['quantity']} × $itemName',
            valueLabel: '₱${(r['total_amount'] as num).toStringAsFixed(0)}',
            statusLabel: 'Pending',
            timestamp: DateTime.parse(r['requested_at'] as String),
          ),
        );
    }
    } catch (_) {}
    return items;
  }

  // ─── Capital Reinvestment Activity ──────────────────────────────────────────
  // Filtered to source = 'patronage_capital' ("Add to Capital") only —
  // capital_contribution_events also carries 'member_payment',
  // 'manual_adjustment', and 'opening_balance' rows, which are
  // Admin/system-driven and out of scope for this entry.

  Future<List<ActivityItem>> _fetchCapitalReinvestmentActivity({
    required String userId,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
    try {
      final rows = await _client
          .from('capital_contribution_events')
          .select('id, amount, created_at')
          .eq('farmer_id', userId)
          .eq('source', 'patronage_capital')
          .order('created_at', ascending: false)
          .limit(limit);
      for (final r in rows) {
        items.add(
          ActivityItem(
            id: r['id'] as String,
            type: ActivityType.capitalReinvestment,
            title: 'Added to Capital Share',
            subtitle: 'My Contribution',
            valueLabel: '₱${(r['amount'] as num).toStringAsFixed(0)}',
            timestamp: DateTime.parse(r['created_at'] as String),
          ),
        );
    }
    } catch (_) {}
    return items;
  }

  // ─── Sync Activity ───────────────────────────────────────────────────────────
  // Home's only self-originated action.

  // Called by FarmerDashboardScreen's Sync Now handler, only when there was
  // a nonzero unsynced count before SyncService.syncPending() ran — a sync
  // tap that had nothing queued isn't a meaningful action to log.
  Future<void> logSyncCompleted() async {
    try {
      await _client.from('farmer_home_activity').insert({
        'farmer_id': _userId,
        'description': 'Synced offline records',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<List<ActivityItem>> _fetchSyncActivity({
    required String userId,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
    try {
      final rows = await _client
          .from('farmer_home_activity')
          .select('id, description, created_at')
          .eq('farmer_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      for (final r in rows) {
        items.add(
          ActivityItem(
            id: r['id'] as String,
            type: ActivityType.syncCompleted,
            title: r['description'] as String,
            subtitle: 'Home',
            statusLabel: 'Synced',
            timestamp: DateTime.parse(r['created_at'] as String),
          ),
        );
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
}

// ─── Latest price for a specific crop (Create Listing reference) ──────────────

extension CropPriceFetch on DashboardRepository {
  // priceType (sp3_cooperative | open_market), when the caller has it —
  // Create Listing does, via the selected batch's own cropType — narrows
  // the match to the crop's actual market-type price record. Without it,
  // this fell back to "most recent price under any type," which happened
  // to be harmless while every crop had at most one price_type on record
  // (confirmed via a live DB check), but was never actually correct for a
  // crop with more than one. Left optional, not required, so a caller
  // without a known price type still gets the old fallback behavior
  // rather than being forced to pass one.
  Future<double?> fetchLatestPriceForCrop(
    String cropName, {
    String? priceType,
  }) async {
    final client = Supabase.instance.client;
    try {
      var query = client
          .from('price_records')
          .select('price')
          .ilike('crop_name', cropName);
      if (priceType != null) {
        query = query.eq('price_type', priceType);
      }
      final response = await query
          .order('recorded_at', ascending: false)
          .limit(1);
      if (response.isEmpty) return null;
      return (response.first['price'] as num).toDouble();
    } catch (_) {
      return null;
    }
  }
}