import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_batch_model.dart';

class InventoryRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  // ─── Fetch all batches ────────────────────────────────────────────────────

  Future<List<InventoryBatchModel>> fetchBatches() async {
    try {
      final response = await _client
          .from('inventory_batches')
          .select('*, harvest_records(harvest_date)')
          .eq('farmer_id', _userId)
          .order('created_at', ascending: false);
      return response
          .map((row) => InventoryBatchModel.fromMap(row))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Summary metrics ──────────────────────────────────────────────────────

  Future<Map<String, double>> fetchSummary() async {
    try {
      final response = await _client
          .from('inventory_batches')
          .select('available_kg, reserved_kg, sold_kg')
          .eq('farmer_id', _userId);

      double available = 0, reserved = 0, sold = 0;
      for (final row in response) {
        available += (row['available_kg'] as num).toDouble();
        reserved += (row['reserved_kg'] as num).toDouble();
        sold += (row['sold_kg'] as num).toDouble();
      }
      return {'available': available, 'reserved': reserved, 'sold': sold};
    } catch (_) {
      return {'available': 0, 'reserved': 0, 'sold': 0};
    }
  }

  // ─── Update quantity ──────────────────────────────────────────────────────

  Future<void> updateQuantity(String batchId, double newAvailableKg) async {
    final batch = await _client
        .from('inventory_batches')
        .select('quantity_kg, reserved_kg, sold_kg')
        .eq('id', batchId)
        .single();

    final qty = (batch['quantity_kg'] as num).toDouble();
    final sold = (batch['sold_kg'] as num).toDouble();

    String newStatus = 'available';
    if (newAvailableKg <= 0) {
      newStatus = sold >= qty ? 'sold_out' : 'reserved';
    } else if (newAvailableKg < qty * 0.15) {
      newStatus = 'low_stock';
    }

    await _client.from('inventory_batches').update({
      'available_kg': newAvailableKg,
      'status': newStatus,
    }).eq('id', batchId);
  }

  // ─── Mark as sold ─────────────────────────────────────────────────────────

  Future<void> markAsSold(String batchId) async {
    final batch = await _client
        .from('inventory_batches')
        .select('available_kg, sold_kg')
        .eq('id', batchId)
        .single();

    final available = (batch['available_kg'] as num).toDouble();
    final sold = (batch['sold_kg'] as num).toDouble();

    await _client.from('inventory_batches').update({
      'available_kg': 0,
      'sold_kg': sold + available,
      'status': 'sold_out',
    }).eq('id', batchId);
  }

  // ─── Withdraw / Delete batch ──────────────────────────────────────────────

  Future<void> deleteBatch(String batchId) async {
    await _client
        .from('inventory_batches')
        .delete()
        .eq('id', batchId)
        .eq('farmer_id', _userId);
  }
}

// ─── Fetch available batches only (for Create Listing source selector) ────

extension AvailableBatchesFetch on InventoryRepository {
  Future<List<InventoryBatchModel>> fetchAvailableBatches() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;
    try {
      final response = await client
          .from('inventory_batches')
          .select('*, harvest_records(harvest_date)')
          .eq('farmer_id', userId)
          .inFilter('status', ['available', 'low_stock'])
          .order('created_at', ascending: false);
      return response
          .map((row) => InventoryBatchModel.fromMap(row))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
