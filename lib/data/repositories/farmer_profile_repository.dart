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
    DateTime? dateOfBirth,
    String? gender,
  }) async {
    if (dateOfBirth != null) {
      final now = DateTime.now();
      final eighteenth = DateTime(
        dateOfBirth.year + 18,
        dateOfBirth.month,
        dateOfBirth.day,
      );
      if (eighteenth.isAfter(now)) {
        throw Exception('You must be at least 18 years old.');
      }
    }

    // Fetched before the writes below since, unlike updateBasicInfo()'s
    // conditional-field pattern, both updates here always fully overwrite
    // every field — a null value passed in genuinely means "clear this
    // field" (the whole draft form resubmits together), so the diff below
    // compares every field unconditionally rather than skipping null
    // inputs. Recording nothing here previously — an applicant's edits
    // (including their very first submission) never appeared anywhere.
    Map<String, dynamic>? beforeUserInfo;
    try {
      beforeUserInfo = await _client
          .from('user_information')
          .select('full_name, phone_number, contact_email')
          .eq('user_id', _userId)
          .maybeSingle();
    } catch (_) {}

    Map<String, dynamic>? beforeFarmerProfile;
    try {
      beforeFarmerProfile = await _client
          .from('farmer_profiles')
          .select('date_of_birth, gender')
          .eq('user_id', _userId)
          .maybeSingle();
    } catch (_) {}

    final newPhone = (phoneNumber != null && phoneNumber.trim().isNotEmpty)
              ? phoneNumber.trim()
        : null;
    final newEmail = (contactEmail != null && contactEmail.trim().isNotEmpty)
              ? contactEmail.trim()
        : null;
    final newDobStr = dateOfBirth?.toIso8601String().split('T').first;

    await _client
        .from('user_information')
        .update({
          'full_name': fullName.trim(),
          'phone_number': newPhone,
          'contact_email': newEmail,
        })
        .eq('user_id', _userId);

    await _client
        .from('farmer_profiles')
        .update({'date_of_birth': newDobStr, 'gender': gender})
        .eq('user_id', _userId);

    final changes = <String>[];
    if (beforeUserInfo != null) {
      if ((beforeUserInfo['full_name'] as String?) != fullName.trim()) {
        changes.add('name');
      }
      if ((beforeUserInfo['phone_number'] as String?) != newPhone) {
        changes.add('phone number');
      }
      if ((beforeUserInfo['contact_email'] as String?) != newEmail) {
        changes.add('email');
      }
    }
    if (beforeFarmerProfile != null) {
      if ((beforeFarmerProfile['date_of_birth'] as String?) != newDobStr) {
        changes.add('date of birth');
      }
      if ((beforeFarmerProfile['gender'] as String?) != gender) {
        changes.add('gender');
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

  // ─── Update basic info (name, phone) ───────────────────────────────────────

  Future<void> updateBasicInfo({
    String? fullName,
    String? phoneNumber,
    String? contactEmail,
    DateTime? dateOfBirth, // farmer personal info (Phase B) — 18+ enforced
    String? gender,        // male | female | prefer_not_to_say
    bool clearDateOfBirth = false,
    bool clearGender = false,
  }) async {
    await AuthService.requireActiveMembership();

    if (dateOfBirth != null) {
      final now = DateTime.now();
      final eighteenth = DateTime(
        dateOfBirth.year + 18,
        dateOfBirth.month,
        dateOfBirth.day,
      );
      if (eighteenth.isAfter(now)) {
        throw Exception('You must be at least 18 years old.');
      }
    }

    // Fetched before any writes below so _logBasicInfoActivity() can tell
    // what actually changed — same reasoning as
    // BuyerProfileRepository._logProfileActivity(): these tables only ever
    // carry current state. Two separate snapshots (user_information vs
    // farmer_profiles) since DOB/gender and name/phone/email live on
    // different tables. Previously only name/phone were captured
    // here at all — email, date of birth, and gender changes were silently
    // invisible to the logger even though this method updates all three
    // (the bug behind a live-testing report of an email change not
    // appearing in Recent Activity).
    Map<String, dynamic>? beforeUserInfo;
    try {
      beforeUserInfo = await _client
          .from('user_information')
          .select('full_name, phone_number, contact_email')
          .eq('user_id', _userId)
          .maybeSingle();
    } catch (_) {}

    Map<String, dynamic>? beforeFarmerProfile;
    try {
      beforeFarmerProfile = await _client
          .from('farmer_profiles')
          .select('date_of_birth, gender')
          .eq('user_id', _userId)
          .maybeSingle();
    } catch (_) {}

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

    if (fullName != null || phoneNumber != null) {
      await _client
          .from('user_information')
          .update({
        if (fullName != null) 'full_name': fullName,
        if (phoneNumber != null) 'phone_number': phoneNumber,
          })
          .eq('user_id', _userId);
    }
    // Handles auth.users + auth.identities + contact_email together —
    // see promote_contact_email(). Deliberately not doing a plain column
    // update here anymore; that would silently desync the three.
    if (contactEmail != null) {
      try {
        await _client.rpc(
          'promote_contact_email',
          params: {'p_email': contactEmail},
        );
      } on PostgrestException catch (e) {
        throw Exception(e.message);
      }
    }

    await _logBasicInfoActivity(
      beforeUserInfo: beforeUserInfo,
      beforeFarmerProfile: beforeFarmerProfile,
      newName: fullName,
      newPhone: phoneNumber,
      newEmail: contactEmail,
      newDateOfBirth: dateOfBirth,
      clearDateOfBirth: clearDateOfBirth,
      newGender: gender,
      clearGender: clearGender,
    );
  }

  // Only logs when something genuinely changed — matches
  // BuyerProfileRepository's "not a passive interaction" rule.
  Future<void> _logBasicInfoActivity({
    Map<String, dynamic>? beforeUserInfo,
    Map<String, dynamic>? beforeFarmerProfile,
    String? newName,
    String? newPhone,
    String? newEmail,
    DateTime? newDateOfBirth,
    bool clearDateOfBirth = false,
    String? newGender,
    bool clearGender = false,
  }) async {
    final changes = <String>[];
    if (beforeUserInfo != null) {
      if (newName != null &&
          (beforeUserInfo['full_name'] as String?) != newName) {
        changes.add('name');
      }
      if (newPhone != null &&
          (beforeUserInfo['phone_number'] as String?) != newPhone) {
        changes.add('phone number');
      }
      if (newEmail != null &&
          (beforeUserInfo['contact_email'] as String?) != newEmail) {
        changes.add('email');
      }
    }
    if (beforeFarmerProfile != null) {
      final beforeDob = beforeFarmerProfile['date_of_birth'] as String?;
      final newDobStr = newDateOfBirth?.toIso8601String().split('T').first;
      if ((newDateOfBirth != null && beforeDob != newDobStr) ||
          (clearDateOfBirth && beforeDob != null)) {
        changes.add('date of birth');
      }
      final beforeGender = beforeFarmerProfile['gender'] as String?;
      if ((newGender != null && beforeGender != newGender) ||
          (clearGender && beforeGender != null)) {
        changes.add('gender');
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

  // ─── Farm ownership type options (admin-managed lookup table) ────────────
  // Replaces the previously hardcoded Owned/Leased/Communal list in
  // edit_farm_details_screen.dart, mirroring CategoryRepository's existing
  // inventory_categories/crop_categories pattern (supabase_schema_
  // category_lookup_tables.sql) so the option set lives in one DB table
  // instead of scattered Dart copies.
  Future<List<String>> fetchOwnershipTypes() async {
    try {
      final rows = await _client
          .from('farm_ownership_types')
          .select('name')
          .eq('is_active', true)
          .order('sort_order')
          .order('name');
      return rows.map((r) => r['name'] as String).toList();
    } catch (_) {
      return [];
    }
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
            'farm_latitude, farm_longitude, farm_ownership_type, soil_type, water_source',
          )
          .eq('user_id', _userId)
          .maybeSingle();
    } catch (_) {}

    final hasAnyFieldToUpdate =
        farmName != null ||
        farmAddress != null ||
        landAreaHectares != null ||
        yearsFarming != null ||
        farmLatitude != null ||
        farmLongitude != null ||
        farmOwnershipType != null ||
        soilType != null ||
        waterSource != null;

    await _client
        .from('farmer_profiles')
        .update({
      if (farmName != null) 'farm_name': farmName,
      if (farmAddress != null) 'farm_address': farmAddress,
      if (landAreaHectares != null) 'land_area_hectares': landAreaHectares,
      if (yearsFarming != null) 'years_farming': yearsFarming,
      if (farmLatitude != null) 'farm_latitude': farmLatitude,
      if (farmLongitude != null) 'farm_longitude': farmLongitude,
          if (farmOwnershipType != null)
            'farm_ownership_type': farmOwnershipType,
      if (soilType != null) 'soil_type': soilType,
      if (waterSource != null) 'water_source': waterSource,
        })
        .eq('user_id', _userId);

    final changes = <String>[];
    if (before != null) {
      if (farmName != null && (before['farm_name'] as String?) != farmName) {
        changes.add('farm name');
      }
      if (farmAddress != null &&
          (before['farm_address'] as String?) != farmAddress) {
        changes.add('farm address');
      }
      if (landAreaHectares != null &&
          (before['land_area_hectares'] as num?)?.toDouble() !=
              landAreaHectares) {
        changes.add('land area');
      }
      if (yearsFarming != null &&
          (before['years_farming'] as num?)?.toInt() != yearsFarming) {
        changes.add('years farming');
      }
      final latChanged =
          farmLatitude != null &&
          (before['farm_latitude'] as num?)?.toDouble() != farmLatitude;
      final lngChanged =
          farmLongitude != null &&
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
      if (waterSource != null &&
          (before['water_source'] as String?) != waterSource) {
        changes.add('water source');
      }
    } else if (hasAnyFieldToUpdate) {
      // The before-snapshot couldn't be read (a transient failure, or no
      // matching row) — the update above still ran and can't be assumed
      // to have failed just because this read did. Falls back to a
      // generic label rather than silently logging nothing, which
      // previously let a real, successful save disappear from Recent
      // Activity with no trace (the bug behind a live-testing report).
      changes.add('farm details');
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
      await _client
          .from('farmer_profiles')
          .update({'farm_latitude': null, 'farm_longitude': null})
          .eq('user_id', _userId);
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
          .gte('expense_date', monthStart.toIso8601String().split('T').first);
      for (final row in rows) {
        total += (row['amount'] as num? ?? 0).toDouble();
      }
    } catch (_) {
      // Falls through to pending-only total below.
    }
    // Merge in Hive-queued offline expenses so this tile can't undercount
    // relative to My Expenses now that expenses queue offline (Phase 2 /
    // U2). Explicitly filters is_subsidy — previously this matched My
    // Expenses' own this-month figure only because addExpense() enforces
    // amount=0 for subsidy rows as an unenforced invariant (Phase 4 /
    // W2); this makes the query correct on its own instead of relying on
    // that.
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
          .select(
            'id, program_id, status, enrolled_at, quantity_given, distributed_at, '
              'amount_returned, settled_at, distributed_item_name, '
            'distribution_outcome, outcome_recorded_at, converted_loan_id, '
            'cooperative_programs(program_name, program_type, description, benefit_type, program_purpose, status, expected_return_percent, distribution_category, image_url), '
            'cooperative_inventory(item_name, unit, image_url)',
          )
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
          .update({'profile_photo_url': url})
          .eq('user_id', _userId);
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