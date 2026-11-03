import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cooperative_inventory_history.dart';

class CooperativeInventoryHistoryRepository {
  CooperativeInventoryHistoryRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;
  static const pageSize = 50;

  Future<List<CooperativeInventoryEvent>> history(
    String inventoryId,
    int offset,
  ) async {
    final rows = await _client
        .from('cooperative_inventory_history')
        .select('*, batch:cooperative_harvest_batches(*)')
        .eq('inventory_id', inventoryId)
        .order('occurred_at', ascending: false)
        .order('id')
        .range(offset, offset + pageSize - 1);
    return rows.map(CooperativeInventoryEvent.fromMap).toList();
  }

  Future<List<CooperativeHarvestBatch>> batches(
    String inventoryId,
    int offset,
  ) async {
    final rows = await _client
        .from('cooperative_harvest_batches')
        .select()
        .eq('inventory_id', inventoryId)
        .order('received_at', ascending: false)
        .order('id')
        .range(offset, offset + pageSize - 1);
    return rows.map(CooperativeHarvestBatch.new).toList();
  }
}
