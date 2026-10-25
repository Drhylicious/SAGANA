import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/farmer_registration_address.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../core/utils/person_name.dart';
import '../../data/models/buyer_address_model.dart';
import '../../data/models/buyer_profile_model.dart' show buyerGenderLabel;
import '../../data/models/farmer_member_model.dart' show MemberStatus;
import '../../data/models/farmer_profile_model.dart';
import 'address_map_widgets.dart';
import 'map_attribution_links.dart';

/// The cards on a member's Profile tab (Manager → Members → Member Details).
/// They show what the farmer entered in Edit Profile, My Addresses and Farm
/// Details, read-only, in the same order and with the same card style.

/// "rain_fed" -> "Rain fed". Soil and water are stored as lowercase codes.
String _codeLabel(String code) {
  final text = code.replaceAll('_', ' ').trim();
  return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}

/// One "Label   value" row. A missing value reads "Not set" in the muted colour.
class MemberInfoRow extends StatelessWidget {
  final String label;
  final String? value;
  const MemberInfoRow({super.key, required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final text = value?.trim() ?? '';
    final has = text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              has ? text : l10n.pendingNotSet,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: has ? FontWeight.w500 : FontWeight.w400,
                color: has ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MutedText extends StatelessWidget {
  final String text;
  const _MutedText(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: GoogleFonts.inter(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

/// The top card of a member's Profile tab: photo, status, then the contact and
/// personal details in two rows of equal tiles (Email | Phone, then Date of
/// Birth | Gender). The complete name sits under the picture.
class MemberIdentityCard extends StatelessWidget {
  final FarmerProfileModel profile;

  const MemberIdentityCard({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          // Status badge now lives in its own full-width Row so it always
          // anchors to the card's right edge. Previously it sat inside a
          // Stack whose only sized child was the identity Column — a Stack
          // shrinks to the width of its widest non-positioned child, so the
          // Positioned badge drifted left/right depending on name length
          // ("Jhon Drhy M. Salangsang" wrapping to two lines vs. "Juan Dela
          // Cruz" on one). That was the source of the inconsistent badge
          // placement between member cards.
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppConstants.successGreen.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  profile.memberStatus == MemberStatus.pending
                      ? l10n.farmerDetailsPendingApplicantBadge
                      : profile.memberStatus == MemberStatus.rejected
                      ? l10n.farmerMgmtStatusRejectedLabel
                      : profile.isVerified
                      ? l10n.farmerDetailsActiveMemberBadge
                      : l10n.farmerDetailsPendingVerificationBadge,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: profile.memberStatus == MemberStatus.rejected
                        ? AppConstants.errorRed
                        : profile.isVerified
                        ? AppConstants.successGreen
                        : AppConstants.warningAmber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cs.primary, width: 3),
            ),
            child: profile.hasPhoto
                ? ClipOval(
                    child: Image.network(
                      profile.profilePhotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _avatarFallback(profile.fullName, cs),
                    ),
                  )
                : _avatarFallback(profile.fullName, cs),
          ),
          const SizedBox(height: 12),
          // The complete name, built from Surname, First Name, M.I. and Suffix
          // by the database (full_name). It is shown here, under the picture,
          // and not repeated anywhere else on the Profile tab.
          Text(
            profile.fullName,
            key: const ValueKey('member-header-name'),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: cs.outline.withValues(alpha: 0.10)),
          const SizedBox(height: 12),

          // Contact details and date of birth / gender, in two rows of equal
          // tiles.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _fieldTile(
                    Icons.email_rounded,
                    l10n.emailAddress,
                    profile.contactEmail,
                    cs,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _fieldTile(
                    Icons.phone_rounded,
                    l10n.adminProfilePhoneNumber,
                    profile.phoneNumber,
                    cs,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _fieldTile(
                    Icons.cake_rounded,
                    l10n.dateOfBirthLabel,
                    profile.dateOfBirthLabel,
                    cs,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _fieldTile(
                    Icons.person_outline_rounded,
                    l10n.addMemberGenderLabel,
                    buyerGenderLabel(l10n, profile.gender),
                    cs,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldTile(
    IconData icon,
    String label,
    String? value,
    ColorScheme cs,
  ) {
    final hasValue = value != null && value.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: hasValue ? cs.primary : cs.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            hasValue ? value : '–',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: hasValue ? cs.onSurface : cs.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String name, ColorScheme cs) {
    final initials = PersonName.initials(name);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surfaceContainerHighest,
      ),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: cs.primary,
          ),
        ),
      ),
    );
  }
}

/// Every address the farmer saved under My Addresses (default first), each with
/// its structured fields and its map pin. The farm is not here: it is a separate
/// address with its own pin.
class MemberResidentialAddressCard extends StatelessWidget {
  final List<BuyerAddressModel> addresses;
  const MemberResidentialAddressCard({super.key, required this.addresses});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AddressSectionCard(
      title: l10n.memberProfileResidentialTitle,
      child: addresses.isEmpty
          ? _MutedText(l10n.pendingNoAddressYet)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < addresses.length; i++) ...[
                  if (i > 0) ...[
                    const SizedBox(height: 12),
                    Divider(
                      height: 1,
                      color: Theme.of(context).colorScheme.outline
                          .withValues(alpha: 0.15),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _AddressBlock(address: addresses[i]),
                ],
              ],
            ),
    );
  }
}

class _AddressBlock extends StatelessWidget {
  final BuyerAddressModel address;
  const _AddressBlock({required this.address});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final a = address;
    final hasPin = a.latitude != null && a.longitude != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                a.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (a.isDefault) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppConstants.successGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  l10n.buyerAddressesDefaultBadge,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.successGreen,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          a.addressLine,
          style: GoogleFonts.inter(fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 12),
        MemberInfoRow(label: l10n.registerRegionLabel, value: a.regionName),
        MemberInfoRow(label: l10n.registerProvinceLabel, value: a.provinceName),
        MemberInfoRow(
          label: l10n.registerCityLabel,
          value: a.cityMunicipalityName,
        ),
        MemberInfoRow(label: l10n.registerBarangayLabel, value: a.barangayName),
        MemberInfoRow(label: l10n.registerPostalLabel, value: a.postalCode),
        MemberInfoRow(label: l10n.registerStreetLabel, value: a.street),
        MemberInfoRow(label: l10n.registerBuildingLabel, value: a.building),
        MemberInfoRow(label: l10n.registerHouseNoLabel, value: a.houseNo),
        if (a.notes != null && a.notes!.trim().isNotEmpty)
          MemberInfoRow(label: l10n.buyerAddressNotesField, value: a.notes),
        const SizedBox(height: 4),
        if (hasPin) ...[
          AddressMapPreview(pin: LatLng(a.latitude!, a.longitude!)),
          const SizedBox(height: 6),
          const MapAttributionLinks(),
        ] else
          _MutedText(l10n.memberProfileNoMapPin),
      ],
    );
  }
}

/// The farm, in the order of the farmer's Farm Details screen: the farm's own
/// information, then its address, then its map pin. The farm address and pin are
/// kept apart from the residential address above.
class MemberFarmSection extends StatelessWidget {
  final FarmerProfileModel profile;
  const MemberFarmSection({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FarmInfoCard(profile: profile),
        const SizedBox(height: 16),
        _FarmAddressCard(profile: profile),
        const SizedBox(height: 16),
        _FarmLocationCard(profile: profile),
      ],
    );
  }
}

class _FarmInfoCard extends StatelessWidget {
  final FarmerProfileModel profile;
  const _FarmInfoCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final p = profile;
    final soil = p.soilType?.trim() ?? '';
    final water = p.waterSource?.trim() ?? '';
    return AddressSectionCard(
      title: l10n.memberProfileFarmInfoTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MemberInfoRow(label: l10n.memberProfileFarmName, value: p.farmName),
          MemberInfoRow(
            label: l10n.farmerDetailsTotalArea,
            value: p.landAreaHectares != null
                ? '${p.landAreaHectares!.toStringAsFixed(2)} ha'
                : null,
          ),
          MemberInfoRow(
            label: l10n.farmerDetailsExperience,
            value: p.yearsFarming != null
                ? l10n.farmerDetailsYearsValue(p.yearsFarming!)
                : null,
          ),
          MemberInfoRow(
            label: l10n.memberProfileOwnership,
            value: p.farmOwnershipType,
          ),
          // Soil and water have no field on the farmer's screen any more, so
          // they only show when an older record still has a value.
          if (soil.isNotEmpty)
            MemberInfoRow(
              label: l10n.memberProfileSoilType,
              value: _codeLabel(soil),
            ),
          if (water.isNotEmpty)
            MemberInfoRow(
              label: l10n.memberProfileWaterSource,
              value: _codeLabel(water),
            ),
          const SizedBox(height: 4),
          Text(
            l10n.memberProfileCropsTitle,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (p.primaryCrops.isEmpty)
            _MutedText(l10n.farmerDetailsNoCropsYet)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final crop in p.primaryCrops)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppConstants.secondaryContainer.withValues(
                        alpha: 0.20,
                      ),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                    child: Text(
                      crop,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF694300),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.farmerDetailsManagedByFarmer,
                  style: GoogleFonts.inter(fontSize: 11, color: cs.primary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FarmAddressCard extends StatelessWidget {
  final FarmerProfileModel profile;
  const _FarmAddressCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = profile;
    final line = p.farmAddress?.trim() ?? '';
    return AddressSectionCard(
      title: l10n.farmAddressSectionTitle,
      child: p.hasStructuredFarmAddress
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (line.isNotEmpty) ...[
                  Text(
                    line,
                    style: GoogleFonts.inter(fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                ],
                MemberInfoRow(
                  label: l10n.registerRegionLabel,
                  value: FarmerRegistrationAddress.regionName,
                ),
                MemberInfoRow(
                  label: l10n.registerProvinceLabel,
                  value: FarmerRegistrationAddress.provinceName,
                ),
                MemberInfoRow(
                  label: l10n.registerCityLabel,
                  value: FarmerRegistrationAddress.cityName,
                ),
                MemberInfoRow(
                  label: l10n.registerBarangayLabel,
                  value: FarmerRegistrationAddress.barangayName,
                ),
                MemberInfoRow(
                  label: l10n.registerPostalLabel,
                  value: FarmerRegistrationAddress.postalCode,
                ),
                MemberInfoRow(
                  label: l10n.registerStreetLabel,
                  value: p.farmStreet,
                ),
                MemberInfoRow(
                  label: l10n.registerBuildingLabel,
                  value: p.farmBuilding,
                ),
                MemberInfoRow(
                  label: l10n.registerHouseNoLabel,
                  value: p.farmHouseNo,
                ),
              ],
            )
          // A farm saved as one line of text, before the address had fields.
          : line.isNotEmpty
          ? Text(line, style: GoogleFonts.inter(fontSize: 13, height: 1.5))
          : _MutedText(l10n.memberProfileNoFarmAddress),
    );
  }
}

class _FarmLocationCard extends StatelessWidget {
  final FarmerProfileModel profile;
  const _FarmLocationCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = profile;
    return AddressSectionCard(
      title: l10n.farmLocationSectionTitle,
      child: !p.hasCoordinates
          ? _MutedText(l10n.memberProfileNoFarmPin)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AddressMapPreview(
                  pin: LatLng(p.farmLatitude!, p.farmLongitude!),
                  pinColor: AppConstants.primaryGreen,
                ),
                const SizedBox(height: 6),
                const MapAttributionLinks(),
                const SizedBox(height: 10),
                MemberInfoRow(
                  label: l10n.memberProfileCoordinates,
                  value: p.coordinatesLabel,
                ),
              ],
            ),
    );
  }
}
