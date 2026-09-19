import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_activity_repository.dart';
import 'crop_lookup.dart';

// ─── Admin Listing Model ──────────────────────────────────────────────────────
// Extends the farmer-side MarketplaceListingModel with admin-only fields.

class AdminListingModel {
  final String id;
  final String farmerId;
  final String farmerName;
  final String? farmerPhotoUrl;
  final String cropName;
  final String? variety;
  final double volumeKg;
  final double remainingKg;
  final double pricePerKg;
  final String status; // pending_review | approved | changes_required | sold
  final String? adminNotes;
  final String? batchId;
  final double? batchAvailableKg; // from inventory_batches
  final double? marketRefPricePerKg; // from price_records
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? listingPhotoUrl;

  // Farmer context (from joined queries)
  final int farmerTotalSubmissions;
  final int farmerApprovedCount;
  final int farmerRejectedCount;
  final double farmerOutstandingLoan;

  // Canonical crop_master.crop_name, resolved via crop_id — see
  // AdminListingRepository's fetch methods. Falls back to cropName when
  // the crop_id didn't resolve (e.g. a very old row predating the
  // crop_id migration).
  final String? canonicalCropName;

  const AdminListingModel({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    this.farmerPhotoUrl,
    required this.cropName,
    this.variety,
    required this.volumeKg,
    required this.remainingKg,
    required this.pricePerKg,
    required this.status,
    this.adminNotes,
    this.batchId,
    this.batchAvailableKg,
    this.marketRefPricePerKg,
    required this.createdAt,
    this.updatedAt,
    this.listingPhotoUrl,
    this.farmerTotalSubmissions = 0,
    this.farmerApprovedCount = 0,
    this.farmerRejectedCount = 0,
    this.farmerOutstandingLoan = 0,
    this.canonicalCropName,
  });

  // ── Computed helpers ──────────────────────────────────────────────────────

  bool get isPending => status == 'pending_review';
  bool get isApproved => status == 'approved';
  bool get needsChanges => status == 'changes_required';
  bool get isSold => status == 'sold';
  bool get isRejected => status == 'rejected';

  /// Matches MarketplaceListingModel.displayName — crop + variety when present.
  String get displayName {
    final name = canonicalCropName ?? cropName;
    final v = variety?.trim();
    if (v == null || v.isEmpty) return name;
    if (name.toLowerCase().contains(v.toLowerCase())) return name;
    return '$name ($v)';
  }

  /// The admin query orders by created_at (no submitted_at column in the
  /// select). Exposing this as submittedAt keeps the screen compatible with
  /// the same pattern used on MarketplaceListingModel (submittedAt ?? createdAt).
  DateTime get submittedAt => createdAt;

  String get statusLabel {
    switch (status) {
      case 'pending_review':
        return 'Pending';
      case 'approved':
        return 'Live';
      case 'changes_required':
        return 'Changes Required';
      case 'sold':
        return 'Sold';
      case 'rejected':
        return 'Rejected';
      default:
        return status;
    }
  }

  double get totalValue => volumeKg * pricePerKg;

  /// Whether listing qty exceeds available batch stock
  bool get hasStockWarning =>
      batchAvailableKg != null && volumeKg > batchAvailableKg!;

  double get stockSurplus =>
      batchAvailableKg != null ? volumeKg - batchAvailableKg! : 0;

  /// Price vs market reference comparison
  double? get priceDiffVsMarket =>
      marketRefPricePerKg != null ? pricePerKg - marketRefPricePerKg! : null;

  double? get priceDiffPercent =>
      marketRefPricePerKg != null && marketRefPricePerKg! > 0
      ? ((pricePerKg - marketRefPricePerKg!) / marketRefPricePerKg!) * 100
      : null;

  bool get isPriceWithinMarketRange {
    final pct = priceDiffPercent;
    if (pct == null) return true; // no market ref — can't judge
    return pct.abs() <= 20.0; // within ±20% of DA market ref
  }

  int get farmerApprovalRate => farmerTotalSubmissions > 0
      ? ((farmerApprovedCount / farmerTotalSubmissions) * 100).round()
      : 0;

  String get submittedLabel {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${m[createdAt.month - 1]} ${createdAt.day}';
  }

  factory AdminListingModel.fromMap(Map<String, dynamic> map) {
    return AdminListingModel(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      farmerName: map['farmer_name'] as String? ?? 'Farmer',
      farmerPhotoUrl: map['farmer_photo_url'] as String?,
      cropName: map['crop_name'] as String,
      variety: map['variety'] as String?,
      volumeKg: (map['volume_kg'] as num).toDouble(),
      // remaining_kg is the single source of truth for buyer-order
      // availability (see supabase_schema_marketplace_order_reservation_fix.sql).
      // Falls back to volume_kg if not selected/backfilled yet.
      remainingKg: (map['remaining_kg'] as num?)?.toDouble() ??
          (map['volume_kg'] as num).toDouble(),
      pricePerKg: (map['price_per_kg'] as num).toDouble(),
      status: map['status'] as String? ?? 'pending_review',
      adminNotes: map['admin_notes'] as String?,
      batchId: map['batch_id'] as String?,
      batchAvailableKg: map['batch_available_kg'] != null
          ? (map['batch_available_kg'] as num).toDouble()
          : null,
      marketRefPricePerKg: map['market_ref_price'] != null
          ? (map['market_ref_price'] as num).toDouble()
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      listingPhotoUrl: map['listing_photo_url'] as String?,
      farmerTotalSubmissions: map['farmer_total_submissions'] as int? ?? 0,
      farmerApprovedCount: map['farmer_approved_count'] as int? ?? 0,
      farmerRejectedCount: map['farmer_rejected_count'] as int? ?? 0,
      farmerOutstandingLoan: (map['farmer_outstanding_loan'] as num? ?? 0)
          .toDouble(),
      canonicalCropName: map['canonical_crop_name'] as String?,
    );
  }
}

// ─── Listing Summary Stats ────────────────────────────────────────────────────

class ListingSummaryStats {
  final int total;
  final int pending;
  final int approved;
  final int changesRequired;
  final int sold;
  final int rejected;

  const ListingSummaryStats({
    required this.total,
    required this.pending,
    required this.approved,
    required this.changesRequired,
    required this.sold,
    required this.rejected,
  });

  static const empty = ListingSummaryStats(
    total: 0,
    pending: 0,
    approved: 0,
    changesRequired: 0,
    sold: 0,
    rejected: 0,
  );
}

// ─── Admin Listing Repository ─────────────────────────────────────────────────

class AdminListingRepository {
  final SupabaseClient _client = Supabase.instance.client;

  static const List<String> cropCategories = [
    'Grain', 'Legume', 'Root & Spice Crop', 'Fruit', 'Tree Crop', 'Vegetable', 'Other',
  ];

  Future<List<String>> fetchCropsByCategory({String? category}) async {
    try {
      var query = _client
          .from('crop_master')
          .select('crop_name')
          .eq('is_active', true);
      if (category != null) {
        query = query.eq('category', category);
      }
      final rows = await query.order('crop_name');
      return rows.map((r) => r['crop_name'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<AdminListingModel>> fetchPendingListings() async {
    return _fetchListings(statusFilter: 'pending_review');
  }

  Future<List<AdminListingModel>> fetchAllListings({
    String? statusFilter,
    String? searchQuery,
    String? cropFilter,
    String? categoryFilter,
  }) async {
    return _fetchListings(
      statusFilter: statusFilter,
      searchQuery: searchQuery,
      cropFilter: cropFilter,
      categoryFilter: categoryFilter,
    );
  }

  /// Pending Review now browses review *outcomes* (pending/approved/rejected),
  /// not just the open queue — a scoped fetch rather than reusing
  /// fetchAllListings, so this screen never accidentally shows
  /// changes_required/sold/withdrawn listings that belong to All Listings.
  Future<List<AdminListingModel>> fetchReviewListings({
    String? statusFilter, // null = pending_review + approved + rejected combined
    String? searchQuery,
    String? cropFilter,
    String? categoryFilter,
  }) async {
    if (statusFilter != null) {
      return _fetchListings(
        statusFilter: statusFilter,
        searchQuery: searchQuery,
        cropFilter: cropFilter,
        categoryFilter: categoryFilter,
      );
    }
    final all = await _fetchListings(
      searchQuery: searchQuery,
      cropFilter: cropFilter,
      categoryFilter: categoryFilter,
    );
    return all.where((l) => l.isPending || l.isApproved || l.isRejected).toList();
  }

  Future<List<AdminListingModel>> _fetchListings({
    String? statusFilter,
    String? searchQuery,
    String? cropFilter,
    String? categoryFilter,
    int? limit,
  }) async {
    try {
      var query = _client
          .from('marketplace_listings')
          .select(
            'id, farmer_id, crop_name, crop_id, variety, volume_kg, remaining_kg, price_per_kg, '
            'status, admin_notes, inventory_batch_id, photo_url, created_at, updated_at',
          );

      if (statusFilter != null) {
        query = query.eq('status', statusFilter);
      } else {
        // Withdrawn is a farmer housekeeping action, not something admin
        // reviews or acts on — excluded whenever no specific status was
        // asked for (the "All" chip), so All = Pending + Live + Changes +
        // Sold + Rejected always holds without a 7th chip nobody needs.
        query = query.neq('status', 'withdrawn');
      }
      if (cropFilter != null) {
        // Crops now comes from a crop_master-backed picker rather than
        // free-text search, so exact match is correct — .ilike substring
        // matching was only ever a workaround for a text field with no picker.
        query = query.eq('crop_name', cropFilter);
      }
      if (categoryFilter != null) {
        final namesInCategory = await fetchCropsByCategory(category: categoryFilter);
        if (namesInCategory.isEmpty) return [];
        query = query.inFilter('crop_name', namesInCategory);
      }

      final ordered = query.order('created_at', ascending: false);
      final rows = limit != null ? await ordered.limit(limit) : await ordered;

      if (rows.isEmpty) return [];

      final farmerIds = rows
          .map((r) => r['farmer_id'] as String)
          .toSet()
          .toList();
      final batchIds = rows
          .where((r) => r['inventory_batch_id'] != null)
          .map((r) => r['inventory_batch_id'] as String)
          .toSet()
          .toList();
      final cropNames = rows
          .map((r) => r['crop_name'] as String)
          .toSet()
          .toList();
      final cropIds = rows
          .map((r) => r['crop_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final canonicalCropNames = await fetchCropNameMap(_client, cropIds);

      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name, profile_photo_url')
          .inFilter('user_id', farmerIds);
      final infoMap = {for (final r in infoRows) r['user_id'] as String: r};

      final batchMap = <String, double>{};
      if (batchIds.isNotEmpty) {
        final batchRows = await _client
            .from('inventory_batches')
            .select('id, available_kg')
            .inFilter('id', batchIds);
        for (final r in batchRows) {
          batchMap[r['id'] as String] = (r['available_kg'] as num).toDouble();
        }
      }

      final priceMap = <String, double>{};
      try {
        final priceRows = await _client
            .from('price_records')
            .select('crop_name, price')
            .inFilter('crop_name', cropNames)
            .order('recorded_at', ascending: false);
        for (final r in priceRows) {
          final cn = r['crop_name'] as String;
          priceMap.putIfAbsent(cn, () => (r['price'] as num).toDouble());
        }
      } catch (_) {}

      final historyRows = await _client
          .from('marketplace_listings')
          .select('farmer_id, status')
          .inFilter('farmer_id', farmerIds);
      final historyMap = <String, Map<String, int>>{};
      for (final r in historyRows) {
        final fid = r['farmer_id'] as String;
        final stat = r['status'] as String;
        historyMap.putIfAbsent(
          fid,
          () => {'total': 0, 'approved': 0, 'rejected': 0},
        );
        historyMap[fid]!['total'] = (historyMap[fid]!['total'] ?? 0) + 1;
        if (stat == 'approved') {
          historyMap[fid]!['approved'] =
              (historyMap[fid]!['approved'] ?? 0) + 1;
        }
        if (stat == 'rejected') {
          historyMap[fid]!['rejected'] =
              (historyMap[fid]!['rejected'] ?? 0) + 1;
        }
      }

      final loanMap = <String, double>{};
      try {
        final loanRows = await _client
            .from('farmer_loans')
            .select('farmer_id, total_value, amount_paid')
            .inFilter('farmer_id', farmerIds)
            .neq('status', 'paid');
        for (final r in loanRows) {
          final fid = r['farmer_id'] as String;
          final rem =
              ((r['total_value'] as num).toDouble() -
                      (r['amount_paid'] as num? ?? 0).toDouble())
                  .clamp(0.0, double.infinity);
          loanMap[fid] = (loanMap[fid] ?? 0) + rem;
        }
      } catch (_) {}

      var result = rows.map((r) {
        final fid = r['farmer_id'] as String;
        final info = infoMap[fid] ?? {};
        final batchId = r['inventory_batch_id'] as String?;
        final history = historyMap[fid] ?? {};
        final cn = r['crop_name'] as String;
        final cropId = r['crop_id'] as String?;

        return AdminListingModel.fromMap({
          ...r,
          'farmer_name': info['full_name'] as String? ?? 'Farmer',
          'farmer_photo_url': info['profile_photo_url'] as String?,
          'listing_photo_url': r['photo_url'],
          'batch_id': r['inventory_batch_id'],
          'batch_available_kg': batchId != null ? batchMap[batchId] : null,
          'market_ref_price': priceMap[cn],
          'canonical_crop_name': cropId != null ? canonicalCropNames[cropId] : null,
          'farmer_total_submissions': history['total'] ?? 0,
          'farmer_approved_count': history['approved'] ?? 0,
          'farmer_rejected_count': history['rejected'] ?? 0,
          'farmer_outstanding_loan': loanMap[fid] ?? 0.0,
        });
      }).toList();

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        result = result
            .where(
              (l) =>
                  l.cropName.toLowerCase().contains(q) ||
                  l.farmerName.toLowerCase().contains(q) ||
                  (l.variety?.toLowerCase().contains(q) ?? false),
            )
            .toList();
      }

      return result;
    } catch (_) {
      return [];
    }
  }

  Future<ListingSummaryStats> fetchSummaryStats() async {
    try {
      final rows = await _client
          .from('marketplace_listings')
          .select('status')
          .neq('status', 'withdrawn');

      int pending = 0, approved = 0, changes = 0, sold = 0, rejected = 0;
      for (final r in rows) {
        switch (r['status'] as String?) {
          case 'pending_review':
            pending++;
            break;
          case 'approved':
            approved++;
            break;
          case 'changes_required':
            changes++;
            break;
          case 'sold':
            sold++;
            break;
          case 'rejected':
            rejected++;
            break;
        }
      }
      return ListingSummaryStats(
        total: rows.length,
        pending: pending,
        approved: approved,
        changesRequired: changes,
        sold: sold,
        rejected: rejected,
      );
    } catch (_) {
      return ListingSummaryStats.empty;
    }
  }

  Future<List<String>> fetchActiveCropNames() async {
    try {
      final rows = await _client
          .from('crop_master')
          .select('crop_name')
          .eq('is_active', true)
          .order('crop_name');
      return rows.map((r) => r['crop_name'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> approveListing(String listingId) async {
    await _client.rpc('approve_listing', params: {'p_listing_id': listingId});
  }

  /// "Changes Required" is not terminal — the listing stays alive and the
  /// farmer is expected to edit and resubmit the same listing. The batch
  /// reservation from create_listing_with_reservation() is intentionally
  /// left in place here: releasing it would leave the stock unprotected
  /// between "changes requested" and the farmer's resubmission, letting
  /// another listing claim it out from under them.
  Future<void> requestChanges({
    required String listingId,
    required String notes,
  }) async {
    await _client.rpc('request_listing_changes', params: {
      'p_listing_id': listingId,
      'p_notes': notes.trim(),
    });
  }

  Future<AdminListingModel?> fetchListingById(String listingId) async {
    try {
      final row = await _client
          .from('marketplace_listings')
          .select(
            'id, farmer_id, crop_name, variety, volume_kg, remaining_kg, price_per_kg, '
            'status, admin_notes, inventory_batch_id, photo_url, created_at, updated_at',
          )
          .eq('id', listingId)
          .maybeSingle();

      if (row == null) return null;

      final farmerId = row['farmer_id'] as String;
      final cn = row['crop_name'] as String;
      final batchId = row['inventory_batch_id'] as String?;

      String farmerName = 'Farmer';
      String? farmerPhoto;
      try {
        final info = await _client
            .from('user_information')
            .select('full_name, profile_photo_url')
            .eq('user_id', farmerId)
            .maybeSingle();
        farmerName = info?['full_name'] as String? ?? 'Farmer';
        farmerPhoto = info?['profile_photo_url'] as String?;
      } catch (_) {}

      double? batchAvailableKg;
      if (batchId != null) {
        try {
          final batch = await _client
              .from('inventory_batches')
              .select('available_kg')
              .eq('id', batchId)
              .maybeSingle();
          batchAvailableKg = batch?['available_kg'] != null
              ? (batch!['available_kg'] as num).toDouble()
              : null;
        } catch (_) {}
      }

      double? marketRefPrice;
      try {
        final priceRow = await _client
            .from('price_records')
            .select('price')
            .ilike('crop_name', cn)
            .order('recorded_at', ascending: false)
            .limit(1)
            .maybeSingle();
        marketRefPrice = priceRow?['price'] != null
            ? (priceRow!['price'] as num).toDouble()
            : null;
      } catch (_) {}

      int totalSubs = 0, approved = 0, rejected = 0;
      try {
        final histRows = await _client
            .from('marketplace_listings')
            .select('status')
            .eq('farmer_id', farmerId);
        totalSubs = histRows.length;
        for (final r in histRows) {
          if (r['status'] == 'approved') approved++;
          if (r['status'] == 'rejected') rejected++;
        }
      } catch (_) {}

      double outstandingLoan = 0;
      try {
        final loanRows = await _client
            .from('farmer_loans')
            .select('total_value, amount_paid')
            .eq('farmer_id', farmerId)
            .neq('status', 'paid');
        for (final r in loanRows) {
          outstandingLoan +=
              ((r['total_value'] as num).toDouble() -
                      (r['amount_paid'] as num? ?? 0).toDouble())
                  .clamp(0.0, double.infinity);
        }
      } catch (_) {}

      return AdminListingModel.fromMap({
        ...row,
        'farmer_name': farmerName,
        'farmer_photo_url': farmerPhoto,
        'listing_photo_url': row['photo_url'],
        'batch_id': row['inventory_batch_id'],
        'batch_available_kg': batchAvailableKg,
        'market_ref_price': marketRefPrice,
        'farmer_total_submissions': totalSubs,
        'farmer_approved_count': approved,
        'farmer_rejected_count': rejected,
        'farmer_outstanding_loan': outstandingLoan,
      });
    } catch (_) {
      return null;
    }
  }

  /// Rejecting a listing is terminal — no resubmission is coming — so the
  /// stock reserved at listing-creation time (via
  /// create_listing_with_reservation → _apply_batch_reservation) must be
  /// released back to the farmer's available pool. That release, the admin
  /// authorization check, and the farmer notification all now live inside
  /// the reject_listing RPC (see
  /// supabase_schema_listing_rejection_release.sql) rather than being done
  /// piecemeal from the client, so this can no longer silently leave stock
  /// locked behind a dead listing.
  Future<void> rejectListing({
    required String listingId,
    required String reason,
  }) async {
    await _client.rpc('reject_listing', params: {
      'p_listing_id': listingId,
      'p_reason': reason.trim(),
    });
    AdminActivityRepository().log(
      module: 'listings',
      actionType: 'rejected',
      description: 'Rejected a marketplace listing.',
      referenceId: listingId,
    );
  }
}