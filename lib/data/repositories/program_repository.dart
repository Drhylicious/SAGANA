import 'dart:typed_data';
import '../../core/utils/chunked_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/server_only.dart';
import '../models/program_model.dart';
import '../models/program_enrollment_request_model.dart';
import 'admin_activity_repository.dart';
import '../models/admin_log_message.dart';

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
        _selectPrograms(),
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

  /// distribution_item: the program's configured item (Inventory Management).
  Future<List<Map<String, dynamic>>> _selectPrograms() async {
    try {
      final rows = await _client
          .from('cooperative_programs')
          .select(
            '*, '
            'distribution_item:cooperative_inventory!distribution_item_id(item_name, unit, quantity_on_hand)',
          )
          .order('season_year', ascending: false)
          .order('program_name');
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      final rows = await _client
          .from('cooperative_programs')
          .select()
          .order('season_year', ascending: false)
          .order('program_name');
      return List<Map<String, dynamic>>.from(rows);
    }
  }

  Future<List<ProgramMember>> fetchProgramMembers(String programId) async {
    try {
      const baseCols =
          'id, program_id, farmer_id, status, enrolled_at, '
          'inventory_item_id, quantity_given, distributed_at';
      Future<List<Map<String, dynamic>>> read(String cols) async =>
          List<Map<String, dynamic>>.from(
            await _client
                .from('program_members')
                .select(cols)
                .eq('program_id', programId)
                .eq('status', 'active')
                .order('enrolled_at', ascending: false),
          );
      List<Map<String, dynamic>> rows;
      try {
        rows = await read(
          '$baseCols, distributed_item_name, distributed_unit',
        );
      } catch (_) {
        rows = await read(baseCols);
      }

      if (rows.isEmpty) return [];

      final farmerIds = rows.map((r) => r['farmer_id'] as String).toList();
      final infoRows = await chunkedIn(farmerIds, (slice) => _client.from('user_information').select('user_id, full_name').inFilter('user_id', slice));
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

  Future<String?> createProgram({
    required String name,
    required String type,
    String? description,
    double? budget,
    String? distributionCategory,
    String? distributionItemId,
    String programPurpose = 'distribution',
    String? imageUrl,
    double? memberDiscountPercent,
    double? cooperativeSharePercent,
    List<String>? sourceCategories,
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
      final row = await _client
          .from('cooperative_programs')
          .insert({
            'program_name': trimmedName,
            'program_type': type,
            'description': description?.trim(),
            'budget': budget,
            'distribution_category': distributionCategory,
            'distribution_item_id': distributionItemId,
            'program_purpose': programPurpose,
            'image_url': imageUrl,
            'season_year': DateTime.now().year,
            'created_by': _client.auth.currentUser?.id,
            // Sent only when there is a discount to record, so creating a
            // program works the same before and after the pricing script.
            if (memberDiscountPercent != null)
              'member_discount_percent': memberDiscountPercent,
            if (cooperativeSharePercent != null && cooperativeSharePercent > 0)
              'cooperative_share_percent': cooperativeSharePercent,
            if (sourceCategories != null) 'source_categories': sourceCategories,
          })
          .select('id')
          .single();
      AdminActivityRepository().log(
        module: 'programs',
        actionType: 'created',
        message: AdminLogMessage('adminLogProgramCreated', {
          'name': name.trim(),
        }),
        referenceId: row['id'] as String?,
      );
      return row['id'] as String?;
    }
    // Any other failure reaches the screen, which explains it in plain words
    // (and the technical text goes to the developer log).
    catch (_) {
      rethrow;
    }
  }

  Future<bool> updateProgram({
    required String id,
    required String name,
    required String type,
    String? description,
    double? budget,
    String? distributionCategory,
    String? distributionItemId,
    String? imageUrl,
    double? memberDiscountPercent,
    double? cooperativeSharePercent,
    List<String>? sourceCategories,
  }) async {
    // Program Purpose is fixed when a program is created, so it is not sent here.
    try {
      await _client
          .from('cooperative_programs')
          .update({
            if (memberDiscountPercent != null)
              'member_discount_percent': memberDiscountPercent,
            if (cooperativeSharePercent != null)
              'cooperative_share_percent': cooperativeSharePercent,
            if (sourceCategories != null) 'source_categories': sourceCategories,
            'program_name': name.trim(),
            'program_type': type.trim(),
            'description': description?.trim(),
            'budget': budget,
            'distribution_category': distributionCategory,
            'distribution_item_id': distributionItemId,
            'image_url': imageUrl,
          })
          .eq('id', id);
      AdminActivityRepository().log(
        module: 'programs',
        actionType: 'updated',
        message: AdminLogMessage('adminLogProgramUpdated', {
          'name': name.trim(),
        }),
        referenceId: id,
      );
      return true;
    } catch (_) {
      // The screen explains the real reason; nothing is swallowed here.
      rethrow;
    }
  }

  // ─── Program completion ──────────────────────────────────────────────────
  // The ONE way a program is closed. The checklist comes from the database, and
  // complete_program() enforces the same rules there, so a disabled button is
  // not the only thing standing in the way.

  Future<Map<String, ProgramCompletionStatus>> fetchCompletionStatuses() async {
    try {
      final res = await _client.rpc('get_programs_completion_status');
      return {
        for (final r in (res as List))
          (r as Map)['program_id'] as String: ProgramCompletionStatus.fromMap(
            Map<String, dynamic>.from(r),
          ),
      };
    } catch (_) {
      return {};
    }
  }

  /// What completing would leave behind: referred Farmers with no approved loan request (none sent, or all
  /// disapproved) and members still waiting for an item. Completing is allowed, but staff are asked to confirm.
  /// Zeros when the database does not have the rule yet.
  Future<({int unapprovedReferrals, int waitingMembers})>
  fetchCompletionWarnings(String programId) async {
    try {
      final res = await _client.rpc(
        'program_completion_warnings',
        params: {'p_program_id': programId},
      );
      final m = res as Map;
      return (
        unapprovedReferrals: (m['unapproved_referrals'] as num?)?.toInt() ?? 0,
        waitingMembers: (m['waiting_members'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return (unapprovedReferrals: 0, waitingMembers: 0);
    }
  }

  /// Marks the program Completed and returns how many pending enrollment
  /// requests were declined with it. Throws when refused.
  Future<int> completeProgram(
    String programId, {
    int confirmedReferrals = 0,
    int confirmedWaiting = 0,
  }) async {
    final confirmed = confirmedReferrals > 0 || confirmedWaiting > 0;
    await ServerOnly.ensureOnline();
    final res = await _client.rpc(
      'complete_program',
      params: {
        'p_program_id': programId,
        // Sent only when needed, so a database without the confirmation rule still accepts the call.
        if (confirmed) 'p_confirm_warnings': true,
      },
    );
    // When staff confirmed warnings, the log says so (and how many), not just "Completed".
    AdminActivityRepository().log(
      module: 'programs',
      actionType: 'updated',
      message: confirmed
          ? AdminLogMessage('adminLogProgramCompletedWarned', {
              'referred': '$confirmedReferrals',
              'waiting': '$confirmedWaiting',
            })
          : const AdminLogMessage('adminLogProgramCompleted'),
      referenceId: programId,
    );
    return (res as num?)?.toInt() ?? 0;
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

  /// Admin: everyone who is ENROLLED right now, in every program (Distribution and
  /// Product Sales alike) — the active program_members, the same definition the
  /// Program Management count uses, so the two always agree. Where the member came
  /// through a request, that request's details are attached; a member with no
  /// request on record (enrolled directly or before requests existed) still appears.
  Future<List<ProgramEnrollmentRequest>> fetchEnrolledMembers() async {
    final memberRows = await _client
        .from('program_members')
        .select(
          'id, program_id, farmer_id, status, enrolled_at, distributed_at, '
          'quantity_given, distributed_item_name, '
          'cooperative_programs(program_name, image_url, program_type, program_purpose)',
        )
        .eq('status', 'active');
    if (memberRows.isEmpty) return [];

    final farmerIds = memberRows
        .map((r) => r['farmer_id'] as String)
        .toSet()
        .toList();
    final results = await Future.wait([
      _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', farmerIds),
      _client
          .from('program_enrollment_requests')
          .select(
            'id, farmer_id, program_id, admin_notes, submitted_at, reviewed_at',
          )
          .eq('status', 'approved')
          .inFilter('farmer_id', farmerIds)
          .order('reviewed_at', ascending: false),
    ]);
    final names = {
      for (final r in results[0] as List)
        r['user_id'] as String: r['full_name'] as String?,
    };
    // The latest approved request per farmer and program.
    final requests = <String, Map<String, dynamic>>{};
    for (final q in results[1] as List) {
      requests.putIfAbsent(
        '${q['program_id']}|${q['farmer_id']}',
        () => Map<String, dynamic>.from(q as Map),
      );
    }

    final list = memberRows.map((m) {
      final q = requests['${m['program_id']}|${m['farmer_id']}'];
      return ProgramEnrollmentRequest.fromMap({
        'id': q?['id'] ?? 'member:${m['id']}',
        'program_id': m['program_id'],
        'status': 'approved',
        'admin_notes': q?['admin_notes'],
        'submitted_at': q?['submitted_at'] ?? m['enrolled_at'],
        'reviewed_at': q?['reviewed_at'],
        'cooperative_programs': m['cooperative_programs'],
        'user_information': {'full_name': names[m['farmer_id']]},
        'member': m,
        'has_request': q != null,
      });
    }).toList();
    // Grouped by program, newest enrollment first within each.
    list.sort((a, b) {
      final p = a.programName.toLowerCase().compareTo(
        b.programName.toLowerCase(),
      );
      if (p != 0) return p;
      return (b.enrolledAt ?? b.submittedAt).compareTo(
        a.enrolledAt ?? a.submittedAt,
      );
    });
    return list;
  }

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
            'cooperative_programs(program_name, image_url, program_type, program_purpose)',
          )
          .eq('status', status)
          .order('submitted_at', ascending: status == 'pending');
      if (rows.isEmpty) return [];

      final farmerIds = rows
          .map((r) => r['farmer_id'] as String)
          .toSet()
          .toList();
      final infoRows = await chunkedIn(farmerIds, (slice) => _client.from('user_information').select('user_id, full_name').inFilter('user_id', slice));
      final infoMap = {for (final r in infoRows) r['user_id'] as String: r};

      // The farmer's CURRENT membership, so an Enrolled request can show
      // whether they are still enrolled and what they received.
      final memberMap = <String, Map<String, dynamic>>{};
      if (status == 'approved') {
        final programIds = rows
            .map((r) => r['program_id'] as String)
            .toSet()
            .toList();
        final memberRows = await _client
            .from('program_members')
            .select(
              'program_id, farmer_id, status, enrolled_at, distributed_at, '
              'quantity_given, distributed_item_name',
            )
            .inFilter('farmer_id', farmerIds)
            .inFilter('program_id', programIds);
        for (final m in memberRows) {
          memberMap['${m['program_id']}|${m['farmer_id']}'] = m;
        }
      }

      return rows.map((r) {
        final info = infoMap[r['farmer_id']];
        return ProgramEnrollmentRequest.fromMap({
          ...r,
          'user_information': info,
          'member': memberMap['${r['program_id']}|${r['farmer_id']}'],
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// A join request is approved, never declined: it ends either here or, if its program
  /// is completed first, when the database closes it. (The database refuses a decline.)
  Future<bool> approveEnrollmentRequest({
    required String id,
    String? notes,
  }) async {
    try {
      await _client.rpc(
        'respond_to_program_enrollment_request',
        params: {
          'p_request_id': id,
          'p_approve': true,
          if (notes != null && notes.isNotEmpty) 'p_notes': notes,
        },
      );
      AdminActivityRepository().log(
        module: 'programs',
        actionType: 'approved',
        message: const AdminLogMessage('adminLogProgramEnrollmentApproved'),
        referenceId: id,
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
    const base =
        'id, item_name, category, unit, quantity_on_hand, source, source_farmer_id, item_type, crop_master_id';
    final rows = List<Map<String, dynamic>>.from(
      await _client
          .from('cooperative_inventory')
          .select(base)
          .eq('is_active', true)
          .order('item_name'),
    );
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
    await ServerOnly.ensureOnline();
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
      message: const AdminLogMessage('adminLogProgramBenefitDistributed'),
      referenceId: programMemberId,
    );
  }

  // ─── Sales program products (Cooperative Product Sales Program) ────────
  // Admin-side product management for a 'sales'-purpose program — see
  // program_products in supabase_schema_program_product_sales.sql.

  /// The program's sales figures from ONE read of its purchases. A failed read gives none,
  /// so the products still show.
  Future<ProgramSalesSummary> fetchProgramSalesSummary(String programId) async {
    try {
      final rows = await _client
          .from('program_product_purchases')
          .select(
            'product_id, farmer_id, status, quantity, total_amount, discount_amount',
          )
          .eq('program_id', programId);
      return ProgramSalesSummary.fromRows(
        List<Map<String, dynamic>>.from(rows),
      );
    } catch (_) {
      return const ProgramSalesSummary();
    }
  }

  /// 'active' or 'completed'. Anything unreadable is treated as active, because the
  /// database refuses a change to a completed program's products anyway.
  Future<String> fetchProgramStatus(String programId) async {
    try {
      final rows = await _client
          .from('cooperative_programs')
          .select('status')
          .eq('id', programId)
          .limit(1);
      return rows.isEmpty
          ? 'active'
          : (rows.first['status'] as String? ?? 'active');
    } catch (_) {
      return 'active';
    }
  }

  Future<List<ProgramProduct>> fetchProgramProducts(String programId) async {
    try {
      final rows = await _client
          .from('program_products')
          .select(
            'id, program_id, inventory_item_id, unit_price, is_available, stock_allocated, stock_reserved, '
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
  ///
  /// [categories] are the program's "Distribute from" inventory categories: only
  /// items in those categories are offered (none selected = none offered).
  Future<List<DistributionItem>> fetchEligibleInventoryForSaleProgram({
    required List<String> categories,
  }) async {
    if (categories.every((c) => c.trim().isEmpty)) return [];
    try {
      final results = await Future.wait([
        _client
            .from('cooperative_inventory')
            .select(
              'id, item_name, category, unit, quantity_on_hand, source, source_farmer_id',
            )
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
      return itemsInSources(
        invRows
            .where((r) => !loanItemIds.contains(r['id'] as String))
            .map((r) => DistributionItem.fromMap(r)),
        categories,
      );
    } catch (_) {
      return [];
    }
  }

  /// The program's "Distribute from" categories. Throws if it cannot be read.
  Future<List<String>> fetchProgramSources(String programId) async {
    final row = await _client
        .from('cooperative_programs')
        .select('source_categories')
        .eq('id', programId)
        .single();
    return ((row['source_categories'] as List?) ?? const [])
        .map((e) => '$e')
        .toList();
  }

  /// Adds a product. Throws with the database's reason when refused (for example
  /// an item outside the program's categories), so the screen can explain it.
  Future<void> addProgramProduct({
    required String programId,
    required String inventoryItemId,
    required double unitPrice,
    double allocated = 0,
  }) async {
    final row = await _client
        .from('program_products')
        .insert({
          'program_id': programId,
          'inventory_item_id': inventoryItemId,
          'unit_price': unitPrice,
          'created_by': _client.auth.currentUser?.id,
        })
        .select('id')
        .single();
    // The stock for this program is set by a guarded function (the database checks that it
    // fits what is on hand and not already set aside for something else).
    if (allocated > 0) {
      await setProductAllocation(
        productId: row['id'] as String,
        allocated: allocated,
      );
    }
    AdminActivityRepository().log(
      module: 'programs',
      actionType: 'product_added',
      message: const AdminLogMessage('adminLogProgramProductAdded'),
      referenceId: programId,
    );
  }

  /// Sets the stock for this program. Throws with the database's reason when refused
  /// (more than is free, or less than open orders have reserved).
  Future<void> setProductAllocation({
    required String productId,
    required double allocated,
  }) async {
    await _client.rpc(
      'set_program_product_allocation',
      params: {'p_product_id': productId, 'p_allocated': allocated},
    );
    AdminActivityRepository().log(
      module: 'programs',
      actionType: 'product_stock_set',
      message: const AdminLogMessage('adminLogProgramProductUpdated'),
      referenceId: productId,
    );
  }

  /// Gives the unsold part of the program stock back to the cooperative's shared stock.
  Future<void> releaseProductAllocation(String productId) async {
    await _client.rpc(
      'release_program_product_allocation',
      params: {'p_product_id': productId},
    );
    AdminActivityRepository().log(
      module: 'programs',
      actionType: 'product_stock_released',
      message: const AdminLogMessage('adminLogProgramProductUpdated'),
      referenceId: productId,
    );
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
        message: const AdminLogMessage('adminLogProgramProductUpdated'),
        referenceId: productId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // Cooperative Product orders are handled in Marketplace > Orders
  // (CooperativeOrderRepository): there is no separate purchase review here any more.

  // The Manager and Officer cannot cancel a purchase request: only the Farmer who
  // made it can (the database refuses staff too).

  // ─── One member's participation (the Member details view) ────────────────

  /// When a member asked to join and who approved it. Null when there is no approved
  /// request (a member the cooperative added directly).
  Future<MemberJoinInfo?> fetchMemberJoinInfo(
    String programId,
    String farmerId,
  ) async {
    try {
      final rows = await _client
          .from('program_enrollment_requests')
          .select('submitted_at, reviewed_at, reviewed_by')
          .eq('program_id', programId)
          .eq('farmer_id', farmerId)
          .eq('status', 'approved')
          .order('reviewed_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return null;
      final r = rows.first;
      String? name;
      String? role;
      final by = r['reviewed_by'] as String?;
      if (by != null) {
        try {
          final info = await _client
              .from('user_information')
              .select('full_name')
              .eq('user_id', by)
              .limit(1);
          if (info.isNotEmpty) name = info.first['full_name'] as String?;
          final roles = await _client
              .from('user_roles')
              .select('role')
              .eq('user_id', by)
              .limit(1);
          if (roles.isNotEmpty) role = roles.first['role'] as String?;
        } catch (_) {}
      }
      return MemberJoinInfo(
        requestedAt: r['submitted_at'] != null
            ? DateTime.tryParse('${r['submitted_at']}')?.toLocal()
            : null,
        reviewedAt: r['reviewed_at'] != null
            ? DateTime.tryParse('${r['reviewed_at']}')?.toLocal()
            : null,
        reviewerName: name,
        reviewerRole: role,
      );
    } catch (_) {
      return null;
    }
  }

  /// Every member's purchase figures for one Product Sales program, from ONE read (not one
  /// per member). A failed read gives none, so the member list still shows.
  Future<Map<String, MemberPurchaseSummary>> fetchPurchaseSummaries(
    String programId,
  ) async {
    try {
      final rows = await _client
          .from('program_product_purchases')
          .select('farmer_id, status, total_amount, discount_amount')
          .eq('program_id', programId);
      return MemberPurchaseSummary.group(List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      return {};
    }
  }

  /// One Farmer's purchases in one Product Sales program, newest first.
  Future<List<ProgramPurchase>> fetchMemberPurchases(
    String programId,
    String farmerId,
  ) async {
    try {
      final rows = await _client
          .from('program_product_purchases')
          .select(
            '*, program_products(cooperative_inventory(item_name, unit, image_url))',
          )
          .eq('program_id', programId)
          .eq('farmer_id', farmerId)
          .order('requested_at', ascending: false);
      return rows.map<ProgramPurchase>((r) {
        final product = r['program_products'] as Map<String, dynamic>?;
        final inv = product?['cooperative_inventory'] as Map<String, dynamic>?;
        return ProgramPurchase.fromMap({
          ...r,
          'item_name': inv?['item_name'],
          'unit': inv?['unit'],
          'image_url': inv?['image_url'],
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Program history (staff-only) ────────────────────────────────────────
  // One per-program view over the existing accountability trail — see
  // get_program_history() in supabase_schema_program_rework_5a_creation_history.sql.
  // Throws on failure so the History sheet can show an error with Retry
  // instead of an empty list that looks like "nothing happened".
  Future<List<ProgramHistoryEntry>> fetchProgramHistory(
    String programId,
  ) async {
    final rows = await _client.rpc(
      'get_program_history',
      params: {'p_program_id': programId},
    );
    return (rows as List)
        .map(
          (r) =>
              ProgramHistoryEntry.fromMap(Map<String, dynamic>.from(r as Map)),
        )
        .toList();
  }

  Future<ProgramDistributionSummary> fetchProgramDistributionSummary(
    String programId,
  ) async {
    try {
      final res = await _client.rpc(
        'get_program_distribution_summary',
        params: {'p_program_id': programId},
      );
      if (res is Map) {
        return ProgramDistributionSummary.fromMap(
          Map<String, dynamic>.from(res),
        );
      }
    } catch (_) {}
    return const ProgramDistributionSummary();
  }

  Future<void> recordProgramSharePayment(
    String shareId, {
    String? notes,
  }) async {
    await _client.rpc(
      'record_program_share_payment',
      params: {
        'p_share_id': shareId,
        if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
      },
    );
  }

  Future<List<ProgramSaleShare>> fetchMyProgramShares() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    try {
      final rows = await _client
          .from('program_sale_shares')
          .select()
          .eq('farmer_id', uid)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows)
          .map(ProgramSaleShare.fromMap)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
