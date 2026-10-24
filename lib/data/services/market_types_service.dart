import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/foundation.dart'
    show ChangeNotifier, debugPrint, visibleForTesting;
import 'app_settings_service.dart';
import 'connectivity_service.dart';
import 'hive_service.dart';
import 'offline_cache.dart';

/// One row of `market_types`: who can see and buy listings of this type.
/// SAGANA has two (Public, Cooperative); the rows, not this code, define them.
class MarketType {
  final String code;
  final String name;
  final String? nameTl;
  final bool buyerVisible;
  final bool managerSetsPrice;
  final int sortOrder;
  final bool isActive;

  const MarketType({
    required this.code,
    required this.name,
    this.nameTl,
    required this.buyerVisible,
    required this.managerSetsPrice,
    required this.sortOrder,
    required this.isActive,
  });

  factory MarketType.fromMap(Map<String, dynamic> m) => MarketType(
    code: m['code'] as String,
    name: m['name'] as String,
    nameTl: m['name_tl'] as String?,
    buyerVisible: m['buyer_visible'] as bool? ?? false,
    managerSetsPrice: m['manager_sets_price'] as bool? ?? false,
    sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
    isActive: m['is_active'] as bool? ?? true,
  );
}

/// One row of `selling_channels`: how a farmer sells a harvested batch.
class SellingChannel {
  final String code;
  final String name;
  final String? nameTl;
  final bool requiresExclusiveCrop;

  const SellingChannel({
    required this.code,
    required this.name,
    this.nameTl,
    required this.requiresExclusiveCrop,
  });

  factory SellingChannel.fromMap(Map<String, dynamic> m) => SellingChannel(
    code: m['code'] as String,
    name: m['name'] as String,
    nameTl: m['name_tl'] as String?,
    requiresExclusiveCrop: m['requires_exclusive_crop'] as bool? ?? false,
  );
}

/// Single, cached source of the market types and selling channels.
///
/// Market types are DATA (database table `market_types`), so a label, a colour
/// choice or "can a Buyer see this?" is never decided by comparing a code to a
/// literal in a screen. Loaded once after sign-in (and at start-up when already
/// signed in) and kept in memory so widgets can read it synchronously. The
/// last successful load is also kept offline through [OfflineCache].
class MarketTypes extends ChangeNotifier {
  MarketTypes._();
  static final MarketTypes instance = MarketTypes._();

  static const _cacheMarketTypes = 'market_types';
  static const _cacheChannels = 'selling_channels';

  List<MarketType> _types = const [];
  List<SellingChannel> _channels = const [];

  List<MarketType> get types => _types;

  /// Active market types in display order — the options for every market-type
  /// dropdown and filter.
  List<MarketType> get activeTypes =>
      _types.where((t) => t.isActive).toList(growable: false);

  List<SellingChannel> get channels => _channels;

  /// Bumped every time a refresh actually changes the data, so a screen can
  /// tell "something changed" without comparing lists.
  int _version = 0;
  int get version => _version;

  StreamSubscription<List<Map<String, dynamic>>>? _typesSub;
  StreamSubscription<List<Map<String, dynamic>>>? _channelsSub;
  StreamSubscription<bool>? _connectivitySub;
  Timer? _debounce;

  /// Reads both tables (falling back to the offline snapshot). Never throws:
  /// a failed load leaves whatever was loaded before. Listeners are told only
  /// when something really changed.
  Future<void> refresh() async {
    final client = Supabase.instance.client;
    var changed = false;
    try {
      final typeRows = await OfflineCache.load(
        screen: _cacheMarketTypes,
        fetch: () => client
            .from('market_types')
            .select()
            .order('sort_order')
            .order('name'),
      );
      final next = typeRows.map(MarketType.fromMap).toList(growable: false);
      if (!_sameTypes(_types, next)) {
        _types = next;
        changed = true;
      }
    } catch (e) {
      debugPrint('MarketTypes.refresh (market_types) failed: $e');
    }
    try {
      final channelRows = await OfflineCache.load(
        screen: _cacheChannels,
        fetch: () =>
            client.from('selling_channels').select().order('sort_order'),
      );
      final next = channelRows
          .map(SellingChannel.fromMap)
          .toList(growable: false);
      if (!_sameChannels(_channels, next)) {
        _channels = next;
        changed = true;
      }
    } catch (e) {
      debugPrint('MarketTypes.refresh (selling_channels) failed: $e');
    }
    if (changed) {
      _version++;
      notifyListeners();
    }
  }

  static bool _sameTypes(List<MarketType> a, List<MarketType> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.code != y.code ||
          x.name != y.name ||
          x.nameTl != y.nameTl ||
          x.buyerVisible != y.buyerVisible ||
          x.managerSetsPrice != y.managerSetsPrice ||
          x.sortOrder != y.sortOrder ||
          x.isActive != y.isActive) {
        return false;
      }
    }
    return true;
  }

  static bool _sameChannels(List<SellingChannel> a, List<SellingChannel> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.code != y.code ||
          x.name != y.name ||
          x.nameTl != y.nameTl ||
          x.requiresExclusiveCrop != y.requiresExclusiveCrop) {
        return false;
      }
    }
    return true;
  }

  /// Keeps this copy current without a restart or a new sign-in: listens for
  /// changes to market_types / selling_channels (realtime) and re-reads them.
  /// The app also calls [refresh] when it returns to the foreground and when
  /// the connection comes back. Safe to call again; call [stop] on sign-out.
  void start() {
    stop();
    final client = Supabase.instance.client;
    void onChange(List<Map<String, dynamic>> _) {
      // The initial snapshot and a burst of row changes collapse into one read.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        unawaited(refresh());
      });
    }

    void onError(Object e) => debugPrint('MarketTypes realtime error: $e');
    // A device that was offline picks the latest rules up as soon as it is back.
    _connectivitySub = ConnectivityService.instance.onConnectivityChanged
        .listen((online) {
          if (online) unawaited(refresh());
        });
    _typesSub = client
        .from('market_types')
        .stream(primaryKey: ['code'])
        .listen(onChange, onError: onError);
    _channelsSub = client
        .from('selling_channels')
        .stream(primaryKey: ['code'])
        .listen(onChange, onError: onError);
  }

  void stop() {
    _debounce?.cancel();
    _debounce = null;
    _typesSub?.cancel();
    _typesSub = null;
    _channelsSub?.cancel();
    _channelsSub = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  /// Whether the signed-in account may SEE items of market type [code]. Used on
  /// rows served from the offline cache, so a stale snapshot can never show a
  /// listing the current rules hide. The database applies the same rule to
  /// live data; this only mirrors it for what was saved earlier.
  ///   - no market type, or nothing loaded yet: shown (the server decides)
  ///   - Manager / Officer / approved Farmer: every market
  ///   - anyone else (a Buyer): only buyer-visible markets
  bool visibleToCurrentUser(String? code) => visibleTo(
    code,
    role: HiveService.getUserRole(),
    approvedFarmer:
        HiveService.getMemberStatus() == 'active' &&
        !HiveService.getPendingAcknowledgement(),
  );

  /// The same rule with the account passed in (see [visibleToCurrentUser]).
  bool visibleTo(
    String? code, {
    required String? role,
    required bool approvedFarmer,
  }) {
    if (code == null || _types.isEmpty) return true;
    if (role == 'admin' || role == 'officer') return true;
    if (role == 'farmer' && approvedFarmer) return true;
    return isBuyerVisible(code);
  }

  /// Test seam: replaces the loaded data without touching the database.
  @visibleForTesting
  void debugSet({
    List<MarketType> types = const [],
    List<SellingChannel> channels = const [],
  }) {
    _types = types;
    _channels = channels;
  }

  MarketType? byCode(String? code) {
    if (code == null) return null;
    for (final t in _types) {
      if (t.code == code) return t;
    }
    return null;
  }

  SellingChannel? channelByCode(String? code) {
    if (code == null) return null;
    for (final c in _channels) {
      if (c.code == code) return c;
    }
    return null;
  }

  bool get _isTagalog => AppSettingsService.instance.locale.languageCode == 'tl';

  /// Display name for a market-type code, in the app's language. An unknown or
  /// not-yet-loaded code is shown readably (never a raw code, never guessed to
  /// be a particular market).
  String label(String? code) {
    if (code == null) return 'Not yet assigned';
    final t = byCode(code);
    if (t == null) return _humanize(code);
    final tl = t.nameTl;
    return (_isTagalog && tl != null && tl.isNotEmpty) ? tl : t.name;
  }

  /// A compact name for narrow places (badges, chips): the market's name
  /// without the word "Market" ("Public", "Cooperative"). Falls back to the full
  /// name when nothing is left.
  String shortLabel(String? code) {
    final full = label(code);
    final short = full
        .replaceAll(RegExp(r'^Market ng ', caseSensitive: false), '')
        .replaceAll(RegExp(r's*Markets*', caseSensitive: false), ' ')
        .trim();
    return short.isEmpty ? full : short;
  }

  String channelLabel(String? code) {
    if (code == null) return '';
    final c = channelByCode(code);
    if (c == null) return _humanize(code);
    final tl = c.nameTl;
    return (_isTagalog && tl != null && tl.isNotEmpty) ? tl : c.name;
  }

  /// May a Buyer see and purchase listings of this market type? An unknown
  /// code is treated as NOT visible (the database rule is the authority; this
  /// only drives colours and labels).
  bool isBuyerVisible(String? code) => byCode(code)?.buyerVisible ?? false;

  /// The first buyer-visible active type: the default for a new crop or request.
  String? get defaultCode {
    for (final t in activeTypes) {
      if (t.buyerVisible) return t.code;
    }
    return activeTypes.isEmpty ? null : activeTypes.first.code;
  }

  static String _humanize(String code) => code
      .split('_')
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1))
      .join(' ');
}
