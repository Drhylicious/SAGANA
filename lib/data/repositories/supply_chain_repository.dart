import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/supply_chain_model.dart';
import '../services/offline_cache.dart';

/// Read-only access to the Supply Chain tracking records.
///
/// Both calls go to database functions that only read (see
/// supabase_schema_supply_chain_01_read_model.sql) and answer only for a Manager
/// or Officer. This repository has no write method on purpose.
class SupplyChainRepository {
  SupplyChainRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Every tracked supply movement, newest first. The screen filters by date, stage
  /// and movement itself so every chip can show a count. Throws when the records can
  /// neither be read nor found in the saved snapshot, so the screen can say so instead
  /// of showing a misleading "nothing tracked".
  Future<List<SupplyChainRecord>> fetchRecords() async {
    final rows = await OfflineCache.load(
      screen: cacheKey,
      fetch: () async {
        final data = await _client.rpc('get_supply_chain_records');
        return List<Map<String, dynamic>>.from(
          (data as List).map((r) => Map<String, dynamic>.from(r as Map)),
        );
      },
    );
    return rows.map(SupplyChainRecord.fromMap).toList();
  }

  /// The OfflineCache key (for the "saved data" notice).
  static const String cacheKey = 'supply_chain_all';

  /// Total Supplies of the CURRENT calendar year (the Dashboard card): supplies
  /// that moved in and out, plus orders still in progress. A figure that cannot
  /// be read counts as zero.
  Future<SupplyChainTotals> fetchYearTotals() async {
    try {
      final data = await _client.rpc('get_supply_chain_totals');
      final rows = data as List;
      if (rows.isEmpty) return SupplyChainTotals.empty;
      return SupplyChainTotals.fromMap(
        Map<String, dynamic>.from(rows.first as Map),
      );
    } catch (_) {
      return SupplyChainTotals.empty;
    }
  }
}
