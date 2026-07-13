import 'package:supabase_flutter/supabase_flutter.dart';

/// Denormalized farmer identity used across admin repositories wherever a
/// list of records needs display names without a per-row round trip.
class FarmerLookupInfo {
  final String fullName;
  final String memberId;
  const FarmerLookupInfo({required this.fullName, required this.memberId});
}

/// Batch-resolves farmer display info (name + member ID) for a set of
/// farmer IDs. Done as two separate lookups rather than a single nested
/// select, because the record tables (farmer_loans, harvest_records,
/// member_sales_transactions, etc.), user_information.user_id, and
/// farmer_profiles.user_id are sibling foreign keys into auth.users —
/// there's no direct FK between any of these record tables and either
/// info table for PostgREST to embed through.
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
    final results = await Future.wait([
      client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', farmerIds),
      client
          .from('farmer_profiles')
          .select('user_id, member_id')
          .inFilter('user_id', farmerIds),
    ]);

    final names = {
      for (final r in results[0])
        r['user_id'] as String: r['full_name'] as String? ?? 'Unknown Farmer',
    };
    final memberIds = {
      for (final r in results[1])
        r['user_id'] as String: r['member_id'] as String? ?? '—',
    };

    return {
      for (final id in farmerIds)
        id: FarmerLookupInfo(
          fullName: names[id] ?? 'Unknown Farmer',
          memberId: memberIds[id] ?? '—',
        ),
    };
  } catch (_) {
    return {};
  }
}