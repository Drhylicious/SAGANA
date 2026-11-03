class CooperativeHarvestBatch {
  const CooperativeHarvestBatch(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String? get farmerName => data['source_farmer_name'] as String?;
  String? get offerId => data['offer_id'] as String?;
  String? get sourceTransactionId => data['source_transaction_id'] as String?;
  String? get sourceBatchNumber => data['source_batch_number'] as String?;
  String? get storageLocation => data['storage_location'] as String?;
  DateTime? get harvestDate =>
      DateTime.tryParse(data['harvest_date'] as String? ?? '');
  double get originalQuantity => (data['original_quantity'] as num).toDouble();
  String get unit => data['unit'] as String;

  /// A batch that did not come from a completed Farmer offer was added by hand.
  bool get isManualAddition => offerId == null;
}

class CooperativeInventoryEvent {
  CooperativeInventoryEvent.fromMap(Map<String, dynamic> data)
    : id = data['id'] as String,
      action = data['action'] as String,
      occurredAt = DateTime.parse(data['occurred_at'] as String),
      actorName = data['actor_name'] as String?,
      actorId = data['actor_id'] as String?,
      farmerName = data['source_farmer_name'] as String?,
      quantityChange = (data['quantity_change'] as num?)?.toDouble(),
      unit = data['unit'] as String,
      transactionId = data['transaction_id'] as String?,
      referenceId = data['reference_id'] as String?,
      referenceType = data['reference_type'] as String?,
      details = Map<String, dynamic>.from(data['details'] as Map? ?? {}),
      batch = data['batch'] is Map
          ? CooperativeHarvestBatch(
              Map<String, dynamic>.from(data['batch'] as Map),
            )
          : null;

  final String id, action, unit;
  final DateTime occurredAt;
  final String? actorName,
      actorId,
      farmerName,
      transactionId,
      referenceId,
      referenceType;
  final double? quantityChange;
  final Map<String, dynamic> details;
  final CooperativeHarvestBatch? batch;

  /// Stock added through Adjust Stock → Restock (the RPC records it as
  /// `manual`), as opposed to a completed-offer receipt.
  bool get isManualAddition =>
      action == 'restock' && referenceType == 'manual';

  List<String> get changedFields {
    final before = details['before'] as Map? ?? {};
    final after = details['after'] as Map? ?? {};
    return after.keys
        .where((key) => before[key] != after[key])
        .cast<String>()
        .toList();
  }
}
