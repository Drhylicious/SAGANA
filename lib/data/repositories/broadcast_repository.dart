import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/broadcast_model.dart';
import 'admin_activity_repository.dart';
import 'notification_repository.dart';

class BroadcastRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Fetch recent broadcast history ──────────────────────────────────────

Future<List<BroadcastModel>> fetchRecentBroadcasts({int limit = 20}) async {
  try {
    final rows = await _client
        .from('broadcast_logs')
        .select()
        .not('sent_at', 'is', null)
        .order('sent_at', ascending: false)
        .limit(limit);
    return rows.map((r) => BroadcastModel.fromMap(r)).toList();
  } catch (e) {
    debugPrint('BroadcastRepository.fetchRecentBroadcasts failed: $e');
    return [];
  }
}

Future<List<BroadcastModel>> fetchBroadcastHistory({int limit = 100}) async {
  try {
    final rows = await _client
        .from('broadcast_logs')
        .select()
        .order('sent_at', ascending: false, nullsFirst: false)
        .limit(limit);
    return rows.map((r) => BroadcastModel.fromMap(r)).toList();
  } catch (e) {
    debugPrint('BroadcastRepository.fetchBroadcastHistory failed: $e');
    return [];
  }
}

  // ─── Resolve recipient user IDs based on type ─────────────────────────────

  Future<List<String>> resolveRecipientIds({
    required RecipientType type,
    String? filter, // crop name for specificCrop, user_id for specificFarmer
  }) async {
    try {
      switch (type) {
        case RecipientType.allMembers:
          final rows = await _client
              .from('user_roles')
              .select('user_id')
              .eq('role', 'farmer')
              .eq('status', 'active');
          return rows.map((r) => r['user_id'] as String).toList();

        case RecipientType.allBuyers:
          final rows = await _client
              .from('user_roles')
              .select('user_id')
              .eq('role', 'buyer')
              .eq('status', 'active');
          return rows.map((r) => r['user_id'] as String).toList();

        case RecipientType.outstandingLoans:
          final rows = await _client
              .from('farmer_loans')
              .select('farmer_id')
              .neq('status', 'paid');
          return rows.map((r) => r['farmer_id'] as String).toSet().toList();

        case RecipientType.specificCrop:
          if (filter == null || filter.isEmpty) return [];
          final rows = await _client
              .from('farmer_crops')
              .select('farmer_id')
              .ilike('crop_name', filter);
          return rows.map((r) => r['farmer_id'] as String).toSet().toList();

        case RecipientType.specificFarmer:
          if (filter == null || filter.isEmpty) return [];
          return [filter];

        case RecipientType.specificBuyer:
          if (filter == null || filter.isEmpty) return [];
          return [filter];
      }
    } catch (e) {
      debugPrint('BroadcastRepository.resolveRecipientIds failed: $e');
      return [];
    }
  }

  // ─── Send broadcast ───────────────────────────────────────────────────────
  // 1. Resolves recipient IDs
  // 2. Inserts notification rows into notifications table
  // 3. Logs to broadcast_logs

  Future<int> sendBroadcast({
    required String title,
    required String body,
    required BroadcastCategory category,
    required RecipientType recipientType,
    String? recipientFilter,
    DateTime? scheduledAt,
  }) async {
    final adminId = _client.auth.currentUser?.id;
    final now     = DateTime.now();
    final isDeferred = scheduledAt != null && scheduledAt.isAfter(now);

    // 1. Resolve recipients now — for an immediate send this is the actual
    //    recipient list; for a deferred one it's only an estimate for
    //    display (recipient_count gets overwritten with the real count
    //    once process_scheduled_broadcasts() actually sends it, since the
    //    matching set — e.g. outstanding loans — can shift by then).
    final recipientIds = await resolveRecipientIds(
      type:   recipientType,
      filter: recipientFilter,
    );

    if (!isDeferred && recipientIds.isEmpty) return 0;

    if (isDeferred) {
      // Queue only. Notifications are inserted later, once scheduled_at
      // has passed, by process_scheduled_broadcasts() (run periodically —
      // see supabase/functions/process-scheduled-broadcasts).
      await _client.from('broadcast_logs').insert({
        'title':            title,
        'body':             body,
        'category':         category.value,
        'recipient_type':   recipientType.value,
        'recipient_filter': recipientFilter,
        'recipient_count':  recipientIds.length,
        'scheduled_at':     scheduledAt.toIso8601String(),
        'sent_at':          null,
        'created_by':       adminId,
        'created_at':       now.toIso8601String(),
      });

      AdminActivityRepository().log(
        module: 'broadcast',
        actionType: 'scheduled',
        description: 'Broadcast "$title" scheduled for ${scheduledAt.toIso8601String()}.',
      );

      return recipientIds.length;
    }

    // 2. Insert notification rows for each recipient (immediate send)
    final notifDrafts = recipientIds
        .map((uid) => NotificationDraft(
              userId: uid,
              type: 'system',
              title: title,
              body: body,
              createdAt: now,
            ))
        .toList();

    await NotificationRepository().createNotifications(notifDrafts);

    // 3. Log the broadcast
    await _client.from('broadcast_logs').insert({
      'title':            title,
      'body':             body,
      'category':         category.value,
      'recipient_type':   recipientType.value,
      'recipient_filter': recipientFilter,
      'recipient_count':  recipientIds.length,
      'scheduled_at':     scheduledAt?.toIso8601String(),
      'sent_at':          now.toIso8601String(),
      'created_by':       adminId,
      'created_at':       now.toIso8601String(),
    });

    AdminActivityRepository().log(
      module: 'broadcast',
      actionType: 'sent',
      description: 'Broadcast "$title" sent to ${recipientIds.length} recipient${recipientIds.length == 1 ? '' : 's'}.',
    );

    return recipientIds.length;
  }

  // ─── Fetch dynamic recipient count preview ────────────────────────────────
  // Called live when admin changes recipient type to show "Sending to: N"

  Future<int> previewRecipientCount({
    required RecipientType type,
    String? filter,
  }) async {
    try {
      final ids = await resolveRecipientIds(type: type, filter: filter);
      return ids.length;
    } catch (e) {
      debugPrint('BroadcastRepository.previewRecipientCount failed: $e');
      return 0;
    }
  }

  // ─── Fetch distinct crop names (for specificCrop filter) ─────────────────

  Future<List<String>> fetchCropNames() async {
    try {
      final rows = await _client
          .from('farmer_crops')
          .select('crop_name')
          .order('crop_name', ascending: true);
      return rows
          .map((r) => r['crop_name'] as String)
          .toSet()
          .toList()
        ..sort();
    } catch (e) {
      debugPrint('BroadcastRepository.fetchCropNames failed: $e');
      // Fallback to SP3's known primary crops
      return ['Peanut', 'Ginger', 'Palay', 'Banana', 'Copra'];
    }
  }

  // ─── Fetch farmers list (for specificFarmer filter) ──────────────────────

  Future<List<Map<String, String>>> fetchFarmersList() async {
    try {
      final rows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .order('full_name', ascending: true);
      return rows
          .map((r) => {
                'id':   r['user_id'] as String,
                'name': r['full_name'] as String? ?? 'Unknown',
              })
          .toList();
    } catch (e) {
      debugPrint('BroadcastRepository.fetchFarmersList failed: $e');
      return [];
    }
  }

  // ─── Fetch buyers list (for specificBuyer filter) ────────────────────────

  Future<List<Map<String, String>>> fetchBuyersList() async {
    try {
      final roleRows = await _client
          .from('user_roles')
          .select('user_id')
          .eq('role', 'buyer');
      final ids = roleRows.map((r) => r['user_id'] as String).toList();
      if (ids.isEmpty) return [];

      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', ids)
          .order('full_name', ascending: true);

      return infoRows
          .map((r) => {
                'id':   r['user_id'] as String,
                'name': r['full_name'] as String? ?? 'Buyer',
              })
          .toList();
    } catch (e) {
      debugPrint('BroadcastRepository.fetchBuyersList failed: $e');
      return [];
    }
  }
}
