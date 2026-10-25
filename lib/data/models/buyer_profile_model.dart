import 'package:intl/intl.dart';
import '../../core/utils/contact_email.dart';
import '../../core/utils/person_name.dart';
import '../../core/l10n/app_localizations.dart';

// male/female/prefer_not_to_say → localized label, shared by the Buyer's
// own Edit Profile gender dropdown and Admin's read-only Buyer Details
// display — was previously a hardcoded-English static map/getter on
// BuyerProfileModel; moved to a top-level function since display text
// needs AppLocalizations, which the model itself has no access to.
String? buyerGenderLabel(AppLocalizations l10n, String? gender) {
  switch (gender) {
    case 'male':
      return l10n.registerGenderMale;
    case 'female':
      return l10n.registerGenderFemale;
    case 'prefer_not_to_say':
      return l10n.registerGenderPreferNotToSay;
    default:
      return null;
  }
}

// Same reasoning as buyerGenderLabel above — BuyerProfileModel.
// memberSinceLabel/joinedLabel used to hardcode an English 3-letter month
// array ('Jan','Feb',...) and "Member since "/"Since " phrasing directly on
// the model. Moved here as top-level functions; reuses the same
// DateFormat('MMM y', l10n.localeName) + buyerMemberSince ARB key already
// established in buyer_account_screen.dart's local _memberSinceLabel
// bypass (removed now that this is the real fix).
String buyerMemberSinceLabel(AppLocalizations l10n, DateTime memberSince) {
  return l10n.buyerMemberSince(
    DateFormat('MMM y', l10n.localeName).format(memberSince),
  );
}

/// Short form for admin-side cards ("Since Jun 2026") — buyerMemberSinceLabel
/// above is worded for the buyer's own profile screen instead.
String buyerJoinedLabel(AppLocalizations l10n, DateTime memberSince) {
  return DateFormat('MMM y', l10n.localeName).format(memberSince);
}

class BuyerProfileModel {
  final String userId;
  final String fullName;
  // The name as entered in parts. Null for an account created before the name
  // was split.
  final String? surname;
  final String? firstName;
  final String? middleInitial;
  final String? suffix;
  final String? phoneNumber;
  final String? profilePhotoUrl;
  final String email; // synthetic auth address (username@sagana.local)
  final String? contactEmail; // optional real email, entered by the buyer
  // The last email address proven with a code; the contact email is Verified
  // only while it equals this.
  final String? verifiedContactEmail;
  final DateTime memberSince; // buyer_profiles.created_at

  final int totalOrders;
  final int completedOrders;
  final double totalSpent; // sum of total_price for completed orders

  // accountStatus remains admin-view-only — left at its default ('active')
  // when this model represents a buyer's own fetchProfile().
  final String accountStatus; // 'active' | 'suspended'

  // Admin-view-only, same convention as accountStatus above — used
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
    this.surname,
    this.firstName,
    this.middleInitial,
    this.suffix,
    this.phoneNumber,
    this.profilePhotoUrl,
    required this.email,
    this.contactEmail,
    this.verifiedContactEmail,
    required this.memberSince,
    required this.totalOrders,
    required this.completedOrders,
    required this.totalSpent,
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

  /// The contact email has been proven with a code (and has not changed since).
  bool get isContactEmailVerified => ContactEmail.isVerified(
    contactEmail: contactEmail,
    signInEmail: email,
    verifiedEmail: verifiedContactEmail,
  );

  bool get isInactive =>
      accountStatus == 'active' &&
      lastActiveAt != null &&
      DateTime.now().difference(lastActiveAt!) > const Duration(days: 30);

  bool get hasPhoto => profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty;

  String get initials => PersonName.initials(fullName, fallback: 'B');

}
