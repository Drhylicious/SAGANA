class BuyerProfileModel {
  final String userId;
  final String fullName;
  final String? phoneNumber;
  final String? profilePhotoUrl;
  final String email; // synthetic auth address (username@sagana.local)
  final String? contactEmail; // optional real email, entered by the buyer
  final DateTime memberSince; // buyer_profiles.created_at

  final int totalOrders;
  final int completedOrders;
  final double totalSpent; // sum of total_price for completed orders

  // Admin-view-only fields. Left at their defaults (null / 'active') when
  // this model represents a buyer's own fetchProfile() — purok and account
  // status are never shown on that screen. Populated for the admin-side
  // fetchAllBuyers()/fetchAdminView() paths, where they're the whole point.
  final String? purok;
  final String accountStatus; // 'active' | 'suspended'

  // Admin-view-only, same convention as purok/accountStatus above — used
  // only to derive isInactive for Buyer Management's Inactive tab, same
  // 30-day-idle pattern already used for Members (see MemberStatus.derive
  // in farmer_member_model.dart). Sourced from the same shared
  // user_information.last_active_at column farmers use — stamped on every
  // login regardless of role, so no new plumbing was needed for buyers.
  final DateTime? lastActiveAt;

  // Buyer-editable personal fields (Decision: Buyer Management should show
  // every Edit Profile field, always — see buyer_edit_profile_screen.dart).
  final DateTime? dateOfBirth;
  final String? gender; // male | female | prefer_not_to_say

  const BuyerProfileModel({
    required this.userId,
    required this.fullName,
    this.phoneNumber,
    this.profilePhotoUrl,
    required this.email,
    this.contactEmail,
    required this.memberSince,
    required this.totalOrders,
    required this.completedOrders,
    required this.totalSpent,
    this.purok,
    this.accountStatus = 'active',
    this.lastActiveAt,
    this.dateOfBirth,
    this.gender,
  });

  // NOTE: unchanged meaning — literally accountStatus == 'active', still
  // the source of truth for the Suspend/Reactivate toggle and the
  // ACTIVE/SUSPENDED badge. isInactive below is a separate, purely
  // display-derived bucket layered on top for Buyer Management's filter
  // tabs — it does not change what "active" means for suspension purposes,
  // same distinction Members draws between MemberStatus.isEffectivelyActive
  // and the raw active/suspended DB value.
  bool get isActive => accountStatus == 'active';

  bool get isInactive =>
      accountStatus == 'active' &&
      lastActiveAt != null &&
      DateTime.now().difference(lastActiveAt!) > const Duration(days: 30);

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

  static const Map<String, String> genderLabels = {
    'male': 'Male',
    'female': 'Female',
    'prefer_not_to_say': 'Prefer not to say',
  };

  /// null when unset — Buyer Details renders its own placeholder ("–") for
  /// that case, same convention as the phone/email fields there.
  String? get genderLabel => gender != null ? genderLabels[gender] : null;

  String? get dateOfBirthLabel {
    if (dateOfBirth == null) return null;
    return '${dateOfBirth!.year}-${dateOfBirth!.month.toString().padLeft(2, '0')}-${dateOfBirth!.day.toString().padLeft(2, '0')}';
  }
}