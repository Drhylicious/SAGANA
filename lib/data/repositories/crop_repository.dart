import 'dart:typed_data';
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

class CropRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  // ─── Fetch all crops with harvest count ───────────────────────────────────

  Future<List<FarmerCropModel>> fetchCrops({bool approvedOnly = false}) async {
    try {
      var query = _client
          .from('farmer_crops')
          .select(
            '*, harvest_records(count), crop_requests(status, admin_notes), crop_master(image_url, crop_type)',
          )
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
        final catalogMaster = row['crop_master'];
        final catalogImageUrl = catalogMaster is Map
            ? catalogMaster['image_url'] as String?
            : null;
        final catalogCropType = catalogMaster is Map
            ? catalogMaster['crop_type'] as String?
            : null;
        return FarmerCropModel.fromMap({
          ...row,
          'harvest_count': count,
          'request_status': requestStatus,
          'request_notes': requestNotes,
          'catalog_image_url': catalogImageUrl,
          'crop_type': catalogCropType,
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

  // ─── Request photo upload ───────────────────────────────────────────────
  // Same owner-folder upload idiom as Admin's uploadCropImage() /
  // uploadInventoryImage() (crop_management_screen.dart,
  // admin_inventory_screen.dart), against the same 'crop_images' bucket —
  // its RLS policy checks auth.uid() against the folder name, not role,
  // so any authenticated farmer can write to their own uid folder here.
  // This is the farmer's reference photo for a pending request, separate
  // from the crop_master.image_url an admin sets once approved.

  Future<String?> uploadCropRequestPhoto(
    Uint8List bytes,
    String fileExtension,
  ) async {
    try {
      final path =
          '$_userId/request_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      await _client.storage
          .from('crop_images')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      return _client.storage.from('crop_images').getPublicUrl(path);
    } catch (_) {
      return null;
    }
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
    String? photoUrl,
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
      'photo_url': photoUrl,
      'status': 'pending',
    });

    AppEventService.instance.notifyCropRequestSubmitted();

    return FarmerCropModel.fromMap({...cropResponse, 'harvest_count': 0});
  }

  // deleteCrop() / fetchCropDeleteImpact() removed — Crop Roster no longer
  // offers a Delete Crop action (same rationale as Manage Inventory's
  // removed deleteBatch(): a crop can carry real harvest/inventory/sales
  // history; historical records are preserved, not deletable). Replaced by
  // Edit Crop, which only ever touches photo_url below.

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

  // ─── Edit Crop: photo only ─────────────────────────────────────────────
  // Crop Name / Category / Market Type are locked in the UI (admin-owned
  // via crop_master / the approval flow) — the only thing Edit Crop can
  // change is the farmer's own reference photo for their planting. Same
  // owner-folder upload idiom as uploadCropRequestPhoto() above, against
  // the same 'crop_images' bucket.

  Future<String?> uploadCropPhoto(Uint8List bytes, String fileExtension) async {
    try {
      final path =
          '$_userId/crop_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      await _client.storage
          .from('crop_images')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
      );
      return _client.storage.from('crop_images').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateCropPhoto(
    String cropId,
    String cropName,
    String photoUrl,
  ) async {
    try {
      await _client
          .from('farmer_crops')
          .update({'photo_url': photoUrl})
          .eq('id', cropId)
          .eq('farmer_id', _userId);
      // Recent Activity — same pattern as FarmerProfileRepository's own
      // activity logging: a logging failure must never fail the save
      // itself, since farmer_crops already carries the real update.
      try {
        await _client.from('farmer_crop_activity').insert({
          'farmer_id': _userId,
          'crop_id': cropId,
          'description': 'Updated photo for $cropName',
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
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
// ─── Admin: read a farmer's own crops (for Harvest History's View Details
// image, mirrored from the farmer-side screen) ─────────────────────────────

extension CropsForFarmer on CropRepository {
  /// Same photo-then-catalog-image resolution as fetchCrops(), scoped to an
  /// arbitrary farmerId rather than the current session — read-only, for
  /// Admin viewing a farmer's own Harvest History. Relies on the existing
  /// "farmer_crops: admin reads all" RLS policy.
  Future<Map<String, FarmerCropModel>> fetchCropsByIdForFarmer(
    String farmerId,
  ) async {
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('farmer_crops')
          .select('*, crop_master(image_url, crop_type)')
          .eq('farmer_id', farmerId);
      final map = <String, FarmerCropModel>{};
      for (final row in response) {
        final catalogMaster = row['crop_master'];
        final catalogImageUrl = catalogMaster is Map
            ? catalogMaster['image_url'] as String?
            : null;
        final catalogCropType = catalogMaster is Map
            ? catalogMaster['crop_type'] as String?
            : null;
        final crop = FarmerCropModel.fromMap({
          ...row,
          'harvest_count': 0,
          'catalog_image_url': catalogImageUrl,
          'crop_type': catalogCropType,
        });
        map[crop.id] = crop;
      }
      return map;
    } catch (_) {
      return {};
    }
  }
}
