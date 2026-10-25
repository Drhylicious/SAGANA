import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/server_only.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/broadcast_model.dart';
import 'admin_activity_repository.dart';
import 'dart:math' show Random;
import '../models/admin_log_message.dart';

class BroadcastNoRecipientsException implements Exception {
  const BroadcastNoRecipientsException();
}

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

  // ─── Send broadcast ───────────────────────────────────────────────────────
  // 1. Resolves recipient IDs
  // 2. Inserts notification rows into notifications table
  // 3. Logs to broadcast_logs

  /// A new key identifies one send attempt. Keep it across retries of the same
  /// attempt so a repeated request is recognized and not sent twice.
  static String newClientKey() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
        '-${h.substring(16, 20)}-${h.substring(20)}';
  }

  // ─── Send broadcast ──────────────────────────────────────────────────────────
  // Immediate sends go through send_broadcast(): recipients are resolved,
  // notices are inserted and the log is written in one database transaction.
  // The returned count is the number of notices actually inserted.
  // Scheduled sends are queued in broadcast_logs and sent by
  // process_scheduled_broadcasts().

  Future<int> sendBroadcast({
    required String title,
    required String body,
    required BroadcastCategory category,
    required RecipientType recipientType,
    String? recipientFilter,
    DateTime? scheduledAt,
    String? clientKey,
  }) async {
    await ServerOnly.ensureOnline();
    final adminId = _client.auth.currentUser?.id;
    final now     = DateTime.now();
    final isDeferred = scheduledAt != null && scheduledAt.isAfter(now);
    final key = clientKey ?? newClientKey();

    if (!isDeferred) {
      final int count;
      try {
        count = await _client.rpc('send_broadcast', params: {
          'p_title': title,
          'p_body': body,
          'p_category': category.value,
          'p_recipient_type': recipientType.value,
          'p_recipient_filter': recipientFilter,
          'p_client_key': key,
        }) as int;
      } on PostgrestException catch (e) {
        if (e.message.contains('NO_RECIPIENTS')) {
          throw const BroadcastNoRecipientsException();
        }
        rethrow;
      }

      AdminActivityRepository().log(
        module: 'broadcast',
        actionType: 'sent',
        message: AdminLogMessage('adminLogBroadcastSent', {'title': title, 'count': '$count'}),
      );
      return count;
    }

    // Deferred: queue only. Recipients are an estimate for display; the real set
    // is resolved when process_scheduled_broadcasts() sends it.
    final recipientCount = await previewRecipientCount(
      type:   recipientType,
      filter: recipientFilter,
    );

    await _client.from('broadcast_logs').upsert({
      'title':            title,
      'body':             body,
      'category':         category.value,
      'recipient_type':   recipientType.value,
      'recipient_filter': recipientFilter,
      'recipient_count':  recipientCount,
      'scheduled_at':     scheduledAt.toIso8601String(),
      'sent_at':          null,
      'created_by':       adminId,
      'created_at':       now.toIso8601String(),
      'client_key':       key,
    }, onConflict: 'client_key', ignoreDuplicates: true);

    AdminActivityRepository().log(
      module: 'broadcast',
      actionType: 'scheduled',
      message: AdminLogMessage('adminLogBroadcastScheduled', {'title': title, 'when': scheduledAt.toIso8601String()}),
    );

    return recipientCount;
  }

  // ─── Fetch dynamic recipient count preview ────────────────────────────────
  // Called live when admin changes recipient type to show "Sending to: N"

  Future<int> previewRecipientCount({
    required RecipientType type,
    String? filter,
  }) async {
    try {
      final count = await _client.rpc(
        'preview_broadcast_recipients',
        params: {
          'p_recipient_type': type.value,
          'p_recipient_filter': filter,
        },
      );
      return (count as num).toInt();
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
      return ['Peanut', 'Ginger', 'Palay', 'Banana'];
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
