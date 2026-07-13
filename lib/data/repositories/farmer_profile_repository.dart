import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_profile_model.dart';
import '../services/auth_service.dart';

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

      if (userInfo == null) return null;

      return FarmerProfileModel.fromMap({
        ...userInfo,
        ...(farmerProfile ?? {}),
        'primary_crops': crops,
      });
    } catch (_) {
      return null;
    }
  }

  // ─── Update basic info (name, phone, sitio) ────────────────────────────────

  Future<void> updateBasicInfo({
    String? fullName,
    String? phoneNumber,
    String? sitio,
  }) async {
    await AuthService.requireActiveMembership();
    await _client.from('user_information').update({
      if (fullName != null) 'full_name': fullName,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (sitio != null) 'sitio': sitio,
    }).eq('user_id', _userId);
  }

  // ─── Update farm details (all fields incl. new ones) ──────────────────────

  Future<void> updateFarmDetails({
    String? farmName,
    String? farmLocation,
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
    await _client.from('farmer_profiles').update({
      if (farmName != null) 'farm_name': farmName,
      if (farmLocation != null) 'farm_location': farmLocation,
      if (farmAddress != null) 'farm_address': farmAddress,
      if (landAreaHectares != null) 'land_area_hectares': landAreaHectares,
      if (yearsFarming != null) 'years_farming': yearsFarming,
      if (farmLatitude != null) 'farm_latitude': farmLatitude,
      if (farmLongitude != null) 'farm_longitude': farmLongitude,
      if (farmOwnershipType != null) 'farm_ownership_type': farmOwnershipType,
      if (soilType != null) 'soil_type': soilType,
      if (waterSource != null) 'water_source': waterSource,
    }).eq('user_id', _userId);
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
      final rows = await _client
          .from('farmer_loans')
          .select('total_value, amount_paid')
          .eq('farmer_id', _userId)
          .eq('status', 'active');
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
    try {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final rows = await _client
          .from('farmer_expenses')
          .select('amount')
          .eq('farmer_id', _userId)
          .gte('expense_date',
              monthStart.toIso8601String().split('T').first);
      double total = 0;
      for (final row in rows) {
        total += (row['amount'] as num? ?? 0).toDouble();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  // ─── Total harvest record count ───────────────────────────────────────────

  Future<int> fetchHarvestRecordCount() async {
    try {
      final rows = await _client
          .from('harvest_records')
          .select('id')
          .eq('farmer_id', _userId);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  // ─── Upload profile photo ─────────────────────────────────────────────────

  Future<String?> uploadProfilePhoto({
    required Uint8List imageBytes,
    required String fileExtension,
  }) async {
    await AuthService.requireActiveMembership();
    try {
      final path =
          '$_userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      await _client.storage.from('profile_photos').uploadBinary(
            path,
            imageBytes,
            fileOptions: const FileOptions(upsert: true),
          );
      final url =
          _client.storage.from('profile_photos').getPublicUrl(path);
      await _client
          .from('user_information')
          .update({'profile_photo_url': url}).eq('user_id', _userId);
      return url;
    } catch (_) {
      return null;
    }
  }
}