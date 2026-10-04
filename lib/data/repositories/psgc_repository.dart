import 'dart:convert';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../models/psgc_models.dart';

/// Loads the bundled PSGC hierarchy on first use and caches it for the
/// rest of the session. Nothing loads at app start: call [load] only
/// when an address form that needs it opens.
class PsgcRepository {
  static const String _assetPath = 'assets/data/psgc_hierarchy.json';

  static Future<PsgcHierarchy>? _cached;

  /// Returns the hierarchy. If the asset cannot be read, the future
  /// completes with an empty hierarchy and the cache is cleared, so a
  /// later call retries.
  static Future<PsgcHierarchy> load() {
    return _cached ??= _loadFromAsset().catchError((Object e) {
      debugPrint('PsgcRepository.load failed: $e');
      _cached = null;
      return const PsgcHierarchy(regions: []);
    });
  }

  static Future<PsgcHierarchy> _loadFromAsset() async {
    final raw = await rootBundle.loadString(_assetPath);
    // Parse off the UI isolate: the asset is ~1.2 MB.
    final regions = await compute(_parseRegions, raw);
    return PsgcHierarchy(regions: regions);
  }
}

/// Top-level so [compute] can run it in a background isolate.
List<PsgcRegion> _parseRegions(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final regions = (root['regions'] as List).cast<Map<String, dynamic>>();
  return regions.map(_region).toList(growable: false);
}

PsgcRegion _region(Map<String, dynamic> m) {
  return PsgcRegion(
    code: m['code'] as String,
    name: m['name'] as String,
    provinces: (m['provinces'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (p) => PsgcProvince(
            code: p['code'] as String,
            name: p['name'] as String,
            cities: _cities(p['cities'] as List),
          ),
        )
        .toList(growable: false),
    cities: _cities(m['cities'] as List),
  );
}

List<PsgcCity> _cities(List raw) {
  return raw
      .cast<Map<String, dynamic>>()
      .map(
        (c) => PsgcCity(
          code: c['code'] as String,
          name: c['name'] as String,
          barangays: (c['barangays'] as List)
              .cast<List<dynamic>>()
              .map(
                (b) => PsgcBarangay(code: b[0] as String, name: b[1] as String),
              )
              .toList(growable: false),
        ),
      )
      .toList(growable: false);
}
