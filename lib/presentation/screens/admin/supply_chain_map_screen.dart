import 'dart:ui' as ui;
import 'package:flutter/material.dart';
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

const _payanasCenterLat = 13.5767;
const _payanasCenterLng = 122.0862;
const _defaultZoom      = 14.5;
const _officeLocation   = LatLng(13.5767, 122.0862);
const _officeAddress    = 'Barangay Hall Compound, Payanas, Torrijos, Marinduque';

class SupplyChainMapScreen extends StatefulWidget {
  const SupplyChainMapScreen({super.key});

  @override
  State<SupplyChainMapScreen> createState() => _SupplyChainMapScreenState();
}

class _SupplyChainMapScreenState extends State<SupplyChainMapScreen> {
  final _repo    = SupplyChainRepository();
  final _mapCtrl = MapController();

  List<SupplyChainFarmerModel> _farmers = [];
  SupplyChainSummary? _summary;
  bool _isLoading = true;
  bool _isOnline  = true;

  SupplyChainFarmerModel? _selectedFarmer;
  bool _showOfficeDetail = false;
  bool _showFlowPanel    = true; // replaces _showSummary

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
      _farmers   = results[0] as List<SupplyChainFarmerModel>;
      _summary   = results[1] as SupplyChainSummary;
      _isLoading = false;
    });
  }

  void _onFarmerTap(SupplyChainFarmerModel farmer) {
    setState(() {
      _selectedFarmer   = farmer;
      _showOfficeDetail = false;
      _showFlowPanel    = false;
    });
  }

  void _onOfficeTap() {
    setState(() {
      _showOfficeDetail = true;
      _selectedFarmer   = null;
      _showFlowPanel    = false;
    });
  }

  void _closeDrawers() {
    setState(() {
      _selectedFarmer   = null;
      _showOfficeDetail = false;
      _showFlowPanel    = true;
    });
  }

  Color _pinColor(SupplyChainFarmerModel farmer) {
    if (farmer.isOverdue) return AppConstants.errorRed;
    final crop = farmer.primaryCrop.toLowerCase();
    if (crop.contains('peanut') || crop.contains('mani')) return AppConstants.amber;
    if (crop.contains('ginger') || crop.contains('luya')) return const Color(0xFFE65100);
    if (crop.contains('palay') || crop.contains('rice')) return AppConstants.successGreen;
    if (crop.contains('banana') || crop.contains('saging')) return const Color(0xFF8BC34A);
    if (crop.contains('copra') || crop.contains('niyog')) return AppConstants.buyerBlue;
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
          // ── Full-screen map ─────────────────────────────────────────────
          Positioned.fill(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: cs.primary))
                : FlutterMap(
                    mapController: _mapCtrl,
                    options: MapOptions(
                      initialCenter: const LatLng(_payanasCenterLat, _payanasCenterLng),
                      initialZoom: _defaultZoom,
                      interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all),
                      onTap: (_, __) => _closeDrawers(),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.sp3coop.sagana',
                      ),
                      MarkerLayer(
                        markers: _farmers.map((farmer) {
                          final color = _pinColor(farmer);
                          return Marker(
                            point: LatLng(farmer.farmLatitude, farmer.farmLongitude),
                            width: 48,
                            height: 56,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              onTap: () => _onFarmerTap(farmer),
                              child: _FarmerPin(
                                color: color,
                                isSelected: _selectedFarmer?.userId == farmer.userId,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _officeLocation,
                            width: 56,
                            height: 64,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              onTap: _onOfficeTap,
                              child: _OfficePin(isSelected: _showOfficeDetail),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),

          // ── Top App Bar ─────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: _TopAppBar(
              title: l10n.supplyChainTitle,
              onBack: () => context.pop(),
              sagana: sagana,
              cs: cs,
            ),
          ),

          // ── Offline indicator ───────────────────────────────────────────
          if (!_isOnline)
            Positioned(
              top: 72, left: 16, right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 16, color: cs.error),
                    const SizedBox(width: 6),
                    Text('Offline — map data may be stale',
                        style: GoogleFonts.inter(fontSize: 12,
                            color: cs.onErrorContainer)),
                  ],
                ),
              ),
            ),

          // ── Pin legend (top-right) ──────────────────────────────────────
          Positioned(
            top: 72, right: 16,
            child: _PinLegend(cs: cs, sagana: sagana),
          ),

          // ── Zoom controls ───────────────────────────────────────────────
          Positioned(
            right: 16, bottom: 240,
            child: _ZoomControls(
              onZoomIn: () => _mapCtrl.move(
                  _mapCtrl.camera.center, _mapCtrl.camera.zoom + 1),
              onZoomOut: () => _mapCtrl.move(
                  _mapCtrl.camera.center, _mapCtrl.camera.zoom - 1),
              onCenter: () => _mapCtrl.move(
                  const LatLng(_payanasCenterLat, _payanasCenterLng),
                  _defaultZoom),
              cs: cs,
              sagana: sagana,
            ),
          ),

          // ── Flow + summary panel (bottom) ───────────────────────────────
          if (_showFlowPanel && _summary != null)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _FlowSummaryPanel(
                summary: _summary!,
                sagana: sagana,
                cs: cs,
              ),
            ),

          // ── Farmer detail drawer ────────────────────────────────────────
          if (_selectedFarmer != null)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _FarmerDetailDrawer(
                farmer: _selectedFarmer!,
                cs: cs,
                sagana: sagana,
                l10n: l10n,
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
              bottom: 0, left: 0, right: 0,
              child: _OfficeDetailDrawer(
                cs: cs,
                sagana: sagana,
                l10n: l10n,
                onClose: _closeDrawers,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Flow + Summary Panel — replaces the old filter-heavy summary drawer
// ─────────────────────────────────────────────────────────────────────────────

class _FlowSummaryPanel extends StatelessWidget {
  final SupplyChainSummary summary;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _FlowSummaryPanel({
    required this.summary,
    required this.sagana,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground.withValues(alpha: 0.97),
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXl)),
        border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.10))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 20,
              offset: const Offset(0, -4)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 48, height: 4,
              decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SP3 Supply Chain Flow',
                style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: cs.onSurface),
              ),
              Text(
                '${summary.mappedMembers}/${summary.totalMembers} mapped',
                style: GoogleFonts.inter(
                    fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Cooperative flow diagram — horizontal step flow
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FlowStep(
                  icon: Icons.agriculture_rounded,
                  label: 'Farm\nProduction',
                  sublabel: '${summary.totalMembers} farmers',
                  color: AppConstants.primaryGreen,
                ),
                _FlowArrow(cs: cs),
                const _FlowStep(
                  icon: Icons.south_rounded,
                  label: 'Harvest\nCollection',
                  sublabel: 'BOD Saturday',
                  color: AppConstants.warningAmber,
                ),
                _FlowArrow(cs: cs),
                const _FlowStep(
                  icon: Icons.warehouse_rounded,
                  label: 'SP3\nInventory',
                  sublabel: 'Cooperative stock',
                  color: AppConstants.buyerBlue,
                ),
                _FlowArrow(cs: cs),
                const _FlowStep(
                  icon: Icons.store_rounded,
                  label: 'Marketplace\n& DA-AMAD',
                  sublabel: 'Direct to buyers',
                  color: AppConstants.primaryContainer,
                ),
                _FlowArrow(cs: cs),
                const _FlowStep(
                  icon: Icons.monetization_on_rounded,
                  label: 'Balik-\nTangkilik',
                  sublabel: 'Annual dividend',
                  color: AppConstants.successGreen,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Divider
          Divider(color: cs.outline.withValues(alpha: 0.10)),
          const SizedBox(height: 10),

          // Crop breakdown row (existing crop stats)
          if (summary.cropStats.isNotEmpty)
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

class _FlowStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;

  const _FlowStep({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.30), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface),
          ),
          Text(
            sublabel,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontSize: 9,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _FlowArrow extends StatelessWidget {
  final ColorScheme cs;
  const _FlowArrow({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Icon(Icons.arrow_forward_rounded,
          size: 16, color: cs.outline.withValues(alpha: 0.50)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pin Legend (top right)
// ─────────────────────────────────────────────────────────────────────────────

class _PinLegend extends StatelessWidget {
  final ColorScheme cs;
  final SaganaColors sagana;

  const _PinLegend({required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Palay', AppConstants.successGreen),
      ('Peanut', AppConstants.amber),
      ('Banana', Color(0xFF8BC34A)),
      ('Ginger', Color(0xFFE65100)),
      ('Copra', AppConstants.buyerBlue),
      ('Overdue', AppConstants.errorRed),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: sagana.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: item.$2,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.$1,
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface),
                  ),
                ],
              ),
            )).toList(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Keep all existing widgets unchanged below this line:
// _TopAppBar, _FarmerPin, _OfficePin, _PinTailPainter, _ZoomControls,
// _MapButton, _CropStatBadge, _FarmerDetailDrawer, _InfoTile,
// _OfficeDetailDrawer, _OfficeInfoRow
// ─────────────────────────────────────────────────────────────────────────────

class _TopAppBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _TopAppBar({
    required this.title, required this.onBack,
    required this.sagana, required this.cs,
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
                child: Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 20, fontWeight: FontWeight.w700,
                        color: cs.primary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: color, shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: isSelected ? 3 : 2),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45),
                  blurRadius: isSelected ? 12 : 6, offset: const Offset(0, 3))],
            ),
            child: const Icon(Icons.person_rounded, color: Colors.white, size: 18),
          ),
          CustomPaint(size: const Size(10, 8),
              painter: _PinTailPainter(color: color)),
        ],
      ),
    );
  }
}

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
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: AppConstants.secondaryContainer,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [BoxShadow(
                  color: AppConstants.secondaryContainer.withValues(alpha: 0.50),
                  blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: const Icon(Icons.agriculture_rounded,
                color: AppConstants.charcoal, size: 22),
          ),
          const CustomPaint(size: Size(10, 8),
              painter: _PinTailPainter(color: AppConstants.secondaryContainer)),
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
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PinTailPainter old) => old.color != color;
}

class _ZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCenter;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _ZoomControls({
    required this.onZoomIn, required this.onZoomOut,
    required this.onCenter, required this.cs, required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MapButton(icon: Icons.add_rounded, onTap: onZoomIn, sagana: sagana, cs: cs),
        const SizedBox(height: 6),
        _MapButton(icon: Icons.remove_rounded, onTap: onZoomOut, sagana: sagana, cs: cs),
        const SizedBox(height: 6),
        _MapButton(icon: Icons.my_location_rounded, onTap: onCenter, sagana: sagana, cs: cs),
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
    required this.icon, required this.onTap,
    required this.sagana, required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.12), blurRadius: 6)],
        ),
        child: Icon(icon, size: 20, color: cs.primary),
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
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          child: Center(
            child: Text(stat.abbreviation,
                style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w800, color: color)),
          ),
        ),
        const SizedBox(height: 4),
        Text('${stat.farmerCount}',
            style: GoogleFonts.inter(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _FarmerDetailDrawer extends StatelessWidget {
  final SupplyChainFarmerModel farmer;
  final ColorScheme cs;
  final SaganaColors sagana;
  final AppLocalizations l10n;
  final VoidCallback onClose;
  final VoidCallback onViewProfile;
  final VoidCallback onSendNotice;

  const _FarmerDetailDrawer({
    required this.farmer, required this.cs, required this.sagana,
    required this.l10n, required this.onClose,
    required this.onViewProfile, required this.onSendNotice,
  });

  Widget _avatarFallback(String name, ColorScheme cs) {
    final initials = name.split(' ').take(2)
        .map((w) => w.isNotEmpty ? w[0] : '').join();
    return Center(
      child: Text(initials.toUpperCase(),
          style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w700, color: cs.primary)),
    );
  }

  String _dateLabel(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final lastHarvest = farmer.lastHarvestDate != null
        ? _dateLabel(farmer.lastHarvestDate!) : 'No records';

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXl)),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24, offset: const Offset(0, -6))],
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(child: Container(
            width: 48, height: 4,
            decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull)),
          )),
          const SizedBox(height: 14),
          Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
              ),
              child: farmer.profilePhotoUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                      child: Image.network(farmer.profilePhotoUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _avatarFallback(farmer.fullName, cs)))
                  : _avatarFallback(farmer.fullName, cs),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(farmer.fullName,
                    style: GoogleFonts.poppins(fontSize: 17,
                        fontWeight: FontWeight.w700, color: cs.primary)),
                Text(
                  '${farmer.memberId != null ? 'ID: ${farmer.memberId}' : 'Pending ID'}'
                  '${farmer.sitio != null ? ' • ${farmer.sitio}' : ''}',
                  style: GoogleFonts.inter(fontSize: 11,
                      color: cs.onSurfaceVariant)),
              ],
            )),
            IconButton(
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant, size: 20),
              style: IconButton.styleFrom(backgroundColor: cs.surfaceContainerHighest),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _InfoTile(
                label: 'Primary Crops',
                value: farmer.primaryCrops.isEmpty
                    ? 'Not recorded'
                    : farmer.primaryCrops.take(3).join(', '),
                cs: cs)),
            const SizedBox(width: 10),
            Expanded(child: _InfoTile(
                label: 'Last Harvest', value: lastHarvest, cs: cs)),
          ]),
          const SizedBox(height: 10),
          farmer.hasOutstandingLoan
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    border: Border.all(color: cs.error.withValues(alpha: 0.20)),
                  ),
                  child: Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LOAN BALANCE', style: GoogleFonts.inter(
                            fontSize: 9, fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: cs.error.withValues(alpha: 0.70))),
                        const SizedBox(height: 2),
                        Text('₱${farmer.outstandingLoanBalance.toStringAsFixed(2)}'
                            '${farmer.isOverdue ? ' (Overdue)' : ''}',
                            style: GoogleFonts.poppins(fontSize: 14,
                                fontWeight: FontWeight.w700, color: cs.error)),
                      ],
                    )),
                    Icon(Icons.warning_amber_rounded, color: cs.error, size: 22),
                  ]),
                )
              : Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppConstants.successGreen.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    border: Border.all(
                        color: AppConstants.successGreen.withValues(alpha: 0.20)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_outline_rounded,
                        color: AppConstants.successGreen, size: 18),
                    const SizedBox(width: 8),
                    Text('No outstanding loans',
                        style: GoogleFonts.inter(fontSize: 13,
                            color: AppConstants.successGreen)),
                  ]),
                ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: ElevatedButton(
              onPressed: onViewProfile,
              child: Text('View Profile',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            )),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(
              onTap: onSendNotice,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.primary),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Text('Send Notice', textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 14,
                        fontWeight: FontWeight.w600, color: cs.primary)),
              ),
            )),
          ]),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  const _InfoTile({required this.label, required this.value, required this.cs});

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
          Text(label.toUpperCase(),
              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.70))),
          const SizedBox(height: 3),
          Text(value, style: GoogleFonts.inter(fontSize: 13,
              fontWeight: FontWeight.w600, color: cs.onSurface)),
        ],
      ),
    );
  }
}

class _OfficeDetailDrawer extends StatelessWidget {
  final ColorScheme cs;
  final SaganaColors sagana;
  final AppLocalizations l10n;
  final VoidCallback onClose;

  const _OfficeDetailDrawer({
    required this.cs, required this.sagana,
    required this.l10n, required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXl)),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24, offset: const Offset(0, -6))],
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(child: Container(
            width: 48, height: 4,
            decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull)),
          )),
          const SizedBox(height: 14),
          Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: AppConstants.secondaryContainer,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: const Icon(Icons.meeting_room_rounded,
                  color: AppConstants.charcoal, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SP3 Cooperative Office',
                    style: GoogleFonts.poppins(fontSize: 16,
                        fontWeight: FontWeight.w700, color: cs.onSurface)),
                Text(_officeAddress,
                    style: GoogleFonts.inter(fontSize: 11,
                        color: cs.onSurfaceVariant)),
              ],
            )),
            IconButton(
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant, size: 20),
              style: IconButton.styleFrom(backgroundColor: cs.surfaceContainerHighest),
            ),
          ]),
          const SizedBox(height: 16),
          _OfficeInfoRow(icon: Icons.calendar_month_rounded,
              text: 'BOD Meeting: Every 1st Saturday of the month', cs: cs),
          const SizedBox(height: 10),
          _OfficeInfoRow(icon: Icons.groups_rounded,
              text: 'Active Members: 52 Registered Farmers', cs: cs),
          const SizedBox(height: 10),
          _OfficeInfoRow(icon: Icons.location_on_outlined,
              text: 'Payanas, Torrijos, Marinduque, Philippines', cs: cs),
          const SizedBox(height: 10),
          _OfficeInfoRow(icon: Icons.inventory_2_rounded,
              text: 'Primary Crops: Palay · Peanut · Ginger · Banana · Copra',
              cs: cs),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onClose,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.secondaryContainer,
              foregroundColor: AppConstants.charcoal,
            ),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: Text('Close', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
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
  const _OfficeInfoRow({required this.icon, required this.text, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: cs.primary, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Text(text,
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface))),
    ]);
  }
}