import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'connectivity_service.dart';
import 'hive_service.dart';
import 'offline_cache.dart';

/// Completes snapshot coverage for detail pages, counts and read-only RPCs.
/// Only successful, user-scoped REST reads are cached. Storage, realtime and
/// all writes continue directly to the server. Buyers bypass this cache.
/// The one auth request handled here is the token refresh (see "Offline
/// session hold" below), so an expired sign-in token cannot hide saved pages.
class OfflineReadClient extends http.BaseClient {
  /// [inner] is the real network; tests pass a stand-in.
  OfflineReadClient({http.Client? inner}) : _inner = inner ?? http.Client() {
    _instance = this;
  }

  final http.Client _inner;

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
    'get_my_assistance_options',
    'get_my_assistance_requests',
    'get_assistance_requests',
    'list_loanable_items',
    'get_my_loan_requests',
    'get_program_product_stats',
    'get_my_marketplace_buyer_names',
    'get_program_history',
    'get_my_activity_share',
    'get_manager_sign_in_emails',
    'get_my_listing_edit_requests',
    'get_my_listing_history',
    'get_officer_permissions',
    'get_delivery_quote',
    // Read-only (STABLE) functions used by the newer screens: Farmer Details
    // programs, loan capital eligibility, price rules, restrictions, and the
    // market data shared with the guest view. Checks made right before a
    // server decision (program completion warnings) stay live.
    'get_farmer_programs_view',
    'get_program_distribution_summary',
    'get_farmer_distribution_summary',
    'get_loan_capital_standing',
    'get_price_update_required_listings',
    'get_listing_price_rule',
    'my_restrictions',
    'get_member_discipline_history',
    'public_market_types',
    'public_latest_prices',
    'public_price_trend',
    'public_listed_crop_names',
    'public_marketplace_listings',
  };

  // ─── Offline session hold ──────────────────────────────────────────────────
  //
  // The sign-in token lasts about an hour. Once it expires the Supabase library
  // refuses to send ANY request until it has a new one, and it cannot get one
  // without a connection. Offline, that stopped every read before it reached
  // this class, so saved pages stayed empty (after a 10-second wait each).
  //
  // While the server cannot be reached, the refresh request is answered here
  // with the session the device already has, marked [_holdClaim] and given a
  // later expiry. The library then lets requests through and this class serves
  // them from the saved copies. The held token is never accepted by the server
  // (its signature no longer matches), and it is never sent: the first request
  // made with a connection swaps it for a real one first.
  static const _holdClaim = 'sagana_offline_hold';
  static const _offlineRoles = ['admin', 'officer', 'farmer'];
  Future<String?>? _restoring;

  static Map<String, dynamic>? _claimsOf(String? jwt) {
    try {
      final payload = jwt!.split('.')[1];
      return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(payload))))
            as Map,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isTokenRefresh(http.BaseRequest request) =>
      request.method == 'POST' &&
      request.url.path.endsWith('/auth/v1/token') &&
      request.url.queryParameters['grant_type'] == 'refresh_token';

  /// The current session as a refresh answer, held until the server is back.
  /// Null for a Buyer, a guest, or when the request is not for this session.
  String? _heldSessionBody(http.BaseRequest request) {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final owner = HiveService.getUserId();
      final refreshToken = session?.refreshToken;
      if (session == null ||
          owner == null ||
          refreshToken == null ||
          session.user.id != owner ||
          !_offlineRoles.contains(HiveService.getUserRole()) ||
          request is! http.Request ||
          !request.body.contains(refreshToken)) {
        return null;
      }
      final parts = session.accessToken.split('.');
      final claims = _claimsOf(session.accessToken);
      if (parts.length != 3 || claims == null) return null;
      final expiresAt =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
      claims['exp'] = expiresAt;
      claims[_holdClaim] = true;
      final payload = base64Url
          .encode(utf8.encode(jsonEncode(claims)))
          .replaceAll('=', '');
      return jsonEncode({
        ...session.toJson(),
        'access_token': '${parts[0]}.$payload.${parts[2]}',
        'expires_in': 3600,
        'expires_at': expiresAt,
      });
    } catch (_) {
      return null;
    }
  }

  Future<http.StreamedResponse> _sendTokenRefresh(
    http.BaseRequest request,
  ) async {
    try {
      final streamed = await _inner
          .send(request)
          .timeout(const Duration(seconds: 6));
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(const Duration(seconds: 6));
      // Any answer from the server stands, including a refused refresh token.
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
        request: request,
      );
    } catch (_) {
      final held = _heldSessionBody(request);
      if (held == null) rethrow;
      return http.StreamedResponse(
        Stream.value(utf8.encode(held)),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
        request: request,
      );
    }
  }

  /// Swaps a held session for a real one. Returns the new access token, or
  /// null while the server still cannot be reached. One attempt at a time.
  Future<String?> _restoreSession(http.BaseRequest request) =>
      _restoring ??= _doRestoreSession(request).whenComplete(() {
        _restoring = null;
      });

  Future<String?> _doRestoreSession(http.BaseRequest request) async {
    try {
      final url = request.url;
      String? apiKey;
      for (final e in request.headers.entries) {
        if (e.key.toLowerCase() == 'apikey') apiKey = e.value;
      }
      // Any answer proves the server is reachable. Asked first so an offline
      // attempt never reaches the library's refresh (which would only be
      // answered with the held session again).
      await _inner
          .get(
            Uri(
              scheme: url.scheme,
              host: url.host,
              port: url.hasPort ? url.port : null,
              path: '/auth/v1/health',
            ),
            headers: {if (apiKey != null) 'apikey': apiKey},
          )
          .timeout(const Duration(seconds: 3));
      final result = await Supabase.instance.client.auth
          .refreshSession()
          .timeout(const Duration(seconds: 8));
      final token = result.session?.accessToken;
      if (token == null || _claimsOf(token)?[_holdClaim] == true) return null;
      return token;
    } catch (_) {
      return null;
    }
  }

  // ─── Saved pages after sign-in ─────────────────────────────────────────────
  //
  // Saved data is cleared at logout, so after the next sign-in every page was
  // empty offline until it had been opened again. Each saved read is therefore
  // remembered as a request (never its data). [preloadSavedPages] sends the
  // remembered requests that have no saved copy, quietly, while online.
  static OfflineReadClient? _instance;
  static const _maxRecipes = 600;
  static const _recipeLife = Duration(days: 21);

  final Map<String, Map<String, Map<dynamic, dynamic>>> _recipes = {};
  final Set<String> _dirtyRecipes = {};
  Timer? _recipeTimer;
  String? _apiKey;
  bool _preloading = false;

  Map<String, Map<dynamic, dynamic>> _recipesFor(String owner, String role) =>
      _recipes['$owner::$role'] ??= HiveService.getOfflineRecipes(owner, role);

  void _remember(
    String owner,
    String role,
    String key,
    http.BaseRequest request,
    String body,
  ) {
    try {
      final recipes = _recipesFor(owner, role);
      recipes[key] = {
        'm': request.method,
        'u': request.url.toString(),
        'h': {
          for (final e in request.headers.entries)
            if (e.key.toLowerCase() != 'authorization' &&
                e.key.toLowerCase() != 'apikey')
              e.key: e.value,
        },
        'b': body,
        't': DateTime.now().millisecondsSinceEpoch,
      };
      if (recipes.length > _maxRecipes) {
        final oldest = recipes.entries.toList()
          ..sort((a, b) => (a.value['t'] as int).compareTo(b.value['t'] as int));
        for (final e in oldest.take(recipes.length - _maxRecipes)) {
          recipes.remove(e.key);
        }
      }
      _dirtyRecipes.add('$owner::$role');
      _recipeTimer ??= Timer(const Duration(seconds: 3), _flushRecipes);
    } catch (_) {
      // Remembering a page is a convenience; it never fails a read.
    }
  }

  void _flushRecipes() {
    _recipeTimer = null;
    for (final id in _dirtyRecipes.toList()) {
      final parts = id.split('::');
      final recipes = _recipes[id];
      if (recipes != null) {
        unawaited(
          HiveService.saveOfflineRecipes(
            parts[0],
            parts[1],
            recipes,
          ).catchError((_) {}),
        );
      }
    }
    _dirtyRecipes.clear();
  }

  /// Saves again, in the background, the pages this user loaded before that
  /// have no saved copy now (after a sign-in). Does nothing offline, for a
  /// Buyer, or while it is already running. Never throws.
  static Future<void> preloadSavedPages() async {
    try {
      await _instance?._preload();
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> _preload() async {
    final owner = HiveService.getUserId();
    final role = HiveService.getUserRole();
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    final apiKey = _apiKey;
    if (_preloading ||
        owner == null ||
        role == null ||
        token == null ||
        apiKey == null ||
        !_offlineRoles.contains(role) ||
        _claimsOf(token)?['sub'] != owner ||
        _claimsOf(token)?[_holdClaim] == true ||
        !ConnectivityService.instance.isOnline) {
      return;
    }
    _preloading = true;
    try {
      final recipes = _recipesFor(owner, role);
      final cutoff = DateTime.now().subtract(_recipeLife).millisecondsSinceEpoch;
      recipes.removeWhere((_, r) => (r['t'] as int? ?? 0) < cutoff);
      final missing =
          recipes.entries
              .where((e) => HiveService.cacheBox.get(e.key) == null)
              .toList()
            ..sort(
              (a, b) => (b.value['t'] as int).compareTo(a.value['t'] as int),
            );
      var failures = 0;
      var next = 0;
      Future<void> worker() async {
        while (next < missing.length && failures < 4) {
          final entry = missing[next++];
          if (HiveService.getUserId() != owner ||
              HiveService.getUserRole() != role) {
            return;
          }
          try {
            final r = entry.value;
            final request = http.Request(
              r['m'] as String,
              Uri.parse(r['u'] as String),
            );
            request.headers.addAll(Map<String, String>.from(r['h'] as Map));
            request.headers['Authorization'] = 'Bearer $token';
            request.headers['apikey'] = apiKey;
            final body = r['b'] as String? ?? '';
            if (body.isNotEmpty) request.bodyBytes = base64Decode(body);
            final response = await http.Response.fromStream(
              await _inner.send(request).timeout(const Duration(seconds: 10)),
            ).timeout(const Duration(seconds: 10));
            if (response.statusCode >= 200 &&
                response.statusCode < 300 &&
                HiveService.getUserId() == owner &&
                HiveService.cacheBox.get(entry.key) == null) {
              await HiveService.cacheBox.put(entry.key, {
                'body': base64Encode(response.bodyBytes),
                'status': response.statusCode,
                'headers': response.headers,
                'savedAt': DateTime.now().toIso8601String(),
              });
            } else if (response.statusCode >= 400 &&
                response.statusCode < 500) {
              // The page no longer exists or is no longer allowed.
              recipes.remove(entry.key);
              _dirtyRecipes.add('$owner::$role');
            }
          } catch (_) {
            failures++;
          }
        }
      }

      await Future.wait([for (var i = 0; i < 4; i++) worker()]);
      if (_dirtyRecipes.isNotEmpty) _flushRecipes();
    } finally {
      _preloading = false;
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_isTokenRefresh(request)) return _sendTokenRefresh(request);

    final owner = HiveService.getUserId();
    final role = HiveService.getUserRole();
    String? authKey;
    String? bearer;
    for (final e in request.headers.entries) {
      if (e.key.toLowerCase() == 'authorization') {
        authKey = e.key;
        bearer = e.value.split(' ').last;
      }
    }
    // Public/anonymous requests never become a private user's snapshot.
    for (final e in request.headers.entries) {
      if (e.key.toLowerCase() == 'apikey') _apiKey = e.value;
    }
    final claims = _claimsOf(bearer);
    final requestOwner = claims?['sub'] as String?;
    final eligible =
        owner != null &&
        requestOwner == owner &&
        _offlineRoles.contains(role);
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

    // A held session (see above) is replaced before anything is sent with it.
    // Known-offline requests skip the attempt so saved pages open at once; the
    // connectivity probe always tries, which is how reconnecting is noticed.
    var held = false;
    if (claims?[_holdClaim] == true) {
      final isProbe = rpc && segments.last == 'ping';
      final token = ConnectivityService.instance.isOnline || isProbe
          ? await _restoreSession(request)
          : null;
      if (token != null && authKey != null) {
        request.headers[authKey] = 'Bearer $token';
      } else {
        held = true;
      }
    }

    final read = rpc
        ? _readRpcs.contains(segments.last) &&
              const ['GET', 'HEAD', 'POST'].contains(request.method)
        : request.method == 'GET' || request.method == 'HEAD';
    // Account status & active session checks must always be live verdicts;
    // offline routing uses the explicitly saved local session instead.
    final accountStatus =
        rest &&
        !rpc &&
        (segments[2] == 'user_roles' ||
            segments[2] == 'user_active_sessions');
    if (!eligible || !rest || !read || accountStatus) {
      if (held) {
        throw http.ClientException('No internet connection.', request.url);
      }
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

    final savedOnly = Zone.current[OfflineCache.savedReadZoneKey] == true;
    if (held || savedOnly || !ConnectivityService.instance.isOnline) {
      final cached = snapshot();
      if (cached != null) return cached;
      // A list load reports its own miss after trying its other saved copy.
      if (!savedOnly &&
          Zone.current[OfflineCache.liveFetchZoneKey] != true) {
        OfflineCache.reportOfflineMiss();
      }
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
        _remember(owner, role!, key, request, body);
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
