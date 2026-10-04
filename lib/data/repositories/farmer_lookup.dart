import 'package:supabase_flutter/supabase_flutter.dart';

/// Denormalized farmer identity used across admin repositories wherever a
/// list of records needs display names without a per-row round trip.
class FarmerLookupInfo {
  final String fullName;
  const FarmerLookupInfo({required this.fullName});
}

/// Batch-resolves farmer display names for a set of farmer IDs.
///
/// Shared by AdminLoanRepository and AdminReportsRepository (and any
/// future admin repository with the same need) — extracted here after the
/// second occurrence rather than kept as a private copy per repository.
///
/// ASSUMPTION TO VERIFY: uses .inFilter(), the current postgrest-dart API
/// for "IN" queries — same flag as everywhere else this pattern is used.
Future<Map<String, FarmerLookupInfo>> fetchFarmerInfoMap(
  SupabaseClient client,
  List<String> farmerIds,
) async {
  if (farmerIds.isEmpty) return {};
  try {
    final rows = await client
          .from('user_information')
          .select('user_id, full_name')
        .inFilter('user_id', farmerIds);

    final names = {
      for (final r in rows)
        r['user_id'] as String: r['full_name'] as String? ?? 'Unknown Farmer',
    };

    return {
      for (final id in farmerIds)
        id: FarmerLookupInfo(fullName: names[id] ?? 'Unknown Farmer'),
    };
  } catch (_) {
    return {};
  }
}