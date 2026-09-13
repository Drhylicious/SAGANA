import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/notification_model.dart';

class NotificationRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  // ─── Fetch all notifications for current user ─────────────────────────────

  Future<List<NotificationModel>> fetchNotifications() async {
    try {
      final rows = await _client
          .from('notifications')
          .select()
          .eq('user_id', _userId)
          .order('created_at', ascending: false);

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

  Future<void> markAsRead(String notificationId) async {
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

  Future<void> markAllAsRead() async {
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

  Future<void> deleteNotification(String notificationId) async {
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

  Future<void> deleteAllNotifications() async {
    try {
      await _client
          .from('notifications')
          .delete()
          .eq('user_id', _userId);
    } catch (e) {
      debugPrint('NotificationRepository.deleteAllNotifications failed: $e');
    }
  }
}
