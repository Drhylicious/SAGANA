import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_crop_model.dart';

class CropRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  // ─── Fetch all crops with harvest count ───────────────────────────────────

  Future<List<FarmerCropModel>> fetchCrops() async {
    try {
      final response = await _client
          .from('farmer_crops')
          .select('*, harvest_records(count)')
          .eq('farmer_id', _userId)
          .order('created_at', ascending: false);

      return response.map((row) {
        final harvestList = row['harvest_records'] as List?;
        final count = harvestList?.isNotEmpty == true
            ? (harvestList!.first['count'] as int? ?? 0)
            : 0;
        return FarmerCropModel.fromMap({...row, 'harvest_count': count});
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Add new crop ─────────────────────────────────────────────────────────

  Future<FarmerCropModel> addCrop({
    required String cropName,
    required String category,
    String? photoUrl,
  }) async {
    final response = await _client
        .from('farmer_crops')
        .insert({
          'farmer_id': _userId,
          'crop_name': cropName.trim(),
          'category': category,
          'photo_url': photoUrl,
        })
        .select()
        .single();

    return FarmerCropModel.fromMap({...response, 'harvest_count': 0});
  }

  // ─── Upload crop image ────────────────────────────────────────────────────

  Future<String?> uploadCropImage({
    required String cropName,
    required Uint8List imageBytes,
    required String fileExtension,
  }) async {
    try {
      final safeName = cropName
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '_');
      final path =
          '$_userId/${safeName}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';

      await _client.storage.from('crop_images').uploadBinary(
            path,
            imageBytes,
            fileOptions: const FileOptions(upsert: true),
          );

      return _client.storage.from('crop_images').getPublicUrl(path);
    } catch (_) {
      return null;
    }
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
}

// ─── Harvest Summary per crop (for My Harvest Summary screen) ────────────────

extension CropHarvestSummary on CropRepository {
  /// Returns total_kg harvested per crop_id, keyed by crop id.
  Future<Map<String, double>> fetchTotalKgPerCrop() async {
    try {
      final rows = await _client
          .from('harvest_records')
          .select('crop_id, quantity_kg')
          .eq('farmer_id', _userId);

      final Map<String, double> totals = {};
      for (final row in rows) {
        final id = row['crop_id'] as String;
        totals[id] = (totals[id] ?? 0) + (row['quantity_kg'] as num).toDouble();
      }
      return totals;
    } catch (_) {
      return {};
    }
  }
}
