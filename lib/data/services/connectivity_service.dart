import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService _instance = ConnectivityService._();
  static ConnectivityService get instance => _instance;

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  Stream<bool> get onConnectivityChanged => _controller.stream;
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  StreamSubscription? _subscription;
  Timer? _reachabilityTimer;
  Future<bool>? _checking;
  int _interfaceRevision = 0;

  static const _reachabilityTimeout = Duration(seconds: 3);
  static const _reachabilityInterval = Duration(seconds: 30);

  // ─── Initialize ──────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_subscription != null) return;
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      _interfaceRevision++;
      if (!_isConnected(result)) {
        _publish(false);
      } else {
        unawaited(checkConnectivity());
      }
    });
    await checkConnectivity();

    // Interface-level checks can't tell a live pisonet link from a dead
    // one — both report the same ConnectivityResult. This periodically
    // confirms actual reachability and corrects _isOnline (and every
    // screen listening to onConnectivityChanged) without any of those
    // 19 screens needing to change.
    _reachabilityTimer = Timer.periodic(_reachabilityInterval, (_) {
      unawaited(checkConnectivity());
    });
  }

  bool _isConnected(ConnectivityResult result) {
    return result != ConnectivityResult.none;
  }

  void _publish(bool online) {
    if (_isOnline == online) return;
    _isOnline = online;
    _controller.add(online);
  }

  Future<bool> _isReachable() async {
    try {
      await Supabase.instance.client.rpc('ping').timeout(_reachabilityTimeout);
      return true;
    } on PostgrestException {
      // A backend error still proves reachability. A missing ping RPC or an
      // expired token must not mislabel a working connection as offline.
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Interface presence, then actual reachability. Every write-path caller
  /// (Loan issuance/payment, Harvest, Expense, SyncService) already awaits
  /// this, so the added round trip is safe here — bounded by
  /// _reachabilityTimeout, not left to hang.
  Future<bool> checkConnectivity() => _checking ??= _check().whenComplete(() {
    _checking = null;
  });

  Future<bool> _check() async {
    while (true) {
      final revision = _interfaceRevision;
      var online = false;
      try {
        final result = await _connectivity.checkConnectivity();
        online = _isConnected(result) && await _isReachable();
      } catch (_) {
        online = false;
      }
      // A reconnect can arrive during the shared probe. Recheck that new
      // interface before completing, rather than waiting for the next timer.
      if (revision != _interfaceRevision) continue;
      _publish(online);
      return _isOnline;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _reachabilityTimer?.cancel();
    _controller.close();
  }
}
