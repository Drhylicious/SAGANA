import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/supply_chain_model.dart';
import '../../../data/repositories/supply_chain_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

// Barangay Payanas, Torrijos, Marinduque
const _payanasCenterLat = 13.5767;
const _payanasCenterLng = 122.0862;
const _defaultZoom      = 14.5;

// SP3 Cooperative Office (hardcoded — known location)
const _officeLocation = LatLng(13.5767, 122.0862);
const _officeAddress  = 'Barangay Hall Compound, Payanas, Torrijos, Marinduque';

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class SupplyChainMapScreen extends StatefulWidget {
  const SupplyChainMapScreen({super.key});

  @override
  State<SupplyChainMapScreen> createState() => _SupplyChainMapScreenState();
}

class _SupplyChainMapScreenState extends State<SupplyChainMapScreen> {
  final _repo       = SupplyChainRepository();
  final _mapCtrl    = MapController();

  List<SupplyChainFarmerModel> _farmers   = [];
  SupplyChainSummary?          _summary;
  bool _isLoading   = true;
  bool _isOnline    = true;

  MapCropFilter    _cropFilter   = MapCropFilter.all;
  MapStatusFilter? _statusFilter; // null = no status filter

  SupplyChainFarmerModel? _selectedFarmer;
  bool _showOfficeDetail = false;
  bool _showSummary      = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchMappedFarmers(),
      _repo.fetchSummary(),
    ]);
    if (!mounted) return;
    setState(() {
      _farmers  = results[0] as List<SupplyChainFarmerModel>;
      _summary  = results[1] as SupplyChainSummary;
      _isLoading = false;
    });
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  List<SupplyChainFarmerModel> get _visibleFarmers {
    var list = _farmers.where(_cropFilter.matches).toList();
    if (_statusFilter == MapStatusFilter.loans) {
      list = list.where((f) => f.hasOutstandingLoan).toList();
    }
    return list;
  }

  // ── Drawer management ─────────────────────────────────────────────────────

  void _onFarmerTap(SupplyChainFarmerModel farmer) {
    setState(() {
      _selectedFarmer  = farmer;
      _showOfficeDetail = false;
      _showSummary      = false;
    });
  }

  void _onOfficeTap() {
    setState(() {
      _showOfficeDetail = true;
      _selectedFarmer   = null;
      _showSummary      = false;
    });
  }

  void _closeDrawers() {
    setState(() {
      _selectedFarmer   = null;
      _showOfficeDetail = false;
      _showSummary      = true;
    });
  }

  // ── Pin color per crop ────────────────────────────────────────────────────

  Color _pinColor(SupplyChainFarmerModel farmer) {
    if (farmer.isOverdue) return AppConstants.errorRed;
    final crop = farmer.primaryCrop.toLowerCase();
    if (crop.contains('peanut') || crop.contains('mani')) {
      return AppConstants.amber;
    }
    if (crop.contains('ginger') || crop.contains('luya')) {
      return const Color(0xFFE65100);
    }
    if (crop.contains('palay') || crop.contains('rice')) {
      return AppConstants.successGreen;
    }
    if (crop.contains('banana') || crop.contains('saging')) {
      return const Color(0xFF8BC34A);
    }
    if (crop.contains('copra') || crop.contains('niyog')) {
      return AppConstants.buyerBlue;
    }
    return AppConstants.primaryGreen;
  }

  @override
  Widget build(BuildContext context) {
    final l10n   = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs     = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Map (full screen) ───────────────────────────────────────────
          Positioned.fill(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: cs.primary),
                  )
                : FlutterMap(
                    mapController: _mapCtrl,
                    options: MapOptions(
                      initialCenter: const LatLng(_payanasCenterLat, _payanasCenterLng),
                      initialZoom: _defaultZoom,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                      onTap: (_, __) => _closeDrawers(),
                    ),
                    children: [
                      // OSM tile layer
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.sp3coop.sagana',
                      ),

                      // Farmer markers
                      MarkerLayer(
                        markers: _visibleFarmers.map((farmer) {
                          final color = _pinColor(farmer);
                          return Marker(
                            point: LatLng(
                              farmer.farmLatitude,
                              farmer.farmLongitude,
                            ),
                            width: 48,
                            height: 56,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              onTap: () => _onFarmerTap(farmer),
                              child: _FarmerPin(
                                color: color,
                                isSelected: _selectedFarmer?.userId ==
                                    farmer.userId,
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      // Office marker
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _officeLocation,
                            width: 56,
                            height: 64,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              onTap: _onOfficeTap,
                              child: _OfficePin(
                                isSelected: _showOfficeDetail,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),

          // ── Top App Bar ─────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopAppBar(
              title: l10n.supplyChainTitle,
              onBack: () => context.pop(),
              sagana: sagana,
              cs: cs,
            ),
          ),

          // ── Filter chips ────────────────────────────────────────────────
          Positioned(
            top: 80,
            left: 0,
            right: 0,
            child: _FilterRow(
              cropFilter:    _cropFilter,
              statusFilter:  _statusFilter,
              cs: cs,
              onCropChanged: (f) =>
                  setState(() => _cropFilter = f),
              onStatusChanged: (f) =>
                  setState(() => _statusFilter = f),
            ),
          ),

          // ── DA-AMAD Ginger banner ───────────────────────────────────────
          if (_cropFilter == MapCropFilter.ginger)
            Positioned(
              top: 148,
              left: 20,
              right: 20,
              child: _GingerBanner(cs: cs),
            ),

          // ── Offline indicator ───────────────────────────────────────────
          if (!_isOnline)
            Positioned(
              top: 88,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                    border: Border.all(
                        color: cs.error.withValues(alpha: 0.20)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_rounded,
                          size: 16, color: cs.error),
                      const SizedBox(width: 6),
                      Text(
                        'Offline — map data may be stale',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Zoom controls ───────────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: 240,
            child: _ZoomControls(
              onZoomIn:  () => _mapCtrl.move(
                _mapCtrl.camera.center,
                _mapCtrl.camera.zoom + 1,
              ),
              onZoomOut: () => _mapCtrl.move(
                _mapCtrl.camera.center,
                _mapCtrl.camera.zoom - 1,
              ),
              onCenter: () => _mapCtrl.move(
                const LatLng(_payanasCenterLat, _payanasCenterLng),
                _defaultZoom,
              ),
              cs: cs,
              sagana: sagana,
            ),
          ),

          // ── Bottom summary drawer ───────────────────────────────────────
          if (_showSummary && _summary != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _SummaryDrawer(
                summary:  _summary!,
                sagana:   sagana,
                cs:       cs,
                l10n:     l10n,
              ),
            ),

          // ── Farmer detail drawer ────────────────────────────────────────
          if (_selectedFarmer != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _FarmerDetailDrawer(
                farmer: _selectedFarmer!,
                cs:     cs,
                sagana: sagana,
                l10n:   l10n,
                onClose: _closeDrawers,
                onViewProfile: () =>
                    context.push(AppRoutes.farmerDetails,
                        extra: _selectedFarmer!.userId),
                onSendNotice: () {
                  _closeDrawers();
                  context.push(AppRoutes.announcementDashboard);
                },
              ),
            ),

          // ── Office detail drawer ────────────────────────────────────────
          if (_showOfficeDetail)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _OfficeDetailDrawer(
                cs:     cs,
                sagana: sagana,
                l10n:   l10n,
                onClose: _closeDrawers,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top App Bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopAppBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _TopAppBar({
    required this.title,
    required this.onBack,
    required this.sagana,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: onBack,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter Row
// ─────────────────────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  final MapCropFilter cropFilter;
  final MapStatusFilter? statusFilter;
  final ColorScheme cs;
  final ValueChanged<MapCropFilter> onCropChanged;
  final ValueChanged<MapStatusFilter?> onStatusChanged;

  const _FilterRow({
    required this.cropFilter,
    required this.statusFilter,
    required this.cs,
    required this.onCropChanged,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Crop chips
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: MapCropFilter.values.map((f) {
                final active = cropFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => onCropChanged(f),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(
                            sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: active
                                ? cs.primary
                                : Colors.white
                                    .withValues(alpha: 0.80),
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusFull),
                            border: Border.all(
                              color: active
                                  ? cs.primary
                                  : Colors.white
                                      .withValues(alpha: 0.60),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withValues(alpha: 0.08),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Text(
                            f.label,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: active
                                  ? Colors.white
                                  : cs.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),

          // Status filter + legend
          Row(
            children: [
              // Active / Loans toggle
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusFull),
                child: BackdropFilter(
                  filter:
                      ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.80),
                      borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.60),
                      ),
                    ),
                    child: Row(
                      children: [
                        _StatusChip(
                          label: 'Active',
                          isActive: statusFilter == null,
                          onTap: () => onStatusChanged(null),
                          activeColor: cs.primary,
                        ),
                        _StatusChip(
                          label: 'Loans',
                          isActive:
                              statusFilter == MapStatusFilter.loans,
                          onTap: () => onStatusChanged(
                            statusFilter == MapStatusFilter.loans
                                ? null
                                : MapStatusFilter.loans,
                          ),
                          activeColor: AppConstants.errorRed,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final Color activeColor;

  const _StatusChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.transparent,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusFull),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : AppConstants.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DA-AMAD Ginger Banner
// ─────────────────────────────────────────────────────────────────────────────

class _GingerBanner extends StatelessWidget {
  final ColorScheme cs;
  const _GingerBanner({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppConstants.tertiaryContainer.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: AppConstants.onTertiaryContainer.withValues(alpha: 0.30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          const Text('🌿', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DA-AMAD Market Linking',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Ginger cluster farmers eligible for DA-AMAD export program',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Farmer Pin
// ─────────────────────────────────────────────────────────────────────────────

class _FarmerPin extends StatelessWidget {
  final Color color;
  final bool isSelected;

  const _FarmerPin({required this.color, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isSelected ? 1.25 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.elasticOut,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: isSelected ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: isSelected ? 12 : 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          CustomPaint(
            size: const Size(10, 8),
            painter: _PinTailPainter(color: color),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Office Pin
// ─────────────────────────────────────────────────────────────────────────────

class _OfficePin extends StatelessWidget {
  final bool isSelected;
  const _OfficePin({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isSelected ? 1.2 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppConstants.secondaryContainer,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: AppConstants.secondaryContainer
                      .withValues(alpha: 0.50),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.agriculture_rounded,
              color: AppConstants.charcoal,
              size: 22,
            ),
          ),
          CustomPaint(
            size: const Size(10, 8),
            painter: _PinTailPainter(
                color: AppConstants.secondaryContainer),
          ),
        ],
      ),
    );
  }
}

class _PinTailPainter extends CustomPainter {
  final Color color;
  const _PinTailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PinTailPainter old) =>
      old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Zoom Controls
// ─────────────────────────────────────────────────────────────────────────────

class _ZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCenter;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onCenter,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MapButton(icon: Icons.add_rounded, onTap: onZoomIn,
            sagana: sagana, cs: cs),
        const SizedBox(height: 6),
        _MapButton(icon: Icons.remove_rounded, onTap: onZoomOut,
            sagana: sagana, cs: cs),
        const SizedBox(height: 6),
        _MapButton(icon: Icons.my_location_rounded, onTap: onCenter,
            sagana: sagana, cs: cs),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _MapButton({
    required this.icon,
    required this.onTap,
    required this.sagana,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: cs.primary),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary Drawer
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryDrawer extends StatelessWidget {
  final SupplyChainSummary summary;
  final SaganaColors sagana;
  final ColorScheme cs;
  final AppLocalizations l10n;

  const _SummaryDrawer({
    required this.summary,
    required this.sagana,
    required this.cs,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
        border: Border(
          top: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.25),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Title + mapped count
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Barangay Payanas',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                      children: [
                        const TextSpan(text: 'Mapped: '),
                        TextSpan(
                          text:
                              '${summary.mappedMembers} of ${summary.totalMembers} Members',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (summary.unmappedMembers > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppConstants.warningAmber
                        .withValues(alpha: 0.15),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                    border: Border.all(
                      color: AppConstants.warningAmber
                          .withValues(alpha: 0.30),
                    ),
                  ),
                  child: Text(
                    '${summary.unmappedMembers} not mapped',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.warningAmber,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Crop stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: summary.cropStats
                .map((stat) => _CropStatBadge(stat: stat, cs: cs))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _CropStatBadge extends StatelessWidget {
  final CropMapStat stat;
  final ColorScheme cs;

  const _CropStatBadge({required this.stat, required this.cs});

  Color _color(String crop) {
    switch (crop.toLowerCase()) {
      case 'peanut': return AppConstants.amber;
      case 'ginger': return const Color(0xFFE65100);
      case 'palay':  return AppConstants.successGreen;
      case 'banana': return const Color(0xFF8BC34A);
      case 'copra':  return AppConstants.buyerBlue;
      default:       return AppConstants.primaryGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(stat.cropName);
    return Column(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius:
                BorderRadius.circular(AppConstants.radiusMd),
          ),
          child: Center(
            child: Text(
              stat.abbreviation,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${stat.farmerCount}',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Farmer Detail Drawer
// ─────────────────────────────────────────────────────────────────────────────

class _FarmerDetailDrawer extends StatelessWidget {
  final SupplyChainFarmerModel farmer;
  final ColorScheme cs;
  final SaganaColors sagana;
  final AppLocalizations l10n;
  final VoidCallback onClose;
  final VoidCallback onViewProfile;
  final VoidCallback onSendNotice;

  const _FarmerDetailDrawer({
    required this.farmer,
    required this.cs,
    required this.sagana,
    required this.l10n,
    required this.onClose,
    required this.onViewProfile,
    required this.onSendNotice,
  });

  @override
  Widget build(BuildContext context) {
    final lastHarvest = farmer.lastHarvestDate != null
        ? _dateLabel(farmer.lastHarvestDate!)
        : 'No records';

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.25),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              // Avatar
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(
                      color: cs.outline.withValues(alpha: 0.10)),
                ),
                child: farmer.profilePhotoUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd),
                        child: Image.network(
                          farmer.profilePhotoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _avatarFallback(farmer.fullName, cs),
                        ),
                      )
                    : _avatarFallback(farmer.fullName, cs),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      farmer.fullName,
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                    Text(
                      '${farmer.memberId != null ? 'ID: ${farmer.memberId}' : 'Pending ID'}'
                      '${farmer.sitio != null ? ' • ${farmer.sitio}' : ''}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: Icon(Icons.close_rounded,
                    color: cs.onSurfaceVariant, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Info grid
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  label: 'Primary Crops',
                  value: farmer.primaryCrops.isEmpty
                      ? 'Not recorded'
                      : farmer.primaryCrops.take(3).join(', '),
                  cs: cs,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InfoTile(
                  label: 'Last Harvest',
                  value: lastHarvest,
                  cs: cs,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Loan status tile
          if (farmer.hasOutstandingLoan)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.25),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(
                    color: cs.error.withValues(alpha: 0.20)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LOAN BALANCE',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: cs.error.withValues(alpha: 0.70),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: cs.error,
                            ),
                            children: [
                              TextSpan(
                                text:
                                    '₱${farmer.outstandingLoanBalance.toStringAsFixed(2)}',
                              ),
                              if (farmer.isOverdue)
                                TextSpan(
                                  text: ' (Overdue)',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.warning_amber_rounded,
                      color: cs.error, size: 22),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppConstants.successGreen.withValues(alpha: 0.10),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(
                    color: AppConstants.successGreen
                        .withValues(alpha: 0.20)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded,
                      color: AppConstants.successGreen, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'No outstanding loans',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppConstants.successGreen,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onViewProfile,
                  child: Text(
                    'View Profile',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: onSendNotice,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.primary),
                      borderRadius: BorderRadius.circular(
                          AppConstants.radiusMd),
                    ),
                    child: Text(
                      'Send Notice',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String name, ColorScheme cs) {
    final initials = name.split(' ').take(2).map((w) => w.isNotEmpty ? w[0] : '').join();
    return Center(
      child: Text(
        initials.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
      ),
    );
  }

  String _dateLabel(DateTime dt) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;

  const _InfoTile({
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: cs.onSurfaceVariant.withValues(alpha: 0.70),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Office Detail Drawer
// ─────────────────────────────────────────────────────────────────────────────

class _OfficeDetailDrawer extends StatelessWidget {
  final ColorScheme cs;
  final SaganaColors sagana;
  final AppLocalizations l10n;
  final VoidCallback onClose;

  const _OfficeDetailDrawer({
    required this.cs,
    required this.sagana,
    required this.l10n,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.25),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppConstants.secondaryContainer,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: const Icon(
                  Icons.meeting_room_rounded,
                  color: AppConstants.charcoal,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SP3 Cooperative Office',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      _officeAddress,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: Icon(Icons.close_rounded,
                    color: cs.onSurfaceVariant, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Office info
          _OfficeInfoRow(
            icon: Icons.calendar_month_rounded,
            text: 'General Assembly: Every 1st Saturday',
            cs: cs,
          ),
          const SizedBox(height: 10),
          _OfficeInfoRow(
            icon: Icons.groups_rounded,
            text: 'Active Members: 52 Registered Farmers',
            cs: cs,
          ),
          const SizedBox(height: 10),
          _OfficeInfoRow(
            icon: Icons.location_on_outlined,
            text: 'Torrijos, Marinduque, Philippines',
            cs: cs,
          ),
          const SizedBox(height: 16),

          ElevatedButton.icon(
            onPressed: onClose,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.secondaryContainer,
              foregroundColor: AppConstants.charcoal,
            ),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: Text(
              'Center on Map',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficeInfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final ColorScheme cs;

  const _OfficeInfoRow({
    required this.icon,
    required this.text,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: cs.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: cs.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
