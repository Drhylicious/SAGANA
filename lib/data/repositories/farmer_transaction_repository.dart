import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_transaction_model.dart';
import '../services/offline_cache.dart';
import '../../core/utils/order_reference.dart';
import '../../core/utils/quantity_utils.dart';

/// Farmer's own completed sales across all 4 selling channels — the data
/// source behind Farmer Transaction History. Each channel query mirrors
/// AdminReportsRepository's equivalent (admin_reports_repository.dart),
/// scoped down to farmer_id = the logged-in farmer instead of every member.
///
/// Each channel's rows (and the crop photo lookup) are cached through
/// OfflineCache, so the history can still be viewed offline.
class FarmerTransactionRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  Future<List<FarmerTransactionModel>> fetchMyTransactions() async {
    final imageByCropName = await _fetchCropImageByName();
    final results = await Future.wait([
      _fetchOfferToCoop(imageByCropName),
      _fetchMarketplace(imageByCropName),
      _fetchInformalSales(imageByCropName),
      _fetchMarketLinking(imageByCropName),
    ]);
    final all = results.expand((list) => list).toList();
    all.sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
    return all;
  }

  // Same shared-image resolution as everywhere else in the app (Crop
  // Roster, Manage Inventory, Harvest History): the farmer's own photo,
  // falling back to the catalog photo. Keyed by crop name (lowercased)
  // since 3 of the 4 source tables below have no direct crop_id/batch_id
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
        .select('crop_name, photo_url, crop_master_id')
        .eq('farmer_id', _userId);

    final ownPhotoByName = <String, String>{};
    final masterIdByName = <String, String>{};
    for (final r in rows) {
      final name = (r['crop_name'] as String).toLowerCase();
      final ownPhoto = r['photo_url'] as String?;
      if (ownPhoto != null && ownPhoto.isNotEmpty) {
        ownPhotoByName[name] = ownPhoto;
      } else if (r['crop_master_id'] != null) {
        masterIdByName[name] = r['crop_master_id'] as String;
      }
    }

    final masterImageById = <String, String>{};
    if (masterIdByName.isNotEmpty) {
      final masterRows = await _client
          .from('crop_master')
          .select('id, image_url')
          .inFilter('id', masterIdByName.values.toSet().toList());
      for (final r in masterRows) {
        final url = r['image_url'] as String?;
        if (url != null && url.isNotEmpty) {
          masterImageById[r['id'] as String] = url;
        }
      }
    }

    final entries = <Map<String, dynamic>>[];
    for (final name in {...ownPhotoByName.keys, ...masterIdByName.keys}) {
      final own = ownPhotoByName[name];
      if (own != null) {
        entries.add({'name': name, 'url': own});
        continue;
      }
      final catalogUrl = masterImageById[masterIdByName[name]];
      if (catalogUrl != null) entries.add({'name': name, 'url': catalogUrl});
    }
    return entries;
  }

  // No buyer name — this transaction is directly with the cooperative/
  // Admin side, not an external buyer.
  Future<List<FarmerTransactionModel>> _fetchOfferToCoop(
    Map<String, String> imageByCropName,
  ) async {
    try {
      final rows = await OfflineCache.load(
        screen: 'transactions_offer_to_coop',
        fetch: () => _client
            .from('member_sales_transactions')
            .select(
              'id, crop_name, quantity_kg, unit, amount, sale_date, reference_no',
            )
            .eq('farmer_id', _userId),
      );
      return rows
          .map(
            (r) => FarmerTransactionModel(
              id: r['id'] as String,
              sellingType: 'offer_to_cooperative',
              cropName: r['crop_name'] as String,
              quantityKg: (r['quantity_kg'] as num).toDouble(),
              unit: unitOrDefault(r['unit'] as String?),
              amount: (r['amount'] as num).toDouble(),
              transactionDate: DateTime.parse(r['sale_date'] as String),
              referenceNo: r['reference_no'] as String?,
              cropImageUrl:
                  imageByCropName[(r['crop_name'] as String).toLowerCase()],
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Only 'completed' orders are real transactions — matches Admin Sales
  // Report's own definition of this channel. Buyer name resolved via
  // buyer_id -> user_information, same lookup Admin's order history
  // already uses (admin_order_repository.dart).
  Future<List<FarmerTransactionModel>> _fetchMarketplace(
    Map<String, String> imageByCropName,
  ) async {
    try {
      final rows = await OfflineCache.load(
        screen: 'transactions_marketplace',
        fetch: () async {
          final orders = await _client
              .from('orders')
              .select(
                'id, order_number, quantity_kg, unit, total_price, status, created_at, marketplace_listings(crop_name)',
              )
              .eq('farmer_id', _userId)
              .eq('status', 'completed');
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
        final cropName =
            (r['marketplace_listings'] as Map?)?['crop_name'] as String? ??
            'Produce';
        return FarmerTransactionModel(
          id: r['id'] as String,
          sellingType: 'marketplace',
          referenceNo: orderReferenceOf(r['id'] as String, r['order_number'] as String?),
          cropName: cropName,
          quantityKg: (r['quantity_kg'] as num).toDouble(),
          unit: unitOrDefault(r['unit'] as String?),
          amount: (r['total_price'] as num).toDouble(),
          transactionDate: DateTime.parse(r['created_at'] as String),
          orderStatus: r['status'] as String?,
          buyerName: r['buyer_name'] as String?,
          cropImageUrl: imageByCropName[cropName.toLowerCase()],
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<FarmerTransactionModel>> _fetchInformalSales(
    Map<String, String> imageByCropName,
  ) async {
    try {
      final rows = await OfflineCache.load(
        screen: 'transactions_informal_sales',
        fetch: () => _client
            .from('informal_sales')
            .select(
              'id, crop_name, quantity_kg, unit, amount, buyer_name, sale_date',
            )
            .eq('farmer_id', _userId),
      );
      return rows
          .map(
            (r) => FarmerTransactionModel(
              id: r['id'] as String,
              sellingType: 'informal_sale',
              cropName: r['crop_name'] as String,
              quantityKg: (r['quantity_kg'] as num).toDouble(),
              unit: unitOrDefault(r['unit'] as String?),
              amount: (r['amount'] as num?)?.toDouble() ?? 0,
              transactionDate: DateTime.parse(r['sale_date'] as String),
              buyerName: r['buyer_name'] as String?,
              cropImageUrl:
                  imageByCropName[(r['crop_name'] as String).toLowerCase()],
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  // buyer_name now included — see FarmerTransactionModel's own note on why
  // this differs from MyMarketLinkingScreen's in-progress privacy rule.
  Future<List<FarmerTransactionModel>> _fetchMarketLinking(
    Map<String, String> imageByCropName,
  ) async {
    try {
      final rows = await OfflineCache.load(
        screen: 'transactions_market_linking',
        fetch: () => _client
            .from('market_linking_programs')
            .select(
              'id, crop_name, volume_kg, requested_volume_kg, confirmed_volume_kg, price_per_kg, buyer_name, completed_at',
            )
            .eq('farmer_id', _userId)
            .eq('status', 'completed'),
      );
      return rows.where((r) => r['completed_at'] != null).map((r) {
        // Same order as the dashboard and the Manager's Sales Report: the
        // confirmed volume, else what the buyer asked for, else the enrolled
        // volume.
        final qty =
            (r['confirmed_volume_kg'] as num?)?.toDouble() ??
            (r['requested_volume_kg'] as num?)?.toDouble() ??
            (r['volume_kg'] as num?)?.toDouble() ??
            0;
        final pricePerKg = (r['price_per_kg'] as num?)?.toDouble() ?? 0;
        final cropName = r['crop_name'] as String? ?? 'Ginger';
        return FarmerTransactionModel(
          id: r['id'] as String,
          sellingType: 'da_amad_market_linking',
          cropName: cropName,
          quantityKg: qty,
          amount: moneyOf(qty, pricePerKg),
          transactionDate: DateTime.parse(r['completed_at'] as String),
          buyerName: r['buyer_name'] as String?,
          cropImageUrl: imageByCropName[cropName.toLowerCase()],
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
