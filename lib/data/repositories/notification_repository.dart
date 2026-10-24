import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/notification_model.dart';
import '../services/offline_actions.dart';
import '../services/offline_cache.dart';

/// One notification row to be created via [NotificationRepository.createNotification]
/// or [NotificationRepository.createNotifications]. Mirrors the notifications
/// table's insertable columns exactly — no new fields, no behavior change
/// versus the direct `.insert()` calls this replaces.
class NotificationDraft {
  final String userId;
  final String type;
  final String title;
  final String body;
  final DateTime? createdAt;
  final String? routeOnTap;
  final String? routeExtra;

  const NotificationDraft({
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.createdAt,
    this.routeOnTap,
    this.routeExtra,
  });

  Map<String, dynamic> toRow(DateTime fallbackNow) => {
    'user_id': userId,
    'type': type,
    'title': title,
    'body': body,
    'is_read': false,
    'created_at': (createdAt ?? fallbackNow).toIso8601String(),
    'route_on_tap': routeOnTap,
    'route_extra': routeExtra,
  };
}

class NotificationRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  // ─── Create notification(s) ────────────────────────────────────────────────
  // Shared insert path for every notification-creation call site (previously
  // each repository hand-wrote its own `.insert()` into `notifications`).
  // Callers keep their own error handling — these methods do not catch or
  // swallow exceptions themselves.

  Future<void> createNotification({
    required String userId,
    required String type,
    required String title,
    required String body,
    DateTime? createdAt,
    String? routeOnTap,
    String? routeExtra,
  }) {
    return createNotifications([
      NotificationDraft(
        userId: userId,
        type: type,
        title: title,
        body: body,
        createdAt: createdAt,
        routeOnTap: routeOnTap,
        routeExtra: routeExtra,
      ),
    ]);
  }

  Future<void> createNotifications(List<NotificationDraft> drafts) async {
    if (drafts.isEmpty) return;
    final now = DateTime.now();
    await _client
        .from('notifications')
        .insert(drafts.map((d) => d.toRow(now)).toList());
  }

  // ─── Fetch all notifications for current user ─────────────────────────────

  Future<List<NotificationModel>> fetchNotifications() async {
    try {
      final rows = await OfflineCache.load(
        screen: 'notifications',
        fetch: () => _client
            .from('notifications')
            .select()
            .eq('user_id', _userId)
            .order('created_at', ascending: false),
      );

      return rows.map((r) => NotificationModel.fromMap(r)).toList();
    } catch (e) {
      debugPrint('NotificationRepository.fetchNotifications failed: $e');
      return [];
    }
  }

  // ─── Unread count ─────────────────────────────────────────────────────────

  Future<int> fetchUnreadCount() async {
    try {
      final rows = await _client
          .from('notifications')
          .select('id')
          .eq('user_id', _userId)
          .eq('is_read', false);
      return rows.length;
    } catch (e) {
      debugPrint('NotificationRepository.fetchUnreadCount failed: $e');
      return 0;
    }
  }

  // ─── Mark single notification as read ────────────────────────────────────

  /// Marks one notification read now, or on the next Sync when offline.
  Future<SaveOutcome> markAsRead(
    String notificationId, {
    bool queueWhenOffline = true,
  }) => OfflineActions.run(
    kind: 'notification_read',
    payload: {'id': notificationId},
    queueWhenOffline: queueWhenOffline,
    online: () => markAsReadOnline(notificationId),
  );

  Future<void> markAsReadOnline(String notificationId) async {
    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId)
          .eq('user_id', _userId);
    } catch (e) {
      debugPrint('NotificationRepository.markAsRead failed: $e');
    }
  }

  // ─── Mark all notifications as read ──────────────────────────────────────

  /// Marks every unread notification read now, or on the next Sync when offline.
  Future<SaveOutcome> markAllAsRead({bool queueWhenOffline = true}) =>
      OfflineActions.run(
        kind: 'notification_read_all',
        payload: const {},
        queueWhenOffline: queueWhenOffline,
        online: markAllAsReadOnline,
      );

  Future<void> markAllAsReadOnline() async {
    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', _userId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('NotificationRepository.markAllAsRead failed: $e');
    }
  }

  // ─── Delete single notification ───────────────────────────────────────────

  /// Deletes one notification now, or on the next Sync when offline.
  Future<SaveOutcome> deleteNotification(
    String notificationId, {
    bool queueWhenOffline = true,
  }) => OfflineActions.run(
    kind: 'notification_delete',
    payload: {'id': notificationId},
    queueWhenOffline: queueWhenOffline,
    online: () => deleteNotificationOnline(notificationId),
  );

  Future<void> deleteNotificationOnline(String notificationId) async {
    try {
      await _client
          .from('notifications')
          .delete()
          .eq('id', notificationId)
          .eq('user_id', _userId);
    } catch (e) {
      debugPrint('NotificationRepository.deleteNotification failed: $e');
    }
  }

  // ─── Delete all notifications for current user ────────────────────────────

  /// Deletes every notification now, or on the next Sync when offline.
  Future<SaveOutcome> deleteAllNotifications({bool queueWhenOffline = true}) =>
      OfflineActions.run(
        kind: 'notification_delete_all',
        payload: const {},
        queueWhenOffline: queueWhenOffline,
        online: deleteAllNotificationsOnline,
      );

  Future<void> deleteAllNotificationsOnline() async {
    try {
      await _client.from('notifications').delete().eq('user_id', _userId);
    } catch (e) {
      debugPrint('NotificationRepository.deleteAllNotifications failed: $e');
    }
  }
}
