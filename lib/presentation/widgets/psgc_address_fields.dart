import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/models/buyer_address_model.dart';
import '../../data/models/psgc_models.dart';
import 'app_dropdown_field.dart';

/// Editable structured-address state (PSGC levels plus street fields).
///
/// The screen owns one instance for its lifetime, so typed values and
/// selections survive rebuilds. Changing a level clears every level below it.
class AddressStructureDraft {
  PsgcRegion? region;
  PsgcProvince? province;
  PsgcCity? city;
  PsgcBarangay? barangay;

  final postalCtrl = TextEditingController();
  final streetCtrl = TextEditingController();
  final buildingCtrl = TextEditingController();
  final houseNoCtrl = TextEditingController();

  void dispose() {
    postalCtrl.dispose();
    streetCtrl.dispose();
    buildingCtrl.dispose();
    houseNoCtrl.dispose();
  }

  /// Cities/municipalities for the current selection. Regions without
  /// provinces (NCR, HUCs, independent cities) list their cities directly.
  List<PsgcCity> get cityOptions {
    final r = region;
    if (r == null) return const [];
    if (r.hasProvinces) return province?.cities ?? const [];
    return r.cities;
  }

  void selectRegion(PsgcRegion? value) {
    region = value;
    province = null;
    city = null;
    barangay = null;
  }

  void selectProvince(PsgcProvince? value) {
    province = value;
    city = null;
    barangay = null;
  }

  void selectCity(PsgcCity? value) {
    city = value;
    barangay = null;
  }

  void selectBarangay(PsgcBarangay? value) {
    barangay = value;
  }

  bool get postalValid => isValidPhilippinePostalCode(postalCtrl.text);

  /// True when every required field is filled and the postal code is valid.
  /// Building is optional, so it never blocks saving.
  bool get isComplete {
    final r = region;
    if (r == null || city == null || barangay == null) return false;
    if (r.hasProvinces && province == null) return false;
    return postalValid &&
        streetCtrl.text.trim().isNotEmpty &&
        houseNoCtrl.text.trim().isNotEmpty;
  }

  /// Restores a saved address by PSGC code. A code that is no longer in the
  /// bundled data is left unset, and the user picks that level again.
  void loadFrom(BuyerAddressModel address, PsgcHierarchy hierarchy) {
    region = _firstWhere(
      hierarchy.regions,
      (r) => r.code == address.regionCode,
    );
    final r = region;
    province = (r == null || !r.hasProvinces)
        ? null
        : _firstWhere(r.provinces, (p) => p.code == address.provinceCode);
    city = _firstWhere(
      cityOptions,
      (c) => c.code == address.cityMunicipalityCode,
    );
    final c = city;
    barangay = c == null
        ? null
        : _firstWhere(c.barangays, (b) => b.code == address.barangayCode);

    postalCtrl.text = address.postalCode ?? '';
    streetCtrl.text = address.street ?? '';
    buildingCtrl.text = address.building ?? '';
    houseNoCtrl.text = address.houseNo ?? '';
  }

  /// The full structure for a write. Empty optional fields become null, so
  /// the caller can save a cleared field as NULL (replaceStructure).
  BuyerAddressStructure toStructure() {
    final building = buildingCtrl.text.trim();
    return BuyerAddressStructure(
      regionCode: region?.code,
      regionName: region?.name,
      provinceCode: province?.code,
      provinceName: province?.name,
      cityMunicipalityCode: city?.code,
      cityMunicipalityName: city?.name,
      barangayCode: barangay?.code,
      barangayName: barangay?.name,
      postalCode: postalValid ? postalCtrl.text.trim() : null,
      street: _nullIfEmpty(streetCtrl.text),
      building: _nullIfEmpty(building),
      houseNo: _nullIfEmpty(houseNoCtrl.text),
    );
  }

  /// Single-line address for buyer_addresses.address_line (NOT NULL).
  String composeLine() {
    return [
      houseNoCtrl.text.trim(),
      buildingCtrl.text.trim(),
      streetCtrl.text.trim(),
      barangay?.name,
      city?.name,
      province?.name,
      region?.name,
      postalCtrl.text.trim(),
    ].whereType<String>().where((p) => p.isNotEmpty).join(', ');
  }

  static String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static T? _firstWhere<T>(List<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }
}

/// The structured address inputs: Region, Province (only where the region
/// has provinces), City/Municipality, Barangay, postal code, street, building,
/// and house number. [onChanged] runs after every change so the parent can
/// rebuild (for example, to refresh the saved-address summary).
class PsgcAddressFields extends StatelessWidget {
  final AddressStructureDraft draft;
  final PsgcHierarchy? hierarchy;
  final bool isLoading;
  final VoidCallback onChanged;

  const PsgcAddressFields({
    super.key,
    required this.draft,
    required this.hierarchy,
    required this.isLoading,
    required this.onChanged,
  });

  String _required(String label) => '$label *';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final psgc = hierarchy;
    final region = draft.region;
    final postalText = draft.postalCtrl.text;
    final postalInvalid = postalText.isNotEmpty && !draft.postalValid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!isLoading && psgc == null) ...[
          Text(
            l10n.registerAddressLoadFailed,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppConstants.errorRed,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (psgc != null) ...[
          AppDropdownField<PsgcRegion>(
            value: draft.region,
            hintText: l10n.addMemberSelectHint,
            labelText: _required(l10n.registerRegionLabel),
            items: psgc.regions,
            itemLabel: (r) => r.name,
            onChanged: (v) {
              draft.selectRegion(v);
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          if (region != null && region.hasProvinces) ...[
            AppDropdownField<PsgcProvince>(
              value: draft.province,
              hintText: l10n.addMemberSelectHint,
              labelText: _required(l10n.registerProvinceLabel),
              items: region.provinces,
              itemLabel: (p) => p.name,
              onChanged: (v) {
                draft.selectProvince(v);
                onChanged();
              },
            ),
            const SizedBox(height: 12),
          ],
          AppDropdownField<PsgcCity>(
            value: draft.city,
            hintText: l10n.addMemberSelectHint,
            labelText: _required(l10n.registerCityLabel),
            items: draft.cityOptions,
            itemLabel: (c) => c.name,
            onChanged: (v) {
              draft.selectCity(v);
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          AppDropdownField<PsgcBarangay>(
            value: draft.barangay,
            hintText: l10n.addMemberSelectHint,
            labelText: _required(l10n.registerBarangayLabel),
            items: draft.city?.barangays ?? const <PsgcBarangay>[],
            itemLabel: (b) => b.name,
            onChanged: (v) {
              draft.selectBarangay(v);
              onChanged();
            },
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: draft.postalCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          onChanged: (_) => onChanged(),
          decoration: _decoration(_required(l10n.registerPostalLabel)),
        ),
        if (postalInvalid)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.registerPostalInvalid,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppConstants.errorRed,
              ),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: draft.streetCtrl,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => onChanged(),
          decoration: _decoration(_required(l10n.registerStreetLabel)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: draft.buildingCtrl,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => onChanged(),
          decoration: _decoration(l10n.registerBuildingLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: draft.houseNoCtrl,
          onChanged: (_) => onChanged(),
          decoration: _decoration(_required(l10n.registerHouseNoLabel)),
        ),
      ],
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        borderSide: BorderSide(
          color: AppConstants.outline.withValues(alpha: 0.2),
        ),
      ),
      contentPadding: const EdgeInsets.all(12),
    );
  }
}
