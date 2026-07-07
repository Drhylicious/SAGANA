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
  final String? sitio;
  final String cropName;
  final int seasonYear;
  final MarketLinkingStatus status;
  final String? buyerName;
  final String? buyerContact;
  final double? volumeKg;
  final double? pricePerKg;
  final String? notes;
  final DateTime submittedAt;
  final DateTime? buyerFoundAt;
  final DateTime? completedAt;

  const MarketLinkingModel({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    this.farmerPhotoUrl,
    this.sitio,
    required this.cropName,
    required this.seasonYear,
    required this.status,
    this.buyerName,
    this.buyerContact,
    this.volumeKg,
    this.pricePerKg,
    this.notes,
    required this.submittedAt,
    this.buyerFoundAt,
    this.completedAt,
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
      sitio:          map['sitio'] as String?,
      cropName:       map['crop_name'] as String? ?? 'Ginger',
      seasonYear:     map['season_year'] as int? ?? DateTime.now().year,
      status:         MarketLinkingStatusExt.fromString(
                          map['status'] as String?),
      buyerName:      map['buyer_name'] as String?,
      buyerContact:   map['buyer_contact'] as String?,
      volumeKg:       map['volume_kg'] != null
                          ? (map['volume_kg'] as num).toDouble()
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
    );
  }
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
          .select('user_id, full_name, sitio, profile_photo_url')
          .inFilter('user_id', farmerIds);
      final infoMap = {
        for (final r in infoRows) r['user_id'] as String: r,
      };

      return rows.map((r) {
        final fid  = r['farmer_id'] as String;
        final info = infoMap[fid] ?? {};
        return MarketLinkingModel.fromMap({
          ...r,
          'farmer_name':      info['full_name'] as String? ?? 'Farmer',
          'farmer_photo_url': info['profile_photo_url'] as String?,
          'sitio':            info['sitio'] as String?,
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // Fetch Ginger farmers not yet enrolled in current season
  Future<List<Map<String, dynamic>>> fetchUnenrolledGingerFarmers() async {
    try {
      final year = DateTime.now().year;
      // Get already enrolled farmer IDs for this year
      final enrolled = await _client
          .from('market_linking_programs')
          .select('farmer_id')
          .eq('season_year', year)
          .neq('status', 'cancelled');
      final enrolledIds = enrolled.map((r) => r['farmer_id'] as String).toSet();

      // Ginger farmers
      final gingerRows = await _client
          .from('farmer_crops')
          .select('farmer_id')
          .ilike('crop_name', '%ginger%');
      final gingerFarmerIds = gingerRows
          .map((r) => r['farmer_id'] as String)
          .where((id) => !enrolledIds.contains(id))
          .toSet()
          .toList();

      if (gingerFarmerIds.isEmpty) return [];

      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name, sitio')
          .inFilter('user_id', gingerFarmerIds)
          .order('full_name', ascending: true);

      return infoRows
          .map((r) => {
                'id':   r['user_id'] as String,
                'name': r['full_name'] as String? ?? 'Farmer',
                'sitio': r['sitio'] as String?,
              })
          .toList();
    } catch (_) {
      return [];
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

  Future<void> updateStatus({
    required String id,
    required MarketLinkingStatus newStatus,
    String? buyerName,
    String? buyerContact,
    double? pricePerKg,
    String? notes,
  }) async {
    final now = DateTime.now().toIso8601String();
    await _client.from('market_linking_programs').update({
      'status':        newStatus.value,
      if (buyerName != null) 'buyer_name': buyerName,
      if (buyerContact != null) 'buyer_contact': buyerContact,
      if (pricePerKg != null) 'price_per_kg': pricePerKg,
      if (notes != null) 'notes': notes,
      if (newStatus == MarketLinkingStatus.buyerFound)
        'buyer_found_at': now,
      if (newStatus == MarketLinkingStatus.completed)
        'completed_at': now,
    }).eq('id', id);
  }
}
