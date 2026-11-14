import '../services/offline_actions.dart'
    show isOfflineConnectionFailure, OfflineActionBlocked;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/client_id.dart';
import '../../core/utils/quantity_utils.dart';
import '../models/harvest_model.dart';
import '../services/connectivity_service.dart';
import '../services/hive_service.dart';

class HarvestEntryRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  /// Records a harvest.
  ///
  /// The batch number is NOT chosen here: the database issues it when the
  /// harvest row is saved (BATCH-CROP-YYMMDD-X0001, see
  /// supabase_schema_harvest_batch_number_and_units.sql). A harvest saved
  /// offline therefore has no number until it syncs; the returned model's
  /// [HarvestModel.batchNumber] is null in that case.
  ///
  /// [quantityKg] is the quantity in [unit] (the name is historical).
  Future<HarvestModel> submitHarvest({
    required String cropId,
    required String cropName,
    required String cropCategory,
    required double quantityKg,
    required String unit,
    required DateTime harvestDate,
    String? variety,
    String? storageLocation,
  }) async {
    // Database key for this harvest. Kept with the queued record so a replay
    // that finds the row already on the server is recognized, not duplicated.
    final clientId = newClientId();
    final owner = _userId;
    final isOnline = await ConnectivityService.instance.checkConnectivity();

    Future<HarvestModel> queueLocally() async {
      if (HiveService.getUserId() != owner ||
          _client.auth.currentUser?.id != owner) {
        throw const OfflineActionBlocked();
      }
      final localId = await HiveService.savePendingHarvest({
        'client_id': clientId,
        'crop_id': cropId,
        'crop_name': cropName,
        'crop_category': cropCategory,
        'quantity_kg': quantityKg,
        'unit': unit,
        'harvest_date': harvestDate.toIso8601String().split('T').first,
        'variety': variety,
        'storage_location': storageLocation,
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
        unit: unit,
        variety: variety,
        batchNumber: null,
        storageLocation: storageLocation,
        harvestDate: harvestDate,
        isSynced: false,
        createdAt: DateTime.now(),
      );
    }

    if (!isOnline) return queueLocally();
    try {
      return await _submitOnline(
        clientId: clientId,
        cropId: cropId,
        cropName: cropName,
        cropCategory: cropCategory,
        quantityKg: quantityKg,
        unit: unit,
        harvestDate: harvestDate,
        variety: variety,
        storageLocation: storageLocation,
      );
    } catch (error) {
      if (!isOfflineConnectionFailure(error) &&
          !(error is PostgrestException && error.code == '23505')) {
        rethrow;
      }
      return queueLocally();
    }
  }

  /// Performs the real harvest_records + inventory_batches writes against
  /// Supabase. Shared by the immediate online path above and by
  /// SyncService's replay of queued offline submissions, so the two paths
  /// can never drift apart.
  ///
  /// [clientId] is the row's primary key. If a row with that id already exists
  /// (an earlier replay inserted it before failing), it is reused, so the
  /// harvest is never recorded twice.
  Future<HarvestModel> _submitOnline({
    required String clientId,
    required String cropId,
    required String cropName,
    required String cropCategory,
    required double quantityKg,
    required String unit,
    required DateTime harvestDate,
    String? variety,
    String? storageLocation,
  }) async {
    // The quantity is checked again here, not only in the form: a queued
    // offline record is replayed through this path too. The database refuses
    // zero and negative values as well; this keeps the message readable.
    if (quantityKg.isNaN || quantityKg <= 0 || quantityKg > kMaxQuantity) {
      throw Exception('The harvest quantity must be greater than 0.');
    }
    final quantity = roundQuantity(quantityKg);

    var harvestRow = await _client
        .from('harvest_records')
        .select()
        .eq('id', clientId)
        .maybeSingle();
    final createdHere = harvestRow == null;

    // No batch_number is sent: the database issues it (and ignores a value
    // sent by anyone). The row comes back with the number it was given.
    harvestRow ??= await _client
        .from('harvest_records')
        .insert({
          'id': clientId,
          'farmer_id': _userId,
          'crop_id': cropId,
          'crop_name': cropName,
          'crop_category': cropCategory,
          'quantity_kg': quantity,
          'unit': unit,
          'harvest_date': harvestDate.toIso8601String().split('T').first,
          'variety': variety,
          'storage_location': storageLocation,
          'is_synced': true,
        })
        .select()
        .single();

    final harvest = HarvestModel.fromMap(harvestRow);

    // Look up cooperative eligibility and market type once, at harvest
    // time, via the crop's catalog link — denormalized onto the batch so
    // Inventory (and every downstream disposal path) never needs to join
    // through farmer_crops → crop_master at render time.
    bool isCoopEligible = false;
    String? cropType;
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
            .select('is_cooperative_eligible, crop_type')
            .eq('id', cropMasterId)
            .single();
        isCoopEligible =
            catalogRow['is_cooperative_eligible'] as bool? ?? false;
        cropType = catalogRow['crop_type'] as String?;
      }
    } catch (error) {
      if (isOfflineConnectionFailure(error)) rethrow;
      // Unlinked or unresolved crop — defaults to not eligible / unknown
      // market type, matches the "pending approval crops can't yet be
      // offered to the coop" rule.
    }

    // Auto-create inventory batch — required for this harvest to ever be
    // usable (listed, offered to the cooperative, or informally sold).
    // A lost response leaves the same harvest/batch identities available for
    // replay. Never delete an existing harvest or an ambiguously committed
    // batch: doing so could also cascade into stock already used elsewhere.
    try {
      final existingBatch = await _client
          .from('inventory_batches')
          .select('id')
          .eq('harvest_record_id', harvest.id)
          .maybeSingle();
      if (existingBatch == null) {
        // The batch takes its number and unit from the harvest row in the
        // database; they are sent here only so the row is complete.
        await _client.from('inventory_batches').insert({
          'id': clientId,
          'farmer_id': _userId,
          'harvest_record_id': harvest.id,
          'crop_id': cropId,
          'crop_name': cropName,
          'batch_number': harvest.batchNumber,
          'unit': harvest.unit,
          'quantity_kg': harvest.quantityKg,
          'available_kg': harvest.quantityKg,
          'reserved_kg': 0,
          'sold_kg': 0,
          'status': 'available',
          'is_coop_eligible': isCoopEligible,
          'crop_type': cropType,
        });
      }
    } catch (e) {
      if (isOfflineConnectionFailure(e)) rethrow;
      // Only a confirmed rejection of a newly created batch can roll back
      // this request's new harvest. A uniqueness conflict may be a replay
      // whose first insert succeeded, so preserve it for the next lookup.
      if (createdHere && e is PostgrestException && e.code != '23505') {
        try {
          await _client.from('harvest_records').delete().eq('id', harvest.id);
        } catch (rollbackError) {
          // Keep the stable request identity queued if the rollback's result
          // is unknown, so a later sync can safely complete the record.
          if (isOfflineConnectionFailure(rollbackError)) {
            rethrow;
          }
        }
      }
      rethrow;
    }

    return harvest;
  }

  /// Called only by SyncService, to replay one queued offline submission
  /// once connectivity returns.
  Future<HarvestModel> submitQueuedHarvest(Map<dynamic, dynamic> payload) {
    return _submitOnline(
      // Records queued before client ids existed have none. They get a fresh
      // id, so the duplicate check cannot apply to them.
      clientId: payload['client_id'] as String? ?? newClientId(),
      cropId: payload['crop_id'] as String,
      cropName: payload['crop_name'] as String,
      cropCategory: payload['crop_category'] as String? ?? 'Other',
      quantityKg: (payload['quantity_kg'] as num).toDouble(),
      // Records queued before units existed were all in kg. A client-made
      // 'batch_number' in an old queued record is ignored: the database
      // issues the number.
      unit: unitOrDefault(payload['unit'] as String?),
      harvestDate: DateTime.parse(payload['harvest_date'] as String),
      variety: payload['variety'] as String?,
      storageLocation: payload['storage_location'] as String?,
    );
  }
}
