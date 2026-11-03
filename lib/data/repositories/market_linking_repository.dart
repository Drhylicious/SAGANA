import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/quantity_utils.dart';
import '../../core/utils/person_name.dart';
import '../../core/constants/app_constants.dart';
import '../services/offline_cache.dart';
import 'admin_activity_repository.dart';
import 'crop_lookup.dart' show fetchFarmerCropImageMap;
import '../models/admin_log_message.dart';

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

  /// When the Farmer tapped Continue on the approval congratulations. Stored on
  /// the server, so the screen stays gone on any device and after any logout.
  final DateTime? acknowledgedAt;

  // Shown on the Manager's enrollment cards only (the Farmer's own copy leaves
  // them at their defaults).
  final String? farmerPhotoUrl;

  /// Who reviewed it (name), when it has been reviewed.
  final String? reviewerName;

  /// How many Market Linking sale requests this farmer has made so far.
  final int requestCount;

  /// True for a farmer who is already in Market Linking (has requests) but has
  /// no enrollment application on record: they joined before enrollment had to
  /// be reviewed. Shown as Enrolled, with no review date.
  final bool enrolledWithoutReview;

  /// A newer application from the same farmer exists, so this one is history.
  final bool isSuperseded;

  const DaAmadEnrollmentModel({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    required this.status,
    this.adminNotes,
    required this.submittedAt,
    this.reviewedAt,
    this.acknowledgedAt,
    this.farmerPhotoUrl,
    this.reviewerName,
    this.requestCount = 0,
    this.enrolledWithoutReview = false,
    this.isSuperseded = false,
  });

  DaAmadEnrollmentModel copyWith({bool? isSuperseded}) => DaAmadEnrollmentModel(
    id: id,
    farmerId: farmerId,
    farmerName: farmerName,
    status: status,
    adminNotes: adminNotes,
    submittedAt: submittedAt,
    reviewedAt: reviewedAt,
    acknowledgedAt: acknowledgedAt,
    farmerPhotoUrl: farmerPhotoUrl,
    reviewerName: reviewerName,
    requestCount: requestCount,
    enrolledWithoutReview: enrolledWithoutReview,
    isSuperseded: isSuperseded ?? this.isSuperseded,
  );
}

/// The Manager's enrollment queue, split the way the screen shows it.
class DaAmadEnrollmentLists {
  /// Applications waiting for a decision, oldest first.
  final List<DaAmadEnrollmentModel> pending;

  /// Every farmer already decided on: approved, declined, and farmers already
  /// enrolled in Market Linking without an application on record. Most recent
  /// first.
  final List<DaAmadEnrollmentModel> reviewed;

  const DaAmadEnrollmentLists({required this.pending, required this.reviewed});

  /// Farmers approved into Market Linking (the Manager's Enrolled section),
  /// including those already in it with no application on record.
  List<DaAmadEnrollmentModel> get enrolled => [
    for (final e in reviewed)
      if (e.status == DaAmadEnrollmentStatus.approved) e,
  ];
}

/// Splits enrollment rows into the Pending and Reviewed lists.
///
/// [rows] are every application, in any order; [enrolledOnly] are farmers who
/// are in Market Linking but have no application. A farmer whose application
/// was declined and who applied again has an older, superseded row; it stays
/// in Reviewed as history and is marked so.
DaAmadEnrollmentLists splitEnrollments(
  List<DaAmadEnrollmentModel> rows, {
  List<DaAmadEnrollmentModel> enrolledOnly = const [],
}) {
  final latestByFarmer = <String, DateTime>{};
  for (final r in rows) {
    final t = latestByFarmer[r.farmerId];
    if (t == null || r.submittedAt.isAfter(t)) latestByFarmer[r.farmerId] = r.submittedAt;
  }
  final pending = rows
      .where((r) => r.status == DaAmadEnrollmentStatus.pending)
      .toList()
    ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
  final reviewed = [
    for (final r in rows)
      if (r.status != DaAmadEnrollmentStatus.pending)
        r.copyWith(isSuperseded: r.submittedAt.isBefore(latestByFarmer[r.farmerId]!)),
    ...enrolledOnly,
  ]..sort(
      (a, b) => (b.reviewedAt ?? b.submittedAt).compareTo(a.reviewedAt ?? a.submittedAt),
    );
  return DaAmadEnrollmentLists(pending: pending, reviewed: reviewed);
}

// ─── One recorded sale ─────────────────────────────────────────────────────────
// A request can be sold in several parts (80 kg submitted, 50 sold, then 30);
// each part is one row of market_linking_sales, with its own buyer and price.

class MarketLinkingSale {
  final String id;
  final String buyerName;
  final String? buyerContact;
  final double quantityKg;

  /// The unit [quantityKg] and [pricePerKg] are measured in: the harvest
  /// batch's own unit (the fields keep their old names).
  final String unit;
  final double pricePerKg;
  final double totalAmount;
  final String? notes;
  final DateTime completedAt;

  const MarketLinkingSale({
    required this.id,
    required this.buyerName,
    this.buyerContact,
    required this.quantityKg,
    this.unit = kDefaultUnit,
    required this.pricePerKg,
    required this.totalAmount,
    this.notes,
    required this.completedAt,
  });

  factory MarketLinkingSale.fromMap(Map<String, dynamic> map) {
    return MarketLinkingSale(
      id: map['id'] as String,
      buyerName: map['buyer_name'] as String? ?? 'Buyer',
      buyerContact: map['buyer_contact'] as String?,
      quantityKg: (map['confirmed_volume_kg'] as num).toDouble(),
      unit: unitOrDefault(map['unit'] as String?),
      pricePerKg: (map['price_per_kg'] as num).toDouble(),
      totalAmount: (map['total_amount'] as num).toDouble(),
      notes: map['notes'] as String?,
      completedAt: DateTime.parse(map['completed_at'] as String),
    );
  }
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

  /// The unit every quantity and price of this request is measured in: the
  /// harvest batch's own unit. Ginger is no longer fixed to kg, and nothing here
  /// is ever converted.
  final String unit;
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

  /// Buyer Details (stage 2): who the buyer is. Set by Manager/Officer.
  final String? buyerEmail;

  /// The Farmer's cancellation request: null, 'requested' (waiting for review),
  /// 'rejected' (declined), 'approved' or 'withdrawn' (nothing left to cancel).
  final String? cancellationStatus;
  final String? cancellationReason;
  final String? cancellationReviewNotes;
  final DateTime? cancellationRequestedAt;

  /// The Farmer's own camera photo of this crop (never the Crop Master image),
  /// shown to Manager/Officer so they can see the actual crop being sold.
  /// Enrichment only, not a column of this table.
  final String? cropPhotoUrl;

  /// Submitted quantity still held for this request, and how much has been
  /// sold so far (the sum of [sales]).
  final double reservedKg;
  final double soldKg;
  final List<MarketLinkingSale> sales;

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
    this.unit = kDefaultUnit,
    this.requestedVolumeKg,
    this.pricePerKg,
    this.notes,
    required this.submittedAt,
    this.buyerFoundAt,
    this.completedAt,
    this.inventoryBatchId,
    this.confirmedVolumeKg,
    this.batchNumber,
    this.buyerEmail,
    this.cancellationStatus,
    this.cancellationReason,
    this.cancellationReviewNotes,
    this.cancellationRequestedAt,
    this.cropPhotoUrl,
    this.reservedKg = 0,
    this.soldKg = 0,
    this.sales = const [],
    this.enrollmentId,
  });

  /// What is left of the submitted quantity (80 submitted, 50 sold -> 30).
  /// Zero once the request is closed or completed.
  double get remainingKg {
    if (!isActive) return 0;
    final left = (volumeKg ?? 0) - soldKg;
    return left > 0 ? roundQuantity(left) : 0;
  }

  bool get hasSales => soldKg > 0;

  /// True when this request matches what was typed in the search bar: every
  /// word must appear somewhere in the farmer's name, the crop, the batch
  /// number, or the buyer's name, contact number or email (case does not
  /// matter). An empty search matches everything.
  bool matchesSearch(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return true;
    final haystack = [
      farmerName,
      cropName,
      batchNumber,
      formatBatchNumber(batchNumber),
      buyerName,
      buyerContact,
      buyerEmail,
    ].whereType<String>().join(' ').toLowerCase();
    return words.every(haystack.contains);
  }


  /// Buyer Details have been saved (stage 2 done).
  bool get hasBuyer => (buyerName ?? '').trim().isNotEmpty;

  /// The Farmer asked to cancel and the Manager/Officer has not answered yet.
  bool get isCancellationRequested =>
      isActive && cancellationStatus == 'requested';

  /// The last cancellation request was declined (the request is still open).
  bool get wasCancellationDeclined =>
      isActive && cancellationStatus == 'rejected';

  /// The Farmer may ask to cancel an active request that still has something
  /// unsold and no request already waiting.
  bool get canRequestCancellation =>
      isActive && !isCancellationRequested && remainingKg > 0;

  /// Money received so far across every recorded sale, to the centavo.
  double get soldValue =>
      sales.fold<double>(0, (sum, s) => sum + s.totalAmount);

  bool get isActive =>
      status == MarketLinkingStatus.requested ||
      status == MarketLinkingStatus.submitted ||
      status == MarketLinkingStatus.buyerFound;

  /// The money this request has brought in: the sum of its recorded sales. Null
  /// until something is sold.
  double? get totalValue => sales.isEmpty ? null : soldValue;

  String get initials => PersonName.initials(farmerName, fallback: 'F');

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
      unit:           unitOrDefault(map['unit'] as String?),
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
      buyerEmail:     map['buyer_email'] as String?,

      cancellationStatus: map['cancellation_status'] as String?,
      cancellationReason: map['cancellation_reason'] as String?,
      cancellationReviewNotes: map['cancellation_review_notes'] as String?,
      cancellationRequestedAt: map['cancellation_requested_at'] != null
                          ? DateTime.parse(map['cancellation_requested_at'] as String)
                          : null,
      cropPhotoUrl:   map['crop_photo_url'] as String?,

      reservedKg:     (map['reserved_kg'] as num?)?.toDouble() ?? 0,
      soldKg:         (map['sold_kg'] as num?)?.toDouble() ?? 0,
      sales: [
        for (final s in (map['sales'] as List? ?? const []))
          MarketLinkingSale.fromMap(Map<String, dynamic>.from(s as Map)),
      ],
      enrollmentId: map['enrollment_id'] as String?,
    );
  }
}

// ─── Market Linking Summary Stats ──────────────────────────────────────────────

/// The Marketplace Overview's Market Linking figures, taken from the requests
/// themselves (market_linking_programs). A legacy 'requested' row (never created
/// by the current flow) is not counted, so [total] equals the "All" chip on the
/// Manager/Officer Market Linking screen.
class MarketLinkingSummaryStats {
  /// Every Market Linking request, whatever its status.
  final int total;

  /// Waiting for a buyer (status submitted).
  final int waitingForBuyer;

  /// A buyer is saved and the sale is not complete yet.
  final int buyerFound;

  /// Farmers who asked to cancel an open request and are waiting for a review.
  final int cancellationRequests;

  /// Different Farmers with at least one open request.
  final int activeFarmers;

  const MarketLinkingSummaryStats({
    required this.total,
    required this.waitingForBuyer,
    required this.buyerFound,
    required this.cancellationRequests,
    required this.activeFarmers,
  });

  /// Open requests: waiting for a buyer, or buyer found.
  int get active => waitingForBuyer + buyerFound;

  static const empty = MarketLinkingSummaryStats(
    total: 0,
    waitingForBuyer: 0,
    buyerFound: 0,
    cancellationRequests: 0,
    activeFarmers: 0,
  );

  /// Counts [rows] (status, farmer_id, cancellation_status) the way the Market
  /// Linking screen does. Pure, so it is tested without a database.
  factory MarketLinkingSummaryStats.fromRows(List<Map<String, dynamic>> rows) {
    final real = rows.where((r) => r['status'] != 'requested').toList();
    bool isOpen(Map<String, dynamic> r) =>
        r['status'] == 'submitted' || r['status'] == 'buyer_found';
    final open = real.where(isOpen).toList();
    return MarketLinkingSummaryStats(
      total: real.length,
      waitingForBuyer: real.where((r) => r['status'] == 'submitted').length,
      buyerFound: real.where((r) => r['status'] == 'buyer_found').length,
      cancellationRequests: open.where((r) => r['cancellation_status'] == 'requested').length,
      activeFarmers: open.map((r) => r['farmer_id']).whereType<String>().toSet().length,
    );
  }
}

// ─── Repository ────────────────────────────────────────────────────────────────

class MarketLinkingRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<MarketLinkingModel>> fetchAll({String? statusFilter}) async {
    try {
      // Names, photos and batch numbers are merged into each row before it is
      // cached, so the list still reads correctly when the device is offline.
      final enriched = await OfflineCache.load(
        screen: 'market_linking_${statusFilter ?? 'all'}',
        fetch: () async {
          var query = _client
              .from('market_linking_programs')
              .select('*, farmer_id');

          if (statusFilter != null) {
            query = query.eq('status', statusFilter);
          }

          final rows = await query.order('submitted_at', ascending: false);
          if (rows.isEmpty) return <Map<String, dynamic>>[];

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
          final batchUnitMap = <String, String>{};
          final batchCropMap = <String, String>{};
          if (batchIds.isNotEmpty) {
            try {
              final batchRows = await _client
                  .from('inventory_batches')
                  .select('id, batch_number, crop_id, unit')
                  .inFilter('id', batchIds);
              for (final b in batchRows) {
                batchMap[b['id'] as String] = b['batch_number'] as String;
                batchUnitMap[b['id'] as String] = unitOrDefault(b['unit'] as String?);
                final cropId = b['crop_id'] as String?;
                if (cropId != null) batchCropMap[b['id'] as String] = cropId;
              }
            } catch (_) {}
          }

          // The Farmer's own crop photo for each batch's crop — never the
          // Crop Master image.
          final photoByCrop = batchCropMap.isEmpty
              ? <String, String>{}
              : await fetchFarmerCropImageMap(
                  _client,
                  batchCropMap.values.toSet().toList(),
                );

          // Every recorded sale of these requests, oldest first.
          final salesByProgram = <String, List<Map<String, dynamic>>>{};
          try {
            final saleRows = await _client
                .from('market_linking_sales')
                .select(
                  'id, program_id, buyer_name, buyer_contact, confirmed_volume_kg, '
                  'price_per_kg, total_amount, notes, completed_at',
                )
                .inFilter('program_id', rows.map((r) => r['id'] as String).toList())
                .order('completed_at', ascending: true);
            for (final s in saleRows) {
              (salesByProgram[s['program_id'] as String] ??= []).add(s);
            }
          } catch (_) {}

          return rows.map<Map<String, dynamic>>((r) {
            final fid  = r['farmer_id'] as String;
            final info = infoMap[fid] ?? {};
            final batchId = r['inventory_batch_id'] as String?;
            // The request's own unit; the batch's when the column is not there
            // yet. Its sales are measured in the same unit.
            final unit = unitOrDefault(
              (r['unit'] as String?) ?? (batchId != null ? batchUnitMap[batchId] : null),
            );
            return {
              ...r,
              'unit':             unit,
              'farmer_name':      info['full_name'] as String? ?? 'Farmer',
              'farmer_photo_url': info['profile_photo_url'] as String?,
              'batch_number':     batchId != null ? batchMap[batchId] : null,
              'crop_photo_url':   batchId != null
                  ? photoByCrop[batchCropMap[batchId]]
                  : null,
              'sales': [
                for (final s in salesByProgram[r['id'] as String] ?? const [])
                  {...s, 'unit': unit},
              ],
            };
          }).toList();
        },
      );

      return enriched.map((r) => MarketLinkingModel.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  /// The Marketplace Overview's Market Linking figures (see
  /// [MarketLinkingSummaryStats]). A database that does not have the
  /// cancellation column yet still returns the rest.
  Future<MarketLinkingSummaryStats> fetchSummaryStats() async {
    try {
      Future<List<Map<String, dynamic>>> read(String columns) async =>
          List<Map<String, dynamic>>.from(
            await _client.from('market_linking_programs').select(columns).neq('status', 'requested'),
          );
      List<Map<String, dynamic>> rows;
      try {
        rows = await read('status, farmer_id, cancellation_status');
      } catch (_) {
        rows = await read('status, farmer_id');
      }
      return MarketLinkingSummaryStats.fromRows(rows);
    } catch (_) {
      return MarketLinkingSummaryStats.empty;
    }
  }

  // Replaces fetchUnenrolledGingerFarmers() — that method collapsed two
  // different situations into the same empty list: "every Ginger farmer is
  // already enrolled" and "no farmer has Ginger registered at all" produced
  // identical output, so the UI couldn't tell them apart and always showed
  // the same (sometimes wrong) message.
  // The crop(s) reserved for DA-AMAD Market Linking are the ones whose
  // crop_master.exclusive_channel is the DA-AMAD channel. DA-AMAD is a selling
  // channel, not a market type, and the reservation is set in the database
  // only (never from the app), so this never depends on a crop's name or its
  // market type. Multi-step lookup (crop_master -> farmer_crops) rather than a
  // nested PostgREST embed, matching this codebase's established resolution
  // pattern (see harvest_entry_repository.dart's is_coop_eligible lookup).
  Future<List<String>> _daAmadCropMasterIds() async {
    final rows = await _client
        .from('crop_master')
        .select('id')
        .eq('exclusive_channel', AppConstants.channelDaAmad);
    return rows.map((r) => r['id'] as String).toList();
  }

  /// Names of the crop(s) reserved for DA-AMAD, as the Manager's Crop Master
  /// spells them (used to recognise a pending crop request for the same crop).
  Future<List<String>> _daAmadCropNames() async {
    final rows = await _client
        .from('crop_master')
        .select('crop_name')
        .eq('exclusive_channel', AppConstants.channelDaAmad);
    return rows.map((r) => r['crop_name'] as String).toList();
  }

  // fetchEnrollmentCandidates() / enrollFarmer() removed — Market Linking
  // no longer offers an admin-direct "Enroll Farmer" action. Enrollment
  // (see the DA-AMAD Enrollment section below) is now the one gate a
  // farmer passes through, via their own request, reviewed by Admin —
  // never created directly against an arbitrary farmer. Submitting an
  // actual Ginger harvest for sale (submitGingerForSale() below) then
  // requires that enrollment to already be approved.

  // ─── The Manager/Officer's stages ─────────────────────────────────────────
  // Request (the Farmer's submission) -> Buyer Details -> Complete Sale ->
  // Completed. Each stage is its own call, so saving the buyer never sells
  // anything and only Complete Sale moves stock.

  /// Stage 2 — Buyer Details: who the buyer is, and nothing else (full name and
  /// contact number are required; email is optional). Moves the
  /// request to Buyer Found. Never sells, completes or deducts anything.
  Future<void> saveBuyerDetails({
    required String programId,
    required String fullName,
    required String contactNumber,
    String? email,
  }) async {
    await _client.rpc(
      'save_market_linking_buyer_details',
      params: {
        'p_program_id': programId,
        'p_buyer_name': fullName.trim(),
        'p_buyer_contact': contactNumber.trim(),
        'p_buyer_email': (email ?? '').trim().isEmpty ? null : email!.trim(),
      },
    );
    AdminActivityRepository().log(
      module: 'market_linking',
      actionType: 'buyer_found',
      message: const AdminLogMessage('adminLogMarketLinkingStatus', {'status': 'buyer_found'}),
      referenceId: programId,
    );
  }

  /// Stage 3 — Complete Sale: records one sale for the saved buyer: the quantity
  /// purchased, the agreed price per kg and any notes. The total is computed by
  /// the database. Only this step moves stock to Sold. A part-purchase leaves
  /// the unsold quantity reserved for the Farmer; selling the last of it
  /// completes the request. Returns the new sale's id.
  Future<String> recordSale({
    required String programId,
    required double quantityKg,
    required double pricePerKg,
    String? notes,
  }) async {
    final id = await _client.rpc(
      'record_market_linking_sale',
      params: {
        'p_program_id': programId,
        'p_quantity_kg': roundQuantity(quantityKg),
        'p_price_per_kg': roundQuantity(pricePerKg),
        'p_notes': notes,
      },
    );
    AdminActivityRepository().log(
      module: 'market_linking',
      actionType: 'sale_recorded',
      message: const AdminLogMessage('adminLogMarketLinkingCompleted'),
      referenceId: programId,
    );
    return id as String;
  }

  // ─── Cancellation: the Farmer asks, the Manager/Officer reviews ───────────
  // There is deliberately no way for a Manager/Officer to cancel a request on
  // their own (the database refuses it too).

  /// Farmer: asks to cancel an active request. A reason is required. Nothing is
  /// released until the Manager/Officer approves.
  Future<void> requestCancellation({
    required String programId,
    required String reason,
  }) async {
    await _client.rpc(
      'request_market_linking_cancellation',
      params: {'p_program_id': programId, 'p_reason': reason.trim()},
    );
  }

  /// Manager/Officer: approves or declines a Farmer's cancellation. Declining
  /// needs a reason. Approving releases only the unsold reserved quantity and
  /// keeps every sale already recorded.
  Future<void> respondToCancellation({
    required String programId,
    required bool approve,
    String? notes,
  }) async {
    await _client.rpc(
      'respond_to_market_linking_cancellation',
      params: {
        'p_program_id': programId,
        'p_approve': approve,
        'p_notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
      },
    );
    AdminActivityRepository().log(
      module: 'market_linking',
      actionType: approve ? 'cancellation_approved' : 'cancellation_declined',
      message: AdminLogMessage('adminLogMarketLinkingStatus', {
        'status': approve ? 'cancellation approved' : 'cancellation declined',
      }),
      referenceId: programId,
    );
  }

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
      message: const AdminLogMessage('adminLogMarketLinkingDeleted'),
      referenceId: id,
    );
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

  /// How many of the farmer's own requests are still open (waiting for a buyer,
  /// or a buyer found and not yet fully sold) — for the Profile row's subtitle.
  Future<int> fetchMyActiveRequestCount() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return 0;
      final rows = await _client
          .from('market_linking_programs')
          .select('id')
          .eq('farmer_id', uid)
          .inFilter('status', ['submitted', 'buyer_found']);
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
      final names = await _daAmadCropNames();
      if (names.isEmpty) return false;
      final rows = await _client
          .from('crop_requests')
          .select('id, requested_name')
          .eq('farmer_id', uid)
          .eq('status', 'pending');
      final reserved = names.map((n) => n.toLowerCase()).toSet();
      return rows.any(
        (r) => reserved.contains(
          (r['requested_name'] as String? ?? '').trim().toLowerCase(),
        ),
      );
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
        acknowledgedAt: row['acknowledged_at'] != null
            ? DateTime.parse(row['acknowledged_at'] as String)
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// The Farmer tapped Continue on the approval congratulations: remember it on
  /// the server, for that enrollment, so it never shows again. Best effort: the
  /// device also remembers it locally, so a failed call (offline) never brings
  /// the screen back on this device.
  Future<void> acknowledgeEnrollment(String enrollmentId) async {
    try {
      await _client.rpc(
        'acknowledge_da_amad_enrollment',
        params: {'p_enrollment_id': enrollmentId},
      );
    } catch (_) {}
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

  /// Manager / Officer: the whole enrollment queue in one read, so Pending and
  /// Reviewed always come from the same snapshot and their counts agree.
  ///
  /// Reviewed holds every farmer already decided on: approved, declined, and
  /// farmers who are already in Market Linking (they have requests) but have no
  /// application on record. Unlike the earlier two-call version, a failed read
  /// throws, so the screen can say so instead of showing an empty list that
  /// looks like "nobody has been reviewed".
  Future<DaAmadEnrollmentLists> fetchEnrollmentQueue() async {
    final rows = await _client
        .from('da_amad_enrollments')
        .select('id, farmer_id, status, admin_notes, submitted_at, reviewed_at, reviewed_by');
    final programs = await _client
        .from('market_linking_programs')
        .select('farmer_id, submitted_at');

    final requestCounts = <String, int>{};
    final firstRequest = <String, DateTime>{};
    for (final p in programs) {
      final id = p['farmer_id'] as String;
      requestCounts[id] = (requestCounts[id] ?? 0) + 1;
      final at = DateTime.tryParse(p['submitted_at'] as String? ?? '');
      if (at != null && (firstRequest[id] == null || at.isBefore(firstRequest[id]!))) {
        firstRequest[id] = at;
      }
    }
    final applied = {for (final r in rows) r['farmer_id'] as String};
    final unreviewed = requestCounts.keys.where((id) => !applied.contains(id)).toList();

    final peopleIds = <String>{
      ...applied,
      ...unreviewed,
      for (final r in rows)
        if (r['reviewed_by'] != null) r['reviewed_by'] as String,
    }.toList();
    final people = <String, Map<String, dynamic>>{};
    if (peopleIds.isNotEmpty) {
      final info = await _client
          .from('user_information')
          .select('user_id, full_name, profile_photo_url')
          .inFilter('user_id', peopleIds);
      for (final i in info) {
        people[i['user_id'] as String] = i;
      }
    }

    DaAmadEnrollmentModel build(
      String farmerId, {
      required String id,
      required DaAmadEnrollmentStatus status,
      String? notes,
      required DateTime submittedAt,
      DateTime? reviewedAt,
      String? reviewedBy,
      bool enrolledWithoutReview = false,
    }) {
      final person = people[farmerId];
      return DaAmadEnrollmentModel(
        id: id,
        farmerId: farmerId,
        farmerName: person?['full_name'] as String? ?? 'Farmer',
        status: status,
        adminNotes: notes,
        submittedAt: submittedAt,
        reviewedAt: reviewedAt,
        farmerPhotoUrl: person?['profile_photo_url'] as String?,
        reviewerName: reviewedBy == null ? null : people[reviewedBy]?['full_name'] as String?,
        requestCount: requestCounts[farmerId] ?? 0,
        enrolledWithoutReview: enrolledWithoutReview,
      );
    }

    return splitEnrollments(
      [
        for (final r in rows)
          build(
            r['farmer_id'] as String,
            id: r['id'] as String,
            status: DaAmadEnrollmentStatusExt.fromString(r['status'] as String?),
            notes: r['admin_notes'] as String?,
            submittedAt: DateTime.parse(r['submitted_at'] as String),
            reviewedAt: r['reviewed_at'] != null ? DateTime.parse(r['reviewed_at'] as String) : null,
            reviewedBy: r['reviewed_by'] as String?,
          ),
      ],
      enrolledOnly: [
        for (final id in unreviewed)
          build(
            id,
            id: 'enrolled-$id',
            status: DaAmadEnrollmentStatus.approved,
            submittedAt: firstRequest[id] ?? DateTime.fromMillisecondsSinceEpoch(0),
            enrolledWithoutReview: true,
          ),
      ],
    );
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
        message: approve
? const AdminLogMessage('adminLogEnrollmentApproved')
: const AdminLogMessage('adminLogEnrollmentDeclined'),
        referenceId: id,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}