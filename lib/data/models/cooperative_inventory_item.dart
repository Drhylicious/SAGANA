import '../../core/utils/quantity_utils.dart';

class InventoryItem {
  final String id;
  final String itemName;
  final String category;
  final String unit;
  final double quantityOnHand;
  final double quantityReserved;
  final double reorderLevel;
  final double? unitCost;
  // Where the item came from (supplier, donation, resolution...). Required for
  // every new or edited item; null only on items created before the field
  // existed, which the card shows as "Source not recorded".
  final String? source;
  final bool isActive;
  final DateTime? lastRestockedAt;
  final String? imageUrl;
  final String? sourceFarmerId;
  final String? sourceCropId;
  final DateTime? archivedAt;
  bool get isFarmerHarvest => sourceFarmerId != null;

  const InventoryItem({
    required this.id,
    required this.itemName,
    required this.category,
    required this.unit,
    required this.quantityOnHand,
    required this.quantityReserved,
    required this.reorderLevel,
    this.unitCost,
    this.source,
    required this.isActive,
    this.lastRestockedAt,
    this.imageUrl,
    this.sourceFarmerId,
    this.sourceCropId,
    this.archivedAt,
  });

  double get available => quantityOnHand - quantityReserved;
  bool get isLow => reorderLevel > 0 && quantityOnHand <= reorderLevel;
  bool get isDepleted => quantityOnHand <= 0;

  factory InventoryItem.fromMap(Map<String, dynamic> m) => InventoryItem(
    id: m['id'] as String,
    itemName: m['item_name'] as String,
    category: m['category'] as String? ?? 'Agricultural Supplies',
    unit: m['unit'] as String? ?? 'kg',
    quantityOnHand: (m['quantity_on_hand'] as num?)?.toDouble() ?? 0,
    quantityReserved: (m['quantity_reserved'] as num?)?.toDouble() ?? 0,
    reorderLevel: (m['reorder_level'] as num?)?.toDouble() ?? 0,
    unitCost: m['unit_cost'] != null
        ? (m['unit_cost'] as num).toDouble()
        : null,
    source: (m['source'] as String?)?.trim().isEmpty ?? true
        ? null
        : (m['source'] as String).trim(),
    isActive: m['is_active'] as bool? ?? true,
    lastRestockedAt: m['last_restocked_at'] != null
        ? DateTime.parse(m['last_restocked_at'] as String)
        : null,
    imageUrl: m['image_url'] as String?,
    sourceFarmerId: m['source_farmer_id'] as String?,
    sourceCropId: m['source_crop_id'] as String?,
    archivedAt: DateTime.tryParse(m['archived_at'] as String? ?? ''),
  );
}

/// Crop identity, rather than display name, keeps renamed crops together.
/// Units are kept separate; no implicit conversion is made.
List<CooperativeCropTotal> cooperativeCropTotals(
  Iterable<InventoryItem> items,
) {
  final totals = <String, CooperativeCropTotal>{};
  for (final item in items.where((i) => i.category == 'Harvest Stock')) {
    final cropKey = item.sourceCropId ?? item.itemName.trim().toLowerCase();
    final key = '$cropKey::${item.unit.trim().toLowerCase()}';
    final previous = totals[key];
    totals[key] = CooperativeCropTotal(
      previous?.name ?? item.itemName,
      item.unit,
      roundQuantity((previous?.quantity ?? 0) + item.quantityOnHand),
    );
  }
  return totals.values.toList();
}

class CooperativeCropTotal {
  const CooperativeCropTotal(this.name, this.unit, this.quantity);
  final String name, unit;
  final double quantity;
}
