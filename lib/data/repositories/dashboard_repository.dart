import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/offline_cache.dart';
import 'completed_order_dates.dart';
import '../models/dashboard_summary_model.dart';
import '../services/hive_service.dart';
import '../../core/l10n/app_localizations.dart';
import '../services/app_settings_service.dart';
import '../models/activity_text.dart';
import '../models/admin_log_message.dart';
import '../../core/utils/quantity_utils.dart';

/// Localized labels for activity entries. Repositories have no BuildContext,
/// so they resolve the user's current locale directly.
AppLocalizations get _l =>
    lookupAppLocalizations(AppSettingsService.instance.locale);

class DashboardRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  // ─── KPI Summary ─────────────────────────────────────────────────────────────

  /// OfflineCache keys of the summary queries for the current dates (the same keys
  /// fetchSummary writes), for the farmer dashboard notice.
  static List<String> summaryCacheScreens() {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startOfLastMonth = DateTime(now.year, now.month - 1, 1);
    final startOfYear = DateTime(now.year, 1, 1);
    return [
      'dash_yield_month_${startOfMonth.toIso8601String()}',
      'dash_yield_last_month_${startOfLastMonth.toIso8601String()}',
      'dash_yield_year_${startOfYear.toIso8601String()}',
      'dash_earnings_goal',
      'dash_marketplace_${startOfYear.toIso8601String()}',
      'dash_coop_sales_${startOfYear.toIso8601String()}',
      'dash_informal_${startOfYear.toIso8601String()}',
      'dash_market_linking_${startOfYear.toIso8601String()}',
    ];
  }

  Future<DashboardSummaryModel> fetchSummary() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startOfLastMonth = DateTime(now.year, now.month - 1, 1);
    final endOfLastMonth = DateTime(now.year, now.month, 0);

    double monthlyYield = 0;
    double lastMonthYield = 0;

    // Monthly yield — this calendar month's harvest_records rows.
    try {
      final yieldResponse = await OfflineCache.load(
        screen: 'dash_yield_month_${startOfMonth.toIso8601String()}',
        fetch: () => _client
            .from('harvest_records')
            .select('quantity_kg, unit')
            .eq('farmer_id', _userId)
            .gte('harvest_date', startOfMonth.toIso8601String()),
      );
      monthlyYield = yieldResponse.fold<double>(
        0,
        // A kg total: only rows measured in kg are added (units are never mixed).
        (sum, row) => isKg(row['unit'] as String?)
            ? sum + (row['quantity_kg'] as num).toDouble()
            : sum,
      );
    } catch (_) {}

    // Yield last month for trend
    try {
      final lastMonthYieldResponse = await OfflineCache.load(
        screen: 'dash_yield_last_month_${startOfLastMonth.toIso8601String()}',
        fetch: () => _client
            .from('harvest_records')
            .select('quantity_kg, unit')
            .eq('farmer_id', _userId)
            .gte('harvest_date', startOfLastMonth.toIso8601String())
            .lte('harvest_date', endOfLastMonth.toIso8601String()),
      );
      lastMonthYield = lastMonthYieldResponse.fold<double>(
        0,
        // A kg total: only rows measured in kg are added (units are never mixed).
        (sum, row) => isKg(row['unit'] as String?)
            ? sum + (row['quantity_kg'] as num).toDouble()
            : sum,
      );
    } catch (_) {}

    // Annual yield — the kg total of the current calendar year, from the same
    // per-year loader the Profile tab's Annual Yield uses (_loadYearYield), so
    // the two can never disagree. It includes Hive-queued offline harvests, as
    // the Harvest tab's season total does.
    final annualYield = (await _loadYearYield(now.year))[kDefaultUnit] ?? 0;

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
      final qty = isKg(payload['unit'] as String?)
          ? (payload['quantity_kg'] as num?)?.toDouble() ?? 0
          : 0.0;
      if (harvestDate == null) continue;
      if (!harvestDate.isBefore(startOfMonth)) {
        monthlyYield += qty;
      } else if (!harvestDate.isBefore(startOfLastMonth) &&
          !harvestDate.isAfter(endOfLastMonth)) {
        lastMonthYield += qty;
      }
    }

    // Admin-configurable monthly earnings goal (farmer_dashboard_settings),
    // never hardcoded. Falls back to the table's own documented default if
    // the row is unreachable, matching the settings table's own DEFAULT —
    // not a business decision made here, just keeping this screen usable
    // if the read fails.
    double earningsGoal = 5000;
    try {
      final goalRows = await OfflineCache.load(
        screen: 'dash_earnings_goal',
        fetch: () => _client
            .from('farmer_dashboard_settings')
            .select('monthly_earnings_goal')
            .eq('id', 1)
            .limit(1),
      );
      final goalRow = goalRows.first;
      earningsGoal = (goalRow['monthly_earnings_goal'] as num).toDouble();
    } catch (_) {}

    // Earnings — four farmer income channels, from the same per-year loader the
    // Profile tab's Annual Earnings uses (_loadYearEarnings), so Home's monthly
    // figure and Profile's annual figure are built from the very same rows:
    // Marketplace (completed orders, by the day the buyer confirmed receipt),
    // Offer to Cooperative (member_sales_transactions), Informal Sales and
    // DA-AMAD Market Linking (market_linking_sales). Each source keeps its own
    // independent try/catch so one failing can't blank out the others — the
    // app-wide convention of failing toward "show less," never toward a
    // plausible-but-wrong bigger number.
    final earnings = await _loadYearEarnings(now.year);
    final monthlyEarnings = earnings.totalFrom(startOfMonth);
    final annualEarnings = earnings.total;

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

  // ─── Annual summary (Profile tab: Annual Yield / Annual Earnings) ────────────
  //
  // One calendar year at a time. Every figure is computed from the records dated
  // INSIDE that year ([Jan 1, Jan 1 of the next year)), so:
  //   * a new year starts at zero by itself — nothing is reset or deleted, and
  //     every earlier year is still there to look at;
  //   * a sale is counted once, in the year it was completed, and only if it is
  //     a completed sale (see each channel below);
  //   * the Home tab's monthly figures and this annual figure share these loaders.

  /// OfflineCache keys of the annual queries for [year], for the cache notice.
  static List<String> annualCacheScreens(int year) {
    final y = DateTime(year, 1, 1).toIso8601String();
    return [
      'dash_yield_year_$y',
      'dash_marketplace_$y',
      'dash_coop_sales_$y',
      'dash_informal_$y',
      'dash_market_linking_$y',
    ];
  }

  Future<AnnualFarmSummary> fetchAnnualSummary(int year) async {
    final results = await Future.wait([
      _loadYearYield(year),
      _loadYearEarnings(year),
    ]);
    final yieldByUnit = results[0] as Map<String, double>;
    final earnings = results[1] as _YearEarnings;
    return AnnualFarmSummary(
      year: year,
      yieldByUnit: yieldByUnit,
      marketplace: earnings.sumOf(earnings.marketplace),
      cooperative: earnings.sumOf(earnings.cooperative),
      informal: earnings.sumOf(earnings.informal),
      marketLinking: earnings.sumOf(earnings.marketLinking),
    );
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// The harvest of [year], summed per unit (a sack is never added to a
  /// kilogram). harvest_date is a DATE: compared as calendar dates, with an upper
  /// bound so a record dated in a later year is never counted in this one.
  /// Hive-queued harvests not yet synced are included, as on the Harvest tab.
  Future<Map<String, double>> _loadYearYield(int year) async {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);
    final byUnit = <String, double>{};
    try {
      final rows = await OfflineCache.load(
        screen: 'dash_yield_year_${start.toIso8601String()}',
        fetch: () => _client
            .from('harvest_records')
            .select('quantity_kg, unit')
            .eq('farmer_id', _userId)
            .gte('harvest_date', _dateOnly(start))
            .lt('harvest_date', _dateOnly(end)),
      );
      for (final row in rows) {
        final unit = unitOrDefault(row['unit'] as String?);
        byUnit[unit] =
            (byUnit[unit] ?? 0) + (row['quantity_kg'] as num).toDouble();
      }
    } catch (_) {}

    for (final entry in HiveService.getPendingHarvests()) {
      final payload = entry.value;
      final date = DateTime.tryParse(payload['harvest_date'] as String? ?? '');
      if (date == null || date.isBefore(start) || !date.isBefore(end)) continue;
      final unit = unitOrDefault(payload['unit'] as String?);
      byUnit[unit] =
          (byUnit[unit] ?? 0) + ((payload['quantity_kg'] as num?)?.toDouble() ?? 0);
    }
    return {for (final e in byUnit.entries) e.key: roundQuantity(e.value)};
  }

  /// The completed sales of [year], one list per selling channel. Each source
  /// keeps its own try/catch so one failing cannot blank out the others, and
  /// fails toward "show less", never toward a bigger wrong number.
  ///
  ///  * Marketplace — only orders with status 'completed' (the buyer confirmed
  ///    receipt), dated by that confirmation (orders.received_at). An order with
  ///    no received_at (completed before it existed) is dated by its creation, as
  ///    before. An order placed on 30 Dec and received on 2 Jan counts in January.
  ///  * Offer to Cooperative — member_sales_transactions, written once when the
  ///    Manager / Officer confirms the delivery; sale_date is a DATE.
  ///  * Informal Sale — informal_sales; a NULL amount counts as 0.
  ///  * DA-AMAD Market Linking — market_linking_sales, one row per recorded sale.
  Future<_YearEarnings> _loadYearEarnings(int year) async {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);
    final startUtc = start.toUtc().toIso8601String();
    final endUtc = end.toUtc().toIso8601String();
    final key = start.toIso8601String();
    final out = _YearEarnings();

    Future<void> marketplace() async {
      try {
        final rows = await OfflineCache.load(
          screen: 'dash_marketplace_$key',
          fetch: () => CompletedOrderDates.withFallback((withReceivedAt) {
            final base = _client
                .from('orders')
                .select(
                  withReceivedAt
                      ? 'total_price, created_at, received_at'
                      : 'total_price, created_at',
                )
                .eq('farmer_id', _userId)
                .eq('status', 'completed');
            return withReceivedAt
                ? base.or(CompletedOrderDates.window(start, end)!)
                : base.gte('created_at', startUtc).lt('created_at', endUtc);
          }),
        );
        for (final row in rows) {
          out.marketplace.add((
            amount: (row['total_price'] as num).toDouble(),
            date: CompletedOrderDates.of(row),
          ));
        }
      } catch (_) {}
    }

    Future<void> cooperative() async {
      try {
        final rows = await OfflineCache.load(
          screen: 'dash_coop_sales_$key',
          fetch: () => _client
              .from('member_sales_transactions')
              .select('amount, sale_date')
              .eq('farmer_id', _userId)
              .gte('sale_date', _dateOnly(start))
              .lt('sale_date', _dateOnly(end)),
        );
        for (final row in rows) {
          out.cooperative.add((
            amount: (row['amount'] as num).toDouble(),
            date: DateTime.parse(row['sale_date'] as String),
          ));
        }
      } catch (_) {}
    }

    Future<void> informal() async {
      try {
        final rows = await OfflineCache.load(
          screen: 'dash_informal_$key',
          fetch: () => _client
              .from('informal_sales')
              .select('amount, sale_date')
              .eq('farmer_id', _userId)
              .gte('sale_date', startUtc)
              .lt('sale_date', endUtc),
        );
        for (final row in rows) {
          out.informal.add((
            amount: (row['amount'] as num?)?.toDouble() ?? 0,
            date: DateTime.parse(row['sale_date'] as String).toLocal(),
          ));
        }
      } catch (_) {}
    }

    Future<void> marketLinking() async {
      try {
        final rows = await OfflineCache.load(
          screen: 'dash_market_linking_$key',
          fetch: () => _client
              .from('market_linking_sales')
              .select('confirmed_volume_kg, price_per_kg, completed_at')
              .eq('farmer_id', _userId)
              .gte('completed_at', startUtc)
              .lt('completed_at', endUtc),
        );
        for (final row in rows) {
          // (The names keep the legacy "kg": the quantity and price are per
          // the sale's own unit.)
          final pricePerKg = (row['price_per_kg'] as num?)?.toDouble();
          if (pricePerKg == null) continue;
          final quantityKg = (row['confirmed_volume_kg'] as num?)?.toDouble() ?? 0;
          out.marketLinking.add((
            amount: moneyOf(quantityKg, pricePerKg),
            date: DateTime.parse(row['completed_at'] as String).toLocal(),
          ));
        }
      } catch (_) {}
    }

    await Future.wait([marketplace(), cooperative(), informal(), marketLinking()]);
    return out;
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

  /// OfflineCache key for one fetchActivity() page. Screens use it to show the
  /// cache notice for the page they display.
  static String activityCacheScreen({
    int limit = 50,
    int offset = 0,
    ActivityFilter? typeFilter,
    String? searchQuery,
    Set<ActivityType>? excludeTypes,
  }) {
    final excluded =
        (excludeTypes ?? <ActivityType>{}).map((t) => t.name).toList()..sort();
    return 'activity_${typeFilter?.name ?? 'all'}_'
        '${searchQuery ?? ''}_${excluded.join(',')}_${limit}_$offset';
  }

  /// Recent activity, cached per filter combination so the feed can still be
  /// viewed offline. The cache holds the whole result for these inputs.
  Future<List<ActivityItem>> fetchActivity({
    int limit = 50,
    int offset = 0,
    ActivityFilter? typeFilter,
    String? searchQuery,
    Set<ActivityType>? excludeTypes,
  }) async {
    final screen = activityCacheScreen(
      limit: limit,
      offset: offset,
      typeFilter: typeFilter,
      searchQuery: searchQuery,
      excludeTypes: excludeTypes,
    );
    try {
      final rows = await OfflineCache.load(
        screen: screen,
        fetch: () async => (await _fetchActivityLive(
          limit: limit,
          offset: offset,
          typeFilter: typeFilter,
          searchQuery: searchQuery,
          excludeTypes: excludeTypes,
        )).map((item) => item.toMap()).toList(),
      );
      return rows.map(ActivityItem.fromMap).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ActivityItem>> _fetchActivityLive({
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
    final harvests = await _client
        .from('harvest_records')
        .select(
          'id, crop_name, quantity_kg, unit, batch_number, created_at, is_synced',
        )
        .eq('farmer_id', _userId)
        .order('created_at', ascending: false)
        .limit(sourceLimit);
    for (final h in harvests) {
      final cropName = h['crop_name'] as String;
      final batchNo = formatBatchNumber(h['batch_number'] as String?);
      if (!matchesSearch(cropName) && !matchesSearch(batchNo)) continue;
      final isSynced = h['is_synced'] as bool? ?? false;
      items.add(
        ActivityItem(
          id: h['id'] as String,
          type: ActivityType.harvest,
          title: _l.activityHarvestTitle(cropName),
          subtitle:
              '${batchNo.isEmpty ? '—' : batchNo} • ${_formatRelative(DateTime.parse(h['created_at'] as String))}',
          valueLabel: formatQuantityUnit(
            h['quantity_kg'] as num,
            h['unit'] as String?,
          ),
          statusLabel: isSynced ? _l.activitySynced : _l.activityPendingSync,
          timestamp: DateTime.parse(h['created_at'] as String),
        ),
      );
    }

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
          title: _l.activityListingSubmittedTitle(cropName),
          subtitle: subtitle,
          statusLabel: _l.activityPendingReview,
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
            title: _l.activityListingWithdrawnTitle(cropName),
            subtitle: subtitle,
            statusLabel: _l.activityWithdrawn,
            timestamp: DateTime.parse(l['updated_at'] as String),
          ),
        );
      }
    }

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
    final orders = await _client
        .from('orders')
        .select(
          'id, quantity_kg, unit, total_price, created_at, fulfillment_method, marketplace_listings(crop_name)',
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
          title: _l.activityOrderPlacedTitle,
          subtitle: fulfillmentLabel != null
              ? '${formatQuantityUnit(o['quantity_kg'] as num, o['unit'] as String?)} $cropName • $fulfillmentLabel'
              : '${formatQuantityUnit(o['quantity_kg'] as num, o['unit'] as String?)} $cropName',
          valueLabel: formatPesos(o['total_price'] as num),
          statusLabel: fulfillmentLabel,
          timestamp: DateTime.parse(o['created_at'] as String),
        ),
      );
    }

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
          title: _l.activityCropRequestSubmitted,
          subtitle: name,
          statusLabel: _l.activityPendingReview,
          timestamp: DateTime.parse(r['created_at'] as String),
        ),
      );
    }
    return items;
  }

  // ─── Crop Added Activity (instant catalog add) ─────────────────────────────

  Future<List<ActivityItem>> _fetchCropAddedActivity({
    required String userId,
    String? searchQuery,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
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
          title: _l.activityCropAdded,
          subtitle: name,
          statusLabel: _l.activityAdded,
          timestamp: DateTime.parse(c['created_at'] as String),
        ),
      );
    }
    return items;
  }

  // ─── Informal Sale Activity ────────────────────────────────────────────────

  Future<List<ActivityItem>> _fetchInformalSaleActivity({
    required String userId,
    String? searchQuery,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
    final sales = await _client
        .from('informal_sales')
        .select(
          'id, crop_name, quantity_kg, unit, amount, buyer_name, sale_date',
        )
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
          title: _l.activityInformalSaleTitle,
          subtitle: buyer != null && buyer.isNotEmpty
              ? '$cropName • Sold to $buyer'
              : cropName,
          valueLabel: s['amount'] != null
              ? formatPesos(s['amount'] as num)
              : null,
          statusLabel: formatQuantityUnit(
            s['quantity_kg'] as num,
            s['unit'] as String?,
          ),
          timestamp: DateTime.parse(s['sale_date'] as String),
        ),
      );
    }
    return items;
  }

  // ─── Crop Photo Activity ────────────────────────────────────────────────────

  Future<List<ActivityItem>> _fetchCropPhotoActivity({
    required String userId,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
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
          title: localizeActivityRow(r),
          subtitle: _l.activityCropRoster,
          statusLabel: _l.activityUpdated,
          timestamp: DateTime.parse(r['created_at'] as String),
        ),
      );
    }
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
    final offers = await _client
        .from('cooperative_purchase_offers')
        .select('id, crop_name, offered_quantity_kg, unit, offered_at')
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
          title: _l.activityOfferedToCoop,
          subtitle: cropName,
          statusLabel: formatQuantityUnit(
            o['offered_quantity_kg'] as num,
            o['unit'] as String?,
          ),
          timestamp: DateTime.parse(o['offered_at'] as String),
        ),
      );
    }
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
          title: _l.activityMarketLinkingSubmitted,
          subtitle: _l.activityGingerMarketLinking,
          statusLabel: _l.activityPendingReview,
          timestamp: DateTime.parse(r['submitted_at'] as String),
        ),
      );
    }
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
    // The request's own unit when the database has the column yet.
    Future<List<Map<String, dynamic>>> read(String columns) async =>
        List<Map<String, dynamic>>.from(
          await _client
              .from('market_linking_programs')
              .select(columns)
              .eq('farmer_id', userId)
              .not('submitted_at', 'is', null)
              .order('submitted_at', ascending: false)
              .limit(limit),
        );
    List<Map<String, dynamic>> rows;
    try {
      rows = await read('id, volume_kg, unit, submitted_at');
    } catch (_) {
      rows = await read('id, volume_kg, submitted_at');
    }
    for (final r in rows) {
      items.add(
        ActivityItem(
          id: r['id'] as String,
          type: ActivityType.gingerBatchSubmission,
          title: _l.activityGingerBatchSubmitted,
          subtitle: _l.activityMarketLinking,
          statusLabel: formatQuantityUnit(
            (r['volume_kg'] as num?) ?? 0,
            r['unit'] as String?,
          ),
          timestamp: DateTime.parse(r['submitted_at'] as String),
        ),
      );
    }
    return items;
  }

  // ─── Account Activity (password, photo, basic info, farm details) ─────────

  Future<List<ActivityItem>> _fetchProfileActivity({
    required String userId,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
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
          title: localizeActivityRow(r),
          subtitle: _l.activityAccount,
          statusLabel: _l.activityUpdated,
          timestamp: DateTime.parse(r['created_at'] as String),
        ),
      );
    }
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
          title: localizeActivityRow(r),
          subtitle: _l.activityAddress,
          statusLabel: _l.activityUpdated,
          timestamp: DateTime.parse(r['created_at'] as String),
        ),
      );
    }
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
          : localizeActivityRow(r);
      items.add(
        ActivityItem(
          id: r['id'] as String,
          type: ActivityType.expenseAdded,
          title: _l.activityExpenseAdded,
          subtitle: '$label • ${r['category']}',
          valueLabel: isSubsidy
              ? 'Subsidized'
              : '₱${(r['amount'] as num).toStringAsFixed(0)}',
          timestamp: DateTime.parse(r['created_at'] as String),
        ),
      );
    }
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
          title: _l.activityProgramEnrollmentRequested,
          subtitle: programName,
          statusLabel: _l.activityPendingReview,
          timestamp: DateTime.parse(r['submitted_at'] as String),
        ),
      );
    }
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
          title: _l.activityProgramPurchaseRequested,
          subtitle: '${r['quantity']} × $itemName',
          valueLabel: '₱${(r['total_amount'] as num).toStringAsFixed(0)}',
          statusLabel: _l.activityPending,
          timestamp: DateTime.parse(r['requested_at'] as String),
        ),
      );
    }
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
          title: _l.activityCapitalAdded,
          subtitle: _l.activityMyContribution,
          valueLabel: '₱${(r['amount'] as num).toStringAsFixed(0)}',
          timestamp: DateTime.parse(r['created_at'] as String),
        ),
      );
    }
    return items;
  }

  // ─── Sync Activity ───────────────────────────────────────────────────────────
  // Home's only self-originated action.

  // Called by FarmerDashboardScreen's Sync Now handler, only when there was
  // a nonzero unsynced count before SyncService.syncPending() ran — a sync
  // tap that had nothing queued isn't a meaningful action to log.
  Future<void> logSyncCompleted() async {
    await _client.from('farmer_home_activity').insert({
      'farmer_id': _userId,
      ...activityRowFields(
        const AdminLogMessage('activitySyncedOfflineRecords'),
      ),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<ActivityItem>> _fetchSyncActivity({
    required String userId,
    int limit = 15,
  }) async {
    final List<ActivityItem> items = [];
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
          title: localizeActivityRow(r),
          subtitle: _l.activityHome,
          statusLabel: _l.activitySynced,
          timestamp: DateTime.parse(r['created_at'] as String),
        ),
      );
    }
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
  /// [unit]: when given, only a reference price quoted in that same unit is
  /// returned. A price per kg is not a price per sack, so a batch measured in
  /// another unit gets no suggested price rather than a wrong one.
  Future<double?> fetchLatestPriceForCrop(
    String cropName, {
    String? priceType,
    String? unit,
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
      if (unit != null) {
        query = query.ilike('unit', unit.trim());
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

/// The completed sales of one year, per selling channel (amount + the day it
/// counts on). Private to this file; see [DashboardRepository._loadYearEarnings].
class _YearEarnings {
  final List<({double amount, DateTime date})> marketplace = [];
  final List<({double amount, DateTime date})> cooperative = [];
  final List<({double amount, DateTime date})> informal = [];
  final List<({double amount, DateTime date})> marketLinking = [];

  double sumOf(List<({double amount, DateTime date})> rows) =>
      rows.fold<double>(0, (sum, r) => sum + r.amount);

  double get total =>
      sumOf(marketplace) +
      sumOf(cooperative) +
      sumOf(informal) +
      sumOf(marketLinking);

  /// The part of the year from [from] on (e.g. this month).
  double totalFrom(DateTime from) {
    double sum = 0;
    for (final list in [marketplace, cooperative, informal, marketLinking]) {
      for (final r in list) {
        if (!r.date.isBefore(from)) sum += r.amount;
      }
    }
    return sum;
  }
}
