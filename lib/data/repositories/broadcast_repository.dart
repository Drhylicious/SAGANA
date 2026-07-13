import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/broadcast_model.dart';

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
  } catch (_) {
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
  } catch (_) {
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
      }
    } catch (_) {
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

    // 1. Resolve recipients
    final recipientIds = await resolveRecipientIds(
      type:   recipientType,
      filter: recipientFilter,
    );

    if (recipientIds.isEmpty) return 0;

    // 2. Insert notification rows for each recipient
    final notifRows = recipientIds
        .map((uid) => {
              'user_id':    uid,
              'type':       'system',
              'title':      title,
              'body':       body,
              'is_read':    false,
              'created_at': (scheduledAt ?? now).toIso8601String(),
            })
        .toList();

    await _client.from('notifications').insert(notifRows);

    // 3. Log the broadcast
    await _client.from('broadcast_logs').insert({
      'title':            title,
      'body':             body,
      'category':         category.value,
      'recipient_type':   recipientType.value,
      'recipient_filter': recipientFilter,
      'recipient_count':  recipientIds.length,
      'scheduled_at':     scheduledAt?.toIso8601String(),
      'sent_at':          (scheduledAt ?? now).toIso8601String(),
      'created_by':       adminId,
      'created_at':       now.toIso8601String(),
    });

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
    } catch (_) {
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
    } catch (_) {
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
    } catch (_) {
      return [];
    }
  }
}
