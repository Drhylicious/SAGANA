import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/program_model.dart';

class ProgramRepository {
  final _client = Supabase.instance.client;

  Future<List<CooperativeProgram>> fetchPrograms() async {
    try {
      final rows = await _client
          .from('cooperative_programs')
          .select('*, program_members(count)')
          .order('season_year', ascending: false)
          .order('program_name');
      return rows.map((r) {
        final countList = r['program_members'] as List?;
        final count = countList?.isNotEmpty == true
            ? (countList!.first['count'] as int? ?? 0)
            : 0;
        return CooperativeProgram.fromMap({...r, 'member_count': count});
      }).toList();
    } catch (_) { return []; }
  }

  Future<List<ProgramMember>> fetchProgramMembers(String programId) async {
    try {
      final rows = await _client
          .from('program_members')
          .select('id, program_id, farmer_id, status, enrolled_at, '
              'inventory_item_id, quantity_given, distributed_at, '
              'amount_returned, settled_at')
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
  }) async {
    try {
      await _client.from('cooperative_programs').insert({
        'program_name': name.trim(),
        'program_type': type,
        'benefit_type': benefitType,
        'expected_return_percent': expectedReturnPercent,
        'description': description?.trim(),
        'budget': budget,
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
      }).eq('id', id);
      return true;
    } catch (_) { return false; }
  }

  Future<bool> enrollFarmer(String programId, String farmerId) async {
    try {
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
        .select('id, item_name, unit, quantity_on_hand')
        .eq('is_active', true)
        .order('item_name');
    return rows.map((r) => DistributionItem.fromMap(r)).toList();
  }

  Future<void> distributeBenefit({
    required String programMemberId,
    required String inventoryItemId,
    required double quantity,
  }) async {
    final adminId = _client.auth.currentUser?.id;

    await _client.from('inventory_transactions').insert({
      'inventory_id': inventoryItemId,
      'transaction_type': 'program_distribution',
      'quantity': -quantity,
      'reference_id': programMemberId,
      'reference_type': 'program',
      'recorded_by': adminId,
    });

    await _client.rpc('decrement_inventory_stock', params: {
      'p_inventory_id': inventoryItemId,
      'p_quantity': quantity,
    });

    await _client.from('program_members').update({
      'inventory_item_id': inventoryItemId,
      'quantity_given': quantity,
      'distributed_at': DateTime.now().toIso8601String(),
    }).eq('id', programMemberId);
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
