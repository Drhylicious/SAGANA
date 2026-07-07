import 'package:flutter/foundation.dart';
import '../models/farmer_profile_model.dart';
import '../repositories/farmer_profile_repository.dart';

/// Maintains the currently loaded farmer profile for the app.
///
/// This service is used by shared UI widgets to show the latest
/// profile avatar across farmer screens without requiring each screen
/// to manage its own profile image state.
class FarmerProfileStateService extends ChangeNotifier {
  FarmerProfileStateService._();

  static final FarmerProfileStateService instance =
      FarmerProfileStateService._();

  final FarmerProfileRepository _repo = FarmerProfileRepository();

  FarmerProfileModel? _profile;
  bool _isRefreshing = false;

  FarmerProfileModel? get profile => _profile;

  String? get profilePhotoUrl => _profile?.profilePhotoUrl;

  String? get fullName => _profile?.fullName;

  /// Refreshes the current profile from Supabase.
  Future<void> refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final latest = await _repo.fetchProfile();
      if (latest != null) {
        _profile = latest;
        notifyListeners();
      }
    } finally {
      _isRefreshing = false;
    }
  }

  /// Updates the shared profile state with a known profile instance.
  void updateProfile(FarmerProfileModel profile) {
    _profile = profile;
    notifyListeners();
  }

  void clear() {
    _profile = null;
    notifyListeners();
  }
}
