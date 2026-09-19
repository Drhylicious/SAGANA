import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_profile_model.dart';
import '../services/auth_service.dart';
import '../services/profile_photo_service.dart';
import 'expense_repository.dart';
import 'harvest_repository.dart';

class FarmerProfileRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  // ─── Fetch combined profile ───────────────────────────────────────────────
  // Joins user_information + farmer_profiles + farmer_crops (for primaryCrops)

  Future<FarmerProfileModel?> fetchProfile() async {
    try {
      final userInfo = await _client
          .from('user_information')
          .select()
          .eq('user_id', _userId)
          .maybeSingle();

      final farmerProfile = await _client
          .from('farmer_profiles')
          .select()
          .eq('user_id', _userId)
          .maybeSingle();

      List<String> crops = [];
      try {
        final cropRows = await _client
            .from('farmer_crops')
            .select('crop_name')
            .eq('farmer_id', _userId)
            .order('created_at', ascending: false)
            .limit(6);
        crops = cropRows.map((r) => r['crop_name'] as String).toList();
      } catch (_) {}

      // capital_shares isn't a column on user_information or
      // farmer_profiles — it lives in member_capital_shares, the same
      // table ContributionRepository.fetchCapitalShares() reads. Queried
      // directly here (not via ContributionRepository) to stay in this
      // repository's existing pattern, matching how fetchOutstandingLoans()
      // reads farmer_loans directly rather than depending on
      // LoanRepository. Value = total_shares * share_value_per_unit,
      // same formula as CapitalSharesModel.investmentValue, so the
      // Dashboard and My Contribution screen can never disagree.
      double capitalShares = 0;
      try {
        final sharesRow = await _client
            .from('member_capital_shares')
            .select('total_shares, share_value_per_unit')
            .eq('farmer_id', _userId)
            .maybeSingle();
        if (sharesRow != null) {
          final totalShares = (sharesRow['total_shares'] as int? ?? 0);
          final valuePerUnit =
              (sharesRow['share_value_per_unit'] as num? ?? 2000).toDouble();
          capitalShares = totalShares * valuePerUnit;
        }
      } catch (_) {}

      // account_status isn't a column on user_information or farmer_profiles
      // — it lives in user_roles ('active' | 'pending' | 'suspended'),
      // managed by admin (see supabase_schema_auth.sql). Queried directly
      // here, same pattern as the capital_shares/crops reads above: wrapped
      // independently so a missing/failed read degrades to the model's
      // 'active' default rather than failing the whole profile fetch.
      String accountStatus = 'active';
      try {
        final roleRow = await _client
            .from('user_roles')
            .select('status')
            .eq('user_id', _userId)
            .maybeSingle();
        if (roleRow != null) {
          accountStatus = roleRow['status'] as String? ?? 'active';
        }
      } catch (_) {}

      if (userInfo == null) return null;

      return FarmerProfileModel.fromMap({
        ...userInfo,
        ...(farmerProfile ?? {}),
        'email': _client.auth.currentUser?.email ?? userInfo['email'] ?? '',
        'primary_crops': crops,
        'capital_shares': capitalShares,
        'account_status': accountStatus,
      });
    } catch (_) {
      return null;
    }
  }

  // ─── Applicant detail edit (draft / rejected / pending) ──────────────────
  //
  // Used by the Pending Applicant screen so an outsider can review and fix
  // their details before submitting (or resubmitting). Deliberately does
  // NOT call requireActiveMembership() — the whole point is that the
  // caller is not active yet. Writes only the applicant-owned fields on
  // user_information + farmer_profiles; RLS still scopes every write to
  // auth.uid(). 18+ is enforced here too.
  Future<void> updateApplicantDetails({
    required String fullName,
    String? phoneNumber,
    String? contactEmail,
    String? purok,
    DateTime? dateOfBirth,
    String? gender,
  }) async {
    if (dateOfBirth != null) {
      final now = DateTime.now();
      final eighteenth =
          DateTime(dateOfBirth.year + 18, dateOfBirth.month, dateOfBirth.day);
      if (eighteenth.isAfter(now)) {
        throw Exception('You must be at least 18 years old.');
      }
    }

    await _client.from('user_information').update({
      'full_name': fullName.trim(),
      'phone_number':
          (phoneNumber != null && phoneNumber.trim().isNotEmpty)
              ? phoneNumber.trim()
              : null,
      'contact_email':
          (contactEmail != null && contactEmail.trim().isNotEmpty)
              ? contactEmail.trim()
              : null,
      'purok': purok,
    }).eq('user_id', _userId);

    await _client.from('farmer_profiles').update({
      'date_of_birth':
          dateOfBirth?.toIso8601String().split('T').first,
      'gender': gender,
    }).eq('user_id', _userId);
  }

  // ─── Update basic info (name, phone, purok) ────────────────────────────────

  Future<void> updateBasicInfo({
    String? fullName,
    String? phoneNumber,
    String? purok,
    String? contactEmail,
    DateTime? dateOfBirth, // farmer personal info (Phase B) — 18+ enforced
    String? gender,        // male | female | prefer_not_to_say
    bool clearDateOfBirth = false,
    bool clearGender = false,
  }) async {
    await AuthService.requireActiveMembership();

    if (dateOfBirth != null) {
      final now = DateTime.now();
      final eighteenth =
          DateTime(dateOfBirth.year + 18, dateOfBirth.month, dateOfBirth.day);
      if (eighteenth.isAfter(now)) {
        throw Exception('You must be at least 18 years old.');
      }
    }

    // DOB / gender live on farmer_profiles (farmer personal info — NOT
    // the SP3 member registry).
    final farmerUpdate = <String, dynamic>{
      if (dateOfBirth != null)
        'date_of_birth': dateOfBirth.toIso8601String().split('T').first,
      if (clearDateOfBirth) 'date_of_birth': null,
      if (gender != null) 'gender': gender,
      if (clearGender) 'gender': null,
    };
    if (farmerUpdate.isNotEmpty) {
      await _client
          .from('farmer_profiles')
          .update(farmerUpdate)
          .eq('user_id', _userId);
    }

    // Fetched before the update so _logBasicInfoActivity() can tell what
    // actually changed — same reasoning as
    // BuyerProfileRepository._logProfileActivity(): user_information only
    // ever carries current state.
    Map<String, dynamic>? before;
    try {
      before = await _client
          .from('user_information')
          .select('full_name, phone_number, purok')
          .eq('user_id', _userId)
          .maybeSingle();
    } catch (_) {}

    if (fullName != null || phoneNumber != null || purok != null) {
      await _client.from('user_information').update({
        if (fullName != null) 'full_name': fullName,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (purok != null) 'purok': purok,
      }).eq('user_id', _userId);
    }
    // Handles auth.users + auth.identities + contact_email together —
    // see promote_contact_email(). Deliberately not doing a plain column
    // update here anymore; that would silently desync the three.
    if (contactEmail != null) {
      try {
        await _client.rpc('promote_contact_email', params: {'p_email': contactEmail});
      } on PostgrestException catch (e) {
        throw Exception(e.message);
      }
    }

    await _logBasicInfoActivity(before, fullName, phoneNumber, purok);
  }

  // Only logs when something genuinely changed — matches
  // BuyerProfileRepository's "not a passive interaction" rule.
  Future<void> _logBasicInfoActivity(
    Map<String, dynamic>? before,
    String? newName,
    String? newPhone,
    String? newPurok,
  ) async {
    final changes = <String>[];
    if (before != null) {
      if (newName != null && (before['full_name'] as String?) != newName) {
        changes.add('name');
      }
      if (newPhone != null && (before['phone_number'] as String?) != newPhone) {
        changes.add('phone number');
      }
      if (newPurok != null && (before['purok'] as String?) != newPurok) {
        changes.add('purok');
      }
    }
    if (changes.isEmpty) return;
    try {
      await _client.from('farmer_profile_activity').insert({
        'farmer_id': _userId,
        'description': 'Updated ${changes.join(', ')}',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  // ─── Update farm details (all fields incl. new ones) ──────────────────────

  Future<void> updateFarmDetails({
    String? farmName,
    String? farmAddress,
    double? landAreaHectares,
    int? yearsFarming,
    double? farmLatitude,
    double? farmLongitude,
    String? farmOwnershipType,
    String? soilType,
    String? waterSource,
  }) async {
    await AuthService.requireActiveMembership();

    // Diffs all 9 fields individually (Item 4 fix — Phase 7 only diffed
    // 3 of 9, with the remaining 6 falling back to a generic "Updated
    // farm details" label). Latitude/longitude are combined into one
    // "farm location" label since a farmer wouldn't think of them as two
    // separate things — everything else gets its own precise label.
    Map<String, dynamic>? before;
    try {
      before = await _client
          .from('farmer_profiles')
          .select(
              'farm_name, farm_address, land_area_hectares, years_farming, '
              'farm_latitude, farm_longitude, farm_ownership_type, soil_type, water_source')
          .eq('user_id', _userId)
          .maybeSingle();
    } catch (_) {}

    await _client.from('farmer_profiles').update({
      if (farmName != null) 'farm_name': farmName,
      if (farmAddress != null) 'farm_address': farmAddress,
      if (landAreaHectares != null) 'land_area_hectares': landAreaHectares,
      if (yearsFarming != null) 'years_farming': yearsFarming,
      if (farmLatitude != null) 'farm_latitude': farmLatitude,
      if (farmLongitude != null) 'farm_longitude': farmLongitude,
      if (farmOwnershipType != null) 'farm_ownership_type': farmOwnershipType,
      if (soilType != null) 'soil_type': soilType,
      if (waterSource != null) 'water_source': waterSource,
    }).eq('user_id', _userId);

    final changes = <String>[];
    if (before != null) {
      if (farmName != null && (before['farm_name'] as String?) != farmName) {
        changes.add('farm name');
      }
      if (farmAddress != null && (before['farm_address'] as String?) != farmAddress) {
        changes.add('farm address');
      }
      if (landAreaHectares != null &&
          (before['land_area_hectares'] as num?)?.toDouble() != landAreaHectares) {
        changes.add('land area');
      }
      if (yearsFarming != null &&
          (before['years_farming'] as num?)?.toInt() != yearsFarming) {
        changes.add('years farming');
      }
      final latChanged = farmLatitude != null &&
          (before['farm_latitude'] as num?)?.toDouble() != farmLatitude;
      final lngChanged = farmLongitude != null &&
          (before['farm_longitude'] as num?)?.toDouble() != farmLongitude;
      if (latChanged || lngChanged) {
        changes.add('farm location');
      }
      if (farmOwnershipType != null &&
          (before['farm_ownership_type'] as String?) != farmOwnershipType) {
        changes.add('ownership type');
      }
      if (soilType != null && (before['soil_type'] as String?) != soilType) {
        changes.add('soil type');
      }
      if (waterSource != null && (before['water_source'] as String?) != waterSource) {
        changes.add('water source');
      }
    }
    if (changes.isEmpty) return;
    try {
      await _client.from('farmer_profile_activity').insert({
        'farmer_id': _userId,
        'description': 'Updated ${changes.join(', ')}',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  // ─── Clear map pin ────────────────────────────────────────────────────────

  Future<void> clearFarmCoordinates() async {
    await AuthService.requireActiveMembership();
    try {
      await _client.from('farmer_profiles').update({
        'farm_latitude': null,
        'farm_longitude': null,
      }).eq('user_id', _userId);
    } catch (_) {}
  }

  // ─── Outstanding loan amount ──────────────────────────────────────────────

  Future<double> fetchOutstandingLoans() async {
    try {
      // Match LoanRepository.fetchTotalOutstanding(): include 'overdue'
      // loans, not just 'active' ones, so this dashboard figure and the
      // My Loans screen never disagree (Phase 1.3).
      final rows = await _client
          .from('farmer_loans')
          .select('total_value, amount_paid')
          .eq('farmer_id', _userId)
          .neq('status', 'paid');
      double total = 0;
      for (final row in rows) {
        final amount = (row['total_value'] as num? ?? 0).toDouble();
        final paid = (row['amount_paid'] as num? ?? 0).toDouble();
        total += (amount - paid).clamp(0, double.infinity);
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  // ─── This month's expenses ────────────────────────────────────────────────

  Future<double> fetchThisMonthExpenses() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    double total = 0;
    try {
      final rows = await _client
          .from('farmer_expenses')
          .select('amount')
          .eq('farmer_id', _userId)
          .eq('is_subsidy', false)
          .gte('expense_date',
              monthStart.toIso8601String().split('T').first);
      for (final row in rows) {
        total += (row['amount'] as num? ?? 0).toDouble();
      }
    } catch (_) {
      // Falls through to pending-only total below.
    }
    // Merge in Hive-queued offline expenses so this tile can't undercount
    // relative to My Expenses now that expenses queue offline (Phase 2 /
    // U2). Now explicitly filters is_subsidy, matching
    // ExpenseRepository.fetchThisMonthTotal() exactly — previously this
    // matched only because addExpense() enforces amount=0 for subsidy
    // rows as an unenforced invariant (Phase 4 / W2); this makes the two
    // queries structurally identical instead of relying on that.
    for (final e in ExpenseRepository().pendingExpenseModels()) {
      if (!e.isSubsidy && !e.expenseDate.isBefore(monthStart)) {
        total += e.amount;
      }
    }
    return total;
  }

  // ─── Total harvest record count ───────────────────────────────────────────

  Future<int> fetchHarvestRecordCount() async {
    int syncedCount = 0;
    try {
      final rows = await _client
          .from('harvest_records')
          .select('id')
          .eq('farmer_id', _userId);
      syncedCount = rows.length;
    } catch (_) {
      // Falls through to the pending-only count below — an offline
      // farmer should still see their queued harvests reflected here.
    }
    // Merge in Hive-queued offline harvests via the same source
    // HarvestRepository uses everywhere else (Home, Harvest Hub), so
    // this tile can't undercount relative to those screens (Phase 2 / U1).
    return syncedCount + HarvestRepository().pendingHarvestModels().length;
  }

  // ─── My Programs ────────────────────────────────────────────────────────────

  Future<List<MyProgramEntry>> fetchMyPrograms() async {
    try {
      final rows = await _client
          .from('program_members')
          .select('id, program_id, status, enrolled_at, quantity_given, distributed_at, '
              'amount_returned, settled_at, distributed_item_name, '
              'cooperative_programs(program_name, benefit_type, program_purpose, status, expected_return_percent, image_url), '
              'cooperative_inventory(item_name, unit, image_url)')
          .eq('farmer_id', _userId)
          .order('enrolled_at', ascending: false);
      return rows.map((r) => MyProgramEntry.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<int> fetchMyProgramCount() async {
    try {
      final rows = await _client
          .from('program_members')
          .select('id')
          .eq('farmer_id', _userId)
          .eq('status', 'active');
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  // ─── Upload profile photo ─────────────────────────────────────────────────
  // Delegates the actual Storage upload to the shared, role-agnostic
  // profile_photo_service.dart — the function that file's own doc comment
  // says exists specifically so this logic isn't duplicated per-role.
  // This method still owns the Farmer-specific part: writing the
  // resulting URL to user_information.
  Future<String?> updatePhoto({
    required Uint8List imageBytes,
    required String fileExtension,
  }) async {
    await AuthService.requireActiveMembership();
    try {
      final url = await uploadProfilePhoto(
        client: _client,
        userId: _userId,
        imageBytes: imageBytes,
        fileExtension: fileExtension,
      );
      if (url == null) return null;
      await _client
          .from('user_information')
          .update({'profile_photo_url': url}).eq('user_id', _userId);
      try {
        await _client.from('farmer_profile_activity').insert({
          'farmer_id': _userId,
          'description': 'Updated profile photo',
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
      return url;
    } catch (_) {
      return null;
    }
  }

  // ─── Log password change ────────────────────────────────────────────────
  // ChangePasswordDialog is shared across all three roles and doesn't know
  // about farmer_profile_activity — it exposes an optional onSuccess hook
  // instead (purely additive, existing Admin/Buyer call sites unaffected).
  // FarmerEditProfileScreen calls this method through that hook.
  Future<void> logPasswordChanged() async {
    try {
      await _client.from('farmer_profile_activity').insert({
        'farmer_id': _userId,
        'description': 'Changed password',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }
}