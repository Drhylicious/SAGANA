import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/farmer_registration_address.dart';
import '../../core/l10n/app_localizations.dart';
import 'auth_visuals.dart';

/// The fixed-area address fields, used wherever a Farmer or a Buyer enters an
/// address: Farmer registration, the Pending Applicant details, and My
/// Addresses (add and edit).
///
/// Region, province, city / municipality, barangay and postal code are fixed
/// to the cooperative's service area (MIMAROPA Region, Marinduque, Torrijos,
/// Payanas, 4903): shown prefilled and locked so the person can review them,
/// never editable. Only street, building and house number are typed.
///
/// The locked values are for display. The database writes its own copy of
/// them and ignores what the app sends for these fields.
class FixedFarmerAddressFields extends StatelessWidget {
  const FixedFarmerAddressFields({
    super.key,
    required this.streetController,
    required this.buildingController,
    required this.houseNoController,
  });

  final TextEditingController streetController;
  final TextEditingController buildingController;
  final TextEditingController houseNoController;

  Widget _locked({
    required String fieldKey,
    required String label,
    required String value,
    required IconData icon,
    required ColorScheme cs,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey('fixed-address-$fieldKey'),
        initialValue: value,
        readOnly: true,
        enableInteractiveSelection: false,
        decoration: authFieldDecoration(
          label: label,
          icon: icon,
          suffix: Padding(
            padding: const EdgeInsets.all(14),
            child: Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    String required(String label) => '$label *';
    String? requiredValidator(String? v) =>
        (v == null || v.trim().isEmpty) ? l10n.registerFieldRequired : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            l10n.registerAddressFixedNote,
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.5,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
        ),
        _locked(
          fieldKey: 'region',
          label: l10n.registerRegionLabel,
          value: FarmerRegistrationAddress.regionName,
          icon: Icons.public_outlined,
          cs: cs,
        ),
        _locked(
          fieldKey: 'province',
          label: l10n.registerProvinceLabel,
          value: FarmerRegistrationAddress.provinceName,
          icon: Icons.map_outlined,
          cs: cs,
        ),
        _locked(
          fieldKey: 'city',
          label: l10n.registerCityLabel,
          value: FarmerRegistrationAddress.cityName,
          icon: Icons.location_city_outlined,
          cs: cs,
        ),
        _locked(
          fieldKey: 'barangay',
          label: l10n.registerBarangayLabel,
          value: FarmerRegistrationAddress.barangayName,
          icon: Icons.holiday_village_outlined,
          cs: cs,
        ),
        _locked(
          fieldKey: 'postal',
          label: l10n.registerPostalLabel,
          value: FarmerRegistrationAddress.postalCode,
          icon: Icons.markunread_mailbox_outlined,
          cs: cs,
        ),
        TextFormField(
          controller: streetController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: authFieldDecoration(
            label: required(l10n.registerStreetLabel),
            icon: Icons.signpost_outlined,
          ),
          validator: requiredValidator,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: buildingController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: authFieldDecoration(
            label: l10n.registerBuildingLabel,
            icon: Icons.apartment_outlined,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: houseNoController,
          textInputAction: TextInputAction.done,
          decoration: authFieldDecoration(
            label: required(l10n.registerHouseNoLabel),
            icon: Icons.home_outlined,
          ),
          validator: requiredValidator,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
