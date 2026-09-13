import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/harvest_model.dart';
import '../services/connectivity_service.dart';
import '../services/hive_service.dart';

class HarvestEntryRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  Future<HarvestModel> submitHarvest({
    required String cropId,
    required String cropName,
    required String cropCategory,
    required double quantityKg,
    required DateTime harvestDate,
    required String batchNumber,
    String? variety,
    String? storageLocation,
    String? notes,
  }) async {
    final isOnline = await ConnectivityService.instance.checkConnectivity();

    if (!isOnline) {
      final localId = await HiveService.savePendingHarvest({
        'crop_id': cropId,
        'crop_name': cropName,
        'crop_category': cropCategory,
        'quantity_kg': quantityKg,
        'harvest_date': harvestDate.toIso8601String().split('T').first,
        'batch_number': batchNumber,
        'variety': variety,
        'storage_location': storageLocation,
        'notes': notes,
      });

      // Locally-constructed, unsynced representation — shown immediately
      // so the farmer gets real confirmation, not just a vague promise.
      return HarvestModel(
        id: localId,
        farmerId: _userId,
        cropId: cropId,
        cropName: cropName,
        cropCategory: cropCategory,
        quantityKg: quantityKg,
        variety: variety,
        batchNumber: batchNumber,
        storageLocation: storageLocation,
        notes: notes,
        harvestDate: harvestDate,
        isSynced: false,
        submittedToCooperative: false,
        createdAt: DateTime.now(),
      );
    }

    return _submitOnline(
      cropId: cropId,
      cropName: cropName,
      cropCategory: cropCategory,
      quantityKg: quantityKg,
      harvestDate: harvestDate,
      batchNumber: batchNumber,
      variety: variety,
      storageLocation: storageLocation,
      notes: notes,
    );
  }

  /// Performs the real harvest_records + inventory_batches writes against
  /// Supabase. Shared by the immediate online path above and by
  /// SyncService's replay of queued offline submissions, so the two paths
  /// can never drift apart.
  Future<HarvestModel> _submitOnline({
    required String cropId,
    required String cropName,
    required String cropCategory,
    required double quantityKg,
    required DateTime harvestDate,
    required String batchNumber,
    String? variety,
    String? storageLocation,
    String? notes,
  }) async {
    final harvestResponse = await _client
        .from('harvest_records')
        .insert({
          'farmer_id': _userId,
          'crop_id': cropId,
          'crop_name': cropName,
          'crop_category': cropCategory,
          'quantity_kg': quantityKg,
          'harvest_date': harvestDate.toIso8601String().split('T').first,
          'batch_number': batchNumber,
          'variety': variety,
          'storage_location': storageLocation,
          'notes': notes,
          'is_synced': true,
        })
        .select()
        .single();

    final harvest = HarvestModel.fromMap(harvestResponse);

    // Look up cooperative eligibility once, at harvest time, via the crop's
    // catalog link — denormalized onto the batch so Inventory never needs
    // to join through farmer_crops → crop_master at render time.
    bool isCoopEligible = false;
    try {
      final cropRow = await _client
          .from('farmer_crops')
          .select('crop_master_id')
          .eq('id', cropId)
          .single();
      final cropMasterId = cropRow['crop_master_id'] as String?;
      if (cropMasterId != null) {
        final catalogRow = await _client
            .from('crop_master')
            .select('is_cooperative_eligible')
            .eq('id', cropMasterId)
            .single();
        isCoopEligible = catalogRow['is_cooperative_eligible'] as bool? ?? false;
      }
    } catch (_) {
      // Unlinked or unresolved crop — defaults to not eligible, matches
      // the "pending approval crops can't yet be offered to the coop" rule.
    }

    // Auto-create inventory batch — required for this harvest to ever be
    // usable (listed, offered to the cooperative, or informally sold).
    // If this insert fails, the harvest_records row is rolled back rather
    // than left orphaned with no way for the farmer to recover it.
    try {
      await _client.from('inventory_batches').insert({
        'farmer_id': _userId,
        'harvest_record_id': harvest.id,
        'crop_id': cropId,
        'crop_name': cropName,
        'batch_number': batchNumber,
        'quantity_kg': quantityKg,
        'available_kg': quantityKg,
        'reserved_kg': 0,
        'sold_kg': 0,
        'status': 'available',
        'is_coop_eligible': isCoopEligible,
      });
    } catch (e) {
      try {
        await _client.from('harvest_records').delete().eq('id', harvest.id);
      } catch (_) {
        // Best-effort compensating rollback — if this also fails, the
        // exception thrown below is still what reaches the caller.
      }
      throw Exception(
          'Failed to create an inventory batch for this harvest. Nothing was saved — please try again.');
    }

    return harvest;
  }

  /// Called only by SyncService, to replay one queued offline submission
  /// once connectivity returns.
  Future<HarvestModel> submitQueuedHarvest(Map<dynamic, dynamic> payload) {
    return _submitOnline(
      cropId: payload['crop_id'] as String,
      cropName: payload['crop_name'] as String,
      cropCategory: payload['crop_category'] as String? ?? 'Other',
      quantityKg: (payload['quantity_kg'] as num).toDouble(),
      harvestDate: DateTime.parse(payload['harvest_date'] as String),
      batchNumber: payload['batch_number'] as String,
      variety: payload['variety'] as String?,
      storageLocation: payload['storage_location'] as String?,
      notes: payload['notes'] as String?,
    );
  }
}
