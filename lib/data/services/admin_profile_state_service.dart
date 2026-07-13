import 'package:flutter/foundation.dart';
import '../models/admin_profile_model.dart';
import '../repositories/admin_profile_repository.dart';

/// Maintains the currently loaded admin profile for the app — mirrors
/// FarmerProfileStateService's exact shape (singleton, ChangeNotifier,
/// refresh/updateProfile/clear) rather than generalizing across both
/// roles into one class, consistent with the rest of the project keeping
/// admin and farmer data layers structurally parallel but separate.
/// Shared UI widgets like ProfileAvatar only ever consume plain
/// photoUrl/displayName values, so they work with either role's state
/// service without needing to know which one it is.
class AdminProfileStateService extends ChangeNotifier {
  AdminProfileStateService._();

  static final AdminProfileStateService instance = AdminProfileStateService._();

  final AdminProfileRepository _repo = AdminProfileRepository();

  AdminProfileModel? _profile;
  bool _isRefreshing = false;

  AdminProfileModel? get profile => _profile;
  String? get profilePhotoUrl => _profile?.profilePhotoUrl;
  String? get fullName => _profile?.fullName;

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

  void updateProfile(AdminProfileModel profile) {
    _profile = profile;
    notifyListeners();
  }

  void clear() {
    _profile = null;
    notifyListeners();
  }
}