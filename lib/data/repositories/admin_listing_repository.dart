import 'package:supabase_flutter/supabase_flutter.dart';

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

  const AdminListingModel({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    this.farmerPhotoUrl,
    required this.cropName,
    this.variety,
    required this.volumeKg,
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
  });

  // ── Computed helpers ──────────────────────────────────────────────────────

  bool get isPending => status == 'pending_review';
  bool get isApproved => status == 'approved';
  bool get needsChanges => status == 'changes_required';
  bool get isSold => status == 'sold';

  /// Matches MarketplaceListingModel.displayName — crop + variety when present.
  String get displayName => variety != null && variety!.isNotEmpty
      ? '$cropName ($variety)'
      : cropName;

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

  const ListingSummaryStats({
    required this.total,
    required this.pending,
    required this.approved,
    required this.changesRequired,
    required this.sold,
  });

  static const empty = ListingSummaryStats(
    total: 0,
    pending: 0,
    approved: 0,
    changesRequired: 0,
    sold: 0,
  );
}

// ─── Admin Listing Repository ─────────────────────────────────────────────────

class AdminListingRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<AdminListingModel>> fetchPendingListings() async {
    return _fetchListings(statusFilter: 'pending_review');
  }

  Future<List<AdminListingModel>> fetchAllListings({
    String? statusFilter,
    String? searchQuery,
    String? cropFilter,
  }) async {
    return _fetchListings(
      statusFilter: statusFilter,
      searchQuery: searchQuery,
      cropFilter: cropFilter,
    );
  }

  Future<List<AdminListingModel>> fetchRecentListings({int limit = 5}) async {
    return _fetchListings(limit: limit);
  }

  Future<List<AdminListingModel>> _fetchListings({
    String? statusFilter,
    String? searchQuery,
    String? cropFilter,
    int? limit,
  }) async {
    try {
      var query = _client
          .from('marketplace_listings')
          .select(
            'id, farmer_id, crop_name, variety, volume_kg, price_per_kg, '
            'status, admin_notes, inventory_batch_id, photo_url, created_at, updated_at',
          );

      if (statusFilter != null) {
        query = query.eq('status', statusFilter);
      }
      if (cropFilter != null) {
        query = query.ilike('crop_name', '%$cropFilter%');
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

        return AdminListingModel.fromMap({
          ...r,
          'farmer_name': info['full_name'] as String? ?? 'Farmer',
          'farmer_photo_url': info['profile_photo_url'] as String?,
          'listing_photo_url': r['photo_url'],
          'batch_id': r['inventory_batch_id'],
          'batch_available_kg': batchId != null ? batchMap[batchId] : null,
          'market_ref_price': priceMap[cn],
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
      final rows = await _client.from('marketplace_listings').select('status');

      int pending = 0, approved = 0, changes = 0, sold = 0;
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
        }
      }
      return ListingSummaryStats(
        total: rows.length,
        pending: pending,
        approved: approved,
        changesRequired: changes,
        sold: sold,
      );
    } catch (_) {
      return ListingSummaryStats.empty;
    }
  }

  Future<void> approveListing(String listingId) async {
    await _client
        .from('marketplace_listings')
        .update({
          'status': 'approved',
          'admin_notes': null,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', listingId);
  }

  Future<void> requestChanges({
    required String listingId,
    required String notes,
  }) async {
    await _client
        .from('marketplace_listings')
        .update({
          'status': 'changes_required',
          'admin_notes': notes.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', listingId);
  }

  Future<AdminListingModel?> fetchListingById(String listingId) async {
    try {
      final row = await _client
          .from('marketplace_listings')
          .select(
            'id, farmer_id, crop_name, variety, volume_kg, price_per_kg, '
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

  Future<void> rejectListing({
    required String listingId,
    required String reason,
  }) async {
    await _client
        .from('marketplace_listings')
        .update({
          'status': 'rejected',
          'admin_notes': reason.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', listingId);
  }
}