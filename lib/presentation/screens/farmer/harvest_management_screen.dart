import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/models/harvest_model.dart';
import '../../../data/repositories/harvest_repository.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';

class HarvestManagementScreen extends StatefulWidget {
  final dynamic crop;
  const HarvestManagementScreen({super.key, this.crop});

  @override
  State<HarvestManagementScreen> createState() =>
      _HarvestManagementScreenState();
}

class _HarvestManagementScreenState extends State<HarvestManagementScreen> {
  final _harvestRepo = HarvestRepository();

  late FarmerCropModel _crop;
  List<HarvestModel> _harvests = [];
  bool _isLoading = true;
  bool _cropLoaded = false;
  bool _cropMissing = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_cropLoaded) {
      // Prefer crop passed via widget (GoRouter.extra) but fall back to
      // ModalRoute arguments for compatibility with legacy Navigator usage.
      final arg = widget.crop ?? ModalRoute.of(context)?.settings.arguments;
      if (arg is FarmerCropModel) {
        _crop = arg;
        _cropLoaded = true;
        _loadHarvests();
      } else {
        // mark missing so build can show a friendly error instead of crashing
        _cropMissing = true;
        _cropLoaded = true;
      }
    }
  }

  Future<void> _loadHarvests() async {
    setState(() => _isLoading = true);
    final harvests = await _harvestRepo.fetchHarvestsForCrop(_crop.id);
    if (!mounted) return;
    setState(() {
      _harvests = harvests;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_cropLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(
            color: AppConstants.primaryGreen)),
      );
    }

    if (_cropMissing) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 56, color: AppConstants.errorRed),
                const SizedBox(height: 12),
                Text('Crop not found', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('No crop data was provided when opening this screen. Please return to the crop listing and try again.', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 72),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadHarvests,
                  child: _isLoading
                      ? _LoadingBody()
                      : _harvests.isEmpty
                          ? _EmptyState(
                              cropName: _crop.cropName,
                              onRecord: () => _goToEntryForm(),
                            )
                          : _HarvestList(
                              harvests: _harvests,
                              crop: _crop,
                            ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: FarmerTopBar(
              title: _crop.cropName,
              onBack: () => Navigator.of(context).pop(),
              profilePhotoUrl: null,
              onProfileTap: () {},
                onNotificationTap: () => context.pushRoute(AppRoutes.farmerNotifications),
              onSettingsTap: null,
            ),
          ),
        ],
      ),
      // Removed floating '+' action to avoid duplication with the
      // primary "Record Harvest" action shown in the UI.
    );
  }

  Future<void> _goToEntryForm() async {
    final result = await context.pushRoute(AppRoutes.harvestEntryForm, extra: _crop);
    if (result == true) _loadHarvests();
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Harvest List
// ─────────────────────────────────────────────────────────────────────────────

class _HarvestList extends StatelessWidget {
  final List<HarvestModel> harvests;
  final FarmerCropModel crop;

  const _HarvestList({required this.harvests, required this.crop});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Text(
          '${harvests.length} Harvest ${harvests.length == 1 ? 'Entry' : 'Entries'}'.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 10, color: AppConstants.outline, letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        ...harvests.map((h) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _HarvestCard(harvest: h),
            )),
      ],
    );
  }
}

class _HarvestCard extends StatelessWidget {
  final HarvestModel harvest;
  const _HarvestCard({required this.harvest});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 12, offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'Batch #${harvest.displayBatch}',
                      style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: AppConstants.charcoal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _SyncBadge(isSynced: harvest.isSynced),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _InfoChip(
                    icon: Icons.scale_rounded,
                    label: harvest.displayQty,
                    color: AppConstants.primaryGreen,
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.star_rounded,
                    label: harvest.qualityGrade ?? 'Grade A',
                    color: AppConstants.amber,
                  ),
                  if (harvest.variety != null) ...[
                    const SizedBox(width: 8),
                    _InfoChip(
                      icon: Icons.spa_rounded,
                      label: harvest.variety!,
                      color: AppConstants.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 13, color: AppConstants.outline),
                  const SizedBox(width: 5),
                  Text(
                    DateFormat('MMM d, yyyy').format(harvest.harvestDate),
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppConstants.outline),
                  ),
                  if (harvest.storageLocation != null) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.location_on_outlined,
                        size: 13, color: AppConstants.outline),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        harvest.storageLocation!,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppConstants.outline),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              if (harvest.notes != null && harvest.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  harvest.notes!,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppConstants.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (harvest.submittedToCooperative) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: AppConstants.primaryGreen.withValues(alpha: 0.20)),
                  ),
                  child: Text(
                    'Submitted to Cooperative',
                    style: GoogleFonts.inter(
                      fontSize: 10, fontWeight: FontWeight.w600,
                      color: AppConstants.primaryGreen,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  final bool isSynced;
  const _SyncBadge({required this.isSynced});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isSynced
            ? AppConstants.successGreen.withValues(alpha: 0.10)
            : AppConstants.warningAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSynced ? Icons.cloud_done_rounded : Icons.sync_rounded,
            size: 11,
            color: isSynced
                ? AppConstants.successGreen
                : AppConstants.warningAmber,
          ),
          const SizedBox(width: 3),
          Text(
            isSynced ? 'Synced' : 'Pending',
            style: GoogleFonts.inter(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: isSynced
                  ? AppConstants.successGreen
                  : AppConstants.warningAmber,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String cropName;
  final VoidCallback onRecord;

  const _EmptyState({required this.cropName, required this.onRecord});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: AppConstants.primaryGreen.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.eco_outlined, size: 48,
                  color: AppConstants.primaryGreen.withValues(alpha: 0.50)),
            ),
            const SizedBox(height: 20),
            Text('No harvests yet',
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppConstants.charcoal)),
            const SizedBox(height: 8),
            Text(
              "Tap 'Record Harvest' to record your first harvest for $cropName.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppConstants.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRecord,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                ),
              ),
              child: Text('Record Harvest',
                  style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading Body
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingBody extends StatefulWidget {
  @override
  State<_LoadingBody> createState() => _LoadingBodyState();
}

class _LoadingBodyState extends State<_LoadingBody>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _anim = Tween<double>(begin: -1, end: 2)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _block(double w, double h) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Container(
          width: w, height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              stops: [
                (_anim.value - 1).clamp(0.0, 1.0),
                _anim.value.clamp(0.0, 1.0),
                (_anim.value + 1).clamp(0.0, 1.0),
              ],
              colors: const [
                Color(0xFFE8E8E8), Color(0xFFF5F5F5), Color(0xFFE8E8E8),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: List.generate(4, (_) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [_block(140, 14), _block(60, 18)],
              ),
              const SizedBox(height: 10),
              Row(children: [
                _block(70, 24), const SizedBox(width: 8),
                _block(70, 24),
              ]),
              const SizedBox(height: 10),
              _block(120, 11),
            ],
          ),
        ),
      )),
    );
  }
}
