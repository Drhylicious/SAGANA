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
  // Routed through update_batch_available_quantity (see new SQL file) so
  // this follows the same row-locked, validated pattern as every other
  // batch-quantity mutation (_apply_batch_reservation and friends), instead
  // of a client-side read-then-write with no lock and no bounds checking.

  Future<void> updateQuantity(String batchId, double newAvailableKg) async {
    await _client.rpc('update_batch_available_quantity', params: {
      'p_batch_id': batchId,
      'p_new_available_kg': newAvailableKg,
    });
  }

  // ─── Withdraw / Delete batch ──────────────────────────────────────────────
  // Routed through delete_inventory_batch (see
  // supabase_schema_delete_batch_listing_guard.sql) rather than a plain
  // client delete — the RPC blocks deletion while an active listing still
  // references this batch, instead of silently orphaning it via the FK's
  // ON DELETE SET NULL.

  Future<void> deleteBatch(String batchId) async {
    await _client.rpc('delete_inventory_batch', params: {
      'p_batch_id': batchId,
    });
  }

  // ─── Loan Catalog integration ─────────────────────────────────────────────

  /// Publishes a cooperative_inventory item to the loan catalog.
  Future<bool> publishToLoanCatalog({
    required String inventoryItemId,
    required double loanPrice,
    String? notes,
  }) async {
    try {
      await _client.from('loan_items_master').insert({
        'inventory_item_id': inventoryItemId,
        'unit_price': loanPrice,
        'is_loan_eligible': true,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the existing loan catalog link for an inventory item, or null.
  Future<Map<String, dynamic>?> fetchLoanCatalogLink(String inventoryItemId) async {
    try {
      final rows = await _client
          .from('loan_items_master')
          .select('id, unit_price, is_loan_eligible, notes')
          .eq('inventory_item_id', inventoryItemId)
          .limit(1);
      return rows.isEmpty ? null : rows.first;
    } catch (_) {
      return null;
    }
  }
}

// ─── Fetch available batches only (for Create Listing source selector) ────────

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

  /// Fetches one specific batch by id regardless of status — used when
  /// resubmitting a changes_required listing, whose batch is almost
  /// always 'reserved' (fully committed to that pending listing) and
  /// would be silently excluded by fetchAvailableBatches()'s status filter.
  Future<InventoryBatchModel?> fetchBatchById(String batchId) async {
    final client = Supabase.instance.client;
    try {
      final row = await client
          .from('inventory_batches')
          .select('*, harvest_records(harvest_date)')
          .eq('id', batchId)
          .maybeSingle();
      return row != null ? InventoryBatchModel.fromMap(row) : null;
    } catch (_) {
      return null;
    }
  }
}