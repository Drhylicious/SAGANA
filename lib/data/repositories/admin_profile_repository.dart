import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_profile_model.dart';
import '../services/hive_service.dart';
import '../services/profile_photo_service.dart';
import 'admin_activity_repository.dart';

/// Repository for the logged-in admin's own profile — user_information +
/// admin_profiles, joined at this layer. Every method operates on the
/// current auth user's own row only.
class AdminProfileRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  Future<AdminProfileModel?> fetchProfile() async {
    try {
      final infoRow = await _client
          .from('user_information')
          .select('full_name, phone_number, profile_photo_url, purok, contact_email')
          .eq('user_id', _userId)
          .maybeSingle();
      if (infoRow == null) return null;

      final adminRow = await _client
          .from('admin_profiles')
          .select('employee_id, position, department, created_at, date_of_birth, gender')
          .eq('user_id', _userId)
          .maybeSingle();

      // Cosmetic fix (verification pass): an Officer's admin_profiles row
      // (Phase D-2 — grants operational RPC/RLS access) has no
      // employee_id — their real EMP-### lives on officer_profiles. Fall
      // back to it so an Officer viewing this shared profile screen sees
      // their actual Employee ID / position instead of blanks. No-op for
      // a real Admin (no officer_profiles row). Same fallback applies to
      // date_of_birth/gender (Admin Profile & Settings Phase 2) — an
      // Officer's real values live on officer_profiles too, since
      // create_officer_account only ever writes them there.
      Map<String, dynamic>? officerRow;
      try {
        officerRow = await _client
            .from('officer_profiles')
            .select('employee_id, position, date_of_birth, gender')
            .eq('user_id', _userId)
            .maybeSingle();
      } catch (_) {}

      final dobRaw = (adminRow?['date_of_birth'] as String?) ??
          (officerRow?['date_of_birth'] as String?);

      return AdminProfileModel(
        userId: _userId,
        email: _client.auth.currentUser?.email ?? '',
        fullName: infoRow['full_name'] as String? ?? 'Admin',
        phoneNumber: infoRow['phone_number'] as String?,
        profilePhotoUrl: infoRow['profile_photo_url'] as String?,
        purok: infoRow['purok'] as String?,
        contactEmail: infoRow['contact_email'] as String?,
        employeeId: (adminRow?['employee_id'] as String?) ??
            (officerRow?['employee_id'] as String?),
        position: (adminRow?['position'] as String?) ??
            (officerRow?['position'] as String?),
        department: adminRow?['department'] as String?,
        adminSince: adminRow?['created_at'] != null
            ? DateTime.tryParse(adminRow!['created_at'] as String)
            : null,
        dateOfBirth: dobRaw != null ? DateTime.tryParse(dobRaw) : null,
        gender: (adminRow?['gender'] as String?) ??
            (officerRow?['gender'] as String?),
      );
    } catch (_) {
      return null;
    }
  }

  /// Count of price_records this admin has personally entered — confirmed
  /// attributable via price_records.recorded_by, already permitted by the
  /// "authenticated users read" SELECT policy.
  Future<int> fetchPricesUpdatedCount() async {
    try {
      final rows =
          await _client.from('price_records').select('id').eq('recorded_by', _userId);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  /// Count of broadcasts this admin has personally sent — confirmed
  /// attributable via broadcast_logs.created_by, already permitted by the
  /// "Admin full access to broadcast_logs" policy.
  Future<int> fetchBroadcastsSentCount() async {
    try {
      final rows =
          await _client.from('broadcast_logs').select('id').eq('created_by', _userId);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  /// The six additional Activity Summary counts confirmed genuinely
  /// per-admin attributable during the Admin Profile & Settings review
  /// (verification round, Issue A6) — each column was confirmed populated
  /// with real admin user_ids, unlike farmer_loans (no attribution column
  /// at all) which was confirmed NOT to belong here.
  Future<int> fetchOffersConfirmedCount() async {
    try {
      final rows = await _client
          .from('cooperative_purchase_offers')
          .select('id')
          .eq('confirmed_by', _userId);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> fetchLoanPaymentsRecordedCount() async {
    try {
      final rows = await _client
          .from('farmer_loan_payments')
          .select('id')
          .eq('recorded_by', _userId);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> fetchInventoryAdjustmentsCount() async {
    try {
      final rows = await _client
          .from('inventory_transactions')
          .select('id')
          .eq('recorded_by', _userId);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> fetchSalesRecordedCount() async {
    try {
      final rows = await _client
          .from('member_sales_transactions')
          .select('id')
          .eq('recorded_by', _userId);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> fetchCropRequestsReviewedCount() async {
    try {
      final rows = await _client
          .from('crop_requests')
          .select('id')
          .eq('reviewed_by', _userId);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  /// Confirmed working now that the Phase 1 fix populates
  /// marketplace_listings.reviewed_by on approve/reject/request-changes
  /// (it was never set before that fix).
  Future<int> fetchListingsReviewedCount() async {
    try {
      final rows = await _client
          .from('marketplace_listings')
          .select('id')
          .eq('reviewed_by', _userId);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  /// Updates the shared user_information fields, plus date_of_birth/gender
  /// on whichever table actually owns them for this session — admin_profiles
  /// for a true Admin, officer_profiles for an Officer (same split as the
  /// employee_id/position fallback in fetchProfile: an Officer's real
  /// identity fields live on officer_profiles, not the admin_profiles
  /// operational-access grant row). No-op for date_of_birth/gender when
  /// both are left null, so existing callers are unaffected.
  Future<void> updateBasicInfo({
    required String fullName,
    String? phoneNumber,
    String? purok,
    DateTime? dateOfBirth,
    String? gender,
  }) async {
    await _client.from('user_information').update({
      'full_name': fullName.trim(),
      'phone_number': phoneNumber?.trim(),
      'purok': purok,
    }).eq('user_id', _userId);

    AdminActivityRepository().log(
      module: 'profile',
      actionType: 'updated',
      description: '$fullName updated their profile information.',
    );

    if (dateOfBirth == null && gender == null) return;

    final dobValue = dateOfBirth == null
        ? null
        : '${dateOfBirth.year.toString().padLeft(4, '0')}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}';

    final table = HiveService.isOfficer ? 'officer_profiles' : 'admin_profiles';
    await _client.from(table).update({
      if (dateOfBirth != null) 'date_of_birth': dobValue,
      if (gender != null) 'gender': gender,
    }).eq('user_id', _userId);
  }

  Future<String?> updatePhoto({
    required Uint8List imageBytes,
    required String fileExtension,
  }) async {
    final url = await uploadProfilePhoto(
      client: _client,
      userId: _userId,
      imageBytes: imageBytes,
      fileExtension: fileExtension,
    );
    if (url == null) return null;

    try {
      await _client
          .from('user_information')
          .update({'profile_photo_url': url}).eq('user_id', _userId);
      return url;
    } catch (_) {
      return null;
    }
  }

  Future<void> removePhoto() async {
    await _client
        .from('user_information')
        .update({'profile_photo_url': null}).eq('user_id', _userId);
  }
}