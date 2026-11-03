import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/workflow_event_model.dart';

/// The Manager / Officer's view of who did what. Reads `workflow_events` (RLS:
/// staff only) and attaches each actor's name. A Farmer or Buyer never uses this:
/// they have no access to the table, and a Farmer's own listing history comes
/// from ListingRepository.fetchMyHistory, which carries no staff identity.
class WorkflowEventRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// entity types: listing | order | market_linking | market_linking_enrollment
  Future<List<WorkflowEvent>> fetch(String entityType, String entityId) async {
    try {
      final rows = await _client
          .from('workflow_events')
          .select()
          .eq('entity_type', entityType)
          .eq('entity_id', entityId)
          .order('created_at', ascending: true);
      final events = [for (final r in rows) WorkflowEvent.fromMap(r)];
      final names = await fetchNames([
        for (final e in events)
          if (e.actorId != null) e.actorId!,
      ]);
      return [
        for (final e in events) e.withActorName(names[e.actorId]),
      ];
    } catch (_) {
      return [];
    }
  }

  /// user id -> full name, for the people named in a history (staff may read
  /// every user's name).
  Future<Map<String, String>> fetchNames(Iterable<String> userIds) async {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final rows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', ids);
      return {
        for (final r in rows)
          r['user_id'] as String: (r['full_name'] as String? ?? '').trim(),
      };
    } catch (_) {
      return {};
    }
  }
}
