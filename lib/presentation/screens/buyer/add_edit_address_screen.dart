import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/farmer_registration_address.dart';
import '../../../core/utils/db_error_utils.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_address_model.dart';
import '../../../data/repositories/buyer_address_repository.dart';
import '../../../data/repositories/buyer_profile_repository.dart';
import '../../../data/services/device_location_service.dart';
import '../../../data/services/nominatim_service.dart';
import '../../widgets/address_map_widgets.dart';
import '../../widgets/fixed_farmer_address_fields.dart';
import '../../widgets/map_attribution_links.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

/// Add/Edit Address — one screen for Farmers and Buyers (nullable `existing`).
///
/// Sections: Address Label (chips), Complete Address, Contact Information
/// (read-only, from the live profile), Map (current location and a pin),
/// Notes, and the default checkbox.
///
/// For every account, Farmer or Buyer, the five area fields (Region, Province,
/// City / Municipality, Barangay, Postal Code) are fixed to MIMAROPA Region /
/// Marinduque / Torrijos / Payanas / 4903: shown locked, using the same
/// [FixedFarmerAddressFields] and [FarmerRegistrationAddress] as Farmer
/// registration, and also forced by the database. Only Street, Building and
/// House No., the label, the map pin and the notes are editable.
///
/// The map pin is this address's delivery location. It is saved on the
/// address row only and never changes a Farmer's farm location.
class AddEditAddressScreen extends StatefulWidget {
  final BuyerAddressModel? existing;
  const AddEditAddressScreen({super.key, this.existing});

  @override
  State<AddEditAddressScreen> createState() => _AddEditAddressScreenState();
}

class _AddEditAddressScreenState extends State<AddEditAddressScreen> {
  final _repo = BuyerAddressRepository();
  final _profileRepo = BuyerProfileRepository();
  final _mapCtrl = fm.MapController();

  // The only typed parts of the address. The area is fixed.
  final _streetCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _houseNoCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String? _selectedLabel;
  String _profileFullName = '';
  String _profilePhone = '';
  LatLng? _pinnedLocation;
  bool _isDefault = false;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  bool _locating = false;
  String? _locationMessage;
  bool _locationBlocked = false;
  String? _nearestMatch;
  bool _nearestUnavailable = false;

  bool get _isEditing => widget.existing != null;

  /// Saved before the structured form existed: only the old single line is
  /// known, so the user completes the structured fields.
  bool get _isLegacyAddress =>
      widget.existing != null && widget.existing!.regionCode == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _streetCtrl.dispose();
    _buildingCtrl.dispose();
    _houseNoCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Contact info is always the user's CURRENT profile — never a per-address
    // snapshot that can drift out of sync by editing here. Still written into
    // the address row's own columns on save (schema unchanged), just never
    // edited from this screen.
    final profile = await _profileRepo.fetchProfile();
    final existing = widget.existing;
    if (!mounted) return;
    setState(() {
      _profileFullName = profile?.fullName ?? '';
      _profilePhone = profile?.phoneNumber ?? '';
      if (existing != null) {
        _selectedLabel = existing.label;
        _notesCtrl.text = existing.notes ?? '';
        _isDefault = existing.isDefault;
        // Only the three typed fields are read back; the area is fixed, so an
        // older address saved elsewhere shows (and is saved with) the fixed area.
        _streetCtrl.text = existing.street ?? '';
        _buildingCtrl.text = existing.building ?? '';
        _houseNoCtrl.text = existing.houseNo ?? '';
        if (existing.latitude != null && existing.longitude != null) {
          _pinnedLocation = LatLng(existing.latitude!, existing.longitude!);
        }
      }
      _isLoading = false;
    });
  }

  Future<void> _openFullMap() async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LocationPinPickerScreen(
          title: AppLocalizations.of(context).buyerAddressMapSection,
          initialLocation: _pinnedLocation,
        ),
      ),
    );
    if (result != null && mounted) {
      // The inline preview was built with a fixed start point, so move its camera
      // too. Otherwise a pin placed elsewhere stays off screen.
      _mapCtrl.move(result, kAddressMapPinZoom);
      setState(() => _pinnedLocation = result);
    }
  }

  // ── Current location ─────────────────────────────────────────────────────────

  Future<void> _useCurrentLocation() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _locating = true;
      _locationMessage = null;
      _locationBlocked = false;
      _nearestMatch = null;
      _nearestUnavailable = false;
    });
    final result = await DeviceLocationService.current();
    if (!mounted) return;

    final point = result.point;
    if (result.status != DeviceLocationStatus.ok || point == null) {
      setState(() {
        _locating = false;
        _locationBlocked = result.status == DeviceLocationStatus.deniedForever;
        _locationMessage = switch (result.status) {
          DeviceLocationStatus.servicesOff =>
            l10n.buyerAddressLocationServicesOff,
          DeviceLocationStatus.denied => l10n.buyerAddressLocationDenied,
          DeviceLocationStatus.deniedForever =>
            l10n.buyerAddressLocationDeniedForever,
          _ => l10n.buyerAddressLocationFailed,
        };
      });
      return;
    }

    setState(() {
      _pinnedLocation = point;
      _locating = false;
    });
    _mapCtrl.move(point, kAddressMapPinZoom);

    // A hint only. The pin is already set, and the PSGC fields are never
    // filled automatically from a map match.
    try {
      final nearest = await NominatimService.reverse(point);
      if (!mounted) return;
      setState(() => _nearestMatch = nearest?.displayName);
    } catch (_) {
      // Lookup failed: the pin still stands, and the user is told why there
      // is no nearest-match hint.
      if (!mounted) return;
      setState(() => _nearestUnavailable = true);
    }
  }

  // ── Save ────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_selectedLabel == null ||
        _pinnedLocation == null ||
        _notesCtrl.text.trim().isEmpty) {
      setState(() => _error = l10n.buyerAddressFormRequired);
      return;
    }
    if (_streetCtrl.text.trim().isEmpty || _houseNoCtrl.text.trim().isEmpty) {
      setState(() => _error = l10n.buyerAddressStructureRequired);
      return;
    }
    if (_profilePhone.trim().isEmpty) {
      setState(() => _error = l10n.buyerAddressPhoneMissing);
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final building = _buildingCtrl.text.trim();
    final structure = BuyerAddressStructure(
      regionCode: FarmerRegistrationAddress.regionCode,
      regionName: FarmerRegistrationAddress.regionName,
      provinceCode: FarmerRegistrationAddress.provinceCode,
      provinceName: FarmerRegistrationAddress.provinceName,
      cityMunicipalityCode: FarmerRegistrationAddress.cityCode,
      cityMunicipalityName: FarmerRegistrationAddress.cityName,
      barangayCode: FarmerRegistrationAddress.barangayCode,
      barangayName: FarmerRegistrationAddress.barangayName,
      postalCode: FarmerRegistrationAddress.postalCode,
      street: _streetCtrl.text.trim(),
      building: building.isEmpty ? null : building,
      houseNo: _houseNoCtrl.text.trim(),
    );
    final addressLine = FarmerRegistrationAddress.composeLine(
      houseNo: _houseNoCtrl.text,
      building: building,
      street: _streetCtrl.text,
    );
    try {
      final existing = widget.existing;
      if (existing != null) {
        await _repo.updateAddress(
          id: existing.id,
          label: _selectedLabel!,
          recipientName: _profileFullName,
          contactNumber: _profilePhone,
          addressLine: addressLine,
          latitude: _pinnedLocation!.latitude,
          longitude: _pinnedLocation!.longitude,
          notes: _notesCtrl.text.trim(),
          structure: structure,
          // Whole structure is replaced, so a cleared optional field is
          // saved as NULL.
          replaceStructure: true,
        );
        if (_isDefault && !existing.isDefault) {
          await _repo.setDefaultAddress(existing.id);
        }
      } else {
        final newId = await _repo.addAddress(
          label: _selectedLabel!,
          recipientName: _profileFullName,
          contactNumber: _profilePhone,
          addressLine: addressLine,
          latitude: _pinnedLocation!.latitude,
          longitude: _pinnedLocation!.longitude,
          notes: _notesCtrl.text.trim(),
          isDefault: _isDefault,
          structure: structure,
        );
        if (_isDefault) {
          // Implicit consequence of adding this address, not a distinct
          // "Set as default" tap — addAddress() already logged "Added
          // address"; avoid a redundant second entry for one action.
          await _repo.setDefaultAddress(newId, logActivity: false);
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,

      body: Column(
        children: [
          SubPageTopBar(title: _isEditing ? l10n.buyerAddressEditTitle : l10n.buyerAddressAddTitle, onBack: () => Navigator.of(context).pop()),
          OfflineStatusCard(title: l10n.offlineStatusTitle, message: l10n.offlineBuyerBody),
          Expanded(child: _isLoading
          ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingSafeH,
                12,
                AppConstants.spacingSafeH,
                32,
              ),
              children: [
                AddressSectionCard(
                  title: l10n.buyerAddressLineField,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isLegacyAddress) ...[
                        Text(
                          l10n.buyerAddressLegacyNotice,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.warningAmber,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      FixedFarmerAddressFields(
                        streetController: _streetCtrl,
                        buildingController: _buildingCtrl,
                        houseNoController: _houseNoCtrl,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                AddressSectionCard(
                  title: l10n.buyerAddressContactInfoSection,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _readOnlyField(
                        icon: Icons.person_outline_rounded,
                        label: l10n.buyerAddressFullNameField,
                        value: _profileFullName.isNotEmpty
                            ? _profileFullName
                            : '—',
                      ),
                      Divider(
                        height: 20,
                        color: AppConstants.outline.withValues(alpha: 0.12),
                      ),
                      _readOnlyField(
                        icon: Icons.phone_outlined,
                        label: l10n.buyerAddressPhoneField,
                        value: _profilePhone.isNotEmpty ? _profilePhone : '—',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                AddressSectionCard(
                  title: l10n.buyerAddressMapSection,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: _locating ? null : _useCurrentLocation,
                            icon: const Icon(
                              Icons.my_location_rounded,
                              size: 16,
                              color: AppConstants.primaryGreen,
                            ),
                            label: Text(
                              _locating
                                  ? l10n.buyerAddressLocating
                                  : l10n.buyerAddressUseCurrentLocation,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppConstants.primaryGreen,
                              ),
                            ),
                          ),
                          if (_locationBlocked)
                            TextButton(
                              onPressed: DeviceLocationService.openSettings,
                              child: Text(
                                l10n.buyerAddressOpenSettings,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (_locationMessage != null)
                        Text(
                          _locationMessage!,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.warningAmber,
                          ),
                        ),
                      if (_nearestMatch != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          l10n.buyerAddressNearestMatch(_nearestMatch!),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (_nearestUnavailable) ...[
                        const SizedBox(height: 4),
                        Text(
                          l10n.buyerAddressNearestUnavailable,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.warningAmber,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      ViewFullMapLink(
                        onTap: _openFullMap,
                        label: l10n.buyerAddressViewFullMap,
                      ),
                      const SizedBox(height: 10),
                      AddressMapPreview(
                        controller: _mapCtrl,
                        pin: _pinnedLocation,
                      ),
                      const SizedBox(height: 6),
                      const MapAttributionLinks(),
                      if (_pinnedLocation == null) ...[
                        const SizedBox(height: 6),
                        Text(
                          l10n.buyerAddressMapRequiredHint,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.warningAmber,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                AddressSectionCard(
                  title: l10n.buyerAddressLabelSection,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final label in AppConstants.buyerAddressLabels)
                        _LabelChip(
                          label: label,
                          selected: _selectedLabel == label,
                          onTap: () => setState(() => _selectedLabel = label),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                AddressSectionCard(
                  title: l10n.buyerAddressNotesField,
                  child: TextField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: _fieldDecoration(
                      hint: l10n.buyerAddressNotesHint,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: sagana.cardBackground,
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    border: AppConstants.cardBorder,
                    boxShadow: AppConstants.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Transform.translate(
                        offset: const Offset(-6, 0),
                        child: Checkbox(
                          value: _isDefault,
                          activeColor: AppConstants.primaryGreen,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          onChanged: (v) =>
                              setState(() => _isDefault = v ?? false),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          l10n.buyerAddressSetDefaultCheckbox,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppConstants.errorRed,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: l10n.buyerAddressSave,
                    isLoading: _isSubmitting,
                    onPressed: _isSubmitting ? null : _save,
                  ),
                ),
              ],
            )),
        ],
      ),
    );
  }

  Widget _readOnlyField({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppConstants.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.lock_outline_rounded,
          size: 14,
          color: AppConstants.outline.withValues(alpha: 0.6),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        fontSize: 13,
        color: AppConstants.outline.withValues(alpha: 0.6),
      ),
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

class _LabelChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LabelChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  IconData get _icon {
    switch (label.toLowerCase()) {
      case 'home':
        return Icons.home_rounded;
      case 'work':
        return Icons.work_rounded;
      case 'farm':
        return Icons.agriculture_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppConstants.primaryGreen
              : context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: selected
                ? AppConstants.primaryGreen
                : AppConstants.outline.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _icon,
              size: 15,
              color: selected ? Colors.white : AppConstants.primaryGreen,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppConstants.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
