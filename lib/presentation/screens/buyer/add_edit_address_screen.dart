import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/osm_config.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_address_model.dart';
import '../../../data/repositories/buyer_address_repository.dart';
import '../../../data/repositories/buyer_profile_repository.dart';
import '../../../data/repositories/psgc_repository.dart';
import '../../../data/models/psgc_models.dart';
import '../../../data/services/device_location_service.dart';
import '../../../data/services/nominatim_service.dart';
import '../../widgets/map_attribution_links.dart';
import '../../widgets/psgc_address_fields.dart';
import '../../widgets/shared_widgets.dart';

// Same Barangay Payanas default center/zoom, same OpenStreetMap tile
// source, as the farmer Edit Farm Details map picker — reusing that exact
// configuration rather than a second one.
const _defaultCenter = LatLng(13.6302, 121.9392);
const _defaultZoom = 15.0;
const _pinZoom = 16.5;

/// Add/Edit Address — one screen for Farmers and Buyers (nullable `existing`).
///
/// Sections: Address Label (chips), Complete Address (structured PSGC
/// fields, postal code, street, building, house number), Contact
/// Information (read-only, from the live profile), Map (current location and
/// a pin), Notes, and the default checkbox.
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

  final _draft = AddressStructureDraft();
  final _notesCtrl = TextEditingController();

  String? _selectedLabel;
  String _profileFullName = '';
  String _profilePhone = '';
  LatLng? _pinnedLocation;
  bool _isDefault = false;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  PsgcHierarchy? _psgc;
  bool _psgcLoading = true;


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
    _draft.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Contact info is always the buyer's CURRENT profile — never a
    // per-address snapshot the buyer can drift out of sync by editing
    // here. Still written into the address row's own columns on save
    // (schema unchanged), just never edited from this screen.
    final profile = await _profileRepo.fetchProfile();
    final hierarchy = await PsgcRepository.load();
    final existing = widget.existing;
    if (!mounted) return;
    setState(() {
      _profileFullName = profile?.fullName ?? '';
      _profilePhone = profile?.phoneNumber ?? '';
      if (hierarchy.regions.isNotEmpty) _psgc = hierarchy;
      _psgcLoading = false;
      if (existing != null) {
        _selectedLabel = existing.label;
        _notesCtrl.text = existing.notes ?? '';
        _isDefault = existing.isDefault;
        if (_psgc != null) _draft.loadFrom(existing, _psgc!);
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
        builder: (_) => _AddressFullMapScreen(initialLocation: _pinnedLocation),
      ),
    );
    if (result != null && mounted) {
      // The inline preview was built with a fixed start point, so move its camera
      // too. Otherwise a pin placed elsewhere stays off screen.
      _mapCtrl.move(result, _pinZoom);
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
    _mapCtrl.move(point, _pinZoom);

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
    if (_draft.postalCtrl.text.isNotEmpty && !_draft.postalValid) {
      setState(() => _error = l10n.registerPostalInvalid);
      return;
    }
    if (!_draft.isComplete) {
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
    final structure = _draft.toStructure();
    final addressLine = _draft.composeLine();
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
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: sagana.scaffoldBackground,
        elevation: 0,
        leading: BackButton(
          onPressed: () => Navigator.of(context).pop(false),
          color: AppConstants.primaryGreen,
        ),
        title: Text(
          _isEditing ? l10n.buyerAddressEditTitle : l10n.buyerAddressAddTitle,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppConstants.primaryGreen,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingSafeH,
                12,
                AppConstants.spacingSafeH,
                32,
              ),
              children: [
                _SectionCard(
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
                      PsgcAddressFields(
                        draft: _draft,
                        hierarchy: _psgc,
                        isLoading: _psgcLoading,
                        onChanged: () => setState(() {}),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _SectionCard(
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

                _SectionCard(
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
                      GestureDetector(
                        onTap: _openFullMap,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.open_in_full_rounded,
                              size: 14,
                              color: AppConstants.primaryGreen,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l10n.buyerAddressViewFullMap,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppConstants.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusMd,
                        ),
                        child: SizedBox(
                          height: 180,
                          child: fm.FlutterMap(
                            mapController: _mapCtrl,
                            // Static preview, not a picker — dragging,
                            // pinching, or tapping this small inline map
                            // could accidentally move an already-confirmed
                            // pin. Current location and "View Full
                            // Map" are the ways to set or change the pin.
                            options: fm.MapOptions(
                              initialCenter: _pinnedLocation ?? _defaultCenter,
                              initialZoom: _pinnedLocation != null
                                  ? _pinZoom
                                  : _defaultZoom,
                              interactionOptions: const fm.InteractionOptions(
                                flags: fm.InteractiveFlag.none,
                              ),
                            ),
                            children: [
                              fm.TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.sp3coop.sagana',
                                tileProvider: fm.NetworkTileProvider(
                                  headers: {'User-Agent': kOsmTileUserAgent},
                                ),
                              ),
                              if (_pinnedLocation != null)
                                fm.MarkerLayer(
                                  markers: [
                                    fm.Marker(
                                      point: _pinnedLocation!,
                                      width: 40,
                                      height: 40,
                                      alignment: Alignment.topCenter,
                                      child: const Icon(
                                        Icons.location_on_rounded,
                                        color: AppConstants.errorRed,
                                        size: 36,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
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

                _SectionCard(
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

                _SectionCard(
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

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: AppConstants.cardBorder,
        boxShadow: AppConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen map picker — same black-background/back-button-overlay/zoom-
// controls treatment previously used by the buyer checkout flow's own
// delivery map picker, before Checkout replaced post-approval fulfillment;
// rebuilt here since My Addresses is now the map-pin entry point instead.
// ─────────────────────────────────────────────────────────────────────────────

class _AddressFullMapScreen extends StatefulWidget {
  final LatLng? initialLocation;
  const _AddressFullMapScreen({this.initialLocation});

  @override
  State<_AddressFullMapScreen> createState() => _AddressFullMapScreenState();
}

class _AddressFullMapScreenState extends State<_AddressFullMapScreen> {
  final _mapCtrl = fm.MapController();
  LatLng? _pinnedLocation;

  @override
  void initState() {
    super.initState();
    _pinnedLocation = widget.initialLocation;
  }

  void _onMapTap(fm.TapPosition _, LatLng point) {
    setState(() => _pinnedLocation = point);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: fm.FlutterMap(
              mapController: _mapCtrl,
              options: fm.MapOptions(
                initialCenter: _pinnedLocation ?? _defaultCenter,
                initialZoom: _pinnedLocation != null ? _pinZoom : _defaultZoom,
                onTap: _onMapTap,
              ),
              children: [
                fm.TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.sp3coop.sagana',
                  tileProvider: fm.NetworkTileProvider(
                    headers: {'User-Agent': kOsmTileUserAgent},
                  ),
                  errorTileCallback: (tile, error, stackTrace) {},
                ),
                if (_pinnedLocation != null)
                  fm.MarkerLayer(
                    markers: [
                      fm.Marker(
                        point: _pinnedLocation!,
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: AppConstants.errorRed,
                          size: 36,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: context.saganaColors.glassBackground,
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusMd,
                        ),
                        border: Border.all(
                          color: context.saganaColors.glassBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: AppConstants.primaryGreen,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              l10n.buyerAddressMapSection,
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppConstants.primaryGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 100,
            child: Column(
              children: [
                _FullMapButton(
                  icon: Icons.add_rounded,
                  onTap: () => _mapCtrl.move(
                    _mapCtrl.camera.center,
                    _mapCtrl.camera.zoom + 1,
                  ),
                ),
                const SizedBox(height: 6),
                _FullMapButton(
                  icon: Icons.remove_rounded,
                  onTap: () => _mapCtrl.move(
                    _mapCtrl.camera.center,
                    _mapCtrl.camera.zoom - 1,
                  ),
                ),
              ],
            ),
          ),
          // Right edge stops short of the zoom buttons (about 48 px wide plus
          // margin), so the credit wraps instead of running underneath them.
          Positioned(
            left: 12,
            right: 72,
            bottom: 96,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                color: Colors.white.withValues(alpha: 0.75),
                child: const MapAttributionLinks(color: Colors.black87),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: PrimaryButton(
                label: _pinnedLocation != null
                    ? l10n.buyerAddressConfirmLocation
                    : l10n.buyerAddressTapToPlacePin,
                onPressed: _pinnedLocation != null
                    ? () => Navigator.of(context).pop(_pinnedLocation)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullMapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _FullMapButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: context.saganaColors.cardBackground,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: AppConstants.primaryGreen),
      ),
    );
  }
}
