import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/farmer_registration_address.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/repositories/farmer_profile_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/offline_actions.dart';
import '../../widgets/address_map_widgets.dart';
import '../../widgets/fixed_farmer_address_fields.dart';
import '../../widgets/map_attribution_links.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

/// A pin farther than this from Barangay Payanas gets a gentle warning. It is
/// only a hint: a farm near the barangay edge is legitimate, so it never blocks
/// saving.
const _farPinWarningKm = 6.0;

/// Farm Details: the farm's own address and its map pin.
///
/// Laid out like Add / Edit Address (My Addresses), but for the FARM, not the
/// home: the farm address first (the five area fields are locked to MIMAROPA
/// Region / Marinduque / Torrijos / Payanas / 4903, only Street, Building and
/// House No. are typed), then the farm map with "View Full Map", then the other
/// farm details.
///
/// Everything here is stored on `farmer_profiles` (farm_street, farm_building,
/// farm_house_no, farm_address, farm_latitude, farm_longitude). The home
/// addresses in `buyer_addresses` are never read or written by this screen.
class EditFarmDetailsScreen extends StatefulWidget {
  const EditFarmDetailsScreen({super.key, this.initialProfile});

  /// A profile that is already loaded. The route does not pass one (the screen
  /// fetches its own); tests use it to show the form without a database.
  final FarmerProfileModel? initialProfile;

  @override
  State<EditFarmDetailsScreen> createState() => _EditFarmDetailsScreenState();
}

class _EditFarmDetailsScreenState extends State<EditFarmDetailsScreen> {
  final _repo = FarmerProfileRepository();
  final _formKey = GlobalKey<FormState>();
  final _mapCtrl = fm.MapController();

  // ── Text controllers ──────────────────────────────────────────────────────
  final _farmNameCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _houseNoCtrl = TextEditingController();
  final _landAreaCtrl = TextEditingController();
  final _yearsFarmingCtrl = TextEditingController();

  // ── Dropdown selections ───────────────────────────────────────────────────
  String? _ownershipType;
  List<String> _ownershipOptions = [];

  // ── Map state ─────────────────────────────────────────────────────────────
  LatLng? _pinnedLocation;
  bool _isOnline = true;

  // ── Screen state ──────────────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isSaving = false;
  bool _argsRead = false;
  bool _loadFailed = false;
  FarmerProfileModel? _profile;

  /// The farm address was saved as one free-text line, before the structured
  /// form existed. The typed fields are then optional until the farmer fills
  /// any of them, and the saved line is kept if they leave them empty.
  bool get _isLegacyAddress {
    final p = _profile;
    if (p == null) return false;
    return !p.hasStructuredFarmAddress &&
        (p.farmAddress?.trim().isNotEmpty ?? false);
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    final initial = widget.initialProfile;
    if (initial != null) {
      _populateFrom(initial);
      _isLoading = false;
    }
    _loadProfile();
    _loadOwnershipOptions();
  }

  Future<void> _loadOwnershipOptions() async {
    final options = await _repo.fetchOwnershipTypes();
    if (!mounted) return;
    setState(() => _ownershipOptions = options);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Profile can also be passed as a route argument to skip the fetch
    if (!_argsRead) {
      _argsRead = true;
      final arg = ModalRoute.of(context)?.settings.arguments;
      if (arg is FarmerProfileModel) {
        _populateFrom(arg);
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadProfile() async {
    if (!_isLoading) return; // already populated from args
    setState(() => _loadFailed = false);
    try {
      final profile = await _repo.fetchProfile().timeout(
        const Duration(seconds: 15),
      );
      if (!mounted) return;
      if (profile != null) _populateFrom(profile);
      setState(() => _isLoading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  void _retryLoadProfile() {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    _loadProfile();
  }

  void _populateFrom(FarmerProfileModel p) {
    _profile = p;
    _farmNameCtrl.text = p.farmName ?? '';
    // Only the three typed parts are read back; the area is fixed.
    _streetCtrl.text = p.farmStreet ?? '';
    _buildingCtrl.text = p.farmBuilding ?? '';
    _houseNoCtrl.text = p.farmHouseNo ?? '';
    _landAreaCtrl.text = p.landAreaHectares?.toString() ?? '';
    _yearsFarmingCtrl.text = p.yearsFarming?.toString() ?? '';
    _ownershipType = p.farmOwnershipType;
    if (p.hasCoordinates) {
      _pinnedLocation = LatLng(p.farmLatitude!, p.farmLongitude!);
    }
  }

  @override
  void dispose() {
    _farmNameCtrl.dispose();
    _streetCtrl.dispose();
    _buildingCtrl.dispose();
    _houseNoCtrl.dispose();
    _landAreaCtrl.dispose();
    _yearsFarmingCtrl.dispose();
    super.dispose();
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    // Detect an explicit pin-clear: the profile previously had coordinates
    // but the pin is now null. updateFarmDetails() uses conditional
    // `if (x != null)` writes, so passing null lat/lng here would be
    // silently omitted from the update payload — clearing requires the
    // dedicated clearFarmCoordinates() method instead.
    final pinWasCleared =
        (_profile?.hasCoordinates ?? false) && _pinnedLocation == null;
    // Clearing the pin is not queued yet, so it needs a connection.
    if (pinWasCleared && !_isOnline) {
      _showSnack('You\'re offline. Connect to the internet to clear the pin.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    // A farm saved before the structured form keeps its old line when the typed
    // fields are left empty; otherwise the line is built from the typed parts
    // and the fixed area, in the same order as My Addresses.
    final street = _streetCtrl.text.trim();
    final building = _buildingCtrl.text.trim();
    final houseNo = _houseNoCtrl.text.trim();
    final addressTyped =
        street.isNotEmpty || building.isNotEmpty || houseNo.isNotEmpty;
    final farmAddress = addressTyped
        ? FarmerRegistrationAddress.composeLine(
            houseNo: houseNo,
            building: building,
            street: street,
          )
        : null;

    setState(() => _isSaving = true);
    try {
      if (pinWasCleared) {
        await _repo.clearFarmCoordinates();
      }
      final outcome = await _repo.updateFarmDetails(
        farmName: _farmNameCtrl.text.trim().isEmpty
            ? null
            : _farmNameCtrl.text.trim(),
        farmAddress: farmAddress,
        farmStreet: addressTyped ? street : null,
        farmBuilding: addressTyped && building.isNotEmpty ? building : null,
        farmHouseNo: addressTyped ? houseNo : null,
        landAreaHectares: double.tryParse(_landAreaCtrl.text),
        yearsFarming: int.tryParse(_yearsFarmingCtrl.text),
        farmLatitude: _pinnedLocation?.latitude,
        farmLongitude: _pinnedLocation?.longitude,
        farmOwnershipType: _ownershipType,
      );
      if (mounted) {
        _showSnack(
          outcome == SaveOutcome.queued
              ? l10n.savedOnDeviceSyncLater
              : 'Farm details saved successfully.',
        );
        // Use go_router's pop helper to ensure we pop the correct navigator
        // when this screen is presented from different navigator roots.
        // true = refresh caller
        if (context.mounted) context.popRoute(true);
      }
    } catch (_) {
      setState(() => _isSaving = false);
      _showSnack('Failed to save. Please try again.');
    }
  }

  // ── Map interaction ───────────────────────────────────────────────────────

  void _clearPin() {
    setState(() => _pinnedLocation = null);
  }

  Future<void> _openFullMap() async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LocationPinPickerScreen(
          title: AppLocalizations.of(context).farmLocationMapTitle,
          initialLocation: _pinnedLocation,
          pinColor: AppConstants.primaryGreen,
        ),
      ),
    );
    // Back without confirming returns nothing, so the current pin stays.
    if (result != null && mounted) {
      // The preview was built with a fixed start point, so move its camera too.
      _mapCtrl.move(result, kAddressMapPinZoom);
      setState(() => _pinnedLocation = result);
    }
  }

  /// Kilometres from the pin to the middle of Barangay Payanas.
  double? get _pinDistanceKm {
    final pin = _pinnedLocation;
    if (pin == null) return null;
    return const Distance().as(LengthUnit.Kilometer, pin, kAddressMapCenter);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  Widget _addressSection(AppLocalizations l10n) {
    return AddressSectionCard(
      title: l10n.farmAddressSectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isLegacyAddress) ...[
            Text(
              l10n.farmAddressLegacyNotice(_profile!.farmAddress!),
              key: const ValueKey('farm-address-legacy-notice'),
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
            note: l10n.farmAddressFixedNote,
            allowAllBlank: _isLegacyAddress,
          ),
        ],
      ),
    );
  }

  Widget _mapSection(AppLocalizations l10n) {
    final far = _pinDistanceKm;
    return AddressSectionCard(
      title: l10n.farmLocationSectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ViewFullMapLink(
            onTap: _openFullMap,
            label: l10n.farmViewFullMap,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.farmMapHint,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          if (!_isOnline) ...[
            Text(
              'Map tiles need internet to load. Pin position is still saved.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppConstants.warningAmber,
              ),
            ),
            const SizedBox(height: 10),
          ],
          AddressMapPreview(
            controller: _mapCtrl,
            pin: _pinnedLocation,
            pinColor: AppConstants.primaryGreen,
          ),
          const SizedBox(height: 6),
          const MapAttributionLinks(),
          if (_pinnedLocation != null) ...[
            const SizedBox(height: 10),
            _PinPill(location: _pinnedLocation!, onClear: _clearPin),
            if (far != null && far > _farPinWarningKm) ...[
              const SizedBox(height: 6),
              Text(
                l10n.farmPinFarFromBarangay,
                key: const ValueKey('farm-pin-far-warning'),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppConstants.warningAmber,
                ),
              ),
            ],
          ] else ...[
            const SizedBox(height: 6),
            Text(
              l10n.farmPinNotSet,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppConstants.warningAmber,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _basicInfoSection() {
    return AddressSectionCard(
      title: 'Basic Information',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel(label: 'Farm Name'),
          AppTextField(
            controller: _farmNameCtrl,
            hint: 'e.g. Santos Family Farm',
            prefixIcon: Icons.home_work_outlined,
            textCapitalization: TextCapitalization.words,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Farm name is required';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel(label: 'Land Area (ha)'),
                    AppTextField(
                      controller: _landAreaCtrl,
                      hint: '0.00',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      validator: (v) {
                        if (v != null &&
                            v.isNotEmpty &&
                            double.tryParse(v) == null) {
                          return 'Invalid number';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel(label: 'Years Farming'),
                    AppTextField(
                      controller: _yearsFarmingCtrl,
                      hint: '0',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        if (v != null &&
                            v.isNotEmpty &&
                            int.tryParse(v) == null) {
                          return 'Whole number only';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _FieldLabel(label: 'Land Ownership'),
          _OptionChips(
            options: _ownershipOptions,
            selected: _ownershipType,
            onSelected: (v) => setState(() => _ownershipType = v),
          ),
        ],
      ),
    );
  }

  Widget _cropsSection() {
    final crops = _profile?.primaryCrops ?? const <String>[];
    return AddressSectionCard(
      title: 'Primary Crops',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primary crops — read-only from farmer_crops
          Text(
            'Managed via the Harvest tab. Add crops there to update this list.',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (crops.isEmpty)
            Text(
              'No crops added yet',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppConstants.outline,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: crops
                  .map(
                    (crop) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD5ECF8),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusMd,
                        ),
                      ),
                      child: Text(
                        crop,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.primaryGreen,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Column(
        children: [
          SubPageTopBar(title: l10n.editFarmDetails, onBack: context.popRoute),
          if (!_isOnline) OfflineStatusCard(message: l10n.offlineSaveNotice),
          Expanded(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : _loadFailed
                ? _FarmDetailsLoadError(
                    onRetry: _retryLoadProfile,
                    isOnline: _isOnline,
                  )
                : Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.spacingSafeH,
                        12,
                        AppConstants.spacingSafeH,
                        24,
                      ),
                      children: [
                        // 1. The farm address, then 2. its map.
                        _addressSection(l10n),
                        const SizedBox(height: 16),
                        _mapSection(l10n),
                        const SizedBox(height: 16),
                        _basicInfoSection(),
                        const SizedBox(height: 16),
                        _cropsSection(),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppConstants.primaryGreen.withValues(
                              alpha: 0.06,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusMd,
                            ),
                            border: Border.all(
                              color: AppConstants.primaryGreen.withValues(
                                alpha: 0.15,
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: AppConstants.primaryGreen,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Your farm location pin helps SP3 Manager verify your membership '
                                  'and will be used in future cooperative planning features.',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppConstants.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      // Laid out by Scaffold itself rather than a Positioned+Stack offset,
      // so it can never visually track the ListView's scroll position
      // regardless of keyboard insets or content height.
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(context).padding.bottom + 12,
        ),
        decoration: BoxDecoration(
          color: AppConstants.offWhite,
          border: Border(
            top: BorderSide(
              color: AppConstants.outline.withValues(alpha: 0.10),
            ),
          ),
        ),
        child: PrimaryButton(
          label: _isSaving ? 'Saving...' : 'Save Farm Details',
          isLoading: _isSaving,
          onPressed: _isSaving ? null : _save,
          icon: Icons.check_rounded,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coordinates pill: the saved/selected farm pin, with a clear button.
// ─────────────────────────────────────────────────────────────────────────────

class _PinPill extends StatelessWidget {
  final LatLng location;
  final VoidCallback onClear;
  const _PinPill({required this.location, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppConstants.primaryGreen.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: AppConstants.primaryGreen.withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.my_location_rounded,
            size: 16,
            color: AppConstants.primaryGreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pin set',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.primaryGreen,
                  ),
                ),
                Text(
                  '${location.latitude.toStringAsFixed(5)}° N, '
                  '${location.longitude.toStringAsFixed(5)}° E',
                  key: const ValueKey('farm-pin-coordinates'),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppConstants.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppConstants.errorRed.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 14,
                color: AppConstants.errorRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Farm Details Load Error — shown when fetchProfile() fails or times out.
// Message/icon distinguish "you're offline" from a genuine load failure,
// matching FarmerProfileScreen's _ProfileLoadError pattern.
// ─────────────────────────────────────────────────────────────────────────────

class _FarmDetailsLoadError extends StatelessWidget {
  final VoidCallback onRetry;
  final bool isOnline;
  const _FarmDetailsLoadError({required this.onRetry, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOnline ? Icons.error_outline_rounded : Icons.wifi_off_rounded,
              size: 40,
              color: AppConstants.outline.withValues(alpha: 0.60),
            ),
            const SizedBox(height: 12),
            Text(
              isOnline ? 'Could not load your farm details' : 'You\'re offline',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppConstants.charcoal,
              ),
            ),
            if (!isOnline) ...[
              const SizedBox(height: 4),
              Text(
                'Your farm details will load once you\'re back online.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Retry',
                style: GoogleFonts.poppins(color: AppConstants.primaryGreen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private layout widgets
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppConstants.outline,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// Options are plain strings (value == label), sourced from a DB-backed
// lookup table (see FarmerProfileRepository.fetchOwnershipTypes()) rather
// than a hardcoded list — no separate code/label split needed since the
// lookup table's `name` column already stores the human-readable string.
class _OptionChips extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _OptionChips({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSelected = selected == opt;
        return GestureDetector(
          onTap: () => onSelected(isSelected ? null : opt),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppConstants.primaryGreen : Colors.white,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                color: isSelected
                    ? AppConstants.primaryGreen
                    : AppConstants.outline.withValues(alpha: 0.30),
              ),
            ),
            child: Text(
              opt,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? Colors.white : AppConstants.onSurface,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
