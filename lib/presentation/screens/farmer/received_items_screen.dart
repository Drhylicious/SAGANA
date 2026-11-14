import '../../../core/theme/sagana_colors.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/item_type_utils.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/models/program_return_model.dart';
import '../../../data/repositories/farmer_profile_repository.dart';
import '../../../data/repositories/farmer_program_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/choice_filter_modal.dart';
import '../../widgets/dashboard_cards.dart';
import '../../widgets/filter_icon_button.dart';
import '../../widgets/listing_filter_modal.dart'
    show MarketplaceFilterBar, MarketplaceFilterOption;
import '../../widgets/management_modal.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/top_bar_spacer.dart';

/// What the cooperative has given the Farmer, from the same program records as My Programs (nothing is
/// stored twice). Every item a program gave the Farmer is listed here: seeds, seedlings, produce, tools,
/// livestock, fertilizer and supplies, whether it came through a Free Distribution or a Harvest Return.
/// The layout follows the Supply Chain screen: summary cards, search with the shared filter button,
/// filter chips, then tappable cards that open the item's full details.
class ReceivedItemsScreen extends StatefulWidget {
  const ReceivedItemsScreen({super.key});

  @override
  State<ReceivedItemsScreen> createState() => _ReceivedItemsScreenState();
}

enum _ItemFilter { all, keep, toReturn, returned }

class _ReceivedItemsScreenState extends State<ReceivedItemsScreen> {
  final _repo = FarmerProfileRepository();
  final _programRepo = FarmerProgramRepository();
  final _searchController = TextEditingController();
  List<MyProgramEntry> _items = [];
  MyReturnsSnapshot _returns = const MyReturnsSnapshot();
  _ItemFilter _filter = _ItemFilter.all;
  String? _program; // the filter button: one program, null = every program
  String _query = '';
  bool _isLoading = true;
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.onConnectivityChanged
        .listen((online) {
          if (mounted) setState(() => _isOnline = online);
        });
    _searchController.addListener(() {
      final q = _searchController.text.trim().toLowerCase();
      if (q != _query) setState(() => _query = q);
    });
    _load();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchMyReceivedItems(),
      _programRepo.fetchMyReturns(),
    ]);
    if (!mounted) return;
    setState(() {
      _items = results[0] as List<MyProgramEntry>;
      _returns = results[1] as MyReturnsSnapshot;
      _isLoading = false;
    });
  }

  // ─── What each item's situation is ───────────────────────────────────────

  bool _isReturned(MyProgramEntry e) {
    if (!e.isRevenueShare) return false;
    final r = _returns.byMember[e.id];
    return r != null && (r.status == 'received' || r.status == 'closed_short');
  }

  /// A Harvest Return item is still owed back until its return is fully received (or closed).
  /// A failed outcome with no return opened owes nothing.
  bool _owesReturn(MyProgramEntry e) {
    if (!e.isRevenueShare) return false;
    final r = _returns.byMember[e.id];
    if (r == null) return !e.isOutcomeFailed;
    return !_isReturned(e);
  }

  bool _matchesChip(MyProgramEntry e, _ItemFilter f) {
    switch (f) {
      case _ItemFilter.all:
        return true;
      case _ItemFilter.keep:
        return !e.isRevenueShare;
      case _ItemFilter.toReturn:
        return _owesReturn(e);
      case _ItemFilter.returned:
        return _isReturned(e);
    }
  }

  /// The program picked in the filter and the words typed in the search.
  bool _matchesBase(MyProgramEntry e) {
    if (_program != null && e.programName != _program) return false;
    if (_query.isEmpty) return true;
    return (e.itemName ?? '').toLowerCase().contains(_query) ||
        e.programName.toLowerCase().contains(_query);
  }

  List<MyProgramEntry> get _visible =>
      _items.where((e) => _matchesBase(e) && _matchesChip(e, _filter)).toList();

  int _count(_ItemFilter f) =>
      _items.where((e) => _matchesBase(e) && _matchesChip(e, f)).length;

  String _filterLabel(AppLocalizations l10n, _ItemFilter f) {
    switch (f) {
      case _ItemFilter.all:
        return l10n.receivedItemsFilterAll;
      case _ItemFilter.keep:
        return l10n.receivedItemsFilterKeep;
      case _ItemFilter.toReturn:
        return l10n.receivedItemsFilterReturn;
      case _ItemFilter.returned:
        return l10n.receivedItemsFilterReturned;
    }
  }

  Future<void> _openFilter() async {
    final l10n = AppLocalizations.of(context);
    final programs = {for (final e in _items) e.programName}.toList()..sort();
    final result = await showChoiceFilterModal<String?>(
      context,
      title: l10n.receivedItemsFilterTitle,
      sectionLabel: l10n.receivedItemsFilterProgram,
      choices: [
        FilterChoice<String?>(null, l10n.receivedItemsAllPrograms),
        for (final p in programs) FilterChoice<String?>(p, p),
      ],
      selected: _program,
      resetTo: null,
    );
    if (result == null || !mounted) return;
    setState(() => _program = result.value);
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

  void _openDetails(MyProgramEntry e) {
    showManagementModal<void>(
      context: context,
      builder: (ctx) => _ItemDetailsSheet(
        entry: e,
        harvestReturn: _returns.byMember[e.id],
        formatDate: _formatDate,
        onViewProgram: () {
          Navigator.of(ctx).pop();
          context.push(AppRoutes.programDetails, extra: {'entry': e});
        },
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  Widget _pad(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSafeH),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _load,
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: SkeletonList(),
                        )
                      : _items.isEmpty
                      ? _buildEmpty(l10n)
                      : _buildContent(l10n),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: l10n.receivedItemsTitle,
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

  Widget _buildEmpty(AppLocalizations l10n) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      children: [
        const SizedBox(height: 90),
        Icon(
          Icons.inventory_2_outlined,
          size: 56,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 14),
        Text(
          l10n.receivedItemsEmptyTitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.receivedItemsEmptyBody,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            height: 1.45,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final visible = _visible;
    final keepCount = _items.where((e) => !e.isRevenueShare).length;
    final owedCount = _items.where(_owesReturn).length;
    final returnedCount = _items.where(_isReturned).length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(
        top: AppConstants.spacingGutter,
        bottom: 32,
      ),
      children: [
        // Summary: every item, then how they stand (the same cards as the other dashboards).
        _pad(
          DashboardKpiStrip(
            tiles: [
              DashboardKpiTile(
                label: l10n.receivedItemsStatTotal,
                value: '${_items.length}',
                color: AppConstants.primaryGreen,
                icon: Icons.inventory_2_outlined,
              ),
              DashboardKpiTile(
                label: l10n.receivedItemsKeep,
                value: '$keepCount',
                color: AppConstants.successGreen,
                icon: Icons.check_circle_outline_rounded,
              ),
              DashboardKpiTile(
                label: l10n.receivedItemsStatReturn,
                value: '$owedCount',
                color: AppConstants.warningAmber,
                icon: Icons.assignment_return_outlined,
              ),
              DashboardKpiTile(
                label: l10n.receivedItemsReturned,
                value: '$returnedCount',
                color: AppConstants.buyerBlue,
                icon: Icons.done_all_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingGutter),
        // Search, and the shared filter button beside it.
        _pad(
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: l10n.receivedItemsSearchHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilterIconButton(
                semanticLabel: l10n.receivedItemsFilterTitle,
                active: _program != null,
                onTap: _openFilter,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        MarketplaceFilterBar<_ItemFilter>(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingSafeH,
          ),
          selected: _filter,
          onSelected: (f) => setState(() => _filter = f),
          options: [
            for (final f in _ItemFilter.values)
              MarketplaceFilterOption<_ItemFilter>(
                value: f,
                label: _filterLabel(l10n, f),
                count: _count(f),
                color: cs.primary,
              ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingMd),
        if (visible.isEmpty)
          _pad(
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Text(
                l10n.receivedItemsNoMatch,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          _pad(
            Column(
              children: [
                for (final e in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ItemCard(
                      entry: e,
                      harvestReturn: _returns.byMember[e.id],
                      formatDate: _formatDate,
                      onTap: () => _openDetails(e),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared pieces
// ─────────────────────────────────────────────────────────────────────────────

BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
  border: Border.all(color: AppConstants.outline.withValues(alpha: 0.10)),
  boxShadow: [
    BoxShadow(
      color: const Color(0xFF455A64).withValues(alpha: 0.06),
      blurRadius: 10,
    ),
  ],
);

String _qty(double v, String? unit) =>
    '${formatQuantityGrouped(v)} ${unitOrDefault(unit)}';

/// The one status the Farmer cares about for an item: theirs to keep, or what is owed back.
({String label, Color color}) _itemStatus(
  AppLocalizations l10n,
  MyProgramEntry entry,
  ProgramReturnSummary? r,
) {
  if (!entry.isRevenueShare) {
    return (label: l10n.receivedItemsKeep, color: AppConstants.successGreen);
  }
  if (r == null) {
    return entry.isOutcomeFailed
        ? (label: l10n.receivedItemsReturnClosed, color: AppConstants.outline)
        : (
            label: l10n.receivedItemsReturnExpected,
            color: AppConstants.buyerBlue,
          );
  }
  switch (r.status) {
    case 'received':
      return (
        label: l10n.receivedItemsReturned,
        color: AppConstants.successGreen,
      );
    case 'closed_short':
      return (
        label: l10n.receivedItemsReturnClosed,
        color: AppConstants.outline,
      );
    case 'partial':
      return (
        label: l10n.receivedItemsReturnPartial(
          _qty(r.receivedQuantity, r.unit),
          _qty(r.dueQuantity, r.unit),
        ),
        color: AppConstants.warningAmber,
      );
    default:
      return (
        label: l10n.receivedItemsReturnDue(_qty(r.dueQuantity, r.unit)),
        color: AppConstants.warningAmber,
      );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ItemPhoto extends StatelessWidget {
  const _ItemPhoto({required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.inventory_2_outlined,
      color: Theme.of(context).colorScheme.primary,
      size: size * 0.5,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: Container(
        width: size,
        height: size,
        color: AppConstants.primaryGreen.withValues(alpha: 0.10),
        child: (url != null && url!.isNotEmpty)
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              )
            : fallback,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The card
// ─────────────────────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.entry,
    required this.harvestReturn,
    required this.formatDate,
    required this.onTap,
  });

  final MyProgramEntry entry;
  final ProgramReturnSummary? harvestReturn;
  final String Function(DateTime) formatDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = _itemStatus(l10n, entry, harvestReturn);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ItemPhoto(url: entry.itemImageUrl, size: 60),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.itemName ?? '—',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _qty(entry.quantityGiven ?? 0, entry.itemUnit),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.programName} • ${formatDate(entry.distributedAt!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Pill(label: status.label, color: status.color),
                      _Pill(
                        label: itemTypeLabel(l10n, entry.itemType),
                        color: AppConstants.mutedSlate,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The full details of one received item
// ─────────────────────────────────────────────────────────────────────────────

class _ItemDetailsSheet extends StatelessWidget {
  const _ItemDetailsSheet({
    required this.entry,
    required this.harvestReturn,
    required this.formatDate,
    required this.onViewProgram,
  });

  final MyProgramEntry entry;
  final ProgramReturnSummary? harvestReturn;
  final String Function(DateTime) formatDate;
  final VoidCallback onViewProgram;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = _itemStatus(l10n, entry, harvestReturn);
    final r = harvestReturn;
    final outcome = entry.isOutcomeThriving
        ? l10n.receivedItemsOutcomeSuccessful
        : entry.isOutcomeFailed
        ? l10n.receivedItemsOutcomeFailed
        : l10n.receivedItemsOutcomePending;

    final rows = <(String, String)>[
      (
        l10n.receivedItemsDetailQuantity,
        _qty(entry.quantityGiven ?? 0, entry.itemUnit),
      ),
      (l10n.invItemTypeLabel, itemTypeLabel(l10n, entry.itemType)),
      (l10n.receivedItemsProgram, entry.programName),
      (
        l10n.receivedItemsDetailArrangement,
        entry.isRevenueShare
            ? l10n.receivedItemsBenefitReturn
            : l10n.receivedItemsBenefitFree,
      ),
      (l10n.receivedItemsReceived, formatDate(entry.distributedAt!)),
      // A Free Distribution has no outcome; one recorded earlier stays as history.
      if (entry.isRevenueShare ||
          entry.isOutcomeThriving ||
          entry.isOutcomeFailed)
        (l10n.receivedItemsOutcome, outcome),
      if (r != null) ...[
        (l10n.receivedItemsDetailExpected, _qty(r.dueQuantity, r.unit)),
        (
          l10n.receivedItemsDetailReceivedBack,
          _qty(r.receivedQuantity, r.unit),
        ),
      ],
    ];

    return ManagementModalShell(
      title: entry.itemName ?? '—',
      subtitle: entry.programName,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _ItemPhoto(url: entry.itemImageUrl, size: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Pill(label: status.label, color: status.color),
                    _Pill(
                      label: itemTypeLabel(l10n, entry.itemType),
                      color: AppConstants.mutedSlate,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < rows.length; i++) ...[
            _DetailRow(label: rows[i].$1, value: rows[i].$2),
            if (i < rows.length - 1)
              Divider(
                height: 18,
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.12),
              ),
          ],
        ],
      ),
      footer: ManagementModalActions(
        cancelLabel: l10n.commonClose,
        primaryLabel: l10n.receivedItemsViewProgram,
        onPrimary: onViewProgram,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
