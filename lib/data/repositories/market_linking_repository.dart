import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Market Linking Status ─────────────────────────────────────────────────────

enum MarketLinkingStatus {
  submitted,
  buyerFound,
  completed,
  cancelled,
}

extension MarketLinkingStatusExt on MarketLinkingStatus {
  String get value {
    switch (this) {
      case MarketLinkingStatus.submitted:  return 'submitted';
      case MarketLinkingStatus.buyerFound: return 'buyer_found';
      case MarketLinkingStatus.completed:  return 'completed';
      case MarketLinkingStatus.cancelled:  return 'cancelled';
    }
  }

  String get label {
    switch (this) {
      case MarketLinkingStatus.submitted:  return 'Submitted';
      case MarketLinkingStatus.buyerFound: return 'Buyer Found';
      case MarketLinkingStatus.completed:  return 'Completed';
      case MarketLinkingStatus.cancelled:  return 'Cancelled';
    }
  }

  static MarketLinkingStatus fromString(String? v) {
    switch (v) {
      case 'buyer_found': return MarketLinkingStatus.buyerFound;
      case 'completed':   return MarketLinkingStatus.completed;
      case 'cancelled':   return MarketLinkingStatus.cancelled;
      default:            return MarketLinkingStatus.submitted;
    }
  }
}

// ─── Market Linking Model ──────────────────────────────────────────────────────

class MarketLinkingModel {
  final String id;
  final String farmerId;
  final String farmerName;
  final String? farmerPhotoUrl;
  final String? purok;
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

  const MarketLinkingModel({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    this.farmerPhotoUrl,
    this.purok,
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
  });

  bool get isActive =>
      status == MarketLinkingStatus.submitted ||
      status == MarketLinkingStatus.buyerFound;

  double? get totalValue =>
      volumeKg != null && pricePerKg != null
          ? volumeKg! * pricePerKg!
          : null;

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
      purok:          map['purok'] as String?,
      cropName:       map['crop_name'] as String? ?? 'Ginger',
      seasonYear:     map['season_year'] as int? ?? DateTime.now().year,
      status:         MarketLinkingStatusExt.fromString(
                          map['status'] as String?),
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

  static const empty = MarketLinkingSummaryStats(total: 0, submitted: 0, enrolledFarmers: 0);
}

// ─── Repository ────────────────────────────────────────────────────────────────

class MarketLinkingRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<MarketLinkingModel>> fetchAll({
    String? statusFilter,
  }) async {
    try {
      var query = _client
          .from('market_linking_programs')
          .select('*, farmer_id');

      if (statusFilter != null) {
        query = query.eq('status', statusFilter);
      }

      final rows = await query.order('submitted_at', ascending: false);
      if (rows.isEmpty) return [];

      final farmerIds = rows.map((r) => r['farmer_id'] as String).toSet().toList();

      // Fetch farmer info
      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name, purok, profile_photo_url')
          .inFilter('user_id', farmerIds);
      final infoMap = {
        for (final r in infoRows) r['user_id'] as String: r,
      };

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
          'purok':            info['purok'] as String?,
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
  Future<MarketLinkingSummaryStats> fetchSummaryStats() async {
    try {
      final rows = await _client
          .from('market_linking_programs')
          .select('status, farmer_id');

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

  Future<Map<String, dynamic>> fetchEnrollmentCandidates() async {
    try {
      final year = DateTime.now().year;

      final enrolled = await _client
          .from('market_linking_programs')
          .select('farmer_id')
          .eq('season_year', year)
          .neq('status', 'cancelled');
      final enrolledIds = enrolled.map((r) => r['farmer_id'] as String).toSet();

      final daAmadCropIds = await _daAmadCropMasterIds();
      Set<String> allGingerFarmerIds = {};
      if (daAmadCropIds.isNotEmpty) {
        final gingerRows = await _client
            .from('farmer_crops')
            .select('farmer_id')
            .inFilter('crop_master_id', daAmadCropIds);
        allGingerFarmerIds = gingerRows.map((r) => r['farmer_id'] as String).toSet();
      }

      final unenrolledIds =
          allGingerFarmerIds.difference(enrolledIds).toList();

      List<Map<String, dynamic>> unenrolled = [];
      if (unenrolledIds.isNotEmpty) {
        final infoRows = await _client
            .from('user_information')
            .select('user_id, full_name, purok')
            .inFilter('user_id', unenrolledIds)
            .order('full_name', ascending: true);
        unenrolled = infoRows
            .map((r) => {
                  'id': r['user_id'] as String,
                  'name': r['full_name'] as String? ?? 'Farmer',
                  'purok': r['purok'] as String?,
                })
            .toList();
      }

      return {
        'totalGingerFarmers': allGingerFarmerIds.length,
        'unenrolled': unenrolled,
      };
    } catch (_) {
      return {'totalGingerFarmers': 0, 'unenrolled': <Map<String, dynamic>>[]};
    }
  }

  Future<void> enrollFarmer({
    required String farmerId,
    required double? volumeKg,
  }) async {
    final adminId = _client.auth.currentUser?.id;
    await _client.from('market_linking_programs').insert({
      'farmer_id':   farmerId,
      'crop_name':   'Ginger',
      'season_year': DateTime.now().year,
      'status':      'submitted',
      if (volumeKg != null) 'volume_kg': volumeKg,
      'created_by':  adminId,
      'submitted_at': DateTime.now().toIso8601String(),
    });
  }

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
      await _client.rpc('complete_market_linking', params: {
        'p_id': id,
        if (inventoryBatchId != null) 'p_batch_id': inventoryBatchId,
        if (confirmedVolumeKg != null) 'p_confirmed_volume_kg': confirmedVolumeKg,
        if (buyerName != null) 'p_buyer_name': buyerName,
        if (buyerContact != null) 'p_buyer_contact': buyerContact,
        if (pricePerKg != null) 'p_price_per_kg': pricePerKg,
        if (notes != null) 'p_notes': notes,
      });
      return;
    }

    final now = DateTime.now().toIso8601String();
    await _client.from('market_linking_programs').update({
      'status':        newStatus.value,
      if (buyerName != null) 'buyer_name': buyerName,
      if (buyerContact != null) 'buyer_contact': buyerContact,
      if (pricePerKg != null) 'price_per_kg': pricePerKg,
      if (requestedVolumeKg != null) 'requested_volume_kg': requestedVolumeKg,
      if (notes != null) 'notes': notes,
      if (newStatus == MarketLinkingStatus.buyerFound)
        'buyer_found_at': now,
    }).eq('id', id);
  }

  /// Creates a fresh enrollment for the same farmer after a prior round
  /// reached Completed or Cancelled — rather than mutating the terminal
  /// row, which would erase its history. Lets a farmer sell another batch
  /// of ginger, and the admin find another buyer for it, without losing
  /// the record of the previous round. See "Start New Round" design.
  Future<void> startNewRound({required String farmerId}) async {
    final adminId = _client.auth.currentUser?.id;
    await _client.from('market_linking_programs').insert({
      'farmer_id':    farmerId,
      'crop_name':    'Ginger',
      'season_year':  DateTime.now().year,
      'status':       'submitted',
      'created_by':   adminId,
      'submitted_at': DateTime.now().toIso8601String(),
    });
  }

  /// Permanently removes a cancelled entry so cancelled records don't
  /// accumulate indefinitely. The `.eq('status', 'cancelled')` is a
  /// query-level guard, same convention as AdminOrderRepository.approveOrder's
  /// `.eq('status', 'pending')` — the delete simply matches zero rows (and
  /// is a safe no-op) if the entry isn't actually cancelled, e.g. a race
  /// with Start New Round. Active/completed records are never deletable
  /// this way.
  Future<void> deleteEntry(String id) async {
    await _client
        .from('market_linking_programs')
        .delete()
        .eq('id', id)
        .eq('status', 'cancelled');
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
  }

  /// Any Ginger (da_amad_market-classified) batch belonging to this farmer
  /// with stock left — no is_coop_eligible-style gating, per the approved
  /// decision. Resolves via crop_master -> farmer_crops -> inventory_batches
  /// rather than a crop-name match, same reasoning as
  /// fetchEnrollmentCandidates() above.
  Future<List<Map<String, dynamic>>> fetchEligibleBatches(String farmerId) async {
    try {
      final daAmadCropIds = await _daAmadCropMasterIds();
      if (daAmadCropIds.isEmpty) return [];

      final farmerCropRows = await _client
          .from('farmer_crops')
          .select('id')
          .eq('farmer_id', farmerId)
          .inFilter('crop_master_id', daAmadCropIds);
      final farmerCropIds = farmerCropRows.map((r) => r['id'] as String).toList();
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

  /// Used by FarmerProfileScreen to decide whether "My Market Linking"
  /// should even appear — most farmers will never have a row here.
  Future<int> fetchMyEnrollmentCount() async {
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
}