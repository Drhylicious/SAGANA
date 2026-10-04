import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/program_model.dart';
import '../models/program_enrollment_request_model.dart';
import 'admin_activity_repository.dart';

class ProgramDuplicateNameException implements Exception {
  final String programName;
  const ProgramDuplicateNameException(this.programName);
}

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
        return CooperativeProgram.fromMap({
          ...r,
          'member_count': countByProgram[id] ?? 0,
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ProgramMember>> fetchProgramMembers(String programId) async {
    try {
      final rows = await _client
          .from('program_members')
          .select(
            'id, program_id, farmer_id, status, enrolled_at, '
              'inventory_item_id, quantity_given, distributed_at, '
              'amount_returned, settled_at, distribution_outcome, '
            'outcome_recorded_at, converted_loan_id',
          )
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
          r['user_id'] as String: r['full_name'] as String? ?? 'Unknown',
      };

      return rows
          .map(
            (r) => ProgramMember.fromMap({
        ...r,
              'user_information': {
                'full_name': nameMap[r['farmer_id'] as String] ?? 'Unknown',
              },
            }),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Same bucket as uploadInventoryImage() (cooperative_inventory_images),
  // under a program_images/ prefix — see
  // supabase_schema_inventory_images_feature.sql. Upload-only, no camera
  // capture: a program isn't a physical item.
  Future<String?> uploadProgramImage(
    Uint8List bytes,
    String fileExtension,
  ) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;
      final path =
          '$uid/program_images/${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      await _client.storage
          .from('cooperative_inventory_images')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      return _client.storage
          .from('cooperative_inventory_images')
          .getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  Future<bool> createProgram({
    required String name,
    required String type,
    String benefitType = 'grant',
    double? expectedReturnPercent,
    String? description,
    double? budget,
    String? distributionCategory,
    String programPurpose = 'distribution',
    String? imageUrl,
  }) async {
    final trimmedName = name.trim();
    // program_name already has a DB-level UNIQUE constraint (so a
    // duplicate can never actually be saved regardless of this check) —
    // this pre-check exists purely to give a specific "already exists"
    // message instead of the generic "Failed. Try again." a raw
    // unique-violation would otherwise fall through to. Applies to every
    // program_purpose equally, since the constraint is on program_name
    // alone — there is no (and should not be a) uniqueness rule on
    // purpose itself, since multiple programs of the same purpose is the
    // normal, expected case (e.g. multiple distribution programs already
    // coexist: Crop Program, Peanut Program, Livestock Program, ...).
    try {
      final existing = await _client
          .from('cooperative_programs')
          .select('id')
          .ilike('program_name', trimmedName)
          .maybeSingle();
      if (existing != null) {
        throw ProgramDuplicateNameException(trimmedName);
      }
    } on ProgramDuplicateNameException {
      rethrow;
    } catch (_) {
      // Pre-check failing (network, etc.) isn't fatal — fall through to
      // the insert, which is still protected by the DB constraint.
    }
    try {
      await _client.from('cooperative_programs').insert({
        'program_name': trimmedName,
        'program_type': type,
        'benefit_type': benefitType,
        'expected_return_percent': expectedReturnPercent,
        'description': description?.trim(),
        'budget': budget,
        'distribution_category': distributionCategory,
        'program_purpose': programPurpose,
        'image_url': imageUrl,
        'season_year': DateTime.now().year,
        'created_by': _client.auth.currentUser?.id,
      });
      AdminActivityRepository().log(
        module: 'programs',
        actionType: 'created',
        description: 'Created program "${name.trim()}".',
      );
      return true;
    } catch (_) {
      return false;
    }
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
    String programPurpose = 'distribution',
    String? imageUrl,
  }) async {
    try {
      await _client
          .from('cooperative_programs')
          .update({
        'program_name': name.trim(),
        'program_type': type.trim(),
        'benefit_type': benefitType,
        'expected_return_percent': expectedReturnPercent,
        'description': description?.trim(),
        'budget': budget,
        'status': status,
        'distribution_category': distributionCategory,
        'program_purpose': programPurpose,
        'image_url': imageUrl,
          })
          .eq('id', id);
      AdminActivityRepository().log(
        module: 'programs',
        actionType: 'updated',
        description: 'Updated program "${name.trim()}".',
        referenceId: id,
      );
      return true;
    } catch (_) {
      return false;
    }
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
      final distributedCount = rows
          .where((r) => r['distributed_at'] != null)
          .length;
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
      final row = await _client
          .from('cooperative_programs')
          .select('program_name')
          .eq('id', programId)
          .maybeSingle();
      await _client.from('cooperative_programs').delete().eq('id', programId);
      AdminActivityRepository().log(
        module: 'programs',
        actionType: 'deleted',
        description: 'Deleted program "${row?['program_name'] ?? programId}".',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── Program enrollment requests (farmer-initiated, Full Workflow) ────────
  // Enrollment itself is now exclusively farmer-initiated (request) +
  // admin-reviewed (respond) below — the old direct enrollFarmer()/
  // _notifyEnrolled() admin-picks-a-farmer path was removed along with
  // the "Enroll a Member" UI in program_management_screen.dart's Manage
  // Members modal.
  // See supabase_schema_program_enrollment_requests.sql. Structurally
  // mirrors MarketLinkingRepository's DA-AMAD enrollment review methods
  // (_fetchEnrollmentsByStatus/respondToEnrollment) — same two-step
  // farmer-info join (program_enrollment_requests has no direct FK
  // PostgREST can embed user_information through), same admin RPC pattern.

  Future<List<ProgramEnrollmentRequest>> fetchPendingEnrollmentRequests() =>
      _fetchEnrollmentRequestsByStatus('pending');

  /// Admin: requests already reviewed (approved or rejected), most
  /// recently reviewed first.
  Future<List<ProgramEnrollmentRequest>>
  fetchReviewedEnrollmentRequests() async {
    final results = await Future.wait([
      _fetchEnrollmentRequestsByStatus('approved'),
      _fetchEnrollmentRequestsByStatus('rejected'),
    ]);
    final combined = [...results[0], ...results[1]]
      ..sort(
        (a, b) => (b.reviewedAt ?? b.submittedAt).compareTo(
          a.reviewedAt ?? a.submittedAt,
        ),
      );
    return combined;
      }

  Future<List<ProgramEnrollmentRequest>> _fetchEnrollmentRequestsByStatus(
    String status,
  ) async {
    try {
      final rows = await _client
          .from('program_enrollment_requests')
          .select(
            'id, farmer_id, program_id, status, admin_notes, submitted_at, reviewed_at, '
            'cooperative_programs(program_name, image_url)',
          )
          .eq('status', status)
          .order('submitted_at', ascending: status == 'pending');
      if (rows.isEmpty) return [];

      final farmerIds = rows
          .map((r) => r['farmer_id'] as String)
          .toSet()
          .toList();
      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', farmerIds);
      final infoMap = {for (final r in infoRows) r['user_id'] as String: r};

      return rows.map((r) {
        final info = infoMap[r['farmer_id']];
        return ProgramEnrollmentRequest.fromMap({
          ...r,
          'user_information': info,
      });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> respondToEnrollmentRequest({
    required String id,
    required bool approve,
    String? notes,
  }) async {
    try {
      await _client.rpc(
        'respond_to_program_enrollment_request',
        params: {
          'p_request_id': id,
          'p_approve': approve,
          if (notes != null && notes.isNotEmpty) 'p_notes': notes,
        },
      );
      AdminActivityRepository().log(
        module: 'programs',
        actionType: approve ? 'approved' : 'rejected',
        description: approve
            ? 'Approved a farmer\'s program enrollment request.'
            : 'Declined a farmer\'s program enrollment request.',
        referenceId: id,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeMember(String programMemberId) async {
    try {
      await _client
          .from('program_members')
          .update({'status': 'withdrawn'})
          .eq('id', programMemberId);
      AdminActivityRepository().log(
        module: 'programs',
        actionType: 'member_removed',
        description: 'Removed a member from a program.',
        referenceId: programMemberId,
      );
      return true;
    } catch (_) {
      return false;
    }
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
    await _client.rpc(
      'distribute_program_benefit',
      params: {
      'p_program_member_id': programMemberId,
      'p_inventory_item_id': inventoryItemId,
      'p_quantity': quantity,
      'p_recorded_by': _client.auth.currentUser?.id,
      },
    );
    AdminActivityRepository().log(
      module: 'programs',
      actionType: 'benefit_distributed',
      description: 'Distributed a program benefit to a member.',
      referenceId: programMemberId,
    );
  }

  // ─── Sales program products (Cooperative Product Sales Program) ────────
  // Admin-side product management for a 'sales'-purpose program — see
  // program_products in supabase_schema_program_product_sales.sql.

  Future<List<ProgramProduct>> fetchProgramProducts(String programId) async {
    try {
      final rows = await _client
          .from('program_products')
          .select(
            'id, program_id, inventory_item_id, unit_price, is_available, '
            'cooperative_inventory(item_name, category, unit, quantity_on_hand, image_url)',
          )
          .eq('program_id', programId)
          .order('created_at');
      return rows.map((r) {
        final inv = r['cooperative_inventory'] as Map<String, dynamic>?;
        return ProgramProduct.fromMap({
          ...r,
          'item_name': inv?['item_name'],
          'category': inv?['category'],
          'unit': inv?['unit'],
          'quantity_on_hand': inv?['quantity_on_hand'],
          'image_url': inv?['image_url'],
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Active inventory items not already published to the Loan Item
  /// Catalog — a query-level exclusion (decision: keep cross-catalog
  /// separation adjustable without a migration, see
  /// supabase_schema_program_product_sales.sql), not a DB constraint.
  Future<List<DistributionItem>> fetchEligibleInventoryForSaleProgram() async {
    try {
      final results = await Future.wait([
        _client
            .from('cooperative_inventory')
            .select('id, item_name, category, unit, quantity_on_hand')
            .eq('is_active', true)
            .order('item_name'),
        _client.from('loan_items_master').select('inventory_item_id'),
      ]);
      final invRows = results[0] as List;
      final loanRows = results[1] as List;
      final loanItemIds = loanRows
          .map((r) => r['inventory_item_id'] as String?)
          .whereType<String>()
          .toSet();
      return invRows
          .where((r) => !loanItemIds.contains(r['id'] as String))
          .map((r) => DistributionItem.fromMap(r))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> addProgramProduct({
    required String programId,
    required String inventoryItemId,
    required double unitPrice,
  }) async {
    try {
      await _client.from('program_products').insert({
        'program_id': programId,
        'inventory_item_id': inventoryItemId,
        'unit_price': unitPrice,
        'created_by': _client.auth.currentUser?.id,
      });
      AdminActivityRepository().log(
        module: 'programs',
        actionType: 'product_added',
        description: 'Added a product to a sales program.',
        referenceId: programId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateProgramProduct({
    required String productId,
    required double unitPrice,
    required bool isAvailable,
  }) async {
    try {
      await _client
          .from('program_products')
          .update({'unit_price': unitPrice, 'is_available': isAvailable})
          .eq('id', productId);
      AdminActivityRepository().log(
        module: 'programs',
        actionType: 'product_updated',
        description: 'Updated a sales program product.',
        referenceId: productId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeProgramProduct(String productId) async {
    try {
      await _client.from('program_products').delete().eq('id', productId);
      AdminActivityRepository().log(
        module: 'programs',
        actionType: 'product_removed',
        description: 'Removed a product from a sales program.',
        referenceId: productId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── Purchase review (Cooperative Product Sales Program) ────────────────
  // Admin-wide — spans every 'sales' program, not just one, since an admin
  // reviewing payment confirmations wants one place to see all of them.

  Future<List<ProgramPurchase>> fetchPurchasesByStatus(String status) async {
    try {
      final rows = await _client
          .from('program_product_purchases')
          .select(
            'id, program_id, product_id, farmer_id, quantity, unit_price, '
              'total_amount, status, requested_at, confirmed_at, cancelled_at, cancel_reason, '
              'cooperative_programs(program_name), '
            'program_products(cooperative_inventory(item_name, unit, image_url))',
          )
          .eq('status', status)
          .order('requested_at', ascending: status != 'pending');
      if (rows.isEmpty) return [];

      final farmerIds = rows
          .map((r) => r['farmer_id'] as String)
          .toSet()
          .toList();
      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', farmerIds);
      final nameMap = {
        for (final r in infoRows)
          r['user_id'] as String: r['full_name'] as String? ?? 'Unknown',
      };

      return rows.map((r) {
        final program = r['cooperative_programs'] as Map<String, dynamic>?;
        final product = r['program_products'] as Map<String, dynamic>?;
        final inv = product?['cooperative_inventory'] as Map<String, dynamic>?;
        return ProgramPurchase.fromMap({
          ...r,
          'program_name': program?['program_name'],
          'item_name': inv?['item_name'],
          'unit': inv?['unit'],
          'image_url': inv?['image_url'],
          'farmer_name': nameMap[r['farmer_id'] as String],
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Moves a pending purchase to 'paid' and deducts stock — see
  /// confirm_program_purchase() in supabase_schema_program_product_sales.sql.
  /// Deliberately uncaught, same reasoning as issueLoan()/distributeBenefit():
  /// a stock-moving, real-money write failing silently would let inventory
  /// and the purchase record disagree.
  Future<void> confirmPurchase(String purchaseId) async {
    await _client.rpc(
      'confirm_program_purchase',
      params: {'p_purchase_id': purchaseId},
    );
    AdminActivityRepository().log(
      module: 'programs',
      actionType: 'purchase_confirmed',
      description: 'Confirmed payment for a program product purchase.',
      referenceId: purchaseId,
    );
  }

  // p_reason has no default on the DB function (confirmed live:
  // cancel_program_purchase(p_purchase_id uuid, p_reason text)), so it must
  // always be supplied — omitting it previously meant PostgREST couldn't
  // match the function overload and every cancellation silently failed.
  Future<bool> cancelPurchase(String purchaseId, String reason) async {
    try {
      await _client.rpc(
        'cancel_program_purchase',
        params: {'p_purchase_id': purchaseId, 'p_reason': reason},
      );
      AdminActivityRepository().log(
        module: 'programs',
        actionType: 'purchase_cancelled',
        description: 'Cancelled a program product purchase.',
        referenceId: purchaseId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── Revenue-share settlement ───────────────────────────────────────────

  Future<void> confirmProgramReturn({
    required String programMemberId,
    required double amountReturned,
    String? adminNotes,
  }) async {
    await _client.rpc(
      'confirm_program_return',
      params: {
      'p_program_member_id': programMemberId,
      'p_amount_returned': amountReturned,
      'p_admin_notes': adminNotes,
      },
    );
    AdminActivityRepository().log(
      module: 'programs',
      actionType: 'return_confirmed',
      description:
          'Confirmed a revenue-share return (₱${amountReturned.toStringAsFixed(2)}).',
      referenceId: programMemberId,
    );
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
      await _client
          .from('program_members')
          .update({
        'distribution_outcome': 'thriving',
        'outcome_recorded_at': DateTime.now().toIso8601String(),
          })
          .eq('id', programMemberId);
      AdminActivityRepository().log(
        module: 'programs',
        actionType: 'outcome_recorded',
        description: 'Recorded a distribution outcome as thriving.',
        referenceId: programMemberId,
      );
      return true;
    } catch (_) {
      return false;
    }
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
      await _client.rpc(
        'convert_program_distribution_to_loan',
        params: {
        'p_program_member_id': programMemberId,
        'p_monthly_payment': monthlyPayment,
          'p_next_payment_date': nextPaymentDate
              .toIso8601String()
              .split('T')
              .first,
        'p_notes': notes,
        },
      );
      AdminActivityRepository().log(
        module: 'programs',
        actionType: 'converted_to_loan',
        description: 'Converted a failed distribution into a loan.',
        referenceId: programMemberId,
      );
      return true;
    } catch (_) {
      return false;
    }
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
    } catch (_) {
      return [];
    }
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
      AdminActivityRepository().log(
        module: 'programs',
        actionType: 'activity_created',
        description: 'Scheduled "${title.trim()}" for a program.',
        referenceId: programId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteActivity(String activityId) async {
    try {
      await _client.from('program_activities').delete().eq('id', activityId);
      AdminActivityRepository().log(
        module: 'programs',
        actionType: 'activity_deleted',
        description: 'Deleted a program activity.',
        referenceId: activityId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}