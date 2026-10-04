import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../widgets/map_attribution_links.dart';
import '../../../core/constants/osm_config.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/repositories/farmer_profile_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';
import 'farm_location_full_map_screen.dart';

// ─── Barangay Payanas default center ─────────────────────────────────────────
const _defaultCenter = LatLng(13.6302, 121.9392);
const _defaultZoom = 15.0;
const _pinZoom = 16.5;

class EditFarmDetailsScreen extends StatefulWidget {
  const EditFarmDetailsScreen({super.key});

  @override
  State<EditFarmDetailsScreen> createState() => _EditFarmDetailsScreenState();
}

class _EditFarmDetailsScreenState extends State<EditFarmDetailsScreen> {
  final _repo = FarmerProfileRepository();
  final _formKey = GlobalKey<FormState>();

  // ── Text controllers ──────────────────────────────────────────────────────
  final _farmNameCtrl = TextEditingController();
  final _farmAddressCtrl = TextEditingController();
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
    _farmAddressCtrl.text = p.farmAddress ?? '';
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
    _farmAddressCtrl.dispose();
    _landAreaCtrl.dispose();
    _yearsFarmingCtrl.dispose();
    super.dispose();
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_isOnline) {
      _showSnack('You\'re offline. Connect to the internet to save changes.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      // Detect an explicit pin-clear: the profile previously had coordinates
      // but the pin is now null. updateFarmDetails() uses conditional
      // `if (x != null)` writes, so passing null lat/lng here would be
      // silently omitted from the update payload — clearing requires the
      // dedicated clearFarmCoordinates() method instead.
      final pinWasCleared =
          (_profile?.hasCoordinates ?? false) && _pinnedLocation == null;
      if (pinWasCleared) {
        await _repo.clearFarmCoordinates();
      }
      await _repo.updateFarmDetails(
        farmName: _farmNameCtrl.text.trim().isEmpty
            ? null
            : _farmNameCtrl.text.trim(),
        farmAddress: _farmAddressCtrl.text.trim().isEmpty
            ? null
            : _farmAddressCtrl.text.trim(),
        landAreaHectares: double.tryParse(_landAreaCtrl.text),
        yearsFarming: int.tryParse(_yearsFarmingCtrl.text),
        farmLatitude: _pinnedLocation?.latitude,
        farmLongitude: _pinnedLocation?.longitude,
        farmOwnershipType: _ownershipType,
      );
      if (mounted) {
        _showSnack('Farm details saved successfully.');
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
    final result = await Navigator.of(context).push<LatLng?>(
      MaterialPageRoute(
        builder: (_) =>
            FarmLocationFullMapScreen(initialLocation: _pinnedLocation),
      ),
    );
    // Always applied unconditionally — the full-map screen's own back
    // arrow and "Use This Location" button both pop with its current pin
    // state, so there's no separate "cancelled" case to special-case here.
    if (mounted) setState(() => _pinnedLocation = result);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(
              message:
                  "You're offline — you won't be able to save changes until you're reconnected.",
            ),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 64),
                    Expanded(
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: AppConstants.primaryGreen,
                              ),
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
                                  20,
                                  16,
                                  20,
                                  24,
                                ),
                                children: [
                                  // ── Section: Basic Information ─────────────────
                                  const _SectionHeader(
                                    icon: Icons.agriculture_rounded,
                                    label: 'Basic Information',
                                  ),
                                  const SizedBox(height: 10),
                                  _FormCard(
                                    children: [
                                      const _FieldLabel(label: 'Farm Name'),
                                      AppTextField(
                                        controller: _farmNameCtrl,
                                        hint: 'e.g. Santos Family Farm',
                                        prefixIcon: Icons.home_work_outlined,
                                        textCapitalization:
                                            TextCapitalization.words,
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) {
                                            return 'Farm name is required';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const _FieldLabel(
                                                  label: 'Land Area (ha)',
                                                ),
                                                AppTextField(
                                                  controller: _landAreaCtrl,
                                                  hint: '0.00',
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                        decimal: true,
                                                      ),
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter.allow(
                                                      RegExp(r'[0-9.]'),
                                                    ),
                                                  ],
                                                  validator: (v) {
                                                    if (v != null &&
                                                        v.isNotEmpty &&
                                                        double.tryParse(v) ==
                                                            null) {
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
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const _FieldLabel(
                                                  label: 'Years Farming',
                                                ),
                                                AppTextField(
                                                  controller: _yearsFarmingCtrl,
                                                  hint: '0',
                                                  keyboardType:
                                                      TextInputType.number,
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter
                                                        .digitsOnly,
                                                  ],
                                                  validator: (v) {
                                                    if (v != null &&
                                                        v.isNotEmpty &&
                                                        int.tryParse(v) ==
                                                            null) {
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
                                      const _FieldLabel(
                                        label: 'Land Ownership',
                                      ),
                                      _OptionChips(
                                        options: _ownershipOptions,
                                        selected: _ownershipType,
                                        onSelected: (v) =>
                                            setState(() => _ownershipType = v),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  // ── Section: Farm Location ─────────────────────
                                  const _SectionHeader(
                                    icon: Icons.location_on_rounded,
                                    label: 'Farm Location',
                                  ),
                                  const SizedBox(height: 10),
                                  _FormCard(
                                    children: [
                                      // Map section first, per the requested field
                                      // order (map before address).
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          GestureDetector(
                                            onTap: _openFullMap,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.open_in_full_rounded,
                                                  size: 14,
                                                  color:
                                                      AppConstants.primaryGreen,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'View Full Map',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppConstants
                                                        .primaryGreen,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Use "View Full Map" to place or adjust your farm pin.',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppConstants.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 10),

                                      // Coordinate display pill
                                      if (_pinnedLocation != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppConstants.primaryGreen
                                                .withValues(alpha: 0.07),
                                            borderRadius: BorderRadius.circular(
                                              AppConstants.radiusMd,
                                            ),
                                            border: Border.all(
                                              color: AppConstants.primaryGreen
                                                  .withValues(alpha: 0.20),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.my_location_rounded,
                                                size: 16,
                                                color:
                                                    AppConstants.primaryGreen,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Pin set',
                                                      style:
                                                          GoogleFonts.poppins(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: AppConstants
                                                                .primaryGreen,
                                                          ),
                                                    ),
                                                    Text(
                                                      '${_pinnedLocation!.latitude.toStringAsFixed(5)}° N, '
                                                      '${_pinnedLocation!.longitude.toStringAsFixed(5)}° E',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 11,
                                                        color: AppConstants
                                                            .onSurfaceVariant,
                                                        fontFeatures: const [
                                                          FontFeature.tabularFigures(),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap: _clearPin,
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppConstants.errorRed
                                                        .withValues(
                                                          alpha: 0.08,
                                                        ),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.close_rounded,
                                                    size: 14,
                                                    color:
                                                        AppConstants.errorRed,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (_pinnedLocation != null)
                                        const SizedBox(height: 10),

                                      // Offline warning
                                      if (!_isOnline)
                                        Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: AppConstants.warningAmber
                                                .withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(
                                              AppConstants.radiusMd,
                                            ),
                                            border: Border.all(
                                              color: AppConstants.warningAmber
                                                  .withValues(alpha: 0.25),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.wifi_off_rounded,
                                                size: 15,
                                                color:
                                                    AppConstants.warningAmber,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Map tiles need internet to load. '
                                                  'Pin position is still saved.',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    color: AppConstants
                                                        .warningAmber,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                      // Map preview — static display only (matches
                                      // the read-only Farm Details section's own
                                      // "LOCATION PREVIEW" map exactly). No
                                      // tap-to-expand/collapse affordance: the only
                                      // way to edit the pin is "View Full Map"
                                      // above, closing the redundant, overlapping
                                      // pair of controls the inline collapse/expand
                                      // toggle used to have alongside it.
                                      Container(
                                        height: 160,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            AppConstants.radiusLg,
                                          ),
                                          border: Border.all(
                                            color: AppConstants.primaryGreen
                                                .withValues(alpha: 0.20),
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: fm.FlutterMap(
                                          options: fm.MapOptions(
                                            initialCenter:
                                                _pinnedLocation ??
                                                _defaultCenter,
                                            initialZoom: _pinnedLocation != null
                                                ? _pinZoom
                                                : _defaultZoom,
                                            interactionOptions:
                                                const fm.InteractionOptions(
                                                  flags:
                                                      fm.InteractiveFlag.none,
                                                ),
                                          ),
                                          children: [
                                            const OsmMapAttribution(),
                                            fm.TileLayer(
                                              urlTemplate:
                                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                              userAgentPackageName:
                                                  'com.sp3coop.sagana',
                                              tileProvider:
                                                  fm.NetworkTileProvider(
                                                    headers: {
                                                      'User-Agent':
                                                          kOsmTileUserAgent,
                                                    },
                                                  ),
                                              // flutter_map cancels in-flight tile
                                              // requests for tiles that scroll out
                                              // of view mid-pan/zoom — expected, not
                                              // a real failure. Without this it
                                              // surfaces as a noisy "EXCEPTION
                                              // CAUGHT BY IMAGE RESOURCE SERVICE" log.
                                              errorTileCallback:
                                                  (tile, error, stackTrace) {},
                                            ),
                                            if (_pinnedLocation != null)
                                              fm.MarkerLayer(
                                                markers: [
                                                  fm.Marker(
                                                    point: _pinnedLocation!,
                                                    width: 48,
                                                    height: 56,
                                                    alignment:
                                                        Alignment.topCenter,
                                                    child: _MapPin(),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      const _FieldLabel(label: 'Address'),
                                      AppTextField(
                                        controller: _farmAddressCtrl,
                                        hint: 'e.g. Near the old barangay hall',
                                        prefixIcon: Icons.place_outlined,
                                        textCapitalization:
                                            TextCapitalization.sentences,
                                        maxLines: 2,
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) {
                                            return 'Address is required';
                                          }
                                          return null;
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  // ── Section: Primary Crops ─────────────────────
                                  const _SectionHeader(
                                    icon: Icons.grass_rounded,
                                    label: 'Primary Crops',
                                  ),
                                  const SizedBox(height: 10),
                                  _FormCard(
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
                                      if (_profile?.primaryCrops.isEmpty ??
                                          true)
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
                                          children: (_profile?.primaryCrops ?? [])
                                              .map(
                                                (crop) => Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 6,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFD5ECF8,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          AppConstants.radiusMd,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    crop,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: AppConstants
                                                          .primaryGreen,
                                                    ),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  // ── Info banner ────────────────────────────────
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppConstants.primaryGreen
                                          .withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(
                                        AppConstants.radiusMd,
                                      ),
                                      border: Border.all(
                                        color: AppConstants.primaryGreen
                                            .withValues(alpha: 0.15),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.info_outline_rounded,
                                          size: 16,
                                          color: AppConstants.primaryGreen,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Your farm location pin helps SP3 Admin verify your membership '
                                            'and will be used in future cooperative planning features.',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color:
                                                  AppConstants.onSurfaceVariant,
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

                // ── Top App Bar ──────────────────────────────────────────────────
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: FarmerTopBar(
                    title: 'Edit Farm Details',
                    onBack: () => context.popRoute(),
                    hideProfileAvatar: true,
                    onProfileTap: () {},
                    onNotificationTap: () {},
                    showNotificationButton: false,
                  ),
                ),
              ],
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
          label: !_isOnline
              ? 'Offline'
              : _isSaving
              ? 'Saving...'
              : 'Save Farm Details',
          isLoading: _isSaving,
          onPressed: (!_isOnline || _isSaving) ? null : _save,
          icon: Icons.check_rounded,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Map Pin widget
// ─────────────────────────────────────────────────────────────────────────────

class _MapPin extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppConstants.primaryGreen,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: AppConstants.primaryGreen.withValues(alpha: 0.40),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.agriculture_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
        CustomPaint(size: const Size(12, 10), painter: _PinTailPainter()),
      ],
    );
  }
}

class _PinTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppConstants.primaryGreen
      ..style = PaintingStyle.fill;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppConstants.primaryGreen),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppConstants.primaryGreen,
          ),
        ),
      ],
    );
  }
}

class _FormCard extends StatelessWidget {
  final List<Widget> children;
  const _FormCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.50)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

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
