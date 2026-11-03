import 'dart:async';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'hive_service.dart';

/// The five modules an Officer's access is set for. [key] is the value stored in
/// `officer_permissions.module`.
enum StaffModule {
  dashboard,
  members,
  marketplace,
  loans,
  reports;

  String get key => name;

  static StaffModule? fromKey(String? key) {
    for (final m in StaffModule.values) {
      if (m.key == key) return m;
    }
    return null;
  }
}

/// View Only sees everything in the module; Manage may also act on it.
enum StaffAccess {
  view,
  manage;

  String get key => name;

  static StaffAccess fromKey(String? key) =>
      key == 'manage' ? StaffAccess.manage : StaffAccess.view;
}

/// What the signed-in Manager or Officer may do in each module.
///
/// The database is the authority (the request gate refuses a write without
/// Manage), so this class only decides what to SHOW: which buttons are enabled
/// and which screens open. A Manager always has Manage everywhere. An Officer's
/// levels come from `get_my_staff_permissions()`; until they are known (or when
/// they cannot be read) every module falls back to View Only, never Manage.
///
/// Kept fresh by: sign-in, app start, returning to the foreground, and a live
/// listener on the Officer's own `officer_permissions` rows so a change made by
/// the Manager applies without signing out.
class StaffPermissions extends ChangeNotifier {
  StaffPermissions._();
  static final StaffPermissions instance = StaffPermissions._();

  Map<StaffModule, StaffAccess> _levels = _fromCache();
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  // The signed-in role, from the local session. Never throws: before the local
  // store is open (or in a test) there is simply no role, so no Manage.
  static String? get _role {
    try {
      return HiveService.getUserRole();
    } catch (_) {
      return null;
    }
  }

  static bool get _isManager => _role == 'admin';
  static bool get _isOfficer => _role == 'officer';

  /// The level for [module]. Managers: always manage. Officers: the loaded
  /// level, else view. Everyone else: view (they never reach these screens).
  StaffAccess levelFor(StaffModule module) {
    if (_isManager) return StaffAccess.manage;
    return _levels[module] ?? StaffAccess.view;
  }

  bool canManage(StaffModule module) =>
      levelFor(module) == StaffAccess.manage;

  /// Every staff member can open and read every module.
  bool canView(StaffModule module) => _isManager || _isOfficer;

  /// The current levels as the module -> level map the RPCs use.
  Map<String, String> get asJson => {
    for (final m in StaffModule.values) m.key: levelFor(m).key,
  };

  /// Parses the `{"dashboard": "manage", ...}` object the database returns.
  /// Unknown modules are ignored; a missing module is View Only.
  static Map<StaffModule, StaffAccess> parse(Object? json) {
    final out = <StaffModule, StaffAccess>{};
    if (json is Map) {
      for (final entry in json.entries) {
        final module = StaffModule.fromKey(entry.key as String?);
        if (module != null) {
          out[module] = StaffAccess.fromKey(entry.value as String?);
        }
      }
    }
    return out;
  }

  static Map<StaffModule, StaffAccess> _fromCache() {
    try {
      return parse(HiveService.getStaffAccess());
    } catch (_) {
      return const {};
    }
  }

  /// Reads the signed-in staff member's levels from the database. Never throws:
  /// offline, the last known levels (or View Only) stay in force.
  Future<void> refresh() async {
    if (!_isOfficer) {
      // A Manager needs no lookup; anyone else has no staff levels.
      if (_levels.isNotEmpty) {
        _levels = const {};
        notifyListeners();
      }
      return;
    }
    try {
      final result = await Supabase.instance.client.rpc(
        'get_my_staff_permissions',
      );
      final next = parse(result);
      await HiveService.saveStaffAccess(
        next.map((k, v) => MapEntry(k.key, v.key)),
      );
      if (!_same(_levels, next)) {
        _levels = next;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('StaffPermissions.refresh failed: $e');
    }
  }

  /// Listens for changes to the signed-in Officer's own permission rows.
  void start() {
    stop();
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || !_isOfficer) return;
    try {
      _sub = Supabase.instance.client
          .from('officer_permissions')
          .stream(primaryKey: ['user_id', 'module'])
          .eq('user_id', uid)
          .listen(
            (_) => unawaited(refresh()),
            onError: (Object e) =>
                debugPrint('StaffPermissions: realtime error: $e'),
          );
    } catch (e) {
      debugPrint('StaffPermissions.start failed: $e');
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// Forgets everything (sign-out).
  void clear() {
    stop();
    if (_levels.isNotEmpty) {
      _levels = const {};
      notifyListeners();
    }
  }

  /// Test hook: set the levels without touching the database.
  void debugSet(Map<StaffModule, StaffAccess> levels) {
    _levels = levels;
    notifyListeners();
  }

  static bool _same(
    Map<StaffModule, StaffAccess> a,
    Map<StaffModule, StaffAccess> b,
  ) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}
