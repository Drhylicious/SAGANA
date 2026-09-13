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
    return {
      for (final r in rows) r['id'] as String: r['crop_name'] as String,
    };
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
