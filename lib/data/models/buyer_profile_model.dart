class BuyerProfileModel {
  final String userId;
  final String fullName;
  final String? phoneNumber;
  final String? profilePhotoUrl;
  final String email;
  final DateTime memberSince; // buyer_profiles.created_at

  final int totalOrders;
  final int completedOrders;
  final double totalSpent; // sum of total_price for completed orders

  // Admin-view-only fields. Left at their defaults (null / 'active') when
  // this model represents a buyer's own fetchProfile() — sitio and account
  // status are never shown on that screen. Populated for the admin-side
  // fetchAllBuyers()/fetchAdminView() paths, where they're the whole point.
  final String? sitio;
  final String accountStatus; // 'active' | 'suspended'

  const BuyerProfileModel({
    required this.userId,
    required this.fullName,
    this.phoneNumber,
    this.profilePhotoUrl,
    required this.email,
    required this.memberSince,
    required this.totalOrders,
    required this.completedOrders,
    required this.totalSpent,
    this.sitio,
    this.accountStatus = 'active',
  });

  bool get isActive => accountStatus == 'active';
  bool get hasPhoto => profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty;

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : 'B';
  }

  String get memberSinceLabel {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return 'Member since ${m[memberSince.month - 1]} ${memberSince.year}';
  }

  /// Short form for admin-side cards ("Since Jun 2026") — memberSinceLabel
  /// above is worded for the buyer's own profile screen instead.
  String get joinedLabel {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[memberSince.month - 1]} ${memberSince.year}';
  }
}