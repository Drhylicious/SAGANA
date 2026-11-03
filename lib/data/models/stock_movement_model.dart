import '../../core/utils/quantity_utils.dart';

/// One row of a harvest batch's stock history (stock_movements).
///
/// The database writes a row whenever a batch's figures change, so the history
/// is complete for every selling channel. [quantity] is always the positive size
/// of the move; the type says which way it went:
///   harvested      the batch was recorded (or its opening balance)
///   reserved       available -> reserved (listing, offer, DA-AMAD request)
///   released       reserved -> available (cancelled, declined, withdrawn, closed)
///   sold           reserved -> sold (a confirmed completion only)
///   sale_reversed  a sale record was removed or corrected
///   adjusted       taken out by the Farmer's Update Quantity
///   adjustment_reversed / quantity_changed   corrections
class StockMovementModel {
  final String id;
  final String batchId;
  final String movementType;

  /// marketplace | cooperative_offer | informal_sale | market_linking, or null
  /// for the harvest itself and manual adjustments.
  final String? channel;
  final String? referenceType;
  final String? referenceId;
  final double quantity;
  final String unit;
  final double availableAfter;
  final double reservedAfter;
  final double soldAfter;
  final double adjustedAfter;
  final String? note;
  final DateTime createdAt;

  const StockMovementModel({
    required this.id,
    required this.batchId,
    required this.movementType,
    this.channel,
    this.referenceType,
    this.referenceId,
    required this.quantity,
    this.unit = kDefaultUnit,
    required this.availableAfter,
    required this.reservedAfter,
    required this.soldAfter,
    this.adjustedAfter = 0,
    this.note,
    required this.createdAt,
  });

  /// Columns every history query selects.
  static const String selectColumns =
      'id, batch_id, movement_type, channel, reference_type, reference_id, '
      'quantity, unit, available_after, reserved_after, sold_after, '
      'adjusted_after, note, created_at';

  factory StockMovementModel.fromMap(Map<String, dynamic> map) {
    double n(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return StockMovementModel(
      id: map['id'] as String,
      batchId: map['batch_id'] as String,
      movementType: map['movement_type'] as String,
      channel: map['channel'] as String?,
      referenceType: map['reference_type'] as String?,
      referenceId: map['reference_id'] as String?,
      quantity: n(map['quantity']),
      unit: unitOrDefault(map['unit'] as String?),
      availableAfter: n(map['available_after']),
      reservedAfter: n(map['reserved_after']),
      soldAfter: n(map['sold_after']),
      adjustedAfter: n(map['adjusted_after']),
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }
}
