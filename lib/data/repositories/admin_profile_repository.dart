import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_profile_model.dart';
import '../services/hive_service.dart';
import '../services/offline_actions.dart';
import '../services/profile_photo_service.dart';
import 'admin_activity_repository.dart';
import '../models/admin_log_message.dart';
import '../../core/utils/person_name.dart';

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
          // All columns, so the name parts come with it (an older database
          // without them still loads).
          .select()
          .eq('user_id', _userId)
          .maybeSingle();
      if (infoRow == null) return null;

      final adminRow = await _client
          .from('admin_profiles')
          .select('position, department, created_at, date_of_birth, gender')
          .eq('user_id', _userId)
          .maybeSingle();

      // An Officer's admin_profiles row (Phase D-2 — grants operational
      // RPC/RLS access) has no position/date_of_birth/gender of its own —
      // those live on officer_profiles. Fall back to it so an Officer
      // viewing this shared profile screen sees their actual values
      // instead of blanks. No-op for a real Admin (no officer_profiles
      // row).
      Map<String, dynamic>? officerRow;
      try {
        officerRow = await _client
            .from('officer_profiles')
            .select('position, date_of_birth, gender')
            .eq('user_id', _userId)
            .maybeSingle();
      } catch (_) {}

      final dobRaw =
          (adminRow?['date_of_birth'] as String?) ??
          (officerRow?['date_of_birth'] as String?);

      return AdminProfileModel(
        userId: _userId,
        email: _client.auth.currentUser?.email ?? '',
        fullName: infoRow['full_name'] as String? ?? 'Manager',
        surname: infoRow['surname'] as String?,
        firstName: infoRow['first_name'] as String?,
        middleInitial: infoRow['middle_initial'] as String?,
        suffix: infoRow['suffix'] as String?,
        phoneNumber: infoRow['phone_number'] as String?,
        profilePhotoUrl: infoRow['profile_photo_url'] as String?,
        contactEmail: infoRow['contact_email'] as String?,
        verifiedContactEmail: infoRow['verified_contact_email'] as String?,
        pendingContactEmail: infoRow['pending_contact_email'] as String?,
        position:
            (adminRow?['position'] as String?) ??
            (officerRow?['position'] as String?),
        department: adminRow?['department'] as String?,
        adminSince: adminRow?['created_at'] != null
            ? DateTime.tryParse(adminRow!['created_at'] as String)
            : null,
        dateOfBirth: dobRaw != null ? DateTime.tryParse(dobRaw) : null,
        gender:
            (adminRow?['gender'] as String?) ??
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
      final rows = await _client
          .from('price_records')
          .select('id')
          .eq('recorded_by', _userId);
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
      final rows = await _client
          .from('broadcast_logs')
          .select('id')
          .eq('created_by', _userId);
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
  /// position fallback in fetchProfile: an Officer's real identity fields
  /// live on officer_profiles, not the admin_profiles operational-access
  /// grant row). No-op for date_of_birth/gender when both are left null,
  /// so existing callers are unaffected.
  /// Saves now, or keeps the change on this device when offline.
  Future<SaveOutcome> updateBasicInfo({
    // The name in parts. Null leaves the name as it is.
    NameParts? name,
    String? phoneNumber,
    DateTime? dateOfBirth,
    String? gender,
  }) {
    return OfflineActions.run(
      kind: 'admin_basic_info',
      payload: {
        'name': name?.toColumns(),
        'phoneNumber': phoneNumber,
        'dateOfBirth': encodeDate(dateOfBirth),
        'gender': gender,
      },
      online: () => updateBasicInfoOnline(
        name: name,
        phoneNumber: phoneNumber,
        dateOfBirth: dateOfBirth,
        gender: gender,
      ),
    );
  }

  /// The server write behind updateBasicInfo(). Also run by offline replay.
  Future<void> updateBasicInfoOnline({
    NameParts? name,
    // A one-line name queued by an earlier version of the app. Screens now send
    // [name].
    String? fullName,
    String? phoneNumber,
    DateTime? dateOfBirth,
    String? gender,
  }) async {
    await _client
        .from('user_information')
        .update({
      // The parts; the database rebuilds full_name from them.
      if (name != null) ...name.toColumns()
      else if (fullName != null) 'full_name': fullName.trim(),
      'phone_number': phoneNumber?.trim(),
        })
        .eq('user_id', _userId);

    AdminActivityRepository().log(
      module: 'profile',
      actionType: 'updated',
      message: AdminLogMessage('adminLogProfileUpdated', {
        'fullName': name?.fullName ?? fullName ?? '',
      }),
    );

    if (dateOfBirth == null && gender == null) return;

    final dobValue = dateOfBirth == null
        ? null
        : '${dateOfBirth.year.toString().padLeft(4, '0')}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}';

    final table = HiveService.isOfficer ? 'officer_profiles' : 'admin_profiles';
    await _client
        .from(table)
        .update({
      if (dateOfBirth != null) 'date_of_birth': dobValue,
      if (gender != null) 'gender': gender,
        })
        .eq('user_id', _userId);
  }

  /// Removes an Officer's contact email (online only). Changing it to another
  /// address does NOT go through here: a new address is only pending until its
  /// code is entered (ContactEmailVerifier.setPendingEmail).
  Future<void> updateContactEmail(String? email) async {
    final v = email?.trim() ?? '';
    await _client
        .from('user_information')
        .update({'contact_email': v.isEmpty ? null : v})
        .eq('user_id', _userId);
  }

  /// Uploads now, or keeps the photo on this device when offline. A queued
  /// photo has no URL until it syncs.
  Future<PhotoSaveResult> updatePhoto({
    required Uint8List imageBytes,
    required String fileExtension,
  }) async {
    String? url;
    try {
      final outcome = await OfflineActions.run(
        kind: 'admin_photo',
        payload: {'imageBytes': imageBytes, 'fileExtension': fileExtension},
        online: () async {
          url = await updatePhotoOnline(
            imageBytes: imageBytes,
            fileExtension: fileExtension,
          );
        },
      );
      return PhotoSaveResult(outcome: outcome, url: url);
    } catch (_) {
      return const PhotoSaveResult.failed();
    }
  }

  /// Uploads the photo and writes its URL. Throws on failure, so a queued
  /// photo that is rejected keeps its reason. Also run by offline replay.
  Future<String> updatePhotoOnline({
    required Uint8List imageBytes,
    required String fileExtension,
  }) async {
    final url = await uploadProfilePhoto(
      client: _client,
      userId: _userId,
      imageBytes: imageBytes,
      fileExtension: fileExtension,
    );
    if (url == null) throw Exception('Photo upload failed.');

    await _client
        .from('user_information')
        .update({'profile_photo_url': url})
        .eq('user_id', _userId);
    AdminActivityRepository().log(
      module: 'profile',
      actionType: 'photo_updated',
      message: const AdminLogMessage('adminLogProfilePhotoUpdated'),
    );
    return url;
  }

  /// Removes the photo now, or keeps the removal on this device when offline.
  Future<SaveOutcome> removePhoto() {
    return OfflineActions.run(
      kind: 'admin_photo_remove',
      payload: const {},
      online: removePhotoOnline,
    );
  }

  Future<void> removePhotoOnline() async {
    await _client
        .from('user_information')
        .update({'profile_photo_url': null})
        .eq('user_id', _userId);
    AdminActivityRepository().log(
      module: 'profile',
      actionType: 'photo_removed',
      message: const AdminLogMessage('adminLogProfilePhotoRemoved'),
    );
  }
}