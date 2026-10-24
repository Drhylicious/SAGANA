import 'package:flutter/foundation.dart' show visibleForTesting;
import 'connectivity_service.dart';
import 'hive_service.dart';

/// Last-loaded snapshot of a list, kept so it can be viewed offline.
///
/// A successful load replaces the snapshot for its screen. When the server
/// cannot be reached, the last snapshot is returned instead and
/// [servedFromCache] is true, so the screen can say so and show [savedAt].
///
/// Snapshots are encrypted (they live in the cache box) and scoped to the
/// signed-in user. They are cleared on logout (HiveService.clearUserSession).
/// Queued offline records and actions are never cleared by this cache.
///
/// Snapshots carry a schema version. A snapshot written by an older release
/// (which may lack fields the app now relies on, such as a crop's market type
/// or exclusive selling channel) is ignored rather than shown, so cached data
/// can never describe market rules the current release no longer follows.
/// Raise [schemaVersion] whenever the shape or meaning of cached rows changes.
class OfflineCache {
  OfflineCache._();

  /// 2: market types and selling channels are database data; listings,
  /// crops and batches carry crop_type / exclusive_channel.
  static const int schemaVersion = 2;

  static final Map<String, bool> _servedFromCache = {};

  static String _key(String screen) =>
      '${HiveService.getUserId() ?? 'anonymous'}::$screen';

  /// Returns the live rows when reachable, otherwise the saved snapshot.
  /// Throws the fetch error only when there is no snapshot to fall back to.
  static Future<List<Map<String, dynamic>>> load({
    required String screen,
    required Future<List<Map<String, dynamic>>> Function() fetch,
  }) async {
    final key = _key(screen);
    Object? failure;
    if (ConnectivityService.instance.isOnline) {
      try {
        final rows = await fetch();
        await HiveService.cacheBox.put(key, {
          'v': schemaVersion,
          'savedAt': DateTime.now().toIso8601String(),
          'rows': rows,
        });
        _servedFromCache[key] = false;
        return rows;
      } catch (e) {
        failure = e;
      }
    }

    final snapshot = _read(key);
    if (snapshot != null) {
      _servedFromCache[key] = true;
      return snapshot.rows;
    }
    _servedFromCache[key] = false;
    if (failure != null) throw failure;
    return const [];
  }

  /// True when the last [load] for [screen] returned the saved snapshot.
  static bool servedFromCache(String screen) =>
      _servedFromCache[_key(screen)] ?? false;

  /// When the snapshot for [screen] was saved, or null if there is none.
  static DateTime? savedAt(String screen) => _read(_key(screen))?.savedAt;

  /// A saved snapshot is trusted only when this release wrote it (see the class
  /// comment): a map carrying the current [schemaVersion].
  @visibleForTesting
  static bool snapshotIsCurrent(Object? raw) =>
      raw is Map && raw['v'] == schemaVersion;

  static ({List<Map<String, dynamic>> rows, DateTime? savedAt})? _read(
    String key,
  ) {
    final raw = HiveService.cacheBox.get(key);
    if (!snapshotIsCurrent(raw)) return null;
    raw as Map;
    final rawRows = raw['rows'];
    if (rawRows is! List) return null;
    return (
      rows: rawRows.map((r) => _plain(r) as Map<String, dynamic>).toList(),
      savedAt: DateTime.tryParse(raw['savedAt'] as String? ?? ''),
    );
  }

  /// Hive returns nested maps as Map<dynamic, dynamic>. Models cast nested
  /// values strictly, so convert the whole row back to the shape Supabase
  /// returns.
  static Object? _plain(Object? value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _plain(v)));
    }
    if (value is List) return value.map(_plain).toList();
    return value;
  }
}
