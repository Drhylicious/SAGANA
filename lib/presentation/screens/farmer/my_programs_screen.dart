import '../../../core/theme/sagana_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/models/program_assistance_model.dart';
import '../../../data/models/program_model.dart';
import '../../../data/repositories/program_assistance_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../core/utils/app_error_message.dart';
import '../../widgets/app_toast.dart';
import '../../../data/repositories/farmer_profile_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/skeleton.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/localized_labels.dart';

class MyProgramsScreen extends StatefulWidget {
  const MyProgramsScreen({super.key});

  @override
  State<MyProgramsScreen> createState() => _MyProgramsScreenState();
}

class _MyProgramsScreenState extends State<MyProgramsScreen> {
  final _repo = FarmerProfileRepository();
  List<MyProgramEntry> _programs = [];
  final _assistRepo = ProgramAssistanceRepository();
  final _programRepo = ProgramRepository();
  Map<String, AssistanceOption> _assistOptions = {};
  Map<String, AssistanceRequest> _assistLatest = {};
  Map<String, List<ProgramSaleShare>> _sharesByMember = {};
  // Search and the All / Free Distribution / Sales chips (the same format as Browse Programs).
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _purposeFilter = 'All';
  bool _isLoading = true;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _searchController.addListener(
      () => setState(() => _searchQuery = _searchController.text.trim().toLowerCase()),
    );
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesPurpose(MyProgramEntry p, String label) =>
      label == 'All' || (label == 'Sales' ? p.isSalesProgram : !p.isSalesProgram);

  List<MyProgramEntry> get _visible => _programs
      .where((p) =>
          _matchesPurpose(p, _purposeFilter) &&
          (_searchQuery.isEmpty || p.programName.toLowerCase().contains(_searchQuery)))
      .toList();

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchMyPrograms(),
      _assistRepo.fetchMyOptions(),
      _assistRepo.fetchMyRequests(),
      _programRepo.fetchMyProgramShares(),
    ]);
    if (!mounted) return;
    final programs = results[0] as List<MyProgramEntry>;
    final sharesMap = <String, List<ProgramSaleShare>>{};
    for (final s in results[3] as List<ProgramSaleShare>) {
      sharesMap.putIfAbsent(s.programMemberId, () => []).add(s);
    }
    setState(() {
      _programs = programs;
      _assistOptions = {
        for (final o in results[1] as List<AssistanceOption>)
          o.programMemberId: o,
      };
      // Newest first, so the first one seen per member is the latest.
      _assistLatest = {};
      for (final r in results[2] as List<AssistanceRequest>) {
        _assistLatest.putIfAbsent(r.programMemberId, () => r);
      }
      _sharesByMember = sharesMap;
      _isLoading = false;
    });
  }

  Future<void> _openAssistance(MyProgramEntry entry) async {
    final sent = await context.push<bool>(
      AppRoutes.requestAssistance,
      extra: {'programMemberId': entry.id, 'programName': entry.programName},
    );
    if (sent == true) _load();
  }

  Future<void> _cancelAssistance(AssistanceRequest r) async {
    final l10n = AppLocalizations.of(context);
    try {
      await _assistRepo.cancel(r.id);
      if (!mounted) return;
      AppToast.show(context, l10n.assistCancelled);
      _load();
    } catch (e, st) {
      if (mounted) {
        AppToast.show(context, friendlyError(l10n, e, st), isError: true);
      }
    }
  }

  String _formatDate(DateTime dt) {
    final months = [
      AppLocalizations.of(context).enhJan,
      AppLocalizations.of(context).enhFeb,
      AppLocalizations.of(context).enhMar,
      AppLocalizations.of(context).enhApr,
      AppLocalizations.of(context).adminCalMonthMay,
      AppLocalizations.of(context).enhJun,
      AppLocalizations.of(context).enhJul,
      AppLocalizations.of(context).enhAug,
      AppLocalizations.of(context).enhSep,
      AppLocalizations.of(context).enhOct,
      AppLocalizations.of(context).enhNov,
      AppLocalizations.of(context).enhDec,
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _statusLabel(AppLocalizations l10n, String status) {
    switch (status) {
      case 'withdrawn':
        return l10n.farmerProgStatusWithdrawn;
      case 'completed':
        return l10n.farmerProgStatusCompleted;
      default:
        return l10n.farmerProgStatusActive;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shown = _visible;
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const TopBarSpacer(height: 64),
              CachedDataNotice(
                screen: 'my_programs',
                isOnline: _isOnline,
                offlineMessage: l10n.offlinePrograms,
              ),
              const SizedBox(height: 4),
              if (!_isLoading && _programs.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.inter(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: l10n.programMgmtSearchHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: context.saganaColors.cardBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
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
                      final label = ['All', 'Distribution', 'Sales'][i];
                      final isSelected = label == _purposeFilter;
                      final count = _programs.where((p) => _matchesPurpose(p, label)).length;
                      return GestureDetector(
                        onTap: () => setState(() => _purposeFilter = label),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? AppConstants.primaryGreen : context.saganaColors.cardBackground,
                            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                            border: Border.all(
                              color: isSelected
                                  ? AppConstants.primaryGreen
                                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${localizeBuiltinLabel(l10n, label)} ($count)',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: RefreshIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  onRefresh: _load,
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: SkeletonList(),
                        )
                      : _programs.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          children: [
                            const SizedBox(height: 90),
                            Icon(
                              Icons.volunteer_activism_outlined,
                              size: 56,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              l10n.farmerProgEmptyTitle,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.farmerProgEmptyBody,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                height: 1.45,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      : shown.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          children: [
                            const SizedBox(height: 70),
                            Text(
                              l10n.farmerProgNoMatch,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 14),
                          itemBuilder: (_, i) => MyProgramCard(
                            entry: shown[i],
                            assistOption: _assistOptions[shown[i].id],
                            assistRequest: _assistLatest[shown[i].id],
                            shares: _sharesByMember[shown[i].id] ?? const [],
                            onAssist: () => _openAssistance(shown[i]),
                            onCancelAssist: () => _cancelAssistance(
                              _assistLatest[shown[i].id]!,
                            ),
                            formatDate: _formatDate,
                            statusLabel: (s) => _statusLabel(l10n, s),
                          ),
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
              title: AppLocalizations.of(context).enhMyPrograms,
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
        ],
      ),
    );
  }
}

/// One enrolled program on the Farmer's My Programs screen (public so its layout can be tested).
class MyProgramCard extends StatelessWidget {
  final MyProgramEntry entry;
  final AssistanceOption? assistOption;
  final AssistanceRequest? assistRequest;
  final List<ProgramSaleShare> shares;
  final VoidCallback? onAssist;
  final VoidCallback? onCancelAssist;
  // Staff view (Farmer Details): the same card, nothing to tap. No buttons, no links.
  final bool readOnly;
  final String Function(DateTime) formatDate;
  final String Function(String) statusLabel;

  const MyProgramCard({
    super.key,
    required this.entry,
    this.assistOption,
    this.assistRequest,
    this.shares = const [],
    this.onAssist,
    this.onCancelAssist,
    this.readOnly = false,
    required this.formatDate,
    required this.statusLabel,
  });

  String _qty(double v) => formatQuantityGrouped(v);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accent = entry.isSalesProgram
        ? AppConstants.successGreen
        : AppConstants.programPurple;
    final hasPhoto =
        entry.programImageUrl != null && entry.programImageUrl!.isNotEmpty;
    final fallbackIcon = entry.isSalesProgram
        ? Icons.storefront_rounded
        : Icons.volunteer_activism_rounded;

    // Every enrolled program opens Program Details.
    return GestureDetector(
      onTap: readOnly
          ? null
          : () => context.push(AppRoutes.programDetails, extra: {'entry': entry}),
      child: Container(
        decoration: BoxDecoration(
          color: context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.10),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF455A64).withValues(alpha: 0.06),
              blurRadius: 10,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Photo header ──────────────────────────────────────────
            SizedBox(
              height: 110,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  hasPhoto
                      ? Image.network(
                          entry.programImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _headerFallback(accent, fallbackIcon),
                        )
                      : _headerFallback(accent, fallbackIcon),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _Badge(
                      label: statusLabel(entry.enrollmentStatus),
                      color: AppConstants.successGreen,
                      solid: true,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.programName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!readOnly)
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Badge(
                        label: entry.isSalesProgram
                            ? l10n.farmerProgSalesProgram
                            : l10n.farmerProgDistributionProgram,
                        color: accent,
                      ),
                      if (!entry.isSalesProgram &&
                          entry.cooperativeSharePercent > 0)
                        _Badge(
                          label:
                              'Return Percentage (${formatQuantity(entry.cooperativeSharePercent)}%)',
                          color: AppConstants.buyerBlue,
                        ),
                      if (entry.isSalesProgram &&
                          entry.memberDiscountPercent > 0)
                        _Badge(
                          label: l10n.programMgmtMemberDiscountChip(
                            formatQuantity(entry.memberDiscountPercent),
                          ),
                          color: AppConstants.successGreen,
                        ),
                      Text(
                        l10n.farmerProgEnrolledOn(formatDate(entry.enrolledAt)),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (entry.programDescription != null &&
                      entry.programDescription!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      entry.programDescription!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Divider(
                    height: 1,
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.12),
                  ),
                  const SizedBox(height: 14),
                  if (entry.isSalesProgram)
                    Text(
                      l10n.farmerProgSalesHint,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    ..._distributionBody(context, l10n),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerFallback(Color accent, IconData icon) => Container(
    color: accent.withValues(alpha: 0.12),
    alignment: Alignment.center,
    child: Icon(icon, size: 38, color: accent.withValues(alpha: 0.7)),
  );

  // Enrolled → Received, for Free Distribution.
  List<Widget> _distributionBody(BuildContext context, AppLocalizations l10n) {
    final received = entry.isDistributed;

    final what = received
        ? '${_qty(entry.quantityGiven ?? 0)}'
              '${entry.itemUnit != null ? ' ${entry.itemUnit}' : ''}'
              '${entry.itemName != null ? ' ${entry.itemName}' : ''}'
        : '';

    return [
      Row(
        children: [
          _Step(
            label: l10n.farmerProgStageEnrolled,
            color: AppConstants.successGreen,
            done: true,
          ),
          _StepLine(active: received),
          _Step(
            label: l10n.farmerProgStageReceived,
            color: AppConstants.successGreen,
            done: received,
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (!received)
        Text(
          l10n.farmerProgAwaiting,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        )
      else ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // The distributed item's photo from Inventory Management (reused,
            // not a separate upload).
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child:
                  (entry.itemImageUrl != null && entry.itemImageUrl!.isNotEmpty)
                  ? Image.network(
                      entry.itemImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.inventory_2_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.farmerProgReceivedLine(
                  what,
                  formatDate(entry.distributedAt!),
                ),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.farmerProgFreeOwned,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppConstants.successGreen,
          ),
        ),
        if (shares.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final s in shares)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Coop Share (${formatQuantity(s.sharePercent)}% on ${formatQuantity(s.quantitySold)} ${s.unit}): ₱${s.amountOwed.toStringAsFixed(2)} · ${s.isPaid ? 'Paid' : 'Unpaid'}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: s.isPaid
                      ? AppConstants.successGreen
                      : AppConstants.warningAmber,
                ),
              ),
            ),
        ],
      ],
    ];
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final bool solid;
  const _Badge({required this.label, required this.color, this.solid = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: solid ? Colors.white : color,
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String label;
  final Color color;
  final bool done;
  const _Step({required this.label, required this.color, required this.done});

  @override
  Widget build(BuildContext context) {
    final c = done
        ? color
        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4);
    return Column(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: done ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: c, width: 2),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 4),
        // A 10-point caption: it follows the phone's text size, but only up to 1.3x, so
        // three of them still fit side by side on a small screen at the largest sizes.
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: done ? FontWeight.w700 : FontWeight.w500,
              color: done
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool active;
  const _StepLine({required this.active});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        // Lines up with the middle of the 22px circle, above the label.
        padding: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
        child: Container(
          height: 2,
          color: active
              ? AppConstants.successGreen
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
    );
  }
}


