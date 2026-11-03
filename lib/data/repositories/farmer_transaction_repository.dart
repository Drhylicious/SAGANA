import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_transaction_model.dart';
import '../services/offline_cache.dart';
import '../../core/utils/order_reference.dart';
import '../../core/utils/quantity_utils.dart';
import 'completed_order_dates.dart';

/// Farmer's own completed sales across all 4 selling channels — the data
/// source behind Farmer Transaction History. Each channel query mirrors
/// AdminReportsRepository's equivalent (admin_reports_repository.dart),
/// scoped down to farmer_id = the logged-in farmer instead of every member, and
/// dated the same way, so the Farmer's history and the Manager / Officer Sales
/// Report always agree on which sales exist, their amounts, dates and units.
///
/// Each channel's rows (and the crop photo lookup) are cached through
/// OfflineCache, so the history can still be viewed offline.
class FarmerTransactionRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  Future<List<FarmerTransactionModel>> fetchMyTransactions() async {
    final lookups = await Future.wait([
      _fetchCropImageByName(),
      _fetchCropInfoByName(),
    ]);
    final imageByCropName = lookups[0] as Map<String, String>;
    final cropInfoByName =
        lookups[1] as Map<String, ({String? marketType, String? category})>;

    final results = await Future.wait([
      _fetchOfferToCoop(imageByCropName),
      _fetchMarketplace(imageByCropName),
      _fetchInformalSales(imageByCropName),
      _fetchMarketLinking(imageByCropName),
    ]);
    final entries = results.expand((list) => list).toList();

    final batchNumbers = await _fetchBatchNumbers({
      for (final e in entries)
        if (e.batchId != null) e.batchId!,
    });

    // One row per sale id, in case a sale is ever reachable from two sources.
    final seen = <String>{};
    final all = <FarmerTransactionModel>[];
    for (final e in entries) {
      if (!seen.add('${e.tx.sellingType}:${e.tx.id}')) continue;
      final info = cropInfoByName[e.tx.cropName.toLowerCase()];
      all.add(
        e.tx.withDetails(
          marketType: info?.marketType,
          cropCategory: info?.category,
          batchNumber: e.batchId == null ? null : batchNumbers[e.batchId],
        ),
      );
    }
    all.sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
    return all;
  }

  // Same shared-image resolution as everywhere else in the app (Crop
  // Roster, Manage Inventory, Harvest History): the farmer's own photo, and
  // nothing else — the Crop Master image is never used for a Farmer's crop.
  // Keyed by crop name (lowercased) since 3 of the 4 source tables below have no direct crop_id/batch_id
  // to join through — only marketplace_listings does, and even that isn't
  // used here, so every channel resolves its image the same way.
  //
  // Two explicit queries rather than a nested embed
  // (farmer_crops -> crop_master(image_url)) — see crop_lookup.dart's
  // fetchFarmerCropImageMap for why: that embed shape has previously
  // returned a 400 in production here (schema-cache registration issue),
  // silently caught by this method's own try/catch, which meant
  // cropImageUrl was unconditionally null for every transaction — the
  // actual cause of both the missing list-tile photos and the missing
  // image in the details sheet, not a rendering bug.
  Future<Map<String, String>> _fetchCropImageByName() async {
    try {
      final entries = await OfflineCache.load(
        screen: 'transactions_crop_images',
        fetch: _loadCropImageEntries,
      );
      return {
        for (final e in entries) e['name'] as String: e['url'] as String,
      };
    } catch (_) {
      return {};
    }
  }

  // Returns [{name, url}] rather than a map so it can be cached as rows.
  Future<List<Map<String, dynamic>>> _loadCropImageEntries() async {
    final rows = await _client
        .from('farmer_crops')
        .select('crop_name, photo_url')
        .eq('farmer_id', _userId);

    return [
      for (final r in rows)
        if ((r['photo_url'] as String?)?.isNotEmpty == true)
          {
            'name': (r['crop_name'] as String).toLowerCase(),
            'url': r['photo_url'] as String,
          },
    ];
  }

  /// Each crop's market type (crop_master.crop_type, a market_types code) and
  /// category, by crop name, exactly as the Manager / Officer reports resolve
  /// them. The market type belongs to the crop, so it is the same on every
  /// selling channel (DA-AMAD Market Linking is a channel, not a market type).
  Future<Map<String, ({String? marketType, String? category})>>
  _fetchCropInfoByName() async {
    try {
      final rows = await OfflineCache.load(
        screen: 'transactions_crop_info',
        fetch: () => _client.from('crop_master').select('crop_name, crop_type, category'),
      );
      return {
        for (final r in rows)
          (r['crop_name'] as String).toLowerCase(): (
            marketType: r['crop_type'] as String?,
            category: r['category'] as String?,
          ),
      };
    } catch (_) {
      return {};
    }
  }

  /// batch id -> batch number, for the harvest batches the sales came from.
  Future<Map<String, String>> _fetchBatchNumbers(Set<String> batchIds) async {
    if (batchIds.isEmpty) return {};
    try {
      final rows = await OfflineCache.load(
        screen: 'transactions_batches',
        fetch: () => _client
            .from('inventory_batches')
            .select('id, batch_number')
            .eq('farmer_id', _userId),
      );
      return {
        for (final r in rows)
          if (batchIds.contains(r['id'] as String) && r['batch_number'] != null)
            r['id'] as String: r['batch_number'] as String,
      };
    } catch (_) {
      return {};
    }
  }

  // The Farmer's offers that were completed (delivery received), with the
  // details that are not on the sale row itself: the agreed price per unit, the
  // Farmer's delivery, and the batch. A sale row exists only once that happened, and each offer
  // links to exactly one sale (member_sales_transaction_id).
  Future<Map<String, Map<String, dynamic>>> _fetchCompletedOffersBySale() async {
    try {
      final rows = await OfflineCache.load(
        screen: 'transactions_coop_offers',
        fetch: () => _client
            .from('cooperative_purchase_offers')
            .select(
              'member_sales_transaction_id, agreed_price_per_kg, received_at, '
              'delivered_at, inventory_batch_id',
            )
            .eq('farmer_id', _userId)
            .eq('status', 'completed')
            .not('member_sales_transaction_id', 'is', null),
      );
      return {
        for (final r in rows) r['member_sales_transaction_id'] as String: r,
      };
    } catch (_) {
      return {};
    }
  }

  // No buyer name — this transaction is directly with the cooperative/
  // Admin side, not an external buyer. The sale row is written when the Manager /
  // Officer confirms the delivery, so every row here is a completed sale.
  Future<List<({FarmerTransactionModel tx, String? batchId})>> _fetchOfferToCoop(
    Map<String, String> imageByCropName,
  ) async {
    try {
      final results = await Future.wait([
        OfflineCache.load(
          screen: 'transactions_offer_to_coop',
          fetch: () => _client
              .from('member_sales_transactions')
              .select(
                'id, crop_name, quantity_kg, unit, amount, sale_date, reference_no',
              )
              .eq('farmer_id', _userId),
        ),
        _fetchCompletedOffersBySale(),
      ]);
      final rows = results[0] as List<Map<String, dynamic>>;
      final offers = results[1] as Map<String, Map<String, dynamic>>;
      return rows.map((r) {
        final offer = offers[r['id'] as String];
        final deliveredAt = DateTime.tryParse(
          offer?['delivered_at'] as String? ?? '',
        )?.toLocal();
        return (
          tx: FarmerTransactionModel(
            id: r['id'] as String,
            sellingType: 'offer_to_cooperative',
            cropName: r['crop_name'] as String,
            quantityKg: (r['quantity_kg'] as num).toDouble(),
            unit: unitOrDefault(r['unit'] as String?),
            amount: (r['amount'] as num).toDouble(),
            // The sale's own date — the one the Sales Report, the Annual
            // Earnings and Balik-Tangkilik all use for an Offer to Cooperative.
            transactionDate: DateTime.parse(r['sale_date'] as String),
            referenceNo: r['reference_no'] as String?,
            pricePerKg: (offer?['agreed_price_per_kg'] as num?)?.toDouble(),
            deliveredAt: deliveredAt,
            cropImageUrl:
                imageByCropName[(r['crop_name'] as String).toLowerCase()],
          ),
          batchId: offer?['inventory_batch_id'] as String?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // Only 'completed' orders are real transactions — matches Admin Sales
  // Report's own definition of this channel, and its date: the day the buyer
  // confirmed receipt (see CompletedOrderDates). Buyer name resolved via
  // buyer_id -> user_information, same lookup Admin's order history
  // already uses (admin_order_repository.dart).
  Future<List<({FarmerTransactionModel tx, String? batchId})>> _fetchMarketplace(
    Map<String, String> imageByCropName,
  ) async {
    try {
      final rows = await OfflineCache.load(
        screen: 'transactions_marketplace',
        fetch: () async {
          final orders = await CompletedOrderDates.withFallback(
            (withReceivedAt) => _client
                .from('orders')
                .select(
                  'id, order_number, quantity_kg, unit, price_per_kg, total_price, '
                  'status, created_at, fulfillment_method, '
                  '${withReceivedAt ? 'received_at, ' : ''}'
                  'marketplace_listings(crop_name, inventory_batch_id)',
                )
                .eq('farmer_id', _userId)
                .eq('status', 'completed'),
          );
          if (orders.isEmpty) return <Map<String, dynamic>>[];

          // A direct SELECT against user_information for the buyer's name
          // would be silently filtered to nothing by RLS — a farmer's session
          // has no policy allowing it to read another user's row there (only
          // its own, or an admin/staff session can). Routed through a
          // SECURITY DEFINER RPC instead, scoped to exactly (order_id,
          // buyer_name) for this farmer's own completed orders — see
          // supabase_schema_farmer_transaction_buyer_names.sql.
          final buyerRows =
              await _client.rpc('get_my_marketplace_buyer_names') as List;
          final buyerNamesByOrderId = {
            for (final b in buyerRows)
              b['order_id'] as String: b['buyer_name'] as String?,
          };

          // Buyer name is merged into each row so the cached copy keeps it.
          return orders
              .map<Map<String, dynamic>>(
                (r) => {
                  ...r,
                  'buyer_name': buyerNamesByOrderId[r['id']],
                },
              )
              .toList();
        },
      );

      return rows.map((r) {
        final listing = r['marketplace_listings'] as Map?;
        final cropName = listing?['crop_name'] as String? ?? 'Produce';
        return (
          tx: FarmerTransactionModel(
            id: r['id'] as String,
            sellingType: 'marketplace',
            referenceNo: orderReferenceOf(
              r['id'] as String,
              r['order_number'] as String?,
            ),
            cropName: cropName,
            quantityKg: (r['quantity_kg'] as num).toDouble(),
            unit: unitOrDefault(r['unit'] as String?),
            amount: (r['total_price'] as num).toDouble(),
            transactionDate: CompletedOrderDates.of(r),
            pricePerKg: (r['price_per_kg'] as num?)?.toDouble(),
            orderStatus: r['status'] as String?,
            fulfillmentMethod: r['fulfillment_method'] as String?,
            buyerName: r['buyer_name'] as String?,
            cropImageUrl: imageByCropName[cropName.toLowerCase()],
          ),
          batchId: listing?['inventory_batch_id'] as String?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<({FarmerTransactionModel tx, String? batchId})>> _fetchInformalSales(
    Map<String, String> imageByCropName,
  ) async {
    try {
      Future<List<Map<String, dynamic>>> read(String columns) async =>
          List<Map<String, dynamic>>.from(
            await _client
                .from('informal_sales')
                .select(columns)
                .eq('farmer_id', _userId),
          );
      final rows = await OfflineCache.load(
        screen: 'transactions_informal_sales',
        fetch: () async {
          // A database without the batch link still returns the sale.
          try {
            return await read(
              'id, crop_name, quantity_kg, unit, amount, buyer_name, sale_date, inventory_batch_id',
            );
          } on PostgrestException {
            return await read(
              'id, crop_name, quantity_kg, unit, amount, buyer_name, sale_date',
            );
          }
        },
      );
      return rows
          .map(
            (r) => (
              tx: FarmerTransactionModel(
                id: r['id'] as String,
                sellingType: 'informal_sale',
                cropName: r['crop_name'] as String,
                quantityKg: (r['quantity_kg'] as num).toDouble(),
                unit: unitOrDefault(r['unit'] as String?),
                amount: (r['amount'] as num?)?.toDouble() ?? 0,
                transactionDate: DateTime.parse(r['sale_date'] as String).toLocal(),
                buyerName: r['buyer_name'] as String?,
                cropImageUrl:
                    imageByCropName[(r['crop_name'] as String).toLowerCase()],
              ),
              batchId: r['inventory_batch_id'] as String?,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  // buyer_name now included — see FarmerTransactionModel's own note on why
  // this differs from MyMarketLinkingScreen's in-progress privacy rule. One row
  // per RECORDED sale (market_linking_sales): a request sold in parts is several
  // transactions, and a request that is only waiting for a buyer is none.
  Future<List<({FarmerTransactionModel tx, String? batchId})>> _fetchMarketLinking(
    Map<String, String> imageByCropName,
  ) async {
    try {
      // The buyer's contact and email are saved on each sale. A database that
      // does not have the email column yet still returns the sale itself.
      Future<List<Map<String, dynamic>>> read(String columns) async =>
          List<Map<String, dynamic>>.from(
            await _client
                .from('market_linking_sales')
                .select(columns)
                .eq('farmer_id', _userId),
          );
      const base =
          'id, crop_name, confirmed_volume_kg, price_per_kg, buyer_name, buyer_contact, completed_at';
      final rows = await OfflineCache.load(
        screen: 'transactions_market_linking',
        fetch: () async {
          // Newest columns first; a database that does not have a column yet
          // still returns the sale.
          for (final extra in const [
            ', buyer_email, unit, inventory_batch_id',
            ', buyer_email, unit',
            ', buyer_email',
            '',
          ]) {
            try {
              return await read('$base$extra');
            } catch (_) {
              if (extra.isEmpty) rethrow;
            }
          }
          return <Map<String, dynamic>>[];
        },
      );
      return rows.where((r) => r['completed_at'] != null).map((r) {
        // The quantity of this one sale (a request sold in parts is several
        // transactions, one per sale).
        final qty = (r['confirmed_volume_kg'] as num?)?.toDouble() ?? 0;

        final pricePerKg = (r['price_per_kg'] as num?)?.toDouble() ?? 0;
        final cropName = r['crop_name'] as String? ?? 'Ginger';
        return (
          tx: FarmerTransactionModel(
            id: r['id'] as String,
            sellingType: 'da_amad_market_linking',
            cropName: cropName,
            quantityKg: qty,
            unit: unitOrDefault(r['unit'] as String?),
            amount: moneyOf(qty, pricePerKg),
            transactionDate: DateTime.parse(r['completed_at'] as String).toLocal(),
            buyerName: r['buyer_name'] as String?,
            buyerContact: r['buyer_contact'] as String?,
            buyerEmail: r['buyer_email'] as String?,
            pricePerKg: pricePerKg,
            cropImageUrl: imageByCropName[cropName.toLowerCase()],
          ),
          batchId: r['inventory_batch_id'] as String?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
