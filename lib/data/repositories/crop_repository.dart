import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_crop_model.dart';
import '../services/app_event_service.dart';
import '../services/hive_service.dart';
import '../../core/utils/client_id.dart';
import '../services/offline_actions.dart';
import '../services/offline_cache.dart';
import 'harvest_repository.dart';
import '../models/activity_text.dart';
import '../models/admin_log_message.dart';

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
      // [master] is the crop_master embed. The shelf life is asked for first;
      // a database that does not have that column yet (the shelf-life SQL is
      // run by hand) is read again without it, so the list still loads.
      Future<List<Map<String, dynamic>>> read(String master) {
        return _client
            .from('farmer_crops')
            .select(
              '*, harvest_records(count), crop_requests(status, admin_notes), crop_master($master)',
            )
            .eq('farmer_id', _userId)
            .order('created_at', ascending: false);
      }

      // One saved copy for both the Crop Roster and the harvest screens. The
      // approved-only list used to be saved separately, and only when a harvest
      // screen was opened online; offline it came back empty, so an approved
      // crop looked "still awaiting approval" and no harvest could be recorded.
      final all = await OfflineCache.load(
        screen: 'farmer_crops',
        fetch: () async {
          try {
            return await read('crop_type, exclusive_channel, shelf_life_days');
          } on PostgrestException {
            return await read('crop_type, exclusive_channel');
          }
        },
      );

      // Approved = linked to the cooperative catalog (the same rule the server
      // filter applied).
      // Crops added or requested offline show at once, ahead of their sync.
      final known = {for (final row in all) row['id']};
      final withQueued = [
        for (final row in _queuedCropRows())
          if (!known.contains(row['id'])) row,
        ...all,
      ];
      final response = approvedOnly
          ? withQueued.where((row) => row['crop_master_id'] != null).toList()
          : withQueued;

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
        final catalogCropType = catalogMaster is Map
            ? catalogMaster['crop_type'] as String?
            : null;
        final catalogExclusiveChannel = catalogMaster is Map
            ? catalogMaster['exclusive_channel'] as String?
            : null;
        return FarmerCropModel.fromMap({
          ...row,
          'harvest_count': count,
          'request_status': requestStatus,
          'request_notes': requestNotes,
          'crop_type': catalogCropType,
          'exclusive_channel': catalogExclusiveChannel,
          'shelf_life_days': catalogMaster is Map
              ? catalogMaster['shelf_life_days']
              : null,
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Fetch active catalog (for "Add Crop" / catalog matching) ─────────────

  Future<List<Map<String, dynamic>>> fetchCropCatalog() async {
    const columns =
        'id, crop_name, category, crop_type, exclusive_channel, image_url';
    try {
      // Only crops whose shelf life is set: a crop without one is not ready
      // for Farmers until the Manager sets it in Crop Management. The shelf
      // life is read too, to show it on the list (never the Storage Life,
      // which is the cooperative's own).
      final response = await _client
          .from('crop_master')
          .select('$columns, shelf_life_days')
          .eq('is_active', true)
          .not('shelf_life_days', 'is', null)
          .order('sort_order');
      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      // A database without the shelf-life column yet: the full catalog.
      if (!e.message.contains('shelf_life_days')) return [];
      try {
        final response = await _client
            .from('crop_master')
            .select(columns)
            .eq('is_active', true)
            .order('sort_order');
        return List<Map<String, dynamic>>.from(response);
      } catch (_) {
        return [];
      }
    } catch (_) {
      return [];
    }
  }

  // ─── Add crop from catalog (instant — already Admin-approved) ─────────────
  //
  // Works offline: the crop is kept on this device with its final id and sent
  // on the next sync, so a harvest recorded for it offline points at the same
  // crop once both have synced.

  Future<FarmerCropModel> addCrop({
    required String cropName,
    required String category,
    required String cropMasterId,
  }) async {
    final id = newClientId();
    final createdAt = DateTime.now().toIso8601String();
    FarmerCropModel? saved;
    await OfflineActions.run(
      kind: 'crop_add',
      payload: {
        'id': id,
        'cropName': cropName.trim(),
        'category': category,
        'cropMasterId': cropMasterId,
        'createdAt': createdAt,
      },
      online: () async {
        saved = await addCropOnline(
          id: id,
          cropName: cropName,
          category: category,
          cropMasterId: cropMasterId,
        );
      },
    );
    return saved ??
        FarmerCropModel.fromMap(
          _queuedCropRow(
            id: id,
            cropName: cropName.trim(),
            category: category,
            cropMasterId: cropMasterId,
            createdAt: createdAt,
          ),
        );
  }

  Future<FarmerCropModel> addCropOnline({
    required String id,
    required String cropName,
    required String category,
    required String cropMasterId,
  }) async {
    try {
      final response = await _client
          .from('farmer_crops')
          .insert({
            'id': id,
            'farmer_id': _userId,
            'crop_name': cropName.trim(),
            'category': category,
            'crop_master_id': cropMasterId,
          })
          .select()
          .single();
      return FarmerCropModel.fromMap({...response, 'harvest_count': 0});
    } on PostgrestException catch (e) {
      // A replay of a crop that already reached the server is not an error.
      if (e.code == '23505') {
        final existing = await _client
            .from('farmer_crops')
            .select()
            .eq('id', id)
            .maybeSingle();
        if (existing != null) {
          return FarmerCropModel.fromMap({...existing, 'harvest_count': 0});
        }
      }
      rethrow;
    }
  }

  /// The row shape [fetchCrops] reads, for a crop still waiting to sync.
  Map<String, dynamic> _queuedCropRow({
    required String id,
    required String cropName,
    required String category,
    required String? cropMasterId,
    required String createdAt,
  }) => {
    'id': id,
    'farmer_id': _userId,
    'crop_name': cropName,
    'category': category,
    'crop_master_id': cropMasterId,
    'created_at': createdAt,
    'harvest_records': const [],
    'crop_requests': cropMasterId == null
        ? const [
            {'status': 'pending', 'admin_notes': null},
          ]
        : const [],
    'crop_master': null,
  };

  /// Crops added or requested offline that have not synced yet.
  List<Map<String, dynamic>> _queuedCropRows() {
    try {
      return [
        for (final entry in HiveService.getOfflineActions())
          if (entry.value['kind'] == 'crop_add' ||
              entry.value['kind'] == 'crop_request')
            _queuedCropRow(
              id: (entry.value['payload'] as Map)['id'] as String,
              cropName: (entry.value['payload'] as Map)['cropName'] as String,
              category: (entry.value['payload'] as Map)['category'] as String,
              cropMasterId:
                  (entry.value['payload'] as Map)['cropMasterId'] as String?,
              createdAt:
                  (entry.value['payload'] as Map)['createdAt'] as String,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  // ─── Request a new crop (not yet in the catalog) ───────────────────────────
  // A request is just Crop Name, Category and Market Type: no photo, and it
  // never inherits an image. The Farmer adds a camera photo of their own crop in
  // Crop Roster whenever they like.
  // Creates the farmer_crops row immediately with crop_master_id left null
  // (isPendingApproval == true) so the farmer can see and manage it right
  // away — but it stays unusable for recording a harvest until an admin
  // approves the request. That gate is enforced client-side, in
  // select_crop_screen.dart, crop_details_screen.dart, and
  // harvest_entry_form_screen.dart. Admin approval later backfills
  // crop_master_id via the Crop Request Approval workflow.
  //
  // Works offline: the request is kept on this device and sent on the next
  // sync, where the same name checks run on the server.

  Future<FarmerCropModel> requestNewCrop({
    required String cropName,
    required String category,
    String? cropType,
    int? shelfLifeDays,
  }) async {
    final trimmedName = cropName.trim();
    final id = newClientId();
    final createdAt = DateTime.now().toIso8601String();
    FarmerCropModel? saved;
    final outcome = await OfflineActions.run(
      kind: 'crop_request',
      payload: {
        'id': id,
        'cropName': trimmedName,
        'category': category,
        'cropMasterId': null,
        'cropType': cropType,
        'shelfLifeDays': shelfLifeDays,
        'createdAt': createdAt,
      },
      online: () async {
        saved = await requestNewCropOnline(
          id: id,
          cropName: trimmedName,
          category: category,
          cropType: cropType,
          shelfLifeDays: shelfLifeDays,
        );
      },
    );
    if (outcome == SaveOutcome.saved) {
      AppEventService.instance.notifyCropRequestSubmitted();
    }
    return saved ??
        FarmerCropModel.fromMap(
          _queuedCropRow(
            id: id,
            cropName: trimmedName,
            category: category,
            cropMasterId: null,
            createdAt: createdAt,
          ),
        );
  }

  Future<FarmerCropModel> requestNewCropOnline({
    required String id,
    required String cropName,
    required String category,
    String? cropType,
    int? shelfLifeDays,
  }) async {
    final trimmedName = cropName.trim();

    // A replay that already created the crop row continues from there.
    var cropResponse = await _client
        .from('farmer_crops')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (cropResponse == null) {
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

      cropResponse = await _client
          .from('farmer_crops')
          .insert({
            'id': id,
            'farmer_id': _userId,
            'crop_name': trimmedName,
            'category': category,
            'crop_master_id': null,
          })
          .select()
          .single();
    }

    final alreadyRequested = await _client
        .from('crop_requests')
        .select('id')
        .eq('farmer_crop_id', id)
        .limit(1);
    if (alreadyRequested.isEmpty) {
      final request = {
        'farmer_id': _userId,
        'farmer_crop_id': id,
        'requested_name': trimmedName,
        'category': category,
        'crop_type': cropType,
        'status': 'pending',
      };
      // The Farmer's own shelf-life figure travels with the request and
      // becomes the crop's shelf life when it is approved. A database that
      // does not have the column yet still takes the request, without it.
      try {
        await _client.from('crop_requests').insert({
          ...request,
          if (shelfLifeDays != null) 'shelf_life_days': shelfLifeDays,
        });
      } on PostgrestException catch (e) {
        final missingColumn =
            shelfLifeDays != null &&
            (e.code == 'PGRST204' ||
                e.code == '42703' ||
                e.message.contains('shelf_life_days'));
        if (!missingColumn) rethrow;
        await _client.from('crop_requests').insert(request);
      }
    }

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
  // owner-folder upload idiom as Admin's crop image upload, against
  // the same 'crop_images' bucket.

  /// Uploads a new crop photo and saves it on the crop. Offline, the photo is
  /// kept on this device and uploaded by the next manual Sync.
  Future<PhotoSaveResult> setCropPhoto({
    required Uint8List bytes,
    required String fileExtension,
    required String cropId,
    required String cropName,
  }) async {
    try {
      final outcome = await OfflineActions.run(
        kind: 'crop_photo',
        payload: {
          'bytes': bytes,
          'fileExtension': fileExtension,
          'cropId': cropId,
          'cropName': cropName,
        },
        online: () => setCropPhotoOnline(
          bytes: bytes,
          fileExtension: fileExtension,
          cropId: cropId,
          cropName: cropName,
        ),
      );
      return PhotoSaveResult(outcome: outcome);
    } catch (_) {
      return const PhotoSaveResult.failed();
    }
  }

  /// Uploads the photo, then saves its URL on the crop. Throws on failure, so
  /// a queued photo that is rejected keeps its reason. Also run by offline
  /// replay.
  Future<void> setCropPhotoOnline({
    required Uint8List bytes,
    required String fileExtension,
    required String cropId,
    required String cropName,
  }) async {
    final url = await uploadCropPhoto(
      bytes,
      fileExtension,
      throwOnFailure: true,
    );
    if (url == null) throw Exception('Photo upload failed.');
    final saved = await updateCropPhoto(
      cropId,
      cropName,
      url,
      throwOnFailure: true,
    );
    if (!saved) throw Exception('Could not save the crop photo.');
  }

  Future<String?> uploadCropPhoto(
    Uint8List bytes,
    String fileExtension, {
    bool throwOnFailure = false,
  }) async {
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
      if (throwOnFailure) rethrow;
      return null;
    }
  }

  /// The crop's current photo url (null when it has none).
  Future<String?> fetchCropPhotoUrl(String cropId) async {
    try {
      final row = await _client
          .from('farmer_crops')
          .select('photo_url')
          .eq('id', cropId)
          .eq('farmer_id', _userId)
          .maybeSingle();
      final url = row?['photo_url'] as String?;
      return (url != null && url.isNotEmpty) ? url : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateCropPhoto(
    String cropId,
    String cropName,
    String photoUrl, {
    bool throwOnFailure = false,
  }) async {
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
          ...activityRowFields(
            AdminLogMessage('activityCropPhotoUpdated', {'crop': cropName}),
          ),
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
      return true;
    } catch (_) {
      if (throwOnFailure) rethrow;
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
          .eq('source_type', 'self')
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
  /// Same photo resolution as fetchCrops() (the Farmer's own photo only), scoped to an

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
          .select('*, crop_master(crop_type, exclusive_channel)')
          .eq('farmer_id', farmerId);
      final map = <String, FarmerCropModel>{};
      for (final row in response) {
        final catalogMaster = row['crop_master'];
        final catalogCropType = catalogMaster is Map
            ? catalogMaster['crop_type'] as String?
            : null;
        final catalogExclusiveChannel = catalogMaster is Map
            ? catalogMaster['exclusive_channel'] as String?
            : null;
        final crop = FarmerCropModel.fromMap({
          ...row,
          'harvest_count': 0,
          'crop_type': catalogCropType,
          'exclusive_channel': catalogExclusiveChannel,
        });
        map[crop.id] = crop;
      }
      return map;
    } catch (_) {
      return {};
    }
  }
}
