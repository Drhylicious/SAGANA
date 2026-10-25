import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_market_rate_model.dart';
import '../models/price_record_model.dart';
import '../services/offline_cache.dart';
import 'price_management_repository.dart';

/// Farmer-side read access to market prices. Deliberately separate from
/// PriceManagementRepository (admin, write-side) — this repository only
/// ever reads, following the same "one fetch method, optional filters"
/// shape as crop_repository.dart's fetchCropCatalog() and
/// market_linking_repository.dart's fetchAll().
class FarmerMarketRatesRepository {
  final SupabaseClient _client = Supabase.instance.client;
  final PriceManagementRepository _prices = PriceManagementRepository();

  /// Returns the latest price per (crop_id, price_type), optionally
  /// narrowed by market type, crop category, a specific crop, and a
  /// client-side search term. Home passes only [limit]; View Market passes
  /// whichever filters the farmer has active. Never throws — a failed
  /// read returns an empty list, same convention as every other Farmer
  /// repository.
  /// OfflineCache key for a fetchMarketRates() call with these filters, so
  /// each selection keeps its own offline copy. Search text and limit are
  /// applied after the read and are not part of the key.
  static String cacheScreen({
    String? marketType,
    String? cropCategory,
    String? cropId,
  }) =>
      'market_rates_${marketType ?? 'all'}_${cropCategory ?? 'all'}_${cropId ?? 'all'}';

  Future<List<FarmerMarketRateModel>> fetchMarketRates({
    String? marketType, // price_type: sp3_cooperative | open_market
    String? cropCategory, // crop_master.category
    String? cropId, // exact crop selection
    String? searchQuery, // client-side substring match on crop name
    int? limit,
  }) async {
    try {
      // crop_master!inner so filtering on the embedded resource's columns
      // (category) is honored by PostgREST rather than silently ignored,
      // the way a left join embed would.
      var query = _client
          .from('price_records')
          .select('*, crop_master!inner(category, description, image_url, is_active)');

      if (marketType != null) {
        query = query.eq('price_type', marketType);
      }
      if (cropId != null) {
        query = query.eq('crop_id', cropId);
      }
      if (cropCategory != null) {
        query = query.eq('crop_master.category', cropCategory);
      }

      // No limit applied at the query level yet — dedup has to run first,
      // or a raw-row limit could cut off before every crop's latest entry
      // is even seen (e.g. 20 raw rows might only cover 3 distinct crops
      // if one crop has been repriced many times).
      final rows = await OfflineCache.load(
        screen: cacheScreen(
          marketType: marketType,
          cropCategory: cropCategory,
          cropId: cropId,
        ),
        fetch: () => query.order('recorded_at', ascending: false),
      );

      // Latest entry per (crop_id, price_type) — same dedup key already
      // fixed in PriceManagementRepository.fetchLatestPricePerCrop(),
      // reused here rather than reimplemented.
      final Map<String, FarmerMarketRateModel> latest = {};
      for (final row in rows) {
        // An archived crop (retired from the catalog, e.g. Copra) no longer
        // shows a current rate. Its records stay in the database.
        final master = row['crop_master'];
        if (master is Map && master['is_active'] == false) continue;
        final key = '${row['crop_id']}_${row['price_type']}';
        if (!latest.containsKey(key)) {
          latest[key] = FarmerMarketRateModel.fromMap(row);
        }
      }

      var result = latest.values.toList()
        ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        result = result
            .where((r) => r.cropName.toLowerCase().contains(q))
            .toList();
      }

      if (limit != null && result.length > limit) {
        result = result.sublist(0, limit);
      }

      return result;
    } catch (_) {
      return [];
    }
  }

  /// The price history of one crop in ONE market, oldest first, for the
  /// Market Rate Details trend chart. The same read the Buyer Prices chart
  /// uses (last 30 days, or the 10 latest entries when nothing is that
  /// recent), narrowed to [marketType] so a crop priced in both markets never
  /// has its two price lists drawn as one line. An empty list means there is no
  /// readable history (or the read failed); it never throws.
  Future<List<PriceRecordModel>> fetchTrend(String cropId, String marketType) =>
      _prices.fetchTrendForCrop(cropId, priceType: marketType);
}
