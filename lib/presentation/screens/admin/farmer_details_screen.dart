import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/models/loan_model.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/models/analytics_model.dart';
import '../../../data/repositories/farmer_details_repository.dart';
import '../../../routes/app_routes.dart';

class FarmerDetailsScreen extends StatefulWidget {
  final String farmerId;
  const FarmerDetailsScreen({super.key, required this.farmerId});

  @override
  State<FarmerDetailsScreen> createState() => _FarmerDetailsScreenState();
}

class _FarmerDetailsScreenState extends State<FarmerDetailsScreen> {
  final _repo = FarmerDetailsRepository();

  FarmerProfileModel?       _profile;
  FarmPerformanceSummary    _harvestSummary = FarmPerformanceSummary.empty;
  Map<String, dynamic>      _harvestStats   = {};
  List<LoanModel>           _loans          = [];
  MemberContribution?       _contribution;
  CapitalSharesModel?       _capitalShares;
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _programs = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchFarmerProfile(widget.farmerId),
      _repo.fetchHarvestSummary(widget.farmerId),
      _repo.fetchHarvestStats(widget.farmerId),
      _repo.fetchFarmerLoans(widget.farmerId),
      _repo.fetchCurrentYearContribution(widget.farmerId),
      _repo.fetchCapitalShares(widget.farmerId),
      _repo.fetchFarmerExpenses(widget.farmerId),
      _repo.fetchAssignedPrograms(widget.farmerId),
    ]);
    if (!mounted) return;
    setState(() {
      _profile        = results[0] as FarmerProfileModel?;
      _harvestSummary = results[1] as FarmPerformanceSummary;
      _harvestStats   = results[2] as Map<String, dynamic>;
      _loans          = results[3] as List<LoanModel>;
      _contribution   = results[4] as MemberContribution?;
      _capitalShares  = results[5] as CapitalSharesModel?;
      _expenses       = results[6] as List<Map<String, dynamic>>;
      _programs       = results[7] as List<Map<String, dynamic>>;
      _isLoading      = false;
    });
  }

  double get _totalOutstanding => _loans
      .where((l) => !l.isPaid)
      .fold(0.0, (sum, l) => sum + l.remainingBalance);

  void _showActionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActionsMenu(
        isActive: true, // wire to real status if needed
        onNotify: () {
          Navigator.pop(context);
          context.push(AppRoutes.announcementDashboard);
        },
        onToggleStatus: () async {
          Navigator.pop(context);
          await _repo.setFarmerStatus(
              farmerId: widget.farmerId, status: 'inactive');
          _loadAll();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs     = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(
          child: CircularProgressIndicator(color: AppConstants.primaryGreen),
        ),
      );
    }

    if (_profile == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 40, color: cs.outline),
              const SizedBox(height: 12),
              Text('Farmer not found',
                  style: GoogleFonts.poppins(
                      fontSize: 15, color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    final profile = _profile!;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: RefreshIndicator(
                  color: cs.primary,
                  onRefresh: _loadAll,
                  child: DefaultTabController(
                    length: 6,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: TabBar(
                            isScrollable: true,
                            labelColor: cs.primary,
                            unselectedLabelColor: cs.onSurfaceVariant,
                            indicatorColor: cs.primary,
                            tabs: const [
                              Tab(text: 'Profile'),
                              Tab(text: 'Harvest'),
                              Tab(text: 'Loans'),
                              Tab(text: 'Contribution'),
                              Tab(text: 'Expenses'),
                              Tab(text: 'Programs'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              ListView(
                                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                                children: [
                                  _IdentityCard(profile: profile, cs: cs, sagana: sagana),
                                  const SizedBox(height: 16),
                                  _FarmDetailsCard(profile: profile, cs: cs, sagana: sagana),
                                ],
                              ),
                              ListView(
                                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                                children: [
                                  _HarvestActivityCard(
                                    summary: _harvestSummary,
                                    stats: _harvestStats,
                                    cs: cs,
                                    sagana: sagana,
                                    onViewAll: () => context.push(
                                      AppRoutes.farmerHarvestHistory,
                                      extra: widget.farmerId,
                                    ),
                                  ),
                                ],
                              ),
                              ListView(
                                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                                children: [
                                  _LoanSummaryCard(
                                    loans: _loans,
                                    totalOutstanding: _totalOutstanding,
                                    cs: cs,
                                    sagana: sagana,
                                  ),
                                ],
                              ),
                              ListView(
                                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                                children: [
                                  _ContributionCard(
                                    contribution: _contribution,
                                    capitalShares: _capitalShares,
                                    cs: cs,
                                    sagana: sagana,
                                    onViewFull: () => context.push(
                                      AppRoutes.memberContributionReport,
                                    ),
                                  ),
                                ],
                              ),
                              _ExpensesTab(expenses: _expenses, cs: cs, sagana: sagana),
                              _ProgramsTab(programs: _programs, cs: cs, sagana: sagana),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── Top App Bar ─────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopAppBar(
              title: profile.fullName,
              onBack: () => context.pop(),
              onMenu: _showActionsMenu,
              sagana: sagana,
              cs: cs,
            ),
          ),

          // ── Bottom action bar ───────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomActionBar(
              cs: cs,
              sagana: sagana,
              onNotify: () =>
                  context.push(AppRoutes.announcementDashboard),
              onPay: () => context.push(
                AppRoutes.recordPayment,
                extra: widget.farmerId,
              ),
              onIssueLoan: () => context.push(
                AppRoutes.issueNewLoan,
                extra: widget.farmerId,
              ),
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
  final VoidCallback onMenu;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _TopAppBar({
    required this.title,
    required this.onBack,
    required this.onMenu,
    required this.sagana,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(Icons.more_vert_rounded, color: cs.primary),
                onPressed: onMenu,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Identity Card
// ─────────────────────────────────────────────────────────────────────────────

class _IdentityCard extends StatelessWidget {
  final FarmerProfileModel profile;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _IdentityCard({
    required this.profile,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Column(
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.primary, width: 3),
                    ),
                    child: profile.hasPhoto
                        ? ClipOval(
                            child: Image.network(
                              profile.profilePhotoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _avatarFallback(profile.fullName, cs),
                            ),
                          )
                        : _avatarFallback(profile.fullName, cs),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile.fullName,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Member ID: ${profile.memberId ?? 'Not yet assigned'}',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: cs.outline),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Member since ${profile.memberSinceLabel}'
                    '${profile.sitio != null ? ' • ${profile.sitio}' : ''}',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppConstants.successGreen.withValues(alpha: 0.10),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(
                    profile.isVerified ? 'Active Member' : 'Pending Verification',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: profile.isVerified
                          ? AppConstants.successGreen
                          : AppConstants.warningAmber,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: cs.outline.withValues(alpha: 0.10)),
          const SizedBox(height: 8),

          if (profile.phoneNumber != null)
            _ContactRow(
              icon: Icons.phone_rounded,
              label: profile.phoneNumber!,
              cs: cs,
            ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String name, ColorScheme cs) {
    final parts = name.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'
        : (name.isNotEmpty ? name[0] : '?');
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surfaceContainerHighest,
      ),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: cs.primary,
          ),
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme cs;

  const _ContactRow({
    required this.icon,
    required this.label,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 14, color: cs.onSurface),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Farm Details Card (read-only — no edit; that's farmer-owned data)
// ─────────────────────────────────────────────────────────────────────────────

class _FarmDetailsCard extends StatelessWidget {
  final FarmerProfileModel profile;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _FarmDetailsCard({
    required this.profile,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          // Mini map preview if coordinates exist
          if (profile.hasCoordinates)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppConstants.radiusXl)),
              child: SizedBox(
                height: 130,
                child: IgnorePointer(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(
                          profile.farmLatitude!, profile.farmLongitude!),
                      initialZoom: 15,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.sp3coop.sagana',
                      ),
                      MarkerLayer(markers: [
                        Marker(
                          point: LatLng(
                              profile.farmLatitude!, profile.farmLongitude!),
                          width: 36,
                          height: 36,
                          child: Icon(Icons.location_on_rounded,
                              color: cs.primary, size: 36),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (profile.farmName != null)
                  Text(
                    profile.farmName!,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _StatLabel(
                        label: 'Total Area',
                        value: profile.landAreaHectares != null
                            ? '${profile.landAreaHectares!.toStringAsFixed(1)} ha'
                            : 'Not recorded',
                        cs: cs,
                      ),
                    ),
                    Expanded(
                      child: _StatLabel(
                        label: 'Experience',
                        value: profile.yearsFarming != null
                            ? '${profile.yearsFarming} years'
                            : 'Not recorded',
                        cs: cs,
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (profile.primaryCrops.isEmpty)
                  Text(
                    'No crops registered yet',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: cs.outline),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: profile.primaryCrops
                        .map((c) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppConstants.secondaryContainer
                                    .withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusFull),
                              ),
                              child: Text(
                                c,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF694300),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.06),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 14, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Farm details are managed by the farmer',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: cs.primary,
                        ),
                      ),
                    ],
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

class _StatLabel extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  final bool alignEnd;

  const _StatLabel({
    required this.label,
    required this.value,
    required this.cs,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Harvest Activity Card
// ─────────────────────────────────────────────────────────────────────────────

class _HarvestActivityCard extends StatelessWidget {
  final FarmPerformanceSummary summary;
  final Map<String, dynamic> stats;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onViewAll;

  const _HarvestActivityCard({
    required this.summary,
    required this.stats,
    required this.cs,
    required this.sagana,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final count = stats['count'] as int? ?? 0;
    final lastEntry = stats['last_entry'] as String?;
    final lastEntryLabel = lastEntry != null
        ? _shortDate(DateTime.parse(lastEntry))
        : '—';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  value: '$count',
                  label: 'Records',
                  cs: cs,
                ),
              ),
              Container(
                width: 1,
                height: 32,
                color: cs.outline.withValues(alpha: 0.10),
              ),
              Expanded(
                child: _MiniStat(
                  value: summary.totalYieldKg.toStringAsFixed(0),
                  label: 'Total kg',
                  cs: cs,
                ),
              ),
              Container(
                width: 1,
                height: 32,
                color: cs.outline.withValues(alpha: 0.10),
              ),
              Expanded(
                child: _MiniStat(
                  value: lastEntryLabel,
                  label: 'Last Entry',
                  cs: cs,
                  small: true,
                ),
              ),
            ],
          ),
          if (summary.cropBreakdown.isNotEmpty) ...[
            const SizedBox(height: 18),
            ...summary.cropBreakdown.take(4).map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(c.cropName,
                              style: GoogleFonts.inter(
                                  fontSize: 13, color: cs.onSurface)),
                          Text('${c.quantityKg.toStringAsFixed(0)}kg',
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: cs.outline)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: c.percentOfMax,
                          minHeight: 6,
                          backgroundColor:
                              cs.surfaceContainerHighest,
                          valueColor:
                              AlwaysStoppedAnimation(cs.primary),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onViewAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'View All Harvests',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: cs.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _shortDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  final ColorScheme cs;
  final bool small;

  const _MiniStat({
    required this.value,
    required this.label,
    required this.cs,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: small ? 14 : 20,
            fontWeight: FontWeight.w700,
            color: cs.primary,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 10, color: cs.outline),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loan Summary Card
// ─────────────────────────────────────────────────────────────────────────────

class _LoanSummaryCard extends StatelessWidget {
  final List<LoanModel> loans;
  final double totalOutstanding;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _LoanSummaryCard({
    required this.loans,
    required this.totalOutstanding,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final activeLoans = loans.where((l) => !l.isPaid).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            sagana.cardBackground,
            cs.surfaceContainerHighest,
          ],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Outstanding',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: cs.outline),
                  ),
                  Text(
                    '₱${totalOutstanding.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: totalOutstanding > 0
                          ? AppConstants.warningAmber
                          : AppConstants.successGreen,
                    ),
                  ),
                ],
              ),
              Icon(
                Icons.account_balance_wallet_rounded,
                size: 30,
                color: totalOutstanding > 0
                    ? AppConstants.warningAmber
                    : AppConstants.successGreen,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (activeLoans.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppConstants.successGreen.withValues(alpha: 0.08),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: AppConstants.successGreen, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'No active loans',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppConstants.successGreen),
                  ),
                ],
              ),
            )
          else
            ...activeLoans.take(2).map((loan) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: sagana.cardBackground.withValues(alpha: 0.70),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMd),
                    border: Border.all(
                        color: cs.outline.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              loan.referenceNo,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(loan.repaidPercent * 100).toStringAsFixed(0)}% Paid',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: loan.repaidPercent,
                          minHeight: 5,
                          backgroundColor:
                              cs.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(
                            loan.isOverdue
                                ? cs.error
                                : AppConstants.successGreen,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '₱${loan.remainingBalance.toStringAsFixed(2)} remaining',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: cs.outline),
                          ),
                          if (loan.isOverdue)
                            Text(
                              'OVERDUE',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: cs.error,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contribution Card
// ─────────────────────────────────────────────────────────────────────────────

class _ContributionCard extends StatelessWidget {
  final MemberContribution? contribution;
  final CapitalSharesModel? capitalShares;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onViewFull;

  const _ContributionCard({
    required this.contribution,
    required this.capitalShares,
    required this.cs,
    required this.sagana,
    required this.onViewFull,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _StatLabel(
                  label: 'Volume to SP3 (${DateTime.now().year})',
                  value: contribution != null
                      ? '${(contribution!.palaySalesKg + contribution!.peanutSalesKg).toStringAsFixed(0)}kg'
                      : 'No records',
                  cs: cs,
                ),
              ),
              Expanded(
                child: _StatLabel(
                  label: 'Capital Shares',
                  value: capitalShares != null
                      ? '${capitalShares!.totalShares} (₱${capitalShares!.investmentValue.toStringAsFixed(0)})'
                      : 'None',
                  cs: cs,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Est. Balik-Tangkilik',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                    Text(
                      contribution != null
                          ? '₱${contribution!.estimatedTotal.toStringAsFixed(2)}'
                          : '₱0.00',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
                Icon(Icons.trending_up_rounded,
                    color: cs.primary.withValues(alpha: 0.30), size: 28),
              ],
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onViewFull,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'View Full Contribution',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: cs.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpensesTab extends StatelessWidget {
  final List<Map<String, dynamic>> expenses;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _ExpensesTab({
    required this.expenses,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No expense history yet.',
            style: GoogleFonts.inter(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      itemCount: expenses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final expense = expenses[index];
        final amount = expense['amount'] as num? ?? 0;
        final date = expense['expense_date'] as String?;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: cs.primary.withValues(alpha: 0.10),
                child: Icon(Icons.receipt_long_rounded, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense['description'] as String? ?? 'Expense',
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      date != null ? date.split('T').first : '—',
                      style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(
                '₱${amount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.primary),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgramsTab extends StatelessWidget {
  final List<Map<String, dynamic>> programs;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _ProgramsTab({
    required this.programs,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    if (programs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No assigned programs yet.',
            style: GoogleFonts.inter(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      itemCount: programs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final program = programs[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.emoji_events_rounded, color: AppConstants.programPurple, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      program['name'] as String? ?? 'Program',
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                program['description'] as String? ?? 'Assigned program',
                style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Action Bar
// ─────────────────────────────────────────────────────────────────────────────

class _BottomActionBar extends StatelessWidget {
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onNotify;
  final VoidCallback onPay;
  final VoidCallback onIssueLoan;

  const _BottomActionBar({
    required this.cs,
    required this.sagana,
    required this.onNotify,
    required this.onPay,
    required this.onIssueLoan,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(top: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _OutlineActionButton(
                  icon: Icons.sms_outlined,
                  label: 'Notify',
                  onTap: onNotify,
                  cs: cs,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OutlineActionButton(
                  icon: Icons.payments_outlined,
                  label: 'Pay',
                  onTap: onPay,
                  cs: cs,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: onIssueLoan,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppConstants.primaryGreen,
                          AppConstants.primaryContainer,
                        ],
                      ),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMd),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_card_rounded,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'Issue Loan',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
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

class _OutlineActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _OutlineActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          border: Border.all(color: cs.primary),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actions Menu (top-right ⋮)
// ─────────────────────────────────────────────────────────────────────────────

class _ActionsMenu extends StatelessWidget {
  final bool isActive;
  final VoidCallback onNotify;
  final VoidCallback onToggleStatus;

  const _ActionsMenu({
    required this.isActive,
    required this.onNotify,
    required this.onToggleStatus,
  });

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXl)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.30),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: onNotify,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.notifications_outlined,
                      size: 20, color: cs.onSurface),
                  const SizedBox(width: 14),
                  Text('Notify',
                      style: GoogleFonts.inter(
                          fontSize: 14, color: cs.onSurface)),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: onToggleStatus,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(
                    isActive
                        ? Icons.person_off_outlined
                        : Icons.person_rounded,
                    size: 20,
                    color: isActive ? cs.error : cs.onSurface,
                  ),
                  const SizedBox(width: 14),
                  Text(
                    isActive ? 'Set Inactive' : 'Set Active',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: isActive ? cs.error : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
