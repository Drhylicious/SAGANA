import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_analytics_model.dart';
import '../models/admin_loan_model.dart';
import 'farmer_lookup.dart';
import 'notification_repository.dart';

/// Repository for Analytics Dashboard's genuinely-new pieces only —
/// member participation tiers and the "Send Reminder" action. Everything
/// else the dashboard shows (price snapshot, planting forecasts, top
/// harvested crops, loan health) comes directly from AnalyticsRepository
/// and AdminLoanRepository, both already built — no duplication here.
class AdminAnalyticsRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Categorizes every registered farmer into harvested / listed-only /
  /// inactive within [since] (null = all time).
  Future<MemberParticipationSummary> fetchMemberParticipation({DateTime? since}) async {
    try {
      // Active members only — see BalikTangkilikRepository.
      // fetchDistributionPreview() for the full reasoning; this method
      // shares the identical previously-unfiltered farmer_profiles bug,
      // which was inflating the Inactive tier with draft/rejected/
      // suspended accounts that never became real members.
      final activeRoleRows = await _client
          .from('user_roles')
          .select('user_id')
          .eq('role', 'farmer')
          .eq('status', 'active');
      final activeIds = activeRoleRows.map((r) => r['user_id'] as String).toList();
      if (activeIds.isEmpty) return MemberParticipationSummary.empty();

      final rosterRows = await _client
          .from('farmer_profiles')
          .select('user_id, member_id')
          .inFilter('user_id', activeIds);
      final farmerIds = rosterRows.map((r) => r['user_id'] as String).toList();
      if (farmerIds.isEmpty) return MemberParticipationSummary.empty();

      var harvestQuery = _client.from('harvest_records').select('farmer_id');
      if (since != null) {
        harvestQuery = harvestQuery.gte('harvest_date', _dateOnly(since));
      }
      final harvestRows = await harvestQuery;
      final harvestedIds = harvestRows.map((r) => r['farmer_id'] as String).toSet();

      var listingQuery = _client.from('marketplace_listings').select('farmer_id');
      if (since != null) {
        listingQuery = listingQuery.gte('submitted_at', since.toIso8601String());
      }
      final listingRows = await listingQuery;
      final listedIds = listingRows.map((r) => r['farmer_id'] as String).toSet();

      final inactiveIds = farmerIds
          .where((id) => !harvestedIds.contains(id) && !listedIds.contains(id))
          .toList();
      final activeListedOnlyIds = listedIds.difference(harvestedIds);

      final farmerInfo = await fetchFarmerInfoMap(_client, inactiveIds);
      final inactiveFarmers = inactiveIds
          .map((id) => FarmerPickerResult(
                id: id,
                fullName: farmerInfo[id]?.fullName ?? 'Unknown Farmer',
                memberId: farmerInfo[id]?.memberId ?? '—',
              ))
          .toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));

      return MemberParticipationSummary(
        activeHarvestedCount: harvestedIds.length,
        activeListedCount: activeListedOnlyIds.length,
        inactiveCount: inactiveIds.length,
        totalMembers: farmerIds.length,
        inactiveFarmers: inactiveFarmers,
      );
    } catch (_) {
      return MemberParticipationSummary.empty();
    }
  }

  /// Inserts a notifications row directly for each recipient — no
  /// broadcast_logs entry, no recipient_type inference. Deliberately
  /// simpler than NotificationBroadcastScreen's flow, since the recipient
  /// list here is already a computed, ad-hoc set (inactive members) rather
  /// than one of that screen's defined categories.
  ///
  /// Uses a valid notifications.type value that matches the schema CHECK
  /// constraint: ('order','listing','loan','price','sync','system').
  ///
  /// Throws on failure — same reasoning as AdminLoanRepository's write
  /// methods: silently swallowing a failed reminder send would mean the
  /// admin believes reminders went out when they didn't.
  Future<void> sendReminders({
    required List<String> farmerIds,
    required String title,
    required String body,
  }) async {
    if (farmerIds.isEmpty) return;
    await NotificationRepository().createNotifications(
      farmerIds
          .map((id) => NotificationDraft(
                userId: id,
                type: 'system',
                title: title,
                body: body,
              ))
          .toList(),
    );
  }

  String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;
}