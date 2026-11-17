import 'admin_activity_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/program_assistance_model.dart';
import '../services/server_only.dart';

/// Failed-program assistance. Every rule (who may ask, limits, stock, the single
/// pending request) is enforced by the database functions; this only calls them.
/// Nothing here touches loans.
class ProgramAssistanceRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ── Farmer ────────────────────────────────────────────────────────────────
  Future<List<AssistanceOption>> fetchMyOptions() async {
    try {
      final res = await _client.rpc('get_my_assistance_options');
      return (res as List)
          .map((r) => AssistanceOption.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<AssistanceRequest>> fetchMyRequests() async {
    try {
      final res = await _client.rpc('get_my_assistance_requests');
      return (res as List)
          .map((r) => AssistanceRequest.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// [items] is a list of {inventoryItemId, quantity}. Returns the request number.
  Future<String> submit({
    required String programMemberId,
    required List<Map<String, dynamic>> items,
    String? message,
  }) async {
    await ServerOnly.ensureOnline();
    final res = await _client.rpc('submit_assistance_request', params: {
      'p_program_member_id': programMemberId,
      'p_items': items,
      'p_message': message,
    });
    final row = (res is List && res.isNotEmpty) ? res.first : res;
    return (row as Map)['new_request_no'] as String? ?? '';
  }

  Future<void> cancel(String requestId) async {
    await ServerOnly.ensureOnline();
    await _client.rpc('cancel_my_assistance_request', params: {'p_request_id': requestId});
  }

  /// Approved assistance, newest first: what Loan History lists first (assistance is not a loan).
  static List<AssistanceRequest> approvedNewestFirst(
    List<AssistanceRequest> all,
  ) => all.where((r) => r.isApproved).toList()
    ..sort(
      (a, b) =>
          (b.reviewedAt ?? b.createdAt).compareTo(a.reviewedAt ?? a.createdAt),
    );

  /// The signed-in Farmer's approved assistance.
  Future<List<AssistanceRequest>> fetchMyApproved() async =>
      approvedNewestFirst(await fetchMyRequests());

  /// Every approved assistance request (Manager / Officer). An empty list when it cannot be read.
  Future<List<AssistanceRequest>> fetchApprovedAll() async {
    try {
      return approvedNewestFirst(await fetchAll(status: 'approved'));
    } catch (_) {
      return [];
    }
  }

  /// One Farmer's approved assistance (Manager / Officer, read-only).
  Future<List<AssistanceRequest>> fetchApprovedFor(String farmerId) async => [
    for (final a in await fetchApprovedAll())
      if (a.farmerId == farmerId) a,
  ];

  // ── Staff ─────────────────────────────────────────────────────────────────
  Future<List<AssistanceRequest>> fetchAll({String? status}) async {
    final res = await _client.rpc('get_assistance_requests', params: {'p_status': status});
    return (res as List)
        .map((r) => AssistanceRequest.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Manager / Officer: the Farmer's Capital Share now, and whether this waiting
  /// request cannot be approved because of it (a Capital Share of 0, or an item worth
  /// more than it). The database refuses such an approval too. Null when it cannot
  /// be read: the card then shows nothing and the database still decides.
  Future<({double capitalShare, bool blocked})?> fetchCapitalCheck(
    String requestId,
  ) async {
    try {
      final res =
          await _client.rpc(
                'get_assistance_capital_check',
                params: {'p_request_id': requestId},
              )
              as List;
      if (res.isEmpty) return null;
      final row = Map<String, dynamic>.from(res.first as Map);
      return (
        capitalShare: (row['capital_share'] as num? ?? 0).toDouble(),
        blocked: row['blocked'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Approving checks and deducts the stock inside the database. Returns the
  /// LRN reference when approved.
  Future<String?> review({
    required String requestId,
    required bool approve,
    String? note,
  }) async {
    await ServerOnly.ensureOnline();
    final res = await _client.rpc(
      'review_assistance_request',
      params: {
        'p_request_id': requestId,
        'p_decision': approve ? 'approved' : 'rejected',
        'p_note': note,
      },
    );
    logStaffAction(
      'programs',
      'assistance_reviewed',
      'adminLogProgramAssistanceReviewed',
    );
    return res as String?;
  }
}
