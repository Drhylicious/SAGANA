import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/notification_repository.dart';
import 'app_event_service.dart';
import 'table_change_watcher.dart';

/// The one source of truth for the red dot on the notification icon.
///
/// Every primary screen of every role (Buyer, Farmer, Manager, Officer) draws
/// its bell from this, so the dot follows the user from tab to tab instead of
/// depending on whichever screen happened to load a count. It refreshes when:
///  - the app starts or someone signs in (and clears on sign-out);
///  - a notification is read or marked unread (AppEventService.notify());
///  - a notification arrives or changes (realtime on `notifications`);
///  - the app returns to the foreground ([refresh], called from main.dart).
class NotificationBadgeService extends ChangeNotifier {
  NotificationBadgeService._();
  static final NotificationBadgeService instance = NotificationBadgeService._();

  int _unread = 0;
  bool _started = false;
  bool _refreshing = false;
  bool _refreshAgain = false;
  TableChangeWatcher? _watcher;

  /// How many notifications are unread for the signed-in user.
  int get unread => _unread;
  bool get hasUnread => _unread > 0;

  /// Call once at start-up, after Supabase is initialised.
  void start() {
    if (_started) return;
    _started = true;
    AppEventService.instance.addListener(_onEvent);
    try {
      // Lives as long as the app, so the subscription is never cancelled.
      Supabase.instance.client.auth.onAuthStateChange.listen((s) {
        if (s.session == null) {
          _set(0);
        } else {
          _restartWatcher();
          unawaited(refresh());
        }
      });
    } catch (_) {
      // No Supabase (tests): the badge simply stays at 0.
    }
    _restartWatcher();
    unawaited(refresh());
  }

  void _onEvent() => unawaited(refresh());

  void _restartWatcher() {
    _watcher?.dispose();
    _watcher = TableChangeWatcher(
      tables: const ['notifications'],
      onChange: () => unawaited(refresh()),
    )..start();
  }

  /// Re-reads the unread count. Overlapping calls are merged into one follow-up.
  Future<void> refresh() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        _set(await NotificationRepository().fetchUnreadCount());
      } while (_refreshAgain);
    } catch (_) {
      // Keep the last known count.
    } finally {
      _refreshing = false;
    }
  }

  void _set(int value) {
    if (value == _unread) return;
    _unread = value;
    notifyListeners();
  }
}
