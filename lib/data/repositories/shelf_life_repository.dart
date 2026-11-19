import 'package:flutter/foundation.dart' show debugPrint;
import '../../core/utils/chunked_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/quantity_utils.dart';
import '../models/shelf_life_model.dart';
import '../services/app_event_service.dart';
import '../services/connectivity_service.dart';
import '../services/server_only.dart';

/// Runs a read with a shelf-life embed added to its columns ("[base], [embed]").
/// If the database does not have the shelf-life tables yet (the SQL scripts are
/// run by hand), the same read is done again without the embed, so the screen
/// still loads exactly as it did before, just without shelf-life data.
Future<T> withShelfLifeEmbed<T>(
  String base,
  String embed,
  Future<T> Function(String columns) run,
) async {
  try {
    return await run('$base, $embed');
  } on PostgrestException catch (e) {
    final missing =
        e.code == 'PGRST200' ||
        e.code == 'PGRST201' ||
        e.code == 'PGRST205' ||
        e.code == '42P01' ||
        e.message.contains('shelf_life');
    if (!missing) rethrow;
    return await run(base);
  }
}

/// What happened when the Farmer confirmed a batch is still good.
enum ShelfLifeConfirmResult {
  /// The new duration is in effect.
  applied,

  /// A published listing was already discounted or unavailable, so the change
  /// was sent to the Manager / Officer for approval.
  submitted,
}

/// Shelf-life actions and settings. Every rule is enforced in Supabase
/// (supabase_schema_shelf_life_s01_foundation.sql); this only calls it.
class ShelfLifeRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Runs the daily pass (reminder, expiry-day discount, unavailable listings).
  /// The database also runs it on a schedule; calling it again is harmless, so
  /// the screens that show shelf-life state call it before loading. Never
  /// throws: offline, or before the SQL is applied, it simply does nothing.
  Future<void> process() async {
    if (!ConnectivityService.instance.isOnline) return;
    try {
      await _client.rpc('process_shelf_life');
    } catch (e) {
      debugPrint('ShelfLifeRepository.process skipped: $e');
    }
  }

  /// The Farmer checked the produce and it is still good for [days] more days.
  /// [price] matters only when a published listing needs approval.
  Future<ShelfLifeConfirmResult> confirmStillGood({
    required String batchId,
    required int days,
    double? price,
  }) async {
    await ServerOnly.ensureOnline();
    final result = await _client.rpc(
      'confirm_batch_still_good',
      params: {
        'p_batch_id': batchId,
        'p_days': days,
        'p_price': price == null ? null : roundQuantity(price),
      },
    );
    AppEventService.instance.notify();
    return result == 'submitted'
        ? ShelfLifeConfirmResult.submitted
        : ShelfLifeConfirmResult.applied;
  }

  /// The Farmer reports the unsold part of the batch as rotten. Returns the
  /// quantity recorded as a loss.
  Future<double> reportRotten({required String batchId, String? note}) async {
    await ServerOnly.ensureOnline();
    final result = await _client.rpc(
      'report_batch_rotten',
      params: {'p_batch_id': batchId, 'p_note': note},
    );
    AppEventService.instance.notify();
    return (result as num?)?.toDouble() ?? 0;
  }

  /// The Marketplace price rule for a harvest batch (null = no restriction).
  /// Pass [listingId] when editing, so a discounted listing's lower limit is
  /// included.
  Future<ListingPriceRule?> fetchPriceRule(
    String batchId, {
    String? listingId,
  }) async {
    try {
      final result = await _client.rpc(
        'get_listing_price_rule',
        params: {'p_batch_id': batchId, 'p_listing_id': listingId},
      );
      return ListingPriceRule.fromMap(result);
    } catch (e) {
      debugPrint('ShelfLifeRepository.fetchPriceRule failed: $e');
      return null;
    }
  }

  /// Open listings whose price is outside their crop's current Reference Price
  /// Range, keyed by listing id, with the range to move into. A Farmer gets
  /// their own listings; staff get all of them. Worked out by the database from
  /// live data, so a listing drops out as soon as an in-range price is approved.
  ///
  /// The values are plain maps ({mode, price_min, price_max, unit}) so the
  /// listing repositories can store them on the listing rows they cache;
  /// [ListingPriceRule.fromMap] reads one.
  Future<Map<String, Map<String, dynamic>>> fetchPriceUpdateRequired() async {
    try {
      final result = await _client.rpc('get_price_update_required_listings');
      final out = <String, Map<String, dynamic>>{};
      for (final row in (result as List? ?? const [])) {
        final m = Map<String, dynamic>.from(row as Map);
        out[m['listing_id'] as String] = {...m, 'mode': 'range'};
      }
      return out;
    } catch (e) {
      debugPrint('ShelfLifeRepository.fetchPriceUpdateRequired failed: $e');
      return {};
    }
  }

  /// The price rule of a batch, and whether the lookup itself worked. [known]
  /// is false when the database could not answer (offline, or the price-rule
  /// SQL is not applied yet); Create Listing then does not claim the crop has
  /// no Reference Price, and leaves the decision to the database.
  Future<({ListingPriceRule? rule, bool known})> lookupPriceRule(
    String batchId,
  ) async {
    try {
      final result = await _client.rpc(
        'get_listing_price_rule',
        params: {'p_batch_id': batchId, 'p_listing_id': null},
      );
      return (rule: ListingPriceRule.fromMap(result), known: true);
    } catch (e) {
      debugPrint('ShelfLifeRepository.lookupPriceRule failed: $e');
      return (rule: null, known: false);
    }
  }

  /// "cropId|marketType" of every crop that has a Reference Price in its own
  /// market type (any unit). Crop Management marks the crops missing from it.
  /// Null when the prices cannot be read, so nothing is marked by mistake.
  Future<Set<String>?> fetchPricedCropKeys() async {
    try {
      final rows = await _client
          .from('price_records')
          .select('crop_id, price_type')
          .not('crop_id', 'is', null);
      return {for (final r in rows) '${r['crop_id']}|${r['price_type']}'};
    } catch (e) {
      debugPrint('ShelfLifeRepository.fetchPricedCropKeys failed: $e');
      return null;
    }
  }

  // ─── Staff ────────────────────────────────────────────────────────────────

  /// The expiry-day Marketplace discount, in percent. Null if it cannot be read.
  Future<double?> fetchExpiryDiscountPercent() async {
    try {
      final row = await _client
          .from('shelf_life_settings')
          .select('expiry_discount_percent')
          .maybeSingle();
      return (row?['expiry_discount_percent'] as num?)?.toDouble();
    } catch (e) {
      debugPrint('ShelfLifeRepository.fetchExpiryDiscountPercent failed: $e');
      return null;
    }
  }

  Future<void> saveExpiryDiscountPercent(double percent) async {
    await _client
        .from('shelf_life_settings')
        .update({
          'expiry_discount_percent': percent,
          'updated_by': _client.auth.currentUser?.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', true);
  }

  /// The sourced shelf-life figures on file, keyed by lower-case crop name.
  /// Used to suggest a value in Add New Crop.
  Future<Map<String, ({int days, String source})>> fetchReference() async {
    try {
      final rows = await _client
          .from('crop_shelf_life_reference')
          .select('crop_key, shelf_life_days, source');
      return {
        for (final r in rows)
          (r['crop_key'] as String): (
            days: (r['shelf_life_days'] as num).toInt(),
            source: r['source'] as String? ?? '',
          ),
      };
    } catch (_) {
      return {};
    }
  }

  /// Shelf-life history for the reports, newest first. [types] narrows it
  /// (for example only `reported_rotten` for losses).
  Future<List<ShelfLifeEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
    List<String>? types,
    String? farmerId,
    String? batchId,
  }) async {
    try {
      var q = _client.from('shelf_life_events').select();
      if (types != null && types.isNotEmpty) q = q.inFilter('event_type', types);
      if (farmerId != null) q = q.eq('farmer_id', farmerId);
      if (batchId != null) q = q.eq('batch_id', batchId);
      if (from != null) q = q.gte('created_at', from.toUtc().toIso8601String());
      if (to != null) q = q.lt('created_at', to.toUtc().toIso8601String());
      final rows = await q.order('created_at', ascending: false).limit(2000);
      return rows.map(ShelfLifeEvent.fromMap).toList();
    } catch (e) {
      debugPrint('ShelfLifeRepository.fetchEvents failed: $e');
      return [];
    }
  }

  /// Shelf-life rows for a set of batches (staff screens that already hold the
  /// batch ids of the listings they show).
  Future<Map<String, BatchShelfLife>> fetchForBatches(
    List<String> batchIds,
  ) async {
    if (batchIds.isEmpty) return {};
    try {
      final rows = await chunkedIn(batchIds, (slice) => _client.from('batch_shelf_life').select().inFilter('batch_id', slice));
      final out = <String, BatchShelfLife>{};
      for (final r in rows) {
        final s = BatchShelfLife.fromEmbed(r);
        if (s != null) out[r['batch_id'] as String] = s;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Shelf-life state of a set of listings (unavailable / discounted).
  Future<Map<String, ListingShelfLife>> fetchForListings(
    List<String> listingIds,
  ) async {
    if (listingIds.isEmpty) return {};
    try {
      final rows = await chunkedIn(listingIds, (slice) => _client.from('listing_shelf_life').select().inFilter('listing_id', slice));
      final out = <String, ListingShelfLife>{};
      for (final r in rows) {
        final s = ListingShelfLife.fromEmbed(r);
        if (s != null) out[r['listing_id'] as String] = s;
      }
      return out;
    } catch (_) {
      return {};
    }
  }
}
