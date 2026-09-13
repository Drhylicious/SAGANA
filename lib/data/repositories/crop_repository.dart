import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_crop_model.dart';
import '../services/app_event_service.dart';
import 'harvest_repository.dart';

class CropAlreadyExistsException implements Exception {
  final String cropName;
  CropAlreadyExistsException(this.cropName);
}

class CropRequestAlreadyPendingException implements Exception {
  final String cropName;
  CropRequestAlreadyPendingException(this.cropName);
}

/// What deleting a crop would cascade-delete, so the confirmation UI can
/// warn with real numbers instead of a generic message.
class CropDeleteImpact {
  final int harvestCount;
  final int inventoryBatchCount;
  final int soldBatchCount;
  /// True if the impact check itself failed (network, RLS, etc.) — the UI
  /// should treat this as "assume there's data at risk" rather than "safe".
  final bool checkFailed;

  const CropDeleteImpact({
    required this.harvestCount,
    required this.inventoryBatchCount,
    required this.soldBatchCount,
    this.checkFailed = false,
  });

  bool get isRisky => checkFailed || harvestCount > 0 || inventoryBatchCount > 0;
  bool get hasSoldBatches => soldBatchCount > 0;
}

class CropRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  // ─── Fetch all crops with harvest count ───────────────────────────────────

  Future<List<FarmerCropModel>> fetchCrops({bool approvedOnly = false}) async {
    try {
      var query = _client
          .from('farmer_crops')
          .select('*, harvest_records(count), crop_requests(status, admin_notes)')
          .eq('farmer_id', _userId);

      if (approvedOnly) {
        query = query.not('crop_master_id', 'is', null);
      }

      final response = await query.order('created_at', ascending: false);

      return response.map((row) {
        final harvestList = row['harvest_records'] as List?;
        final count = harvestList?.isNotEmpty == true
            ? (harvestList!.first['count'] as int? ?? 0)
            : 0;
        final requestList = row['crop_requests'] as List?;
        final requestStatus = requestList?.isNotEmpty == true
            ? requestList!.first['status'] as String?
            : null;
        final requestNotes = requestList?.isNotEmpty == true
            ? requestList!.first['admin_notes'] as String?
            : null;
        return FarmerCropModel.fromMap({
          ...row,
          'harvest_count': count,
          'request_status': requestStatus,
          'request_notes': requestNotes,
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Fetch active catalog (for "Add Crop" / catalog matching) ─────────────

  Future<List<Map<String, dynamic>>> fetchCropCatalog() async {
    try {
      final response = await _client
          .from('crop_master')
          .select('id, crop_name, category, crop_type, image_url')
          .eq('is_active', true)
          .order('sort_order');
      return List<Map<String, dynamic>>.from(response);
    } catch (_) {
      return [];
    }
  }

  // ─── Add crop from catalog (instant — already Admin-approved) ─────────────

  Future<FarmerCropModel> addCrop({
    required String cropName,
    required String category,
    required String cropMasterId,
  }) async {
    final response = await _client
        .from('farmer_crops')
        .insert({
          'farmer_id': _userId,
          'crop_name': cropName.trim(),
          'category': category,
          'crop_master_id': cropMasterId,
        })
        .select()
        .single();

    return FarmerCropModel.fromMap({...response, 'harvest_count': 0});
  }

  // ─── Request a new crop (not yet in the catalog) ───────────────────────────
  // Creates the farmer_crops row immediately with crop_master_id left null
  // (isPendingApproval == true) so the farmer can see and manage it right
  // away — but it stays unusable for recording a harvest until an admin
  // approves the request. That gate is enforced client-side, in
  // select_crop_screen.dart, crop_details_screen.dart, and
  // harvest_entry_form_screen.dart. Admin approval later backfills
  // crop_master_id via the Crop Request Approval workflow.

  Future<FarmerCropModel> requestNewCrop({
    required String cropName,
    required String category,
    String? cropType,
  }) async {
    final trimmedName = cropName.trim();

    final existingCatalog = await _client
        .from('crop_master')
        .select('id')
        .ilike('crop_name', trimmedName)
        .limit(1);
    if (existingCatalog.isNotEmpty) {
      throw CropAlreadyExistsException(trimmedName);
    }

    final existingPending = await _client
        .from('crop_requests')
        .select('id')
        .ilike('requested_name', trimmedName)
        .eq('status', 'pending')
        .limit(1);
    if (existingPending.isNotEmpty) {
      throw CropRequestAlreadyPendingException(trimmedName);
    }

    // farmer_crops has UNIQUE(farmer_id, crop_name) — without this check,
    // a duplicate name against the farmer's own existing list falls
    // through to a raw Postgres unique-violation instead of the named
    // exception the UI expects to catch.
    final existingOwnCrop = await _client
        .from('farmer_crops')
        .select('id')
        .eq('farmer_id', _userId)
        .ilike('crop_name', trimmedName)
        .limit(1);
    if (existingOwnCrop.isNotEmpty) {
      throw CropAlreadyExistsException(trimmedName);
    }

    final cropResponse = await _client
        .from('farmer_crops')
        .insert({
          'farmer_id': _userId,
          'crop_name': trimmedName,
          'category': category,
          'crop_master_id': null,
        })
        .select()
        .single();

    await _client.from('crop_requests').insert({
      'farmer_id': _userId,
      'farmer_crop_id': cropResponse['id'],
      'requested_name': trimmedName,
      'category': category,
      'crop_type': cropType,
      'status': 'pending',
    });

    AppEventService.instance.notifyCropRequestSubmitted();

    return FarmerCropModel.fromMap({...cropResponse, 'harvest_count': 0});
  }

  // ─── Delete crop ──────────────────────────────────────────────────────────

  Future<void> deleteCrop(String cropId) async {
    await _client
        .from('farmer_crops')
        .delete()
        .eq('id', cropId)
        .eq('farmer_id', _userId);
  }

  // ─── Check if crop has harvests ───────────────────────────────────────────

  Future<bool> cropHasHarvests(String cropId) async {
    try {
      final response = await _client
          .from('harvest_records')
          .select('id')
          .eq('crop_id', cropId)
          .limit(1);
      return response.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ─── Delete-impact check ────────────────────────────────────────────────
  // farmer_crops has ON DELETE CASCADE from harvest_records, inventory_batches,
  // and crop_requests. Deleting a crop silently wipes all of these — this
  // surfaces exact counts so the confirmation dialog can warn honestly
  // instead of a generic "are you sure?".

  Future<CropDeleteImpact> fetchCropDeleteImpact(String cropId) async {
    try {
      final results = await Future.wait([
        _client.from('harvest_records').select('id').eq('crop_id', cropId),
        _client.from('inventory_batches').select('id, status').eq('crop_id', cropId),
      ]);
      final harvestRows = results[0];
      final batchRows = results[1];
      final soldCount = batchRows.where((b) => b['status'] == 'sold_out').length;
      return CropDeleteImpact(
        harvestCount: harvestRows.length,
        inventoryBatchCount: batchRows.length,
        soldBatchCount: soldCount,
      );
    } catch (_) {
      // Fail closed: if we can't verify impact, assume there may be
      // records so the UI shows the cautious warning path.
      return const CropDeleteImpact(
        harvestCount: 0,
        inventoryBatchCount: 0,
        soldBatchCount: 0,
        checkFailed: true,
      );
    }
  }
}

// ─── Harvest Summary per crop (for My Harvest Summary screen) ────────────────

extension CropHarvestSummary on CropRepository {
  /// Returns total_kg harvested per crop_id, keyed by crop id.
  Future<Map<String, double>> fetchTotalKgPerCrop() async {
    final Map<String, double> totals = {};
    try {
      final rows = await _client
          .from('harvest_records')
          .select('crop_id, quantity_kg')
          .eq('farmer_id', _userId);
      for (final row in rows) {
        final id = row['crop_id'] as String;
        totals[id] = (totals[id] ?? 0) + (row['quantity_kg'] as num).toDouble();
      }
    } catch (_) {
      // Falls through to pending-only totals below.
    }
    // Merge in Hive-queued offline harvests, same source HarvestRepository
    // uses everywhere else, so My Harvest Summary matches Home/Harvest Hub
    // even before a queued harvest has synced (Phase 2 / U1).
    for (final h in HarvestRepository().pendingHarvestModels()) {
      totals[h.cropId] = (totals[h.cropId] ?? 0) + h.quantityKg;
    }
    return totals;
  }
}