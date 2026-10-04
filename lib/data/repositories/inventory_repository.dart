import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_batch_model.dart';
import 'admin_activity_repository.dart';
import 'crop_lookup.dart';

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
      return response.map((row) => InventoryBatchModel.fromMap(row)).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Summary metrics ──────────────────────────────────────────────────────

  Future<Map<String, double>> fetchSummary() async {
    try {
      final response = await _client
          .from('inventory_batches')
          .select('quantity_kg, available_kg, sold_kg')
          .eq('farmer_id', _userId);

      double available = 0, reserved = 0, sold = 0;
      for (final row in response) {
        final quantity = (row['quantity_kg'] as num).toDouble();
        final avail = (row['available_kg'] as num).toDouble();
        final soldKg = (row['sold_kg'] as num).toDouble();
        available += avail;
        sold += soldKg;
        // reserved_kg is dead schema — never written by any live RPC
        // (see supabase_schema_update_batch_quantity_reservation_guard*.sql).
        // Real reservation state is whatever's left over once available
        // and sold are accounted for, not that column.
        final reservedForBatch = quantity - avail - soldKg;
        reserved += reservedForBatch > 0 ? reservedForBatch : 0;
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
    await _client.rpc(
      'update_batch_available_quantity',
      params: {'p_batch_id': batchId, 'p_new_available_kg': newAvailableKg},
    );
  }

  // deleteBatch() removed — Manage Inventory no longer offers a Delete
  // Batch action (a batch can carry real selling/transaction history
  // across 4 disposal channels; historical records are preserved, not
  // deletable). The server-side delete_inventory_batch RPC this used to
  // call is left in place at the database level, unreferenced from here.

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
      AdminActivityRepository().log(
        module: 'loans',
        actionType: 'created',
        description:
            'Published an inventory item to the loan catalog (₱${loanPrice.toStringAsFixed(2)}).',
        referenceId: inventoryItemId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the existing loan catalog link for an inventory item, or null.
  Future<Map<String, dynamic>?> fetchLoanCatalogLink(
    String inventoryItemId,
  ) async {
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
  /// Ginger is excluded here — its only disposal path is Market Linking
  /// (DA-AMAD), never the open Marketplace. create_listing_with_reservation
  /// already rejects it server-side as a backstop, but that only fires at
  /// final submission; without this filter a farmer could pick a Ginger
  /// batch, fill out the whole form, and only find out it's disallowed on
  /// submit. This method is Create Listing's own batch source selector
  /// only (confirmed the sole caller) — Manage Inventory and Market
  /// Linking resolve batches through their own separate queries, so this
  /// filter can't affect either of those screens' own Ginger handling.
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

      final farmerCropIds = response
          .map((r) => r['crop_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final imageMap = await fetchFarmerCropImageMap(client, farmerCropIds);
      final categoryMap = await fetchFarmerCropCategoryMap(
        client,
        farmerCropIds,
      );

      return response
          .map(
            (row) => InventoryBatchModel.fromMap({
              ...row,
              'display_image_url': imageMap[row['crop_id']],
              'category': categoryMap[row['crop_id']],
            }),
          )
          .where((batch) => batch.cropType != 'da_amad_market')
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches one specific batch by id regardless of status — a listing's
  /// batch is almost always 'reserved' (fully committed to that listing)
  /// and would be silently excluded by fetchAvailableBatches()'s status
  /// filter. Used by Create Listing and the Listing Detail screen.
  Future<InventoryBatchModel?> fetchBatchById(String batchId) async {
    final client = Supabase.instance.client;
    try {
      final row = await client
          .from('inventory_batches')
          .select('*, harvest_records(harvest_date)')
          .eq('id', batchId)
          .maybeSingle();
      if (row == null) return null;

      final cropId = row['crop_id'] as String?;
      final imageMap = cropId != null
          ? await fetchFarmerCropImageMap(client, [cropId])
          : <String, String>{};
      final categoryMap = cropId != null
          ? await fetchFarmerCropCategoryMap(client, [cropId])
          : <String, String>{};

      return InventoryBatchModel.fromMap({
        ...row,
        'display_image_url': cropId != null ? imageMap[cropId] : null,
        'category': cropId != null ? categoryMap[cropId] : null,
      });
    } catch (_) {
      return null;
    }
  }
}