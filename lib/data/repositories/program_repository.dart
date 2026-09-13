import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/program_model.dart';

class ProgramRepository {
  final _client = Supabase.instance.client;

  /// member_count must match fetchProgramMembers()'s own definition of
  /// "enrolled" (status='active') exactly, or the list card and the
  /// Members modal disagree — which is exactly what was reported. Computed
  /// as a separate lightweight query + client-side tally rather than
  /// PostgREST's embedded `program_members(count)`, since that syntax
  /// counts every row regardless of status (active/withdrawn/completed)
  /// with no reliable way to filter it inline without an inner join that
  /// would incorrectly drop programs with zero active members entirely.
  Future<List<CooperativeProgram>> fetchPrograms() async {
    try {
      final results = await Future.wait([
        _client
            .from('cooperative_programs')
            .select()
            .order('season_year', ascending: false)
            .order('program_name'),
        _client
            .from('program_members')
            .select('program_id')
            .eq('status', 'active'),
      ]);
      final programRows = results[0] as List;
      final memberRows = results[1] as List;

      final countByProgram = <String, int>{};
      for (final r in memberRows) {
        final id = r['program_id'] as String;
        countByProgram[id] = (countByProgram[id] ?? 0) + 1;
      }

      return programRows.map((r) {
        final id = r['id'] as String;
        return CooperativeProgram.fromMap({...r, 'member_count': countByProgram[id] ?? 0});
      }).toList();
    } catch (_) { return []; }
  }

  Future<List<ProgramMember>> fetchProgramMembers(String programId) async {
    try {
      final rows = await _client
          .from('program_members')
          .select('id, program_id, farmer_id, status, enrolled_at, '
              'inventory_item_id, quantity_given, distributed_at, '
              'amount_returned, settled_at, distribution_outcome, '
              'outcome_recorded_at, converted_loan_id')
          .eq('program_id', programId)
          .eq('status', 'active')
          .order('enrolled_at', ascending: false);

      if (rows.isEmpty) return [];

      final farmerIds = rows.map((r) => r['farmer_id'] as String).toList();
      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', farmerIds);
      final nameMap = {
        for (final r in infoRows)
          r['user_id'] as String: r['full_name'] as String? ?? 'Unknown'
      };

      return rows.map((r) => ProgramMember.fromMap({
        ...r,
        'user_information': {'full_name': nameMap[r['farmer_id'] as String] ?? 'Unknown'},
      })).toList();
    } catch (_) { return []; }
  }

  Future<List<Map<String, String>>> fetchUnenrolledFarmers(String programId) async {
    try {
      final enrolled = await _client
          .from('program_members')
          .select('farmer_id')
          .eq('program_id', programId)
          .eq('status', 'active');
      final enrolledIds = enrolled.map((r) => r['farmer_id'] as String).toSet();

      final allRoles = await _client
          .from('user_roles')
          .select('user_id')
          .eq('role', 'farmer')
          .eq('status', 'active');

      final unenrolledIds = allRoles
          .map((r) => r['user_id'] as String)
          .where((id) => !enrolledIds.contains(id))
          .toList();

      if (unenrolledIds.isEmpty) return [];

      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', unenrolledIds);

      return infoRows.map((r) => {
        'id': r['user_id'] as String,
        'name': r['full_name'] as String? ?? 'Unknown',
      }).toList();
    } catch (_) { return []; }
  }

  Future<bool> createProgram({
    required String name,
    required String type,
    String benefitType = 'grant',
    double? expectedReturnPercent,
    String? description,
    double? budget,
    String? distributionCategory,
  }) async {
    try {
      await _client.from('cooperative_programs').insert({
        'program_name': name.trim(),
        'program_type': type,
        'benefit_type': benefitType,
        'expected_return_percent': expectedReturnPercent,
        'description': description?.trim(),
        'budget': budget,
        'distribution_category': distributionCategory,
        'season_year': DateTime.now().year,
        'created_by': _client.auth.currentUser?.id,
      });
      return true;
    } catch (_) { return false; }
  }

  Future<bool> updateProgram({
    required String id,
    required String name,
    required String type,
    String benefitType = 'grant',
    double? expectedReturnPercent,
    String? description,
    double? budget,
    required String status,
    String? distributionCategory,
  }) async {
    try {
      await _client.from('cooperative_programs').update({
        'program_name': name.trim(),
        'program_type': type.trim(),
        'benefit_type': benefitType,
        'expected_return_percent': expectedReturnPercent,
        'description': description?.trim(),
        'budget': budget,
        'status': status,
        'distribution_category': distributionCategory,
      }).eq('id', id);
      return true;
    } catch (_) { return false; }
  }

  // ─── Delete program ─────────────────────────────────────────────────────
  // program_members and program_activities both cascade-delete with the
  // program (ON DELETE CASCADE); farmer_loans.source_program_id uses
  // ON DELETE SET NULL, so a loan converted from a distribution survives —
  // it just loses the "From Program Distribution" tag, which is correct
  // (deleting a program record shouldn't make a real loan disappear).

  Future<ProgramDeleteImpact> fetchProgramDeleteImpact(String programId) async {
    try {
      final rows = await _client
          .from('program_members')
          .select('distributed_at')
          .eq('program_id', programId);
      final memberCount = rows.length;
      final distributedCount =
          rows.where((r) => r['distributed_at'] != null).length;
      return ProgramDeleteImpact(
        memberCount: memberCount,
        distributedCount: distributedCount,
      );
    } catch (_) {
      return const ProgramDeleteImpact(
        memberCount: 0,
        distributedCount: 0,
        checkFailed: true,
      );
    }
  }

  Future<bool> deleteProgram(String programId) async {
    try {
      await _client.from('cooperative_programs').delete().eq('id', programId);
      return true;
    } catch (_) { return false; }
  }

  /// program_members has UNIQUE(program_id, farmer_id), and removeMember()
  /// only ever soft-deletes (status='withdrawn') rather than deleting the
  /// row — so a blind insert here would 409 the moment anyone tries to
  /// re-enroll a farmer who was previously removed. Checking for an
  /// existing row first and reactivating it (rather than inserting a
  /// second one) fixes both that conflict and the member-count drift it
  /// caused: fetchPrograms()'s count includes every row regardless of
  /// status, so a leftover withdrawn row was inflating that count above
  /// what the Members modal's active-only count showed.
  Future<bool> enrollFarmer(String programId, String farmerId) async {
    try {
      final existing = await _client
          .from('program_members')
          .select('id, status')
          .eq('program_id', programId)
          .eq('farmer_id', farmerId)
          .maybeSingle();

      if (existing != null) {
        if (existing['status'] == 'active') return false; // already enrolled
        await _client.from('program_members').update({
          'status': 'active',
          'enrolled_at': DateTime.now().toIso8601String(),
        }).eq('id', existing['id'] as String);
        return true;
      }

      await _client.from('program_members').insert({
        'program_id': programId,
        'farmer_id': farmerId,
      });
      return true;
    } catch (_) { return false; }
  }

  Future<bool> removeMember(String programMemberId) async {
    try {
      await _client
          .from('program_members')
          .update({'status': 'withdrawn'})
          .eq('id', programMemberId);
      return true;
    } catch (_) { return false; }
  }

  // ─── Benefit distribution ───────────────────────────────────────────────
  // Mirrors AdminLoanRepository.issueLoan(): log the movement, then decrement
  // stock. Deliberately not wrapped in try/catch — a stock-moving write
  // failing silently would let inventory drift from reality.

  Future<List<DistributionItem>> fetchDistributionItems() async {
    final rows = await _client
        .from('cooperative_inventory')
        .select('id, item_name, category, unit, quantity_on_hand')
        .eq('is_active', true)
        .order('item_name');
    return rows.map((r) => DistributionItem.fromMap(r)).toList();
  }

  /// Atomic via distribute_program_benefit() — see
  /// supabase_schema_program_atomic_distribution.sql. Rejects if
  /// cooperative_inventory lacks enough quantity_on_hand, rather than
  /// silently distributing less than what gets recorded. Still
  /// deliberately uncaught (per the original comment this replaces) — a
  /// stock-moving write failing silently would let inventory drift from
  /// reality.
  Future<void> distributeBenefit({
    required String programMemberId,
    required String inventoryItemId,
    required double quantity,
  }) async {
    await _client.rpc('distribute_program_benefit', params: {
      'p_program_member_id': programMemberId,
      'p_inventory_item_id': inventoryItemId,
      'p_quantity': quantity,
      'p_recorded_by': _client.auth.currentUser?.id,
    });
  }

  // ─── Revenue-share settlement ───────────────────────────────────────────

  Future<void> confirmProgramReturn({
    required String programMemberId,
    required double amountReturned,
    String? adminNotes,
  }) async {
    await _client.rpc('confirm_program_return', params: {
      'p_program_member_id': programMemberId,
      'p_amount_returned': amountReturned,
      'p_admin_notes': adminNotes,
    });
  }

  // ─── Distribution outcome (Phase 8 / Issue 3's Loan/ROI workflow) ───────
  // 'thriving' is a plain column update (program_members' existing
  // "admin manages all" RLS policy already covers this) — it just marks the
  // member eligible for the Revenue Share settlement above, which already
  // exists and needed no changes. 'failed' needs an RPC because it must
  // atomically create the farmer_loans row and mark the distribution
  // converted in one transaction — see convertDistributionToLoan() below.

  Future<bool> recordThrivingOutcome(String programMemberId) async {
    try {
      await _client.from('program_members').update({
        'distribution_outcome': 'thriving',
        'outcome_recorded_at': DateTime.now().toIso8601String(),
      }).eq('id', programMemberId);
      return true;
    } catch (_) { return false; }
  }

  /// Converts a failed distribution into a farmer_loans entry via
  /// convert_program_distribution_to_loan() — see
  /// supabase_schema_program_loan_roi_workflow.sql. Deliberately does not
  /// deduct inventory again: the stock was already taken at distribution
  /// time by distributeBenefit().
  Future<bool> convertDistributionToLoan({
    required String programMemberId,
    required double monthlyPayment,
    required DateTime nextPaymentDate,
    String? notes,
  }) async {
    try {
      await _client.rpc('convert_program_distribution_to_loan', params: {
        'p_program_member_id': programMemberId,
        'p_monthly_payment': monthlyPayment,
        'p_next_payment_date': nextPaymentDate.toIso8601String().split('T').first,
        'p_notes': notes,
      });
      return true;
    } catch (_) { return false; }
  }

  // ─── Program activities ──────────────────────────────────────────────────

  Future<List<ProgramActivity>> fetchActivities(String programId) async {
    try {
      final rows = await _client
          .from('program_activities')
          .select()
          .eq('program_id', programId)
          .order('activity_date', ascending: true);
      return rows.map((r) => ProgramActivity.fromMap(r)).toList();
    } catch (_) { return []; }
  }

  Future<bool> createActivity({
    required String programId,
    required String title,
    String? description,
    required DateTime activityDate,
    String? location,
  }) async {
    try {
      await _client.from('program_activities').insert({
        'program_id': programId,
        'title': title.trim(),
        'description': description?.trim(),
        'activity_date': activityDate.toIso8601String().split('T').first,
        'location': location?.trim(),
        'created_by': _client.auth.currentUser?.id,
      });
      return true;
    } catch (_) { return false; }
  }

  Future<bool> deleteActivity(String activityId) async {
    try {
      await _client.from('program_activities').delete().eq('id', activityId);
      return true;
    } catch (_) { return false; }
  }
}