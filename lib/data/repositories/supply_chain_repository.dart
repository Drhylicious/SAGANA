import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/supply_chain_model.dart';

class SupplyChainRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Fetch all mapped farmers (have coordinates) ──────────────────────────

  Future<List<SupplyChainFarmerModel>> fetchMappedFarmers() async {
    try {
      // Fetch farmer_profiles with coordinates
      final profileRows = await _client
          .from('farmer_profiles')
          .select(
              'user_id, member_id, farm_latitude, farm_longitude, is_verified')
          .not('farm_latitude', 'is', null)
          .not('farm_longitude', 'is', null);

      if (profileRows.isEmpty) return [];

      final userIds =
          profileRows.map((r) => r['user_id'] as String).toList();

      // Fetch user_information for names and photos
      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name, sitio, profile_photo_url')
          .inFilter('user_id', userIds);

      final infoMap = {
        for (final r in infoRows) r['user_id'] as String: r,
      };

      // Fetch crops per farmer
      final cropRows = await _client
          .from('farmer_crops')
          .select('farmer_id, crop_name')
          .inFilter('farmer_id', userIds);

      final cropsMap = <String, List<String>>{};
      for (final r in cropRows) {
        final id = r['farmer_id'] as String;
        cropsMap.putIfAbsent(id, () => []).add(r['crop_name'] as String);
      }

      // Fetch loan balances
      final loanRows = await _client
          .from('farmer_loans')
          .select('farmer_id, total_value, amount_paid, status')
          .inFilter('farmer_id', userIds)
          .neq('status', 'paid');

      final loanMap = <String, Map<String, dynamic>>{};
      for (final r in loanRows) {
        final id = r['farmer_id'] as String;
        final remaining =
            (r['total_value'] as num).toDouble() -
            (r['amount_paid'] as num? ?? 0).toDouble();
        final existing = loanMap[id];
        final existingBalance = (existing?['balance'] as double?) ?? 0.0;
        final balance = existingBalance + remaining.clamp(0.0, double.infinity);
        final status = r['status'] as String;
        final existingStatus = existing?['status'] as String?;
        final isOverdue = status == 'overdue' ||
            existingStatus == 'overdue';
        loanMap[id] = {
          'balance': balance,
          'status': isOverdue ? 'overdue' : 'active',
        };
      }

      // Fetch last harvest dates
      final harvestRows = await _client
          .from('harvest_records')
          .select('farmer_id, harvest_date')
          .inFilter('farmer_id', userIds)
          .order('harvest_date', ascending: false);

      final harvestMap = <String, String>{};
      for (final r in harvestRows) {
        final id = r['farmer_id'] as String;
        harvestMap.putIfAbsent(id, () => r['harvest_date'] as String);
      }

      return profileRows.map((p) {
        final uid  = p['user_id'] as String;
        final info = infoMap[uid] ?? {};
        final loan = loanMap[uid];

        return SupplyChainFarmerModel.fromMap({
          'user_id':            uid,
          'full_name':          info['full_name'] as String? ?? 'Farmer',
          'member_id':          p['member_id'] as String?,
          'sitio':              info['sitio'] as String?,
          'profile_photo_url':  info['profile_photo_url'] as String?,
          'farm_latitude':      p['farm_latitude'],
          'farm_longitude':     p['farm_longitude'],
          'is_verified':        p['is_verified'] as bool? ?? false,
          'crops':              cropsMap[uid] ?? [],
          'outstanding_balance': loan?['balance'] ?? 0.0,
          'loan_status':        loan != null
              ? loan['status'] as String
              : 'none',
          'last_harvest_date':  harvestMap[uid],
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Fetch supply chain summary ───────────────────────────────────────────

  Future<SupplyChainSummary> fetchSummary() async {
    int totalMembers  = 0;
    int mappedMembers = 0;
    final cropCounts  = <String, int>{};

    try {
      final allFarmers = await _client
          .from('user_roles')
          .select('user_id')
          .eq('role', 'farmer')
          .eq('status', 'active');
      totalMembers = allFarmers.length;
    } catch (_) {
      totalMembers = 52; // SP3 known count fallback
    }

    try {
      final mapped = await _client
          .from('farmer_profiles')
          .select('user_id')
          .not('farm_latitude', 'is', null);
      mappedMembers = mapped.length;
    } catch (_) {}

    try {
      final cropRows = await _client
          .from('farmer_crops')
          .select('crop_name');
      for (final r in cropRows) {
        final name = r['crop_name'] as String;
        cropCounts[name] = (cropCounts[name] ?? 0) + 1;
      }
    } catch (_) {}

    // Map to SP3 primary crops with abbreviations
    const primaryCrops = [
      ('Peanut', 'PNT'),
      ('Ginger', 'GGR'),
      ('Palay', 'PLY'),
      ('Banana', 'BNA'),
      ('Copra', 'CPR'),
    ];

    final stats = primaryCrops.map((pair) {
      final count = cropCounts.entries
          .where((e) =>
              e.key.toLowerCase().contains(pair.$1.toLowerCase()))
          .fold<int>(0, (s, e) => s + e.value);
      return CropMapStat(
        cropName:     pair.$1,
        abbreviation: pair.$2,
        farmerCount:  count,
      );
    }).toList();

    return SupplyChainSummary(
      totalMembers:  totalMembers,
      mappedMembers: mappedMembers,
      cropStats:     stats,
    );
  }
}
