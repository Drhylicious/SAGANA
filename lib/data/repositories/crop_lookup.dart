import 'package:supabase_flutter/supabase_flutter.dart';

/// Batch-resolves canonical crop_master.crop_name for a set of crop_master
/// IDs. Deliberately a separate query rather than a PostgREST nested embed
/// (e.g. .select('*, crop_master(crop_name)')) — an embed was tried first
/// and returned a 400 in production, most likely a schema-cache
/// registration issue after the crop_id migration. Rather than depend on
/// PostgREST correctly resolving the FK relationship, this follows the
/// same proven batch-lookup pattern fetchFarmerInfoMap already established
/// in this codebase, which is more robust and easier to debug either way.
///
/// Shared by AdminReportsRepository and AnalyticsRepository — extracted
/// here rather than duplicated per repository.
Future<Map<String, String>> fetchCropNameMap(
  SupabaseClient client,
  List<String> cropIds,
) async {
  if (cropIds.isEmpty) return {};
  try {
    final rows = await client
        .from('crop_master')
        .select('id, crop_name')
        .inFilter('id', cropIds);
    return {for (final r in rows) r['id'] as String: r['crop_name'] as String};
  } catch (_) {
    return {};
  }
}

/// Batch-resolves farmer_crops.id -> crop_master_id, needed specifically
/// for inventory_batches, whose own crop_id column references
/// farmer_crops(id), not crop_master(id) directly (a pre-existing,
/// unrelated column name collision discovered during the crop-id
/// migration). Feed this method's output into fetchCropNameMap for the
/// final crop_master_id -> crop_name step.
Future<Map<String, String>> fetchFarmerCropToCropMasterMap(
  SupabaseClient client,
  List<String> farmerCropIds,
) async {
  if (farmerCropIds.isEmpty) return {};
  try {
    final rows = await client
        .from('farmer_crops')
        .select('id, crop_master_id')
        .inFilter('id', farmerCropIds);
    return {
      for (final r in rows)
        if (r['crop_master_id'] != null)
          r['id'] as String: r['crop_master_id'] as String,
    };
  } catch (_) {
    return {};
  }
}

/// Batch-resolves the display image URL for a set of farmer_crops IDs —
/// the farmer's own crop photo if set, else the crop_master catalog
/// photo, else omitted. Two explicit queries rather than a nested embed
/// (farmer_crops -> crop_master), for the same reason documented on
/// fetchCropNameMap above: an embed through a crop_id-style relationship
/// has previously failed in production here, and this file's established
/// convention is to compose independently-debuggable queries instead.
///
/// Mirrors FarmerCropModel.displayImageUrl's own precedence exactly, so
/// an inventory batch and its originating Crop Roster entry always agree
/// on which photo to show.
/// Batch-resolves crop_master.category for a set of farmer_crops IDs —
/// same farmer_crops -> crop_master_id -> crop_master composition as
/// fetchFarmerCropImageMap above, for the same reason (no nested embed).
/// Phase 11: closes the Create Listing / Submission Success Category gap —
/// inventory_batches carries no category of its own, only crop_master does.
Future<Map<String, String>> fetchFarmerCropCategoryMap(
  SupabaseClient client,
  List<String> farmerCropIds,
) async {
  if (farmerCropIds.isEmpty) return {};
  try {
    final masterIdMap = await fetchFarmerCropToCropMasterMap(
      client,
      farmerCropIds,
    );
    if (masterIdMap.isEmpty) return {};

    final masterRows = await client
        .from('crop_master')
        .select('id, category')
        .inFilter('id', masterIdMap.values.toSet().toList());
    final categoryByMasterId = <String, String>{
      for (final r in masterRows)
        if (r['category'] != null) r['id'] as String: r['category'] as String,
    };

    final result = <String, String>{};
    for (final entry in masterIdMap.entries) {
      final category = categoryByMasterId[entry.value];
      if (category != null) result[entry.key] = category;
    }
    return result;
  } catch (_) {
    return {};
  }
}

Future<Map<String, String>> fetchFarmerCropImageMap(
  SupabaseClient client,
  List<String> farmerCropIds,
) async {
  if (farmerCropIds.isEmpty) return {};
  try {
    final rows = await client
        .from('farmer_crops')
        .select('id, photo_url, crop_master_id')
        .inFilter('id', farmerCropIds);

    final ownPhotoById = <String, String>{};
    final masterIdById = <String, String>{};
    for (final r in rows) {
      final id = r['id'] as String;
      final ownPhoto = r['photo_url'] as String?;
      if (ownPhoto != null && ownPhoto.isNotEmpty) {
        ownPhotoById[id] = ownPhoto;
      } else if (r['crop_master_id'] != null) {
        masterIdById[id] = r['crop_master_id'] as String;
      }
    }

    final masterImageById = <String, String>{};
    if (masterIdById.isNotEmpty) {
      final masterRows = await client
          .from('crop_master')
          .select('id, image_url')
          .inFilter('id', masterIdById.values.toSet().toList());
      for (final r in masterRows) {
        final url = r['image_url'] as String?;
        if (url != null && url.isNotEmpty) {
          masterImageById[r['id'] as String] = url;
        }
      }
    }

    final result = <String, String>{};
    for (final id in farmerCropIds) {
      final own = ownPhotoById[id];
      if (own != null) {
        result[id] = own;
        continue;
      }
      final masterId = masterIdById[id];
      final catalogUrl = masterId != null ? masterImageById[masterId] : null;
      if (catalogUrl != null) result[id] = catalogUrl;
    }
    return result;
  } catch (_) {
    return {};
  }
}
