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
          .select('user_id, full_name, purok, profile_photo_url')
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

      return profileRows.map((p) {
        final uid  = p['user_id'] as String;
        final info = infoMap[uid] ?? {};

        return SupplyChainFarmerModel.fromMap({
          'user_id':            uid,
          'full_name':          info['full_name'] as String? ?? 'Farmer',
          'member_id':          p['member_id'] as String?,
          'purok':              info['purok'] as String?,
          'profile_photo_url':  info['profile_photo_url'] as String?,
          'farm_latitude':      p['farm_latitude'],
          'farm_longitude':     p['farm_longitude'],
          'is_verified':        p['is_verified'] as bool? ?? false,
          'crops':              cropsMap[uid] ?? [],
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

  // ─── Fetch coverage (mapped vs. unmapped members) ──────────────────────────
  // Replaces fetchOperationsSnapshot(), which queried farmer_loans,
  // marketplace_listings, and inventory_batches — none of which describe
  // supply chain map coverage. Only membership + mapping status belong here.

  Future<SupplyChainCoverage> fetchCoverage() async {
    int totalMembers = 0;
    int mappedMembers = 0;

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

    return SupplyChainCoverage(
      totalMembers: totalMembers,
      mappedMembers: mappedMembers,
    );
  }

  // ─── Fetch unmapped members (for the "no farm location" insight) ──────────

  Future<List<UnmappedMemberEntry>> fetchUnmappedMembers() async {
    try {
      final allFarmers = await _client
          .from('user_roles')
          .select('user_id')
          .eq('role', 'farmer')
          .eq('status', 'active');
      final allIds = allFarmers.map((r) => r['user_id'] as String).toSet();

      final mapped = await _client
          .from('farmer_profiles')
          .select('user_id')
          .not('farm_latitude', 'is', null);
      final mappedIds = mapped.map((r) => r['user_id'] as String).toSet();

      final unmappedIds = allIds.difference(mappedIds).toList();
      if (unmappedIds.isEmpty) return [];

      final info = await _client
          .from('user_information')
          .select('user_id, full_name, purok')
          .inFilter('user_id', unmappedIds);

      return info
          .map((r) => UnmappedMemberEntry(
                userId: r['user_id'] as String,
                fullName: r['full_name'] as String? ?? 'Unknown',
                purok: r['purok'] as String?,
              ))
          .toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));
    } catch (_) {
      return [];
    }
  }

}
