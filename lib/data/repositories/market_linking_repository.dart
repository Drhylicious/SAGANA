import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_activity_repository.dart';

// ─── Market Linking Status ─────────────────────────────────────────────────────

enum MarketLinkingStatus {
  // Farmer-initiated, not yet reviewed by an admin. Strictly before
  // submitted in the lifecycle — see supabase_schema_market_linking_
  // farmer_requests.sql for why this couldn't just reuse 'submitted'.
  requested,
  submitted,
  buyerFound,
  completed,
  cancelled,
}

extension MarketLinkingStatusExt on MarketLinkingStatus {
  String get value {
    switch (this) {
      case MarketLinkingStatus.requested:
        return 'requested';
      case MarketLinkingStatus.submitted:
        return 'submitted';
      case MarketLinkingStatus.buyerFound:
        return 'buyer_found';
      case MarketLinkingStatus.completed:
        return 'completed';
      case MarketLinkingStatus.cancelled:
        return 'cancelled';
    }
  }

  String get label {
    switch (this) {
      case MarketLinkingStatus.requested:
        return 'Requested';
      case MarketLinkingStatus.submitted:
        return 'Submitted';
      case MarketLinkingStatus.buyerFound:
        return 'Buyer Found';
      case MarketLinkingStatus.completed:
        return 'Completed';
      case MarketLinkingStatus.cancelled:
        return 'Cancelled';
    }
  }

  static MarketLinkingStatus fromString(String? v) {
    switch (v) {
      case 'requested':
        return MarketLinkingStatus.requested;
      case 'buyer_found':
        return MarketLinkingStatus.buyerFound;
      case 'completed':
        return MarketLinkingStatus.completed;
      case 'cancelled':
        return MarketLinkingStatus.cancelled;
      default:
        return MarketLinkingStatus.submitted;
    }
  }
}

// ─── DA-AMAD Enrollment ─────────────────────────────────────────────────────
// Distinct from MarketLinkingStatus above: this tracks whether a farmer is
// a participant in the DA-AMAD Ginger program at all, independent of any
// specific harvest submission. One farmer has at most one active
// (pending/approved) enrollment at a time; market_linking_programs rows
// (individual harvest sales) only become reachable once approved here.

enum DaAmadEnrollmentStatus { pending, approved, rejected }

extension DaAmadEnrollmentStatusExt on DaAmadEnrollmentStatus {
  String get value {
    switch (this) {
      case DaAmadEnrollmentStatus.pending:
        return 'pending';
      case DaAmadEnrollmentStatus.approved:
        return 'approved';
      case DaAmadEnrollmentStatus.rejected:
        return 'rejected';
    }
  }

  static DaAmadEnrollmentStatus fromString(String? v) {
    switch (v) {
      case 'approved':
        return DaAmadEnrollmentStatus.approved;
      case 'rejected':
        return DaAmadEnrollmentStatus.rejected;
      default:
        return DaAmadEnrollmentStatus.pending;
    }
  }
}

class DaAmadEnrollmentModel {
  final String id;
  final String farmerId;
  final String farmerName;
  final DaAmadEnrollmentStatus status;
  final String? adminNotes;
  final DateTime submittedAt;
  final DateTime? reviewedAt;

  const DaAmadEnrollmentModel({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    required this.status,
    this.adminNotes,
    required this.submittedAt,
    this.reviewedAt,
  });
}

// ─── Market Linking Model ──────────────────────────────────────────────────────

class MarketLinkingModel {
  final String id;
  final String farmerId;
  final String farmerName;
  final String? farmerPhotoUrl;
  final String cropName;
  final int seasonYear;
  final MarketLinkingStatus status;
  final String? buyerName;
  final String? buyerContact;
  final double? volumeKg;
  // Captured when the entry moves to Buyer Found — the quantity the buyer
  // wants to purchase, distinct from volumeKg (farmer's committed volume
  // at enrollment) and confirmedVolumeKg (final, set at Completion).
  final double? requestedVolumeKg;
  final double? pricePerKg;
  final String? notes;
  final DateTime submittedAt;
  final DateTime? buyerFoundAt;
  final DateTime? completedAt;

  // Optional inventory tie-in — absent for the entire life of most
  // enrollments. Only ever set by completing with a batch attached.
  final String? inventoryBatchId;
  final double? confirmedVolumeKg;
  final String? batchNumber; // enrichment only, not a real column

  // The DA-AMAD Enrollment that authorized this submission — see
  // supabase_schema_market_linking_enrollment_link.sql. Null for any row
  // submitted before that migration (genuinely wasn't authorized through
  // this gate, since Enrollment didn't exist yet), and not currently
  // surfaced anywhere in the UI — the explicit link is a schema-level
  // improvement, not a new feature.
  final String? enrollmentId;

  const MarketLinkingModel({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    this.farmerPhotoUrl,
    required this.cropName,
    required this.seasonYear,
    required this.status,
    this.buyerName,
    this.buyerContact,
    this.volumeKg,
    this.requestedVolumeKg,
    this.pricePerKg,
    this.notes,
    required this.submittedAt,
    this.buyerFoundAt,
    this.completedAt,
    this.inventoryBatchId,
    this.confirmedVolumeKg,
    this.batchNumber,
    this.enrollmentId,
  });

  bool get isActive =>
      status == MarketLinkingStatus.requested ||
      status == MarketLinkingStatus.submitted ||
      status == MarketLinkingStatus.buyerFound;

  double? get totalValue =>
      volumeKg != null && pricePerKg != null ? volumeKg! * pricePerKg! : null;

  String get initials {
    final parts = farmerName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return farmerName.isNotEmpty ? farmerName[0].toUpperCase() : 'F';
  }

  factory MarketLinkingModel.fromMap(Map<String, dynamic> map) {
    return MarketLinkingModel(
      id:             map['id'] as String,
      farmerId:       map['farmer_id'] as String,
      farmerName:     map['farmer_name'] as String? ?? 'Farmer',
      farmerPhotoUrl: map['farmer_photo_url'] as String?,
      cropName:       map['crop_name'] as String? ?? 'Ginger',
      seasonYear:     map['season_year'] as int? ?? DateTime.now().year,
      status: MarketLinkingStatusExt.fromString(map['status'] as String?),
      buyerName:      map['buyer_name'] as String?,
      buyerContact:   map['buyer_contact'] as String?,
      volumeKg:       map['volume_kg'] != null
                          ? (map['volume_kg'] as num).toDouble()
                          : null,
      requestedVolumeKg: map['requested_volume_kg'] != null
                          ? (map['requested_volume_kg'] as num).toDouble()
                          : null,
      pricePerKg:     map['price_per_kg'] != null
                          ? (map['price_per_kg'] as num).toDouble()
                          : null,
      notes:          map['notes'] as String?,
      submittedAt:    DateTime.parse(map['submitted_at'] as String),
      buyerFoundAt:   map['buyer_found_at'] != null
                          ? DateTime.parse(map['buyer_found_at'] as String)
                          : null,
      completedAt:    map['completed_at'] != null
                          ? DateTime.parse(map['completed_at'] as String)
                          : null,
      inventoryBatchId: map['inventory_batch_id'] as String?,
      confirmedVolumeKg: map['confirmed_volume_kg'] != null
                          ? (map['confirmed_volume_kg'] as num).toDouble()
                          : null,
      batchNumber:    map['batch_number'] as String?,
      enrollmentId: map['enrollment_id'] as String?,
    );
  }
}

// ─── Market Linking Summary Stats ──────────────────────────────────────────────

/// Lightweight aggregate for dashboard use — status column only, no farmer
/// join, no full row hydration. Matches the fetchSummaryStats() pattern
/// already established by AdminListingRepository/AdminOrderRepository
/// (M-11, Admin Marketplace review, Phase 7).
class MarketLinkingSummaryStats {
  final int total;
  final int submitted;
  // Unique farmers enrolled — NOT the same as total (total rounds/records;
  // a farmer with two rounds via Start New Round is still one enrolled
  // farmer). The Marketplace Dashboard's "Market Linking" tile shows this,
  // not total, for the same reason the screen's own KPI strip does
  // (see M-marketplace-6/M-marketplace-8).
  final int enrolledFarmers;

  const MarketLinkingSummaryStats({
    required this.total,
    required this.submitted,
    required this.enrolledFarmers,
  });

  static const empty = MarketLinkingSummaryStats(
    total: 0,
    submitted: 0,
    enrolledFarmers: 0,
  );
}

// ─── Repository ────────────────────────────────────────────────────────────────

class MarketLinkingRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<MarketLinkingModel>> fetchAll({String? statusFilter}) async {
    try {
      var query = _client
          .from('market_linking_programs')
          .select('*, farmer_id');

      if (statusFilter != null) {
        query = query.eq('status', statusFilter);
      }

      final rows = await query.order('submitted_at', ascending: false);
      if (rows.isEmpty) return [];

      final farmerIds = rows
          .map((r) => r['farmer_id'] as String)
          .toSet()
          .toList();

      // Fetch farmer info
      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name, profile_photo_url')
          .inFilter('user_id', farmerIds);
      final infoMap = {for (final r in infoRows) r['user_id'] as String: r};

      // Batch numbers — only for rows that actually have one attached.
      // Most enrollments never do, so this query is skipped entirely
      // when nothing needs it.
      final batchIds = rows
          .map((r) => r['inventory_batch_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final batchMap = <String, String>{};
      if (batchIds.isNotEmpty) {
        try {
          final batchRows = await _client
              .from('inventory_batches')
              .select('id, batch_number')
              .inFilter('id', batchIds);
          for (final b in batchRows) {
            batchMap[b['id'] as String] = b['batch_number'] as String;
          }
        } catch (_) {}
      }

      return rows.map((r) {
        final fid  = r['farmer_id'] as String;
        final info = infoMap[fid] ?? {};
        final batchId = r['inventory_batch_id'] as String?;
        return MarketLinkingModel.fromMap({
          ...r,
          'farmer_name':      info['full_name'] as String? ?? 'Farmer',
          'farmer_photo_url': info['profile_photo_url'] as String?,
          'batch_number':     batchId != null ? batchMap[batchId] : null,
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Lightweight aggregate for the Marketplace Dashboard's Market Linking
  /// KPI tile and priority alert — selects only status + farmer_id (no
  /// full row hydration) and tallies client-side. farmer_id is included
  /// so the dashboard's "Market Linking" tile can show enrolled farmers
  /// (unique) rather than total rows — the Dashboard tile had the exact
  /// same total-vs-enrolled conflation the screen's own KPI strip did
  /// before it was fixed (M-11, M-marketplace-6/M-marketplace-8).
  ///
  /// 'requested' rows (farmer-submitted, not yet admin-approved — see
  /// supabase_schema_market_linking_farmer_requests.sql) are excluded from
  /// every count here, same as the Market Linking screen's own KPI strip
  /// (_nonRequestedEntries) — a farmer who only has a pending request
  /// isn't actually enrolled yet, and counting them as one would silently
  /// inflate this tile the moment farmer-initiated requests existed.
  Future<MarketLinkingSummaryStats> fetchSummaryStats() async {
    try {
      final rows = await _client
          .from('market_linking_programs')
          .select('status, farmer_id')
          .neq('status', 'requested');

      int submitted = 0;
      final farmerIds = <String>{};
      for (final r in rows) {
        final status = r['status'] as String?;
        if (status == 'submitted') submitted++;
        final farmerId = r['farmer_id'] as String?;
        if (farmerId != null) farmerIds.add(farmerId);
      }
      return MarketLinkingSummaryStats(
        total: rows.length,
        submitted: submitted,
        enrolledFarmers: farmerIds.length,
      );
    } catch (_) {
      return MarketLinkingSummaryStats.empty;
    }
  }

  // Replaces fetchUnenrolledGingerFarmers() — that method collapsed two
  // different situations into the same empty list: "every Ginger farmer is
  // already enrolled" and "no farmer has Ginger registered at all" produced
  // identical output, so the UI couldn't tell them apart and always showed
  // the same (sometimes wrong) message.
  // crop_master's da_amad_market classification now identifies Ginger
  // growers, replacing the previous crop_name ILIKE '%ginger%' match — more
  // robust (survives a variety-qualified name) and consistent with the
  // same classification that already drives Ginger's exclusion from the
  // Marketplace and Offer to Cooperative. Multi-step lookup (crop_master ->
  // farmer_crops) rather than a nested PostgREST embed, matching this
  // codebase's established resolution pattern (see
  // harvest_entry_repository.dart's is_coop_eligible lookup).
  Future<List<String>> _daAmadCropMasterIds() async {
    final rows = await _client
        .from('crop_master')
        .select('id')
        .eq('crop_type', 'da_amad_market');
    return rows.map((r) => r['id'] as String).toList();
  }

  // fetchEnrollmentCandidates() / enrollFarmer() removed — Market Linking
  // no longer offers an admin-direct "Enroll Farmer" action. Enrollment
  // (see the DA-AMAD Enrollment section below) is now the one gate a
  // farmer passes through, via their own request, reviewed by Admin —
  // never created directly against an arbitrary farmer. Submitting an
  // actual Ginger harvest for sale (submitGingerForSale() below) then
  // requires that enrollment to already be approved.

  /// Buyer Found and Cancelled stay a plain update — no inventory
  /// implication either way, per the approved design. Completed branches:
  /// with a batch (newly attached this call, or already attached earlier)
  /// it goes through complete_market_linking so the deduction is validated
  /// and atomic; without one, it's the same plain update as any other
  /// status change.
  Future<void> updateStatus({
    required String id,
    required MarketLinkingStatus newStatus,
    String? buyerName,
    String? buyerContact,
    double? pricePerKg,
    double? requestedVolumeKg,
    String? notes,
    String? inventoryBatchId,
    double? confirmedVolumeKg,
  }) async {
    if (newStatus == MarketLinkingStatus.completed) {
      await _client.rpc(
        'complete_market_linking',
        params: {
        'p_id': id,
        if (inventoryBatchId != null) 'p_batch_id': inventoryBatchId,
          if (confirmedVolumeKg != null)
            'p_confirmed_volume_kg': confirmedVolumeKg,
        if (buyerName != null) 'p_buyer_name': buyerName,
        if (buyerContact != null) 'p_buyer_contact': buyerContact,
        if (pricePerKg != null) 'p_price_per_kg': pricePerKg,
        if (notes != null) 'p_notes': notes,
        },
      );
      AdminActivityRepository().log(
        module: 'market_linking',
        actionType: 'completed',
        description: 'Completed a market linking round.',
        referenceId: id,
      );
      return;
    }

    final now = DateTime.now().toIso8601String();
    await _client
        .from('market_linking_programs')
        .update({
      'status':        newStatus.value,
      if (buyerName != null) 'buyer_name': buyerName,
      if (buyerContact != null) 'buyer_contact': buyerContact,
      if (pricePerKg != null) 'price_per_kg': pricePerKg,
          if (requestedVolumeKg != null)
            'requested_volume_kg': requestedVolumeKg,
      if (notes != null) 'notes': notes,
      if (newStatus == MarketLinkingStatus.buyerFound)
        'buyer_found_at': now,
        })
        .eq('id', id);
    AdminActivityRepository().log(
      module: 'market_linking',
      actionType: newStatus.value,
      description: 'Updated a market linking status to "${newStatus.value}".',
      referenceId: id,
    );
  }

  // startNewRound() removed — it inserted a fresh enrollment directly at
  // status='submitted', the same admin-direct bypass as enrollFarmer()
  // above. A farmer sells another batch of ginger the same way as their
  // first round: Submit to Sell -> 'requested' -> Approve/Decline. The
  // prior round's row is untouched either way (never mutated), so its
  // history is preserved regardless of which path creates the next one.

  /// Permanently removes a cancelled entry so cancelled records don't
  /// accumulate indefinitely. The `.eq('status', 'cancelled')` is a
  /// query-level guard, same convention as AdminOrderRepository.approveOrder's
  /// `.eq('status', 'pending')` — the delete simply matches zero rows (and
  /// is a safe no-op) if the entry isn't actually cancelled. Active/
  /// completed records are never deletable this way.
  Future<void> deleteEntry(String id) async {
    await _client
        .from('market_linking_programs')
        .delete()
        .eq('id', id)
        .eq('status', 'cancelled');
    AdminActivityRepository().log(
      module: 'market_linking',
      actionType: 'deleted',
      description: 'Deleted a cancelled market linking entry.',
      referenceId: id,
    );
  }

  /// Attaches (or clears) a batch link independently of a status change —
  /// callable while still Submitted or Buyer Found. Not usable once
  /// Completed; the sheet enforces that by not showing this control then.
  Future<void> attachBatch({
    required String id,
    required String? batchId,
  }) async {
    await _client
        .from('market_linking_programs')
        .update({'inventory_batch_id': batchId})
        .eq('id', id);
    AdminActivityRepository().log(
      module: 'market_linking',
      actionType: 'batch_attached',
      description: 'Updated the linked batch on a market linking entry.',
      referenceId: id,
    );
  }

  /// Any Ginger (da_amad_market-classified) batch belonging to this farmer
  /// with stock left — no is_coop_eligible-style gating, per the approved
  /// decision. Resolves via crop_master -> farmer_crops -> inventory_batches
  /// rather than a crop-name match, same reasoning as
  /// fetchEnrollmentCandidates() above.
  Future<List<Map<String, dynamic>>> fetchEligibleBatches(
    String farmerId,
  ) async {
    try {
      final daAmadCropIds = await _daAmadCropMasterIds();
      if (daAmadCropIds.isEmpty) return [];

      final farmerCropRows = await _client
          .from('farmer_crops')
          .select('id')
          .eq('farmer_id', farmerId)
          .inFilter('crop_master_id', daAmadCropIds);
      final farmerCropIds = farmerCropRows
          .map((r) => r['id'] as String)
          .toList();
      if (farmerCropIds.isEmpty) return [];

      final rows = await _client
          .from('inventory_batches')
          .select('id, batch_number, available_kg')
          .eq('farmer_id', farmerId)
          .inFilter('crop_id', farmerCropIds)
          .gt('available_kg', 0)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }

  // ─── Farmer submits a Ginger harvest for sale ──────────────────────────
  // Requires an approved DA-AMAD Enrollment (see the Enrollment section
  // below) — that's now the one gate a farmer passes through, once, not
  // per-harvest. Routed through submit_ginger_for_sale() (SECURITY
  // DEFINER), which checks the enrollment and batch ownership server-side
  // and inserts directly at status='submitted'. The old 'requested' ->
  // Approve/Decline path this used to go through (respondToRequest()
  // below, now unused from here) is retired for this call site.

  /// Farmer submits a specific Ginger batch for sale. Requires an approved
  /// enrollment; throws if not enrolled or the batch isn't theirs.
  Future<void> submitGingerForSale({
    required String inventoryBatchId,
    required double volumeKg,
  }) async {
    await _client.rpc(
      'submit_ginger_for_sale',
      params: {
        'p_inventory_batch_id': inventoryBatchId,
        'p_volume_kg': volumeKg,
      },
    );
  }

  // respondToRequest() removed — the per-harvest 'requested' ->
  // Approve/Decline gate it powered is retired (see the note above
  // submitGingerForSale()). The server-side respond_to_market_linking_
  // request() RPC is left in place, unreferenced, same precedent as
  // every other retired code path in this project.

  /// Batch ids the current farmer has already tied to a still-active
  /// (not completed/cancelled) Market Linking submission — used by Manage
  /// Inventory to show "See Progress" instead of "Submit to Sell" on a
  /// Ginger batch that already has one in flight, so a farmer can't
  /// accidentally submit the same batch twice.
  Future<Set<String>> fetchMyActiveSubmissionBatchIds() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return {};
      // 'requested' dropped from this list — nothing creates a row at
      // that status anymore (see submitGingerForSale() above), so it
      // could never match; kept the list otherwise unchanged in case any
      // pre-Enrollment row is still sitting at 'requested' somewhere, it
      // simply won't count as "active" here, which is correct — it was
      // never actionable without Enrollment either.
      final rows = await _client
          .from('market_linking_programs')
          .select('inventory_batch_id')
          .eq('farmer_id', uid)
          .not('inventory_batch_id', 'is', null)
          .inFilter('status', ['submitted', 'buyer_found']);
      return rows.map((r) => r['inventory_batch_id'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Count of the farmer's own harvest submissions (market_linking_programs
  /// rows) — distinct from Enrollment below. Renamed from
  /// fetchMyEnrollmentCount() now that "enrollment" means something more
  /// specific; this is really "how many Ginger sales has this farmer ever
  /// submitted."
  Future<int> fetchMySubmissionCount() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return 0;
      final rows = await _client
          .from('market_linking_programs')
          .select('id')
          .eq('farmer_id', uid);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  // ─── DA-AMAD Enrollment ─────────────────────────────────────────────────

  /// Whether the current farmer has a Ginger crop in their Crop Roster —
  /// the one prerequisite for enrolling. Same crop_type resolution
  /// _daAmadCropMasterIds() already uses elsewhere in this repository.
  /// Only true once approved (crop_master_id set) — a still-pending
  /// request doesn't count here; see fetchHasPendingGingerRequest() for
  /// that distinction, which MyMarketLinkingScreen needs so it doesn't
  /// tell a farmer to "add Ginger" when they already have, and are just
  /// waiting on Admin's crop approval.
  Future<bool> fetchHasGingerCrop() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return false;
      final daAmadCropIds = await _daAmadCropMasterIds();
      if (daAmadCropIds.isEmpty) return false;
      final rows = await _client
          .from('farmer_crops')
          .select('id')
          .eq('farmer_id', uid)
          .inFilter('crop_master_id', daAmadCropIds)
          .limit(1);
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Whether the farmer has a Ginger crop request awaiting Admin's
  /// approval right now — distinct from having none at all (rejected
  /// requests don't count; the farmer would resubmit a new crop request
  /// through Crop Roster the normal way, same as any other crop).
  Future<bool> fetchHasPendingGingerRequest() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return false;
      final rows = await _client
          .from('crop_requests')
          .select('id')
          .eq('farmer_id', uid)
          .eq('status', 'pending')
          .ilike('requested_name', 'Ginger')
          .limit(1);
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// The current farmer's most recent enrollment attempt, or null if
  /// they've never submitted one. A farmer can have multiple rows over
  /// time (each rejection allows a fresh resubmission) — only the latest
  /// one matters for deciding what to show them.
  Future<DaAmadEnrollmentModel?> fetchMyEnrollment() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;
      final row = await _client
          .from('da_amad_enrollments')
          .select()
          .eq('farmer_id', uid)
          .order('submitted_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      return DaAmadEnrollmentModel(
        id: row['id'] as String,
        farmerId: row['farmer_id'] as String,
        farmerName: '',
        status: DaAmadEnrollmentStatusExt.fromString(row['status'] as String?),
        adminNotes: row['admin_notes'] as String?,
        submittedAt: DateTime.parse(row['submitted_at'] as String),
        reviewedAt: row['reviewed_at'] != null
            ? DateTime.parse(row['reviewed_at'] as String)
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Submits (or resubmits, after a rejection) a DA-AMAD enrollment
  /// request. Routed through submit_da_amad_enrollment() (SECURITY
  /// DEFINER), which enforces the Ginger-crop and no-duplicate-active-
  /// enrollment checks server-side — the client-side fetchHasGingerCrop()
  /// check above is only for showing the right screen before the farmer
  /// even tries, not the real gate.
  Future<void> submitEnrollment() async {
    await _client.rpc('submit_da_amad_enrollment');
  }

  /// Admin: enrollments awaiting review.
  Future<List<DaAmadEnrollmentModel>> fetchPendingEnrollments() =>
      _fetchEnrollmentsByStatus('pending');

  /// Admin: enrollments already reviewed (approved or rejected), most
  /// recently reviewed first.
  Future<List<DaAmadEnrollmentModel>> fetchReviewedEnrollments() async {
    final results = await Future.wait([
      _fetchEnrollmentsByStatus('approved'),
      _fetchEnrollmentsByStatus('rejected'),
    ]);
    final combined = [...results[0], ...results[1]]
      ..sort(
        (a, b) => (b.reviewedAt ?? b.submittedAt).compareTo(
          a.reviewedAt ?? a.submittedAt,
        ),
      );
    return combined;
  }

  Future<List<DaAmadEnrollmentModel>> _fetchEnrollmentsByStatus(
    String status,
  ) async {
    try {
      final rows = await _client
          .from('da_amad_enrollments')
          .select(
            'id, farmer_id, status, admin_notes, submitted_at, reviewed_at',
          )
          .eq('status', status)
          .order('submitted_at', ascending: status == 'pending');
      if (rows.isEmpty) return [];

      final farmerIds = rows
          .map((r) => r['farmer_id'] as String)
          .toSet()
          .toList();
      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', farmerIds);
      final infoMap = {for (final r in infoRows) r['user_id'] as String: r};

      return rows.map((r) {
        final info = infoMap[r['farmer_id']];
        return DaAmadEnrollmentModel(
          id: r['id'] as String,
          farmerId: r['farmer_id'] as String,
          farmerName: info?['full_name'] as String? ?? 'Farmer',
          status: DaAmadEnrollmentStatusExt.fromString(r['status'] as String?),
          adminNotes: r['admin_notes'] as String?,
          submittedAt: DateTime.parse(r['submitted_at'] as String),
          reviewedAt: r['reviewed_at'] != null
              ? DateTime.parse(r['reviewed_at'] as String)
              : null,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Admin approves or declines a farmer's enrollment. Routed through
  /// respond_to_da_amad_enrollment() (SECURITY DEFINER) — notifying the
  /// farmer of the outcome requires writing to another user's
  /// notifications row, which no plain admin-session policy allows.
  Future<bool> respondToEnrollment({
    required String id,
    required bool approve,
    String? notes,
  }) async {
    try {
      await _client.rpc(
        'respond_to_da_amad_enrollment',
        params: {
          'p_enrollment_id': id,
          'p_approve': approve,
          if (notes != null && notes.isNotEmpty) 'p_notes': notes,
        },
      );
      AdminActivityRepository().log(
        module: 'market_linking',
        actionType: approve ? 'approved' : 'rejected',
        description: approve
            ? 'Approved a farmer\'s DA-AMAD Market Linking enrollment.'
            : 'Declined a farmer\'s DA-AMAD Market Linking enrollment.',
        referenceId: id,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}