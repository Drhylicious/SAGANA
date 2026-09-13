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

  static const _reachabilityTimeout = Duration(seconds: 3);
  static const _reachabilityInterval = Duration(seconds: 30);

  // ─── Initialize ──────────────────────────────────────────────────────────────

  Future<void> init() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = _isConnected(result);

    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final online = _isConnected(result);
      if (online != _isOnline) {
        _isOnline = online;
        _controller.add(_isOnline);
      }
    });

    // Interface-level checks can't tell a live pisonet link from a dead
    // one — both report the same ConnectivityResult. This periodically
    // confirms actual reachability and corrects _isOnline (and every
    // screen listening to onConnectivityChanged) without any of those
    // 19 screens needing to change.
    _reachabilityTimer = Timer.periodic(_reachabilityInterval, (_) => _probeIfConnected());
  }

  bool _isConnected(ConnectivityResult result) {
    return result == ConnectivityResult.mobile ||
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.ethernet;
  }

  Future<void> _probeIfConnected() async {
    if (!_isOnline) return; // already known down — nothing to correct
    final reachable = await _isReachable();
    if (reachable != _isOnline) {
      _isOnline = reachable;
      _controller.add(_isOnline);
    }
  }

  Future<bool> _isReachable() async {
    try {
      await Supabase.instance.client.rpc('ping').timeout(_reachabilityTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Interface presence, then actual reachability. Every write-path caller
  /// (Loan issuance/payment, Harvest, Expense, SyncService) already awaits
  /// this, so the added round trip is safe here — bounded by
  /// _reachabilityTimeout, not left to hang.
  Future<bool> checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    if (!_isConnected(result)) {
      _isOnline = false;
      return false;
    }
    _isOnline = await _isReachable();
    return _isOnline;
  }

  void dispose() {
    _subscription?.cancel();
    _reachabilityTimer?.cancel();
    _controller.close();
  }
}