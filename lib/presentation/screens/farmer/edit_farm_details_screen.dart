import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/repositories/farmer_profile_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';

// ─── Barangay Payanas default center ─────────────────────────────────────────
const _defaultCenter = LatLng(13.6302, 121.9392);
const _defaultZoom   = 15.0;
const _pinZoom       = 16.5;

class EditFarmDetailsScreen extends StatefulWidget {
  const EditFarmDetailsScreen({super.key});

  @override
  State<EditFarmDetailsScreen> createState() => _EditFarmDetailsScreenState();
}

class _EditFarmDetailsScreenState extends State<EditFarmDetailsScreen> {
  final _repo        = FarmerProfileRepository();
  final _mapCtrl     = fm.MapController();
  final _formKey     = GlobalKey<FormState>();

  // ── Text controllers ──────────────────────────────────────────────────────
  final _farmNameCtrl     = TextEditingController();
  final _farmAddressCtrl  = TextEditingController();
  final _landAreaCtrl     = TextEditingController();
  final _yearsFarmingCtrl = TextEditingController();

  // ── Dropdown selections ───────────────────────────────────────────────────
  String? _ownershipType;
  String? _soilType;
  String? _waterSource;

  // ── Map state ─────────────────────────────────────────────────────────────
  LatLng? _pinnedLocation;
  bool _mapExpanded   = false;
  bool _isOnline      = true;

  // ── Screen state ──────────────────────────────────────────────────────────
  bool _isLoading     = true;
  bool _isSaving      = false;
  bool _argsRead      = false;
  FarmerProfileModel? _profile;

  // ── Option lists ──────────────────────────────────────────────────────────
  static const _ownershipOptions = [
    _Option('owned',    'Owned'),
    _Option('leased',   'Leased'),
    _Option('communal', 'Communal / Shared'),
  ];
  static const _soilOptions = [
    _Option('sandy',    'Sandy'),
    _Option('clay',     'Clay'),
    _Option('loam',     'Loam'),
    _Option('volcanic', 'Volcanic'),
    _Option('mixed',    'Mixed'),
  ];
  static const _waterOptions = [
    _Option('rain_fed',  'Rain-fed'),
    _Option('irrigated', 'Irrigated'),
    _Option('well',      'Well'),
    _Option('river',     'River'),
    _Option('mixed',     'Mixed'),
  ];

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
    _loadProfile();
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
    final profile = await _repo.fetchProfile();
    if (!mounted) return;
    if (profile != null) _populateFrom(profile);
    setState(() => _isLoading = false);
  }

  void _populateFrom(FarmerProfileModel p) {
    _profile              = p;
    _farmNameCtrl.text    = p.farmName ?? '';
    _farmAddressCtrl.text = p.farmAddress ?? p.farmLocation ?? '';
    _landAreaCtrl.text    = p.landAreaHectares?.toString() ?? '';
    _yearsFarmingCtrl.text = p.yearsFarming?.toString() ?? '';
    _ownershipType        = p.farmOwnershipType;
    _soilType             = p.soilType;
    _waterSource          = p.waterSource;
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
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _repo.updateFarmDetails(
        farmName:          _farmNameCtrl.text.trim().isEmpty
            ? null
            : _farmNameCtrl.text.trim(),
        farmAddress:       _farmAddressCtrl.text.trim().isEmpty
            ? null
            : _farmAddressCtrl.text.trim(),
        farmLocation:      _farmAddressCtrl.text.trim().isEmpty
            ? null
            : _farmAddressCtrl.text.trim(),
        landAreaHectares:  double.tryParse(_landAreaCtrl.text),
        yearsFarming:      int.tryParse(_yearsFarmingCtrl.text),
        farmLatitude:      _pinnedLocation?.latitude,
        farmLongitude:     _pinnedLocation?.longitude,
        farmOwnershipType: _ownershipType,
        soilType:          _soilType,
        waterSource:       _waterSource,
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

  void _onMapTap(fm.TapPosition _, LatLng point) {
    setState(() => _pinnedLocation = point);
  }

  void _clearPin() {
    setState(() => _pinnedLocation = null);
  }

  void _centerOnPin() {
    if (_pinnedLocation != null) {
      _mapCtrl.move(_pinnedLocation!, _pinZoom);
    }
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
      body: Stack(
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
                    : Form(
                        key: _formKey,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                          children: [
                            // ── Section: Basic Information ─────────────────
                            const _SectionHeader(
                              icon: Icons.agriculture_rounded,
                              label: 'Basic Information',
                            ),
                            const SizedBox(height: 10),
                            _FormCard(children: [
                              const _FieldLabel(label: 'Farm Name'),
                              AppTextField(
                                controller: _farmNameCtrl,
                                label: 'e.g. Santos Family Farm',
                                prefixIcon: Icons.home_work_outlined,
                                textCapitalization:
                                    TextCapitalization.words,
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const _FieldLabel(label: 'Land Area (ha)'),
                                        AppTextField(
                                          controller: _landAreaCtrl,
                                          label: '0.00',
                                          keyboardType: const TextInputType
                                              .numberWithOptions(
                                                  decimal: true),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const _FieldLabel(label: 'Years Farming'),
                                        AppTextField(
                                          controller: _yearsFarmingCtrl,
                                          label: '0',
                                          keyboardType:
                                              TextInputType.number,
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
                                onSelected: (v) =>
                                    setState(() => _ownershipType = v),
                              ),
                            ]),
                            const SizedBox(height: 20),

                            // ── Section: Farm Location ─────────────────────
                            const _SectionHeader(
                              icon: Icons.location_on_rounded,
                              label: 'Farm Location',
                            ),
                            const SizedBox(height: 10),
                            _FormCard(children: [
                              const _FieldLabel(label: 'Address / Description'),
                              AppTextField(
                                controller: _farmAddressCtrl,
                                label:
                                    'e.g. Sitio Kailugan, near old barangay hall',
                                prefixIcon: Icons.place_outlined,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                maxLines: 2,
                              ),
                              const SizedBox(height: 16),

                              // Map section
                              const _FieldLabel(label: 'Pin Your Farm on the Map'),
                              const SizedBox(height: 4),
                              Text(
                                'Tap on the map to drop a pin on your exact farm location.',
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
                                        AppConstants.radiusMd),
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
                                        color: AppConstants.primaryGreen,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Pin set',
                                              style: GoogleFonts.poppins(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    AppConstants.primaryGreen,
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
                                                  FontFeature.tabularFigures()
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: _clearPin,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: AppConstants.errorRed
                                                .withValues(alpha: 0.08),
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
                                ),
                              if (_pinnedLocation != null)
                                const SizedBox(height: 10),

                              // Offline warning
                              if (!_isOnline)
                                Container(
                                  margin:
                                      const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppConstants.warningAmber
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(
                                        AppConstants.radiusMd),
                                    border: Border.all(
                                      color: AppConstants.warningAmber
                                          .withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.wifi_off_rounded,
                                          size: 15,
                                          color: AppConstants.warningAmber),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Map tiles need internet to load. '
                                          'Pin position is still saved.',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: AppConstants.warningAmber,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              // Map container
                              GestureDetector(
                                onTap: _mapExpanded
                                    ? null
                                    : () => setState(
                                        () => _mapExpanded = true),
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                  height: _mapExpanded ? 320 : 160,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                        AppConstants.radiusLg),
                                    border: Border.all(
                                      color: AppConstants.primaryGreen
                                          .withValues(alpha: 0.20),
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Stack(
                                    children: [
                                      fm.FlutterMap(
                                        mapController: _mapCtrl,
                                        options: fm.MapOptions(
                                          initialCenter: _pinnedLocation ??
                                              _defaultCenter,
                                          initialZoom: _pinnedLocation !=
                                                  null
                                              ? _pinZoom
                                              : _defaultZoom,
                                          onTap: _mapExpanded
                                              ? _onMapTap
                                              : null,
                                          interactionOptions:
                                              fm.InteractionOptions(
                                            flags: _mapExpanded
                                                ? fm.InteractiveFlag.all
                                                : fm.InteractiveFlag.none,
                                          ),
                                        ),
                                        children: [
                                          fm.TileLayer(
                                            urlTemplate:
                                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                            userAgentPackageName:
                                                'com.sp3coop.sagana',
                                            tileProvider: fm.NetworkTileProvider(),
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

                                      // Collapsed tap-to-expand overlay
                                      if (!_mapExpanded)
                                        Positioned.fill(
                                          child: Container(
                                            color: Colors.black
                                                .withValues(alpha: 0.05),
                                            child: Center(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets
                                                        .symmetric(
                                                  horizontal: 14,
                                                  vertical: 8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(
                                                          alpha: 0.92),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          AppConstants
                                                              .radiusFull),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                              alpha: 0.10),
                                                      blurRadius: 8,
                                                    ),
                                                  ],
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons
                                                          .open_in_full_rounded,
                                                      size: 14,
                                                      color: AppConstants
                                                          .primaryGreen,
                                                    ),
                                                    const SizedBox(
                                                        width: 6),
                                                    Text(
                                                      _pinnedLocation !=
                                                              null
                                                          ? 'Tap to edit pin'
                                                          : 'Tap to open map',
                                                      style:
                                                          GoogleFonts.poppins(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: AppConstants
                                                            .primaryGreen,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),

                                      // Expanded controls
                                      if (_mapExpanded)
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: Column(
                                            children: [
                                              _MapButton(
                                                icon: Icons.close_fullscreen_rounded,
                                                onTap: () => setState(
                                                    () => _mapExpanded =
                                                        false),
                                                tooltip: 'Collapse',
                                              ),
                                              const SizedBox(height: 6),
                                              if (_pinnedLocation != null)
                                                _MapButton(
                                                  icon: Icons
                                                      .my_location_rounded,
                                                  onTap: _centerOnPin,
                                                  tooltip: 'Center on pin',
                                                ),
                                            ],
                                          ),
                                        ),

                                      // Instruction banner (expanded)
                                      if (_mapExpanded)
                                        Positioned(
                                          bottom: 0,
                                          left: 0,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            color: AppConstants.primaryGreen
                                                .withValues(alpha: 0.85),
                                            child: Text(
                                              'Tap anywhere on the map to place your farm pin',
                                              textAlign: TextAlign.center,
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 20),

                            // ── Section: Farm Characteristics ──────────────
                            const _SectionHeader(
                              icon: Icons.grass_rounded,
                              label: 'Farm Characteristics',
                            ),
                            const SizedBox(height: 10),
                            _FormCard(children: [
                              const _FieldLabel(label: 'Soil Type'),
                              _OptionChips(
                                options: _soilOptions,
                                selected: _soilType,
                                onSelected: (v) =>
                                    setState(() => _soilType = v),
                              ),
                              const SizedBox(height: 16),
                              const _FieldLabel(label: 'Water Source'),
                              _OptionChips(
                                options: _waterOptions,
                                selected: _waterSource,
                                onSelected: (v) =>
                                    setState(() => _waterSource = v),
                              ),
                              const SizedBox(height: 16),

                              // Primary crops — read-only from farmer_crops
                              const _FieldLabel(label: 'Primary Crops'),
                              const SizedBox(height: 4),
                              Text(
                                'Managed via the Harvest tab. Add crops there to update this list.',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppConstants.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_profile?.primaryCrops.isEmpty ?? true)
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
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFD5ECF8),
                                            borderRadius:
                                                BorderRadius.circular(
                                                    AppConstants.radiusMd),
                                          ),
                                          child: Text(
                                            crop,
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  AppConstants.primaryGreen,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                            ]),
                            const SizedBox(height: 20),

                            // ── Info banner ────────────────────────────────
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppConstants.primaryGreen
                                    .withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusMd),
                                border: Border.all(
                                  color: AppConstants.primaryGreen
                                      .withValues(alpha: 0.15),
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
                                      'Your farm location pin helps SP3 Admin verify your membership '
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

          // ── Top App Bar ──────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: 'Edit Farm Details',
              onBack: () => context.popRoute(),
              onProfileTap: () {},
              onNotificationTap: () {},
            ),
          ),

          // ── Save Button (floating above bottom) ──────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.of(context).padding.bottom + 12,
              ),
              decoration: BoxDecoration(
                color: AppConstants.offWhite.withValues(alpha: 0.95),
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
          ),
        ],
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
        CustomPaint(
          size: const Size(12, 10),
          painter: _PinTailPainter(),
        ),
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
// Map control button
// ─────────────────────────────────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _MapButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
              ),
            ],
          ),
          child: Icon(icon, size: 18, color: AppConstants.primaryGreen),
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

class _OptionChips extends StatelessWidget {
  final List<_Option> options;
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
        final isSelected = selected == opt.value;
        return GestureDetector(
          onTap: () =>
              onSelected(isSelected ? null : opt.value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppConstants.primaryGreen
                  : Colors.white,
              borderRadius:
                  BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                color: isSelected
                    ? AppConstants.primaryGreen
                    : AppConstants.outline.withValues(alpha: 0.30),
              ),
            ),
            child: Text(
              opt.label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isSelected
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: isSelected
                    ? Colors.white
                    : AppConstants.onSurface,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _Option {
  final String value;
  final String label;
  const _Option(this.value, this.label);
}
