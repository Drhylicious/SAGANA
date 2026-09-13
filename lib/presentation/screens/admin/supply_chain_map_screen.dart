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
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/material_list_tile.dart';

const _payanasCenterLat = 13.5767;
const _payanasCenterLng = 122.0862;
const _defaultZoom      = 14.5;
const _officeLocation   = LatLng(13.5767, 122.0862);
const _officeAddress    = 'Barangay Hall Compound, Payanas, Torrijos, Marinduque';

// Deterministic palette — crops are assigned colors by sorted name order,
// so the same crop always gets the same color across a session, and new
// crops introduced later just extend the assignment predictably instead
// of needing a hardcoded name-to-color mapping.
const _cropPalette = [
  AppConstants.successGreen,
  AppConstants.amber,
  Color(0xFF8BC34A),
  Color(0xFFE65100),
  AppConstants.buyerBlue,
  AppConstants.programPurple,
  Color(0xFF00838F),
  Color(0xFFAD1457),
];

Map<String, Color> _buildCropColorMap(List<SupplyChainFarmerModel> farmers) {
  final names = farmers
      .map((f) => f.primaryCrop.trim())
      .where((c) => c.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return {
    for (int i = 0; i < names.length; i++) names[i]: _cropPalette[i % _cropPalette.length],
  };
}

class SupplyChainMapScreen extends StatefulWidget {
  const SupplyChainMapScreen({super.key});

  @override
  State<SupplyChainMapScreen> createState() => _SupplyChainMapScreenState();
}

class _SupplyChainMapScreenState extends State<SupplyChainMapScreen> {
  final _repo    = SupplyChainRepository();
  final _mapCtrl = MapController();

  List<SupplyChainFarmerModel> _farmers = [];
  Map<String, Color> _cropColors = {};
  SupplyChainSummary? _summary;
  SupplyChainCoverage? _coverage;
  bool _isLoading = true;
  bool _isOnline  = true;

  SupplyChainFarmerModel? _selectedFarmer;
  bool _showOfficeDetail = false;

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
      _repo.fetchCoverage(),
    ]);
    if (!mounted) return;
    setState(() {
      _farmers      = results[0] as List<SupplyChainFarmerModel>;
      _cropColors   = _buildCropColorMap(_farmers);
      _summary      = results[1] as SupplyChainSummary;
      _coverage     = results[2] as SupplyChainCoverage;
      _isLoading    = false;
    });
  }

  void _onFarmerTap(SupplyChainFarmerModel farmer) {
    setState(() {
      _selectedFarmer   = farmer;
      _showOfficeDetail = false;
    });
  }

  void _onOfficeTap() {
    setState(() {
      _showOfficeDetail = true;
      _selectedFarmer   = null;
    });
  }

  void _closeDrawers() {
    setState(() {
      _selectedFarmer   = null;
      _showOfficeDetail = false;
    });
  }

  Color _pinColor(SupplyChainFarmerModel farmer, Map<String, Color> cropColors) {
    final crop = farmer.primaryCrop.trim();
    if (crop.isEmpty) return AppConstants.outline;
    return cropColors[crop] ?? AppConstants.primaryGreen;
  }

  void _showUnmappedList() async {
    final members = await _repo.fetchUnmappedMembers();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    showManagementModal(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return ManagementModalShell(
          title: 'Members Without Farm Location',
          subtitle: '${members.length} member${members.length == 1 ? '' : 's'}',
          bodyIsScrollable: true,
          body: members.isEmpty
              ? Center(child: Text(l10n.supplyChainAllMapped,
                  style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  itemCount: members.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: cs.outline.withValues(alpha: 0.08)),
                  itemBuilder: (_, i) {
                    final m = members[i];
                    return MaterialListTile(
                      tileColor: Colors.transparent,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppConstants.primaryContainer,
                        child: Text(
                          m.fullName.isNotEmpty ? m.fullName[0].toUpperCase() : '?',
                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                      title: Text(m.fullName,
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface)),
                      subtitle: m.purok != null
                          ? Text(m.purok!, style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant))
                          : null,
                      trailing: GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          context.pushRoute(AppRoutes.farmerDetails, extra: m.userId);
                        },
                        child: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n      = AppLocalizations.of(context);
    final sagana    = context.saganaColors;
    final cs        = Theme.of(context).colorScheme;
    final mapHeight = MediaQuery.of(context).size.height * 0.42;
    final coverage  = _coverage ?? SupplyChainCoverage.empty;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                        onPressed: () => context.pop(),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          l10n.supplyChainTitle,
                          style: GoogleFonts.poppins(
                              fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: AppConstants.primaryGreen,
                    onRefresh: _loadAll,
                    child: _isLoading && _summary == null
                        ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen))
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                            children: [
                              if (!_isOnline)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
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
                                  Text('Offline — data may be stale',
                                      style: GoogleFonts.inter(fontSize: 12, color: cs.onErrorContainer)),
                                ],
                              ),
                            ),
                          ),

                        // Coverage: the one supply-chain-scoped figure that
                        // belonged in the old Operations Summary/Actionable
                        // Insights sections — everything else there (loan
                        // status, marketplace approvals, inventory stock,
                        // harvest submission status) was account/module
                        // status unrelated to supply chain visibility, and
                        // has been removed rather than reworked.
                        _CoverageBanner(
                          coverage: coverage,
                          cs: cs,
                          sagana: sagana,
                          onViewUnmapped: _showUnmappedList,
                        ),
                        const SizedBox(height: 24),

                        _SectionLabel(text: l10n.supplyChainFlow, cs: cs),
                        const SizedBox(height: 10),
                        _CooperativeFlowRow(cs: cs, sagana: sagana),
                        const SizedBox(height: 24),

                        _PlannedOperationsCard(l10n: l10n, cs: cs, sagana: sagana),
                        const SizedBox(height: 24),

                        Row(
                          children: [
                            Expanded(child: _SectionLabel(text: l10n.supplyChainMapSection, cs: cs)),
                            GestureDetector(
                              onTap: () => context.pushRoute(AppRoutes.supplyChainFullMap),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('View Full Map',
                                      style: GoogleFonts.inter(
                                          fontSize: 11.5, fontWeight: FontWeight.w600, color: cs.primary)),
                                  const SizedBox(width: 2),
                                  Icon(Icons.open_in_full_rounded, size: 14, color: cs.primary),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: mapHeight,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: sagana.cardBackground,
                            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                            border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: _isLoading
                                    ? Center(child: CircularProgressIndicator(color: cs.primary))
                                    : FlutterMap(
                                        mapController: _mapCtrl,
                                        options: MapOptions(
                                          initialCenter: const LatLng(_payanasCenterLat, _payanasCenterLng),
                                          initialZoom: _defaultZoom,
                                          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                                          onTap: (_, __) => _closeDrawers(),
                                        ),
                                        children: [
                                          TileLayer(
                                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                            userAgentPackageName: 'com.sp3coop.sagana',
                                          ),
                                          MarkerLayer(
                                            markers: _farmers.map((farmer) {
                                              final color = _pinColor(farmer, _cropColors);
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
                              Positioned(top: 10, right: 10, child: _MapLayersPanel(cropColors: _cropColors, cs: cs, sagana: sagana)),
                              Positioned(
                                right: 10,
                                bottom: 10,
                                child: _ZoomControls(
                                  onZoomIn: () => _mapCtrl.move(_mapCtrl.camera.center, _mapCtrl.camera.zoom + 1),
                                  onZoomOut: () => _mapCtrl.move(_mapCtrl.camera.center, _mapCtrl.camera.zoom - 1),
                                  onCenter: () => _mapCtrl.move(
                                      const LatLng(_payanasCenterLat, _payanasCenterLng), _defaultZoom),
                                  cs: cs,
                                  sagana: sagana,
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
          ),

          // Drawers stay screen-anchored, not confined to the map card
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
                    context.pushRoute(AppRoutes.farmerDetails, extra: _selectedFarmer!.userId),
                onSendNotice: () {
                  _closeDrawers();
                  context.pushRoute(AppRoutes.announcementDashboard);
                },
              ),
            ),
          if (_showOfficeDetail)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _OfficeDetailDrawer(cs: cs, sagana: sagana, l10n: l10n, onClose: _closeDrawers),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen map (drill-down from the dashboard card's "View Full Map")
// ─────────────────────────────────────────────────────────────────────────────

class SupplyChainFullMapScreen extends StatefulWidget {
  const SupplyChainFullMapScreen({super.key});

  @override
  State<SupplyChainFullMapScreen> createState() => _SupplyChainFullMapScreenState();
}

class _SupplyChainFullMapScreenState extends State<SupplyChainFullMapScreen> {
  final _repo    = SupplyChainRepository();
  final _mapCtrl = MapController();

  List<SupplyChainFarmerModel> _farmers = [];
  Map<String, Color> _cropColors = {};
  bool _isLoading = true;

  SupplyChainFarmerModel? _selectedFarmer;
  bool _showOfficeDetail = false;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final farmers = await _repo.fetchMappedFarmers();
    if (!mounted) return;
    setState(() {
      _farmers    = farmers;
      _cropColors = _buildCropColorMap(farmers);
      _isLoading  = false;
    });
  }

  void _onFarmerTap(SupplyChainFarmerModel farmer) {
    setState(() {
      _selectedFarmer   = farmer;
      _showOfficeDetail = false;
    });
  }

  void _onOfficeTap() {
    setState(() {
      _showOfficeDetail = true;
      _selectedFarmer   = null;
    });
  }

  void _closeDrawers() {
    setState(() {
      _selectedFarmer   = null;
      _showOfficeDetail = false;
    });
  }

  Color _pinColor(SupplyChainFarmerModel farmer, Map<String, Color> cropColors) {
    final crop = farmer.primaryCrop.trim();
    if (crop.isEmpty) return AppConstants.outline;
    return cropColors[crop] ?? AppConstants.primaryGreen;
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
          Positioned.fill(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: cs.primary))
                : FlutterMap(
                    mapController: _mapCtrl,
                    options: MapOptions(
                      initialCenter: const LatLng(_payanasCenterLat, _payanasCenterLng),
                      initialZoom: _defaultZoom,
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                      onTap: (_, __) => _closeDrawers(),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.sp3coop.sagana',
                      ),
                      MarkerLayer(
                        markers: _farmers.map((farmer) {
                          final color = _pinColor(farmer, _cropColors);
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
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: sagana.glassBackground,
                        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                        border: Border.all(color: sagana.glassBorder),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => context.pop(),
                            child: const Icon(Icons.arrow_back_rounded, color: AppConstants.primaryGreen),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              l10n.supplyChainMapSection,
                              style: GoogleFonts.poppins(
                                  fontSize: 18, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen),
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
          Positioned(top: 78, right: 12, child: _MapLayersPanel(cropColors: _cropColors, cs: cs, sagana: sagana)),
          Positioned(
            right: 12,
            bottom: _selectedFarmer != null || _showOfficeDetail ? 260 : 24,
            child: _ZoomControls(
              onZoomIn: () => _mapCtrl.move(_mapCtrl.camera.center, _mapCtrl.camera.zoom + 1),
              onZoomOut: () => _mapCtrl.move(_mapCtrl.camera.center, _mapCtrl.camera.zoom - 1),
              onCenter: () => _mapCtrl.move(const LatLng(_payanasCenterLat, _payanasCenterLng), _defaultZoom),
              cs: cs,
              sagana: sagana,
            ),
          ),
          if (_selectedFarmer != null)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _FarmerDetailDrawer(
                farmer: _selectedFarmer!,
                cs: cs, sagana: sagana, l10n: l10n,
                onClose: _closeDrawers,
                onViewProfile: () =>
                    context.pushRoute(AppRoutes.farmerDetails, extra: _selectedFarmer!.userId),
                onSendNotice: () {
                  _closeDrawers();
                  context.pushRoute(AppRoutes.announcementDashboard);
                },
              ),
            ),
          if (_showOfficeDetail)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _OfficeDetailDrawer(cs: cs, sagana: sagana, l10n: l10n, onClose: _closeDrawers),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  const _SectionLabel({required this.text, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface),
    );
  }
}

// ─── Coverage banner — mapped vs. unmapped members ─────────────────────────
// Replaces the old Operations Summary grid + Actionable Insights list, which
// mixed farm-location coverage in with loan status, marketplace approvals,
// low-stock inventory, and harvest submission status — none of which are
// supply chain concerns. Coverage (can this member even be shown on the
// map) is the one figure that belonged here, so it's now a single compact
// banner instead of two sections built to hold unrelated alerts.

class _CoverageBanner extends StatelessWidget {
  final SupplyChainCoverage coverage;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onViewUnmapped;

  const _CoverageBanner({
    required this.coverage,
    required this.cs,
    required this.sagana,
    required this.onViewUnmapped,
  });

  @override
  Widget build(BuildContext context) {
    final unmapped = coverage.unmappedMembers;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppConstants.primaryGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.place_rounded, size: 18, color: AppConstants.primaryGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${coverage.mappedMembers} of ${coverage.totalMembers} members mapped',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
                Text(
                  unmapped > 0
                      ? '$unmapped without a farm location on file'
                      : 'Every active member has a farm location on file',
                  style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (unmapped > 0)
            GestureDetector(
              onTap: onViewUnmapped,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('View List',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary)),
                  Icon(Icons.chevron_right_rounded, size: 16, color: cs.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Cooperative Flow — real navigation + one planned stage ──────────────────

class _CooperativeFlowRow extends StatelessWidget {
  final ColorScheme cs;
  final SaganaColors sagana;
  const _CooperativeFlowRow({required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    final steps = [
      _FlowStepData('Farm', Icons.agriculture_rounded, AppConstants.primaryGreen,
          () => context.goTab(AppRoutes.farmerManagement)),
      _FlowStepData('Inventory', Icons.inventory_2_rounded, AppConstants.buyerBlue,
          () => context.pushRoute(AppRoutes.adminInventory)),
      _FlowStepData('Marketplace', Icons.storefront_rounded, AppConstants.amber,
          () => context.goTab(AppRoutes.adminMarketplace)),
      _FlowStepData('Orders', Icons.receipt_long_rounded, AppConstants.programPurple,
          () => context.pushRoute(AppRoutes.adminOrders)),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (final step in steps) ...[
              _FlowStepChip(data: step, cs: cs),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
              ),
            ],
            _PlannedFlowStepChip(label: 'Logistics', cs: cs),
          ],
        ),
      ),
    );
  }
}

class _FlowStepData {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _FlowStepData(this.label, this.icon, this.color, this.onTap);
}

class _FlowStepChip extends StatelessWidget {
  final _FlowStepData data;
  final ColorScheme cs;
  const _FlowStepChip({required this.data, required this.cs});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: data.onTap,
      child: Column(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: data.color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(data.icon, color: data.color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(data.label,
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ],
      ),
    );
  }
}

class _PlannedFlowStepChip extends StatelessWidget {
  final String label;
  final ColorScheme cs;
  const _PlannedFlowStepChip({required this.label, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: cs.outline.withValues(alpha: 0.35), width: 1.5),
          ),
          child: Icon(Icons.local_shipping_outlined, color: cs.outline, size: 20),
        ),
        const SizedBox(height: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
        Text('Planned',
            style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w600, color: cs.outline)),
      ],
    );
  }
}

// ─── Planned Operations note ──────────────────────────────────────────────────

class _PlannedOperationsCard extends StatelessWidget {
  final AppLocalizations l10n;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _PlannedOperationsCard({required this.l10n, required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10), style: BorderStyle.solid),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_rounded, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.supplyChainPlannedOps,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
                const SizedBox(height: 4),
                Text(l10n.supplyChainPlannedOpsDesc,
                    style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Map Layers Panel (top right) — replaces the old flat Pin Legend.
// Crop Types are built dynamically from whatever's on the map today; loan
// status has been fully decoupled from pin color (see _pinColor) and no
// longer appears here — overdue farmers are still surfaced via Actionable
// Insights → Loan Dashboard. Operational Status is a placeholder section
// for when collection/logistics tracking lands.
// ─────────────────────────────────────────────────────────────────────────────

class _MapLayersPanel extends StatefulWidget {
  final Map<String, Color> cropColors;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _MapLayersPanel({required this.cropColors, required this.cs, required this.sagana});

  @override
  State<_MapLayersPanel> createState() => _MapLayersPanelState();
}

class _MapLayersPanelState extends State<_MapLayersPanel> {
  bool _panelOpen = false;
  bool _cropOpen = true;
  bool _statusOpen = false;

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final sagana = widget.sagana;

    if (!_panelOpen) {
      return GestureDetector(
        onTap: () => setState(() => _panelOpen = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: sagana.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.layers_rounded, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('Layers',
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    final crops = widget.cropColors.entries.toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 195,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: sagana.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.layers_rounded, size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('MAP LAYERS',
                        style: GoogleFonts.inter(
                            fontSize: 9, fontWeight: FontWeight.w700,
                            letterSpacing: 0.5, color: cs.onSurfaceVariant)),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _panelOpen = false),
                    child: Icon(Icons.close_rounded, size: 14, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              _LayerSection(
                title: 'Crop Types',
                isOpen: _cropOpen,
                onToggle: () => setState(() => _cropOpen = !_cropOpen),
                cs: cs,
                child: crops.isEmpty
                    ? Text('No crops recorded yet',
                        style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: crops.map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10, height: 10,
                                    decoration: BoxDecoration(color: e.value, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(e.key,
                                      style: GoogleFonts.inter(
                                          fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurface)),
                                ],
                              ),
                            )).toList(),
                      ),
              ),

              const SizedBox(height: 6),
              Divider(height: 1, color: cs.outline.withValues(alpha: 0.15)),
              const SizedBox(height: 6),

              _LayerSection(
                title: 'Operational Status',
                isOpen: _statusOpen,
                onToggle: () => setState(() => _statusOpen = !_statusOpen),
                cs: cs,
                trailingBadge: 'Planned',
                child: Text(
                  'Will activate once collection and logistics tracking is available.',
                  style: GoogleFonts.inter(fontSize: 9.5, color: cs.onSurfaceVariant, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LayerSection extends StatelessWidget {
  final String title;
  final bool isOpen;
  final VoidCallback onToggle;
  final Widget child;
  final ColorScheme cs;
  final String? trailingBadge;

  const _LayerSection({
    required this.title, required this.isOpen, required this.onToggle,
    required this.child, required this.cs, this.trailingBadge,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onToggle,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Icon(isOpen ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                  size: 16, color: cs.onSurfaceVariant),
              Expanded(
                child: Text(title,
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface)),
              ),
              if (trailingBadge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(trailingBadge!,
                      style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                ),
            ],
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Padding(
            padding: const EdgeInsets.only(left: 20, top: 3, bottom: 2),
            child: child,
          ),
          crossFadeState: isOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
          sizeCurve: Curves.easeOut,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Keep all existing widgets unchanged below this line:
// _FarmerPin, _OfficePin, _PinTailPainter, _ZoomControls,
// _MapButton, _FarmerDetailDrawer, _InfoTile,
// _OfficeDetailDrawer, _OfficeInfoRow
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
                  '${farmer.purok != null ? ' • ${farmer.purok}' : ''}',
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
          // Strictly farm location + currently planted crops — this drawer
          // deliberately carries nothing else (see SupplyChainFarmerModel's
          // header comment for why loan/harvest status were removed).
          Row(children: [
            Expanded(child: _InfoTile(
                label: 'Currently Planted',
                value: farmer.primaryCrops.isEmpty
                    ? 'Not recorded'
                    : farmer.primaryCrops.take(3).join(', '),
                cs: cs)),
            const SizedBox(width: 10),
            Expanded(child: _InfoTile(
                label: 'Farm Coordinates',
                value: '${farmer.farmLatitude.toStringAsFixed(5)}, '
                    '${farmer.farmLongitude.toStringAsFixed(5)}',
                cs: cs)),
          ]),
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