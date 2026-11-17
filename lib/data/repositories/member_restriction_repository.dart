import 'admin_activity_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/member_restriction.dart';

/// Feature restrictions: what staff apply and lift, the history they review, and
/// what a Farmer is restricted from right now. Every write is a database
/// function (restrict_member, lift_member_restriction) that checks who is asking;
/// nothing here writes a table directly.
class MemberRestrictionRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Staff (Manager, Officer) ──────────────────────────────────────────────

  /// Restricts a Farmer from each of [features]. One history row per feature.
  /// [endsAt] null = until lifted. Throws with the database's message on failure.
  Future<int> restrictMember({
    required String userId,
    required Set<RestrictableFeature> features,
    required String reason,
    DateTime? endsAt,
  }) async {
    final result = await _client.rpc(
      'restrict_member',
      params: {
        'p_user_id': userId,
        'p_features': [for (final f in features) f.key],
        'p_reason': reason,
        'p_ends_at': endsAt?.toUtc().toIso8601String(),
      },
    );
    logStaffAction(
      'members',
      'restricted',
      'adminLogMemberRestricted',
      referenceId: userId,
    );
    return (result as num?)?.toInt() ?? features.length;
  }

  Future<void> liftRestriction(String restrictionId) async {
    await _client.rpc(
      'lift_member_restriction',
      params: {'p_restriction_id': restrictionId},
    );
    logStaffAction(
      'members',
      'restriction_lifted',
      'adminLogMemberRestrictionLifted',
    );
  }

  /// The restrictions in force on one member.
  Future<List<MemberRestriction>> fetchActiveForMember(String userId) async {
    final rows = await _client
        .from('member_restrictions')
        .select()
        .eq('member_id', userId)
        .eq('status', 'active')
        .order('starts_at', ascending: false);
    return [
      for (final r in rows)
        if (MemberRestriction.fromMap(r) case final x? when x.inForce) x,
    ];
  }

  /// Every restriction in force, grouped by member, for the Members list.
  Future<Map<String, List<MemberRestriction>>> fetchActiveByMember() async {
    final rows = await _client
        .from('member_restrictions')
        .select()
        .eq('status', 'active')
        .order('starts_at', ascending: false);
    final byMember = <String, List<MemberRestriction>>{};
    for (final r in rows) {
      final x = MemberRestriction.fromMap(r);
      if (x == null || !x.inForce) continue;
      byMember.putIfAbsent(x.memberId, () => []).add(x);
    }
    return byMember;
  }

  /// Restrictions and suspensions of one member, newest first.
  Future<List<DisciplineEntry>> fetchHistory(String userId) async {
    final rows = await _client.rpc(
      'get_member_discipline_history',
      params: {'p_user_id': userId},
    );
    return [
      for (final r in (rows as List))
        DisciplineEntry.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  // ─── Farmer ────────────────────────────────────────────────────────────────

  /// What the signed-in Farmer is restricted from right now.
  Future<List<MyRestriction>> fetchMine() async {
    final rows = await _client.rpc('my_restrictions');
    return [
      for (final r in (rows as List))
        if (MyRestriction.fromMap(Map<String, dynamic>.from(r as Map))
            case final x? when x.inForce)
          x,
    ];
  }
}
