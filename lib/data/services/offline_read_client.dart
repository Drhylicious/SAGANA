import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'connectivity_service.dart';
import 'hive_service.dart';
import 'offline_cache.dart';

/// Completes snapshot coverage for detail pages, counts and read-only RPCs.
/// Only successful, user-scoped REST reads are cached. Auth, storage, realtime
/// and all writes continue directly to the server. Buyers bypass this cache.
class OfflineReadClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  static const _syncUser = #saganaSyncUser;

  /// Keeps a background replay bound to its original account across awaits.
  static Future<T> runForUser<T>(String userId, Future<T> Function() action) =>
      runZoned(action, zoneValues: {_syncUser: userId});

  // Explicit read-only functions: never infer safety from an RPC name prefix.
  static const _readRpcs = {
    'get_cooperative_details',
    'get_delivery_status',
    'get_supply_chain_records',
    'get_supply_chain_totals',
    'get_programs_completion_status',
    'get_program_returns',
    'get_failed_resolutions',
    'get_my_assistance_options',
    'get_my_assistance_requests',
    'get_assistance_requests',
    'list_loanable_items',
    'get_my_loan_requests',
    'get_program_product_stats',
    'get_my_program_returns',
    'get_my_outcome_reports',
    'get_my_marketplace_buyer_names',
    'get_program_outcome_reports',
    'get_program_history',
    'get_my_activity_share',
    'get_manager_sign_in_emails',
    'get_my_listing_edit_requests',
    'get_my_listing_history',
    'get_officer_permissions',
    'get_delivery_quote',
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final owner = HiveService.getUserId();
    final role = HiveService.getUserRole();
    String? requestOwner;
    try {
      final authorization = request.headers.entries
          .firstWhere((e) => e.key.toLowerCase() == 'authorization')
          .value;
      final token = authorization.split(' ').last.split('.')[1];
      final claims =
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token))))
              as Map;
      requestOwner = claims['sub'] as String?;
    } catch (_) {
      // Public/anonymous requests never become a private user's snapshot.
    }
    final eligible =
        owner != null &&
        requestOwner == owner &&
        const ['admin', 'officer', 'farmer'].contains(role);
    final segments = request.url.pathSegments;
    final rpc = segments.length == 4 && segments[2] == 'rpc';
    final rest =
        segments.length >= 3 && segments[0] == 'rest' && segments[1] == 'v1';
    final syncUser = Zone.current[_syncUser] as String?;
    if ((rest || segments.firstOrNull == 'storage') &&
        syncUser != null &&
        requestOwner != syncUser) {
      throw http.ClientException('The signed-in account changed.', request.url);
    }
    final read = rpc
        ? _readRpcs.contains(segments.last) &&
              const ['GET', 'HEAD', 'POST'].contains(request.method)
        : request.method == 'GET' || request.method == 'HEAD';
    // Account status must always be a live verdict; offline routing already
    // uses the explicitly saved local session instead.
    final accountStatus = rest && !rpc && segments[2] == 'user_roles';
    if (!eligible || !rest || !read || accountStatus) {
      return _inner.send(request);
    }

    final body = request is http.Request ? base64Encode(request.bodyBytes) : '';
    final key =
        'rest-v${OfflineCache.schemaVersion}::$owner::$role::${request.method}::'
        '${request.url}::${request.headers['accept']}::'
        '${request.headers['range']}::${request.headers['prefer']}::'
        '${request.headers['accept-profile']}::'
        '${request.headers['content-profile']}::$body';

    http.StreamedResponse? snapshot() {
      if (Zone.current[OfflineCache.liveFetchZoneKey] == true) return null;
      if (HiveService.getUserId() != owner ||
          HiveService.getUserRole() != role) {
        return null;
      }
      try {
        final raw = HiveService.cacheBox.get(key);
        if (raw is! Map) return null;
        final bytes = base64Decode(raw['body'] as String);
        return http.StreamedResponse(
          Stream.value(bytes),
          raw['status'] as int,
          headers: Map<String, String>.from(raw['headers'] as Map),
          request: request,
        );
      } catch (_) {
        // A damaged snapshot is a cache miss, never a fabricated response.
        return null;
      }
    }

    if (!ConnectivityService.instance.isOnline) {
      final cached = snapshot();
      if (cached != null) return cached;
      throw http.ClientException('No saved data for this page.', request.url);
    }

    http.Response response;
    try {
      final streamed = await _inner
          .send(request)
          .timeout(const Duration(seconds: 8));
      response = await http.Response.fromStream(
        streamed,
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      final cached = snapshot();
      if (cached != null) return cached;
      rethrow;
    }
    // Never turn an authorization/validation error into an old successful read.
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        HiveService.getUserId() == owner &&
        HiveService.getUserRole() == role) {
      try {
        await HiveService.cacheBox.put(key, {
          'body': base64Encode(response.bodyBytes),
          'status': response.statusCode,
          'headers': response.headers,
          'savedAt': DateTime.now().toIso8601String(),
        });
      } catch (_) {
        // A local storage failure must not discard a successful server response.
      }
    }
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }

  @override
  void close() => _inner.close();
}
