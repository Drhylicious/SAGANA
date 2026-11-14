import 'package:supabase_flutter/supabase_flutter.dart';

/// One stock-in of a tracked cooperative inventory item (cooperative_stock_lots):
/// Harvested Produce counts down its Shelf Life, Planting Materials their
/// Storage Life. Each lot has its own end date.
class CoopStockLot {
  final String id;
  final String inventoryId;
  final String unit;
  final double quantity;
  final double remaining;
  final double rottenQuantity;
  final DateTime startsOn;
  final DateTime expiresOn;

  const CoopStockLot({
    required this.id,
    required this.inventoryId,
    required this.unit,
    required this.quantity,
    required this.remaining,
    required this.rottenQuantity,
    required this.startsOn,
    required this.expiresOn,
  });

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Whole days until the end date (0 = ends today, negative = past).
  int daysLeft([DateTime? now]) =>
      _day(expiresOn).difference(_day(now ?? DateTime.now())).inDays;

  factory CoopStockLot.fromMap(Map<String, dynamic> m) => CoopStockLot(
    id: m['id'] as String,
    inventoryId: m['inventory_id'] as String,
    unit: m['unit'] as String? ?? '',
    quantity: (m['quantity'] as num? ?? 0).toDouble(),
    remaining: (m['remaining'] as num? ?? 0).toDouble(),
    rottenQuantity: (m['rotten_quantity'] as num? ?? 0).toDouble(),
    startsOn: DateTime.parse(m['starts_on'] as String),
    expiresOn: DateTime.parse(m['expires_on'] as String),
  );
}

/// Where a tracked item stands, from its lots.
enum CoopShelfState {
  /// Not a tracked item, or it has no lot yet.
  none,

  /// Its earliest lot still has more than one day left.
  good,

  /// Its earliest lot ends tomorrow: inspect it now.
  needsInspection,

  /// A lot reached its end date without being inspected: the item is
  /// unavailable until Check Produce is done.
  onHold,

  /// Nothing is left and stock was recorded as Rotten/Lost.
  rottenLost,
}

/// The lots of one inventory item and what they mean for the item.
class CoopItemShelfLife {
  final List<CoopStockLot> lots;
  const CoopItemShelfLife(this.lots);

  static const none = CoopItemShelfLife([]);

  /// Lots that still hold stock, the one ending first at the front.
  List<CoopStockLot> get open =>
      lots.where((l) => l.remaining > 0).toList()
        ..sort((a, b) => a.expiresOn.compareTo(b.expiresOn));

  /// The lot Check Produce works on: the one that ends first.
  CoopStockLot? get next => open.isEmpty ? null : open.first;

  double get rottenQuantity =>
      lots.fold<double>(0, (sum, l) => sum + l.rottenQuantity);

  CoopShelfState get state {
    final lot = next;
    if (lot == null) {
      return rottenQuantity > 0
          ? CoopShelfState.rottenLost
          : CoopShelfState.none;
    }
    final left = lot.daysLeft();
    if (left <= 0) return CoopShelfState.onHold;
    if (left == 1) return CoopShelfState.needsInspection;
    return CoopShelfState.good;
  }
}

class CoopShelfLifeRepository {
  final _client = Supabase.instance.client;

  /// Every lot, grouped by inventory item. Empty when the database does not
  /// have the lots yet (the SQL is run by hand): the Inventory screen then
  /// simply shows no shelf-life information.
  Future<Map<String, CoopItemShelfLife>> fetchByItem() async {
    try {
      final rows = await _client
          .from('cooperative_stock_lots')
          .select(
            'id, inventory_id, unit, quantity, remaining, rotten_quantity, starts_on, expires_on',
          )
          .order('expires_on');
      final byItem = <String, List<CoopStockLot>>{};
      for (final r in rows) {
        final lot = CoopStockLot.fromMap(r);
        (byItem[lot.inventoryId] ??= []).add(lot);
      }
      return {
        for (final e in byItem.entries) e.key: CoopItemShelfLife(e.value),
      };
    } catch (_) {
      return {};
    }
  }

  /// Each crop's configured Shelf Life and Storage Life (days), by Crop Master
  /// id. Empty when they cannot be read.
  Future<Map<String, ({int? shelf, int? storage})>> fetchCropLives() async {
    Future<List<Map<String, dynamic>>> read(String cols) =>
        _client.from('crop_master').select(cols);
    try {
      List<Map<String, dynamic>> rows;
      try {
        rows = await read('id, shelf_life_days, storage_life_days');
      } on PostgrestException {
        // A database without the Storage Life column yet.
        rows = await read('id, shelf_life_days');
      }
      return {
        for (final r in rows)
          r['id'] as String: (
            shelf: (r['shelf_life_days'] as num?)?.toInt(),
            storage: (r['storage_life_days'] as num?)?.toInt(),
          ),
      };
    } catch (_) {
      return {};
    }
  }

  /// Sends the inspection notices that are due. Safe to call often; errors are
  /// ignored (the daily schedule does the same work).
  Future<void> process() async {
    try {
      await _client.rpc('process_cooperative_shelf_life');
    } catch (_) {}
  }

  /// Still good: the lot gets [days] more days from today. Throws when refused.
  Future<void> confirmStillGood(String lotId, int days) async {
    await _client.rpc(
      'confirm_coop_lot_still_good',
      params: {'p_lot_id': lotId, 'p_days': days},
    );
  }

  /// Rotten/Lost: [quantity] leaves the stock. Throws when refused.
  Future<void> reportRotten(
    String lotId,
    double quantity, {
    String? note,
  }) async {
    await _client.rpc(
      'report_coop_lot_rotten',
      params: {
        'p_lot_id': lotId,
        'p_quantity': quantity,
        'p_note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      },
    );
  }
}
