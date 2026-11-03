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

/// The Farmer's own (camera-captured) photo of each crop, by farmer_crops id.
/// A crop without one is simply absent from the map: the Crop Master image is
/// a catalog reference and is never used as a Farmer's photo, so an inventory
/// batch, a listing and its Crop Roster entry always agree on the same photo.
Future<Map<String, String>> fetchFarmerCropImageMap(
  SupabaseClient client,
  List<String> farmerCropIds,
) async {
  if (farmerCropIds.isEmpty) return {};
  try {
    final rows = await client
        .from('farmer_crops')
        .select('id, photo_url')
        .inFilter('id', farmerCropIds);
    return {
      for (final r in rows)
        if ((r['photo_url'] as String?)?.isNotEmpty == true)
          r['id'] as String: r['photo_url'] as String,
    };
  } catch (_) {
    return {};
  }
}

