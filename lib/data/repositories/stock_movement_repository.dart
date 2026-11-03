import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/stock_movement_model.dart';

/// Reads a harvest batch's stock history. The table is written only by the
/// database (a trigger on inventory_batches); a Farmer reads their own batches'
/// history and a Manager / Officer reads all of it.
class StockMovementRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// The newest movements of [batchId] first. Throws on a failed read so the
  /// sheet can show an error instead of a misleading "no movements".
  Future<List<StockMovementModel>> fetchForBatch(
    String batchId, {
    int limit = 200,
  }) async {
    final rows = await _client
        .from('stock_movements')
        .select(StockMovementModel.selectColumns)
        .eq('batch_id', batchId)
        .order('created_at', ascending: false)
        .order('seq', ascending: false)
        .limit(limit);
    return rows.map((r) => StockMovementModel.fromMap(r)).toList();
  }
}
