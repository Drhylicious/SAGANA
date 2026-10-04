import 'dart:async';

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One place returned by Nominatim (OpenStreetMap).
class NominatimPlace {
  final String displayName;
  final LatLng point;

  const NominatimPlace({required this.displayName, required this.point});
}

/// Reverse lookup (nearest place name for the pinned location) for the My
/// Addresses form. The address search was removed; see the Batch 5 notes.
///
/// Requests go through the `nominatim-proxy` Supabase Edge Function, not to
/// nominatim.openstreetmap.org directly. The proxy holds the identifying
/// User-Agent, the shared cache, and the configurable upstream endpoint (see
/// supabase/functions/nominatim-proxy/index.ts).
///
/// This class also keeps its own queue (one request at a time, at least
/// 1.1 s apart) and a session cache, so one phone stays within the Nominatim
/// limit of one request per second even when the proxy is cold.
class NominatimService {
  NominatimService._();

  static const _functionName = 'nominatim-proxy';
  static const _minGap = Duration(milliseconds: 1100);
  static const _timeout = Duration(seconds: 15);

  static final Map<String, NominatimPlace?> _reverseCache = {};

  // Requests run one at a time, in order. A failed request completes its
  // own future with the error and does not stop the queue.
  static Future<void> _queue = Future.value();
  static DateTime? _lastRequestAt;

  static Future<T> _throttled<T>(Future<T> Function() request) {
    final done = Completer<T>();
    _queue = _queue.then((_) async {
      final last = _lastRequestAt;
      if (last != null) {
        final wait = _minGap - DateTime.now().difference(last);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      _lastRequestAt = DateTime.now();
      try {
        done.complete(await request());
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  static Future<dynamic> _invoke(Map<String, dynamic> body) async {
    final response = await Supabase.instance.client.functions
        .invoke(_functionName, body: body)
        .timeout(_timeout);
    return response.data;
  }

  static NominatimPlace? _toPlace(Map<String, dynamic> json) {
    final lat = double.tryParse('${json['lat']}');
    final lon = double.tryParse('${json['lon']}');
    final name = json['display_name'] as String?;
    if (lat == null || lon == null || name == null) return null;
    return NominatimPlace(displayName: name, point: LatLng(lat, lon));
  }

  /// The nearest named place to [point], or null when there is none. Throws
  /// when the proxy or the upstream service cannot be reached.
  static Future<NominatimPlace?> reverse(LatLng point) async {
    final key =
        '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';
    if (_reverseCache.containsKey(key)) return _reverseCache[key];

    final place = await _throttled(() async {
      final json =
          await _invoke({
                'action': 'reverse',
                'lat': point.latitude,
                'lon': point.longitude,
              })
              as Map<String, dynamic>;
      return _toPlace({...json, 'lat': point.latitude, 'lon': point.longitude});
    });
    _reverseCache[key] = place;
    return place;
  }
}
