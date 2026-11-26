import '../../../core/theme/sagana_colors.dart';
import '../../../core/l10n/localized_labels.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/models/program_model.dart';
import '../../../data/models/program_enrollment_request_model.dart';
import '../../../data/repositories/farmer_program_repository.dart';
import '../../../data/repositories/farmer_profile_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/skeleton.dart';

/// Programs — the primary Farmer-side entry point (reached from Profile),
/// mirroring the Marketplace tab's own browse pattern (search + purpose
/// filter chips + list) rather than the old 3-screens-deep flow (Profile →
/// My Programs → Browse Programs → Details). A farmer's own enrolled
/// programs are one tap away via the icon on this screen's top bar
/// (MyProgramsScreen), not a forced step before reaching this list.
class BrowseProgramsScreen extends StatefulWidget {
  const BrowseProgramsScreen({super.key});

  @override
  State<BrowseProgramsScreen> createState() => _BrowseProgramsScreenState();
}

class _BrowseProgramsScreenState extends State<BrowseProgramsScreen> {
  final _repo = FarmerProgramRepository();
  final _profileRepo = FarmerProfileRepository();
  final _searchController = TextEditingController();

  List<CooperativeProgram> _programs = [];
  Map<String, ProgramEnrollmentRequest> _requestsByProgram = {};
  Map<String, MyProgramEntry> _enrolledByProgram = {};
  int _enrolledCount = 0;
  String _searchQuery = '';
  String _purposeFilter = 'All'; // 'All' | 'Distribution' | 'Sales'
  bool _isLoading = true;
  bool _isOnline = ConnectivityService.instance.isOnline;

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _load();
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchAvailablePrograms(),
      _repo.fetchMyEnrollmentRequests(),
      _profileRepo.fetchMyPrograms(),
    ]);
    if (!mounted) return;
    final requests = results[1] as List<ProgramEnrollmentRequest>;
    // Most recent request per program wins (fetchMyEnrollmentRequests is
    // already sorted newest-first), so a rejected-then-resubmitted
    // program shows its latest state, not the stale rejection.
    final requestsByProgram = <String, ProgramEnrollmentRequest>{};
    for (final r in requests) {
      requestsByProgram.putIfAbsent(r.programId, () => r);
    }
    final entries = results[2] as List<MyProgramEntry>;
    final enrolledByProgram = <String, MyProgramEntry>{
      for (final e in entries)
        if (e.enrollmentStatus == 'active') e.programId: e,
    };
    setState(() {
      _programs = results[0] as List<CooperativeProgram>;
      _requestsByProgram = requestsByProgram;
      _enrolledByProgram = enrolledByProgram;
      _enrolledCount = enrolledByProgram.length;
      _isLoading = false;
    });
  }

  List<CooperativeProgram> get _filtered {
    return _programs.where((p) {
      final matchesPurpose =
          _purposeFilter == 'All' ||
          (_purposeFilter == 'Sales' ? p.isSalesProgram : !p.isSalesProgram);
      final matchesSearch =
          _searchQuery.isEmpty ||
          p.programName.toLowerCase().contains(_searchQuery);
      return matchesPurpose && matchesSearch;
    }).toList();
  }

  Future<void> _openDetails(CooperativeProgram program) async {
    final entry = _enrolledByProgram[program.id];
    await context.push(
      AppRoutes.programDetails,
      extra: entry != null
          ? {'entry': entry}
          : {
              "program": program,
              'existingRequest': _requestsByProgram[program.id],
            },
    );
    if (mounted) _load();
  }

  Future<void> _openMyPrograms() async {
    await context.push(AppRoutes.myProgramsEnrolled);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const TopBarSpacer(height: 64),
              CachedDataNotice(
                screen: 'programs_available',
                isOnline: _isOnline,
                offlineMessage: AppLocalizations.of(context).offlinePrograms,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: TextField(
                  controller: _searchController,
                  style: GoogleFonts.inter(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(
                      context,
                    ).programMgmtSearchHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: context.saganaColors.cardBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: 3,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final label = ["All", "Distribution", "Sales"][i];
                    final isSelected = label == _purposeFilter;
                    return GestureDetector(
                      onTap: () => setState(() => _purposeFilter = label),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppConstants.primaryGreen
                              : context.saganaColors.cardBackground,
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusFull,
                          ),
                          border: Border.all(
                            color: isSelected
                                ? AppConstants.primaryGreen
                                : Theme.of(
                                    context,
                                  ).colorScheme.outline.withValues(alpha: 0.25),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${localizeBuiltinLabel(AppLocalizations.of(context), label)} (${label == 'All' ? _programs.length : _programs.where((p) => label == 'Sales' ? p.isSalesProgram : !p.isSalesProgram).length})',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: RefreshIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  onRefresh: _load,
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: SkeletonList(),
                        )
                      : filtered.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 120),
                            Center(
                              child: Text(
                                _programs.isEmpty
                                    ? AppLocalizations.of(
                                        context,
                                      ).enhNoActiveProgramsRightNow
                                    : AppLocalizations.of(
                                        context,
                                      ).enhNoProgramsMatchYourSearch,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final program = filtered[i];
                            final entry = _enrolledByProgram[program.id];
                            final request = _requestsByProgram[program.id];
                            return _AvailableProgramCard(
                              program: program,
                              entry: entry,
                              request: request,
                              onTap: () => _openDetails(program),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: AppLocalizations.of(context).farmerDetailsTabPrograms,
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
              trailing: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      onTap: _openMyPrograms,
                      child: Icon(
                        Icons.assignment_turned_in_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 26,
                      ),
                    ),
                    if (_enrolledCount > 0)
                      Positioned(
                        top: -4,
                        right: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppConstants.programPurple,
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull,
                            ),
                          ),
                          child: Text(
                            '$_enrolledCount',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableProgramCard extends StatelessWidget {
  final CooperativeProgram program;
  final MyProgramEntry? entry;
  final ProgramEnrollmentRequest? request;
  final VoidCallback onTap;

  const _AvailableProgramCard({
    required this.program,
    required this.entry,
    required this.request,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final accent = program.isSalesProgram
        ? AppConstants.successGreen
        : AppConstants.buyerBlue;
    final hasPhoto =
        program.imageUrl != null && program.imageUrl!.isNotEmpty;
    final fallbackIcon = program.isSalesProgram
        ? Icons.storefront_rounded
        : Icons.volunteer_activism_rounded;
    final statusBadgeLabel = entry != null
        ? l10n.farmerProgStageEnrolled
        : request != null
            ? (request!.isPending
                ? l10n.buyerOrderDetailPendingTimestamp
                : request!.isRejected
                    ? l10n.farmerMgmtStatusRejectedLabel
                    : l10n.farmerDetailsProgStatusActive)
            : l10n.farmerDetailsProgStatusActive;
    final statusBadgeColor = entry != null
        ? AppConstants.successGreen
        : request != null
            ? _stateColor(context)
            : AppConstants.successGreen;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF455A64).withValues(alpha: 0.05),
              blurRadius: 8,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 120,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasPhoto)
                    Image.network(
                      program.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _bannerFallback(accent, fallbackIcon),
                    )
                  else
                    _bannerFallback(accent, fallbackIcon),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusBadgeColor,
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull,
                        ),
                      ),
                      child: Text(
                        statusBadgeLabel,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          program.programName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: cs.outline,
                      ),
                    ],
                  ),
                  if (program.programType.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${program.programType} · ${program.seasonYear}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _PurposePill(
                        label: program.isSalesProgram
                            ? l10n.reportsProductSalesShort
                            : l10n.programMgmtFilterDistribution,
                        color: accent,
                      ),
                      if (program.hasCooperativeShare)
                        _PurposePill(
                          label:
                              'Return Percentage (${formatQuantity(program.cooperativeSharePercent)}%)',
                          color: AppConstants.buyerBlue,
                        ),
                      if (program.hasMemberDiscount)
                        _PurposePill(
                          label: l10n.programMgmtMemberDiscountChip(
                            formatQuantity(program.memberDiscountPercent),
                          ),
                          color: AppConstants.successGreen,
                        ),
                    ],
                  ),
                  if ((program.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      program.description!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.4,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    color: cs.outline.withValues(alpha: 0.12),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        entry != null
                            ? Icons.check_circle_outline_rounded
                            : request?.isPending == true
                                ? Icons.hourglass_bottom_rounded
                                : Icons.touch_app_outlined,
                        size: 15,
                        color: _stateColor(context),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _stateLabel(l10n),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _stateColor(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bannerFallback(Color accent, IconData icon) => Container(
    color: accent.withValues(alpha: 0.12),
    alignment: Alignment.center,
    child: Icon(icon, size: 38, color: accent.withValues(alpha: 0.7)),
  );

  String _stateLabel(AppLocalizations l10n) {
    if (entry != null) return l10n.joinTapDetailsJoined;
    if (request == null) return l10n.joinTapDetailsRequest;
    if (request!.isPending) return l10n.joinRequestPendingShort;
    if (request!.isRejected) return l10n.joinRequestDeclinedTryAgain;
    return l10n.joinRequested;
  }

  Color _stateColor(BuildContext context) {
    if (entry != null) return AppConstants.successGreen;
    if (request == null) return Theme.of(context).colorScheme.onSurfaceVariant;
    if (request!.isPending) return AppConstants.warningAmber;
    if (request!.isRejected) return AppConstants.errorRed;
    return AppConstants.successGreen;
  }
}

class _PurposePill extends StatelessWidget {
  final String label;
  final Color color;
  const _PurposePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
    ),
    child: Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}
