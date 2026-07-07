import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/harvest_model.dart';

class HarvestEntryRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  Future<HarvestModel> submitHarvest({
    required String cropId,
    required String cropName,
    required String cropCategory,
    required double quantityKg,
    required String qualityGrade,
    required DateTime harvestDate,
    required String batchNumber,
    String? variety,
    String? storageLocation,
    String? notes,
    bool submittedToCooperative = false,
  }) async {
    final harvestResponse = await _client
        .from('harvest_records')
        .insert({
          'farmer_id': _userId,
          'crop_id': cropId,
          'crop_name': cropName,
          'crop_category': cropCategory,
          'quantity_kg': quantityKg,
          'quality_grade': qualityGrade,
          'harvest_date': harvestDate.toIso8601String().split('T').first,
          'batch_number': batchNumber,
          'variety': variety,
          'storage_location': storageLocation,
          'notes': notes,
          'submitted_to_cooperative': submittedToCooperative,
          'is_synced': true,
        })
        .select()
        .single();

    final harvest = HarvestModel.fromMap(harvestResponse);

    // Auto-create inventory batch
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
        'quality_grade': qualityGrade,
        'status': 'available',
      });
    } catch (_) {
      // Inventory batch failure does not block harvest submission
    }

    return harvest;
  }
}
