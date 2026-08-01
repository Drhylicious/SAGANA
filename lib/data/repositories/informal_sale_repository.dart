import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_batch_model.dart';

class InformalSaleRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> recordInformalSale({
    required InventoryBatchModel batch,
    required double quantityKg,
    String? buyerName,
    double? amount,
    String? notes,
  }) async {
    await _client.rpc('record_informal_sale', params: {
      'p_batch_id': batch.id,
      'p_crop_name': batch.cropName,
      'p_quantity_kg': quantityKg,
      'p_buyer_name': buyerName,
      'p_amount': amount,
      'p_notes': notes,
    });
  }
}
