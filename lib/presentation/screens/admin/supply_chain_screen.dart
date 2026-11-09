import 'dart:async';
import '../../../core/utils/item_type_utils.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/supply_chain_model.dart';
import '../../../data/repositories/supply_chain_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/dashboard_cards.dart';
import '../../widgets/filter_icon_button.dart';
import '../../widgets/listing_filter_modal.dart'
    show MarketplaceFilterBar, MarketplaceFilterOption;
import '../../widgets/order_status_style.dart';
import '../../widgets/report_ui_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

/// Supply Chain Management — Manager and Officer. Route: /admin/supply-chain
///
/// A strictly read-only tracking view of how products move from their source
/// to the consumer. It reads records the other modules already keep (Inventory,
/// Programs, Offer to Cooperative, Order Management, Loans) through two
/// read-only database functions. There is deliberately no button on this screen
/// that creates, edits, approves or processes anything, so it needs no
/// View Only / Manage distinction: every staff member sees the same thing.
class SupplyChainScreen extends StatefulWidget {
  const SupplyChainScreen({super.key});

  @override
  State<SupplyChainScreen> createState() => _SupplyChainScreenState();
}

enum _SupplyView { cards, table }

enum _SortColumn { date, item, quantity }

/// What the filter sheet hands back.
class _SupplyFilterResult {
  const _SupplyFilterResult(this.range, this.stage);
  final SupplyDateRange range;
  final SupplyStageFilter stage;
}

class _SupplyChainScreenState extends State<SupplyChainScreen> {
  static const _pageSize = 40;

  final _repo = SupplyChainRepository();
  final _searchController = TextEditingController();
  StreamSubscription<bool>? _connectivitySub;

  bool _loading = true;
  bool _failed = false;
  bool _isOnline = ConnectivityService.instance.isOnline;
  List<SupplyChainRecord> _records = const [];

  SupplyDateRange _range = SupplyDateRange.allTime;
  SupplyStageFilter _stage = SupplyStageFilter.all;
  SupplyFlowFilter _flow = SupplyFlowFilter.all;
  String _query = '';
  _SupplyView _view = _SupplyView.cards;
  _SortColumn _sortColumn = _SortColumn.date;
  bool _sortAscending = false;
  int _visible = _pageSize;

  @override
  void initState() {
    super.initState();
    _connectivitySub = ConnectivityService.instance.onConnectivityChanged
        .listen((v) {
          if (mounted) setState(() => _isOnline = v);
        });
    _searchController.addListener(() {
      final q = _searchController.text;
      if (q != _query) {
        setState(() {
          _query = q;
          _visible = _pageSize;
        });
      }
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
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await _repo.fetchRecords();
      if (!mounted) return;
      setState(() {
        _records = rows;
        _loading = false;
        _visible = _pageSize;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _records = const [];
        _failed = true;
        _loading = false;
      });
    }
  }

  /// A filter other than the default is applied (the movement chips are on the
  /// main screen, so they do not light the filter button).
  bool get _filterActive =>
      _range != SupplyDateRange.allTime || _stage != SupplyStageFilter.all;

  List<SupplyChainRecord> get _filtered => filterSupplyRecords(
    _records,
    range: _range,
    stage: _stage,
    flow: _flow,
    query: _query,
  );

  List<SupplyChainRecord> _sorted(List<SupplyChainRecord> rows) {
    final list = [...rows];
    int cmp(SupplyChainRecord a, SupplyChainRecord b) {
      switch (_sortColumn) {
        case _SortColumn.date:
          return a.occurredAt.compareTo(b.occurredAt);
        case _SortColumn.item:
          return a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase());
        case _SortColumn.quantity:
          return a.quantity.compareTo(b.quantity);
      }
    }

    list.sort((a, b) => _sortAscending ? cmp(a, b) : cmp(b, a));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(title: l10n.supplyChainTitle, onBack: () => context.pop()),
          CachedDataNotice(
            screen: SupplyChainRepository.cacheKey,
            isOnline: _isOnline,
            offlineMessage: l10n.offlineStaffBody,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SkeletonList(),
                    )
                  : _failed
                  ? _buildError(l10n)
                  : _buildContent(context, l10n),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppConstants.spacingSafeH),
      children: [
        const SizedBox(height: 48),
        Icon(Icons.cloud_off_rounded, size: 44, color: cs.outline),
        const SizedBox(height: 12),
        Text(
          l10n.scmLoadError,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l10n.scmRetry),
          ),
        ),
      ],
    );
  }

  /// Side padding of the header rows (the KPI cards, search and chips).
  Widget _pad(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSafeH),
    child: child,
  );

  Widget _buildContent(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;
    final shown = (_view == _SupplyView.table ? _sorted(filtered) : filtered)
        .take(_visible)
        .toList();
    final hasMore = filtered.length > shown.length;

    // The KPI cards follow the date range, stage and search; the movement chips
    // below split them, so they are not applied here.
    final totals = SupplyChainTotals.of(
      filterSupplyRecords(
        _records,
        range: _range,
        stage: _stage,
        query: _query,
      ),
    );

    int movementCount(SupplyFlowFilter f) => filterSupplyRecords(
      _records,
      range: _range,
      stage: _stage,
      flow: f,
      query: _query,
    ).length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(
        top: AppConstants.spacingGutter,
        bottom: 32,
      ),
      children: [
        _pad(
          DashboardKpiStrip(
            tiles: [
              DashboardKpiTile(
                label: l10n.scmKpiTotal,
                value: '${totals.total}',
                color: AppConstants.primaryGreen,
                icon: Icons.alt_route_rounded,
              ),
              DashboardKpiTile(
                label: l10n.scmKpiIncoming,
                value: '${totals.incoming}',
                color: AppConstants.successGreen,
                icon: Icons.south_west_rounded,
              ),
              DashboardKpiTile(
                label: l10n.scmKpiOutgoing,
                value: '${totals.outgoing}',
                color: AppConstants.buyerBlue,
                icon: Icons.north_east_rounded,
              ),
              DashboardKpiTile(
                label: l10n.scmKpiInProgress,
                value: '${totals.inProgress}',
                color: AppConstants.warningAmber,
                icon: Icons.pending_actions_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingGutter),
        // Search, and the shared filter button beside it (the same pair as Order Management).
        _pad(
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: l10n.scmSearchHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilterIconButton(
                semanticLabel: l10n.scmFilterTitle,
                active: _filterActive,
                onTap: _openFilter,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        MarketplaceFilterBar<SupplyFlowFilter>(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingSafeH,
          ),
          selected: _flow,
          onSelected: (f) => setState(() {
            _flow = f;
            _visible = _pageSize;
          }),
          options: [
            for (final f in SupplyFlowFilter.values)
              MarketplaceFilterOption<SupplyFlowFilter>(
                value: f,
                label: supplyFlowLabel(l10n, f),
                count: movementCount(f),
                color: cs.primary,
              ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingMd),
        _pad(_buildViewToggle(l10n)),
        const SizedBox(height: AppConstants.spacingSm),
        if (filtered.isEmpty)
          _pad(_buildEmpty(l10n))
        else if (_view == _SupplyView.cards)
          _pad(
            Column(
              children: [
                for (final r in shown)
                  _SupplyCard(record: r, onTap: () => _openDetail(r)),
              ],
            ),
          )
        else
          _pad(_buildTable(l10n, shown)),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: TextButton(
                onPressed: () => setState(() => _visible += _pageSize),
                child: Text(
                  '${filtered.length - shown.length} +',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildViewToggle(AppLocalizations l10n) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<_SupplyView>(
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            style: const ButtonStyle(
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            segments: [
              ButtonSegment(
                value: _SupplyView.cards,
                icon: const Icon(Icons.view_agenda_outlined, size: 18),
                label: Text(l10n.scmViewCards),
              ),
              ButtonSegment(
                value: _SupplyView.table,
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: Text(l10n.scmViewTable),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() {
              _view = s.first;
              _visible = _pageSize;
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final noRecords = _records.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.alt_route_rounded, size: 44, color: cs.outline),
          const SizedBox(height: 12),
          Text(
            l10n.scmEmptyTitle,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            noRecords ? l10n.scmEmptyNone : l10n.scmEmptyFiltered,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ─── Filter ───────────────────────────────────────────────────────────────

  Future<void> _openFilter() async {
    final result = await showManagementModal<_SupplyFilterResult>(
      context: context,
      builder: (_) => _SupplyFilterSheet(
        records: _records,
        query: _query,
        range: _range,
        stage: _stage,
        flow: _flow,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _range = result.range;
      _stage = result.stage;
      _visible = _pageSize;
    });
  }

  // ─── Table view ───────────────────────────────────────────────────────────

  Widget _buildTable(AppLocalizations l10n, List<SupplyChainRecord> rows) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final dateFmt = DateFormat('MMM d, yyyy');
    final headStyle = GoogleFonts.poppins(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: cs.onSurfaceVariant,
    );
    final cellStyle = GoogleFonts.inter(fontSize: 12, color: cs.onSurface);

    void sort(_SortColumn c, bool asc) => setState(() {
      _sortColumn = c;
      _sortAscending = asc;
    });

    DataColumn col(String label, {_SortColumn? sortKey, bool numeric = false}) =>
        DataColumn(
          numeric: numeric,
          label: Text(label, style: headStyle),
          onSort: sortKey == null ? null : (_, asc) => sort(sortKey, asc),
        );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
        showCheckboxColumn: false,
        sortColumnIndex: switch (_sortColumn) {
          _SortColumn.date => 0,
          _SortColumn.item => 3,
          _SortColumn.quantity => 4,
        },
        sortAscending: _sortAscending,
        columnSpacing: 24,
        horizontalMargin: 16,
        headingRowHeight: 44,
        dataRowMinHeight: 48,
        dataRowMaxHeight: 58,
        columns: [
          col(l10n.scmLabelDate, sortKey: _SortColumn.date),
          col(l10n.scmLabelStage),
          col(l10n.scmLabelType),
          col(l10n.scmLabelItem, sortKey: _SortColumn.item),
          col(l10n.scmLabelQuantity, sortKey: _SortColumn.quantity, numeric: true),
          col(l10n.scmLabelFrom),
          col(l10n.scmLabelTo),
          col(l10n.scmLabelReference),
          col(l10n.scmLabelStatus),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              onSelectChanged: (_) => _openDetail(r),
              cells: [
                DataCell(Text(dateFmt.format(r.occurredAt), style: cellStyle)),
                DataCell(
                  ReportStatusPill(
                    label: supplyRecordStageLabel(l10n, r),
                    color: supplyStageColor(r.stage),
                  ),
                ),
                DataCell(Text(supplyTypeLabel(l10n, r.type), style: cellStyle)),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      r.itemName,
                      overflow: TextOverflow.ellipsis,
                      style: cellStyle.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    '${r.isIncoming ? '+' : '−'}${formatQuantityUnit(r.quantity, r.unit)}',
                    style: cellStyle.copyWith(
                      fontWeight: FontWeight.w700,
                      color: r.isIncoming
                          ? AppConstants.successGreen
                          : AppConstants.buyerBlue,
                    ),
                  ),
                ),
                DataCell(_PartyCell(party: r.from, style: cellStyle)),
                DataCell(_PartyCell(party: r.to, style: cellStyle)),
                DataCell(Text(r.reference ?? '—', style: cellStyle)),
                DataCell(_StatusPill(record: r)),
              ],
            ),
        ],
        ),
      ),
    );
  }

  // ─── Detail ───────────────────────────────────────────────────────────────

  void _openDetail(SupplyChainRecord record) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupplyDetailSheet(
        record: record,
        related: relatedSupplyRecords(record, _records),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Labels and colours shared by the cards, the table and the detail sheet
// ═════════════════════════════════════════════════════════════════════════════

/// The stage of a record, named after its SAGANA module (Inventory, Programs,
/// Cooperative Purchases, Farmer Members, Buyers, Loans).
String supplyStageFilterLabel(AppLocalizations l10n, SupplyStageFilter s) {
  switch (s) {
    case SupplyStageFilter.all:
      return l10n.scmStageFilterAll;
    case SupplyStageFilter.inventory:
      return l10n.scmStageFilterInventory;
    case SupplyStageFilter.programs:
      return l10n.scmStageFilterPrograms;
    case SupplyStageFilter.cooperativePurchases:
      return l10n.scmStageFilterPurchases;
    case SupplyStageFilter.farmerMembers:
      return l10n.scmStageFilterFarmers;
    case SupplyStageFilter.buyers:
      return l10n.scmStageFilterBuyers;
    case SupplyStageFilter.loans:
      return l10n.scmStageFilterLoans;
  }
}

String supplyRecordStageLabel(AppLocalizations l10n, SupplyChainRecord r) =>
    supplyStageFilterLabel(l10n, SupplyStageFilter.of(r));

String supplyFlowLabel(AppLocalizations l10n, SupplyFlowFilter f) {
  switch (f) {
    case SupplyFlowFilter.all:
      return l10n.scmFlowAll;
    case SupplyFlowFilter.incoming:
      return l10n.scmFlowIncoming;
    case SupplyFlowFilter.outgoing:
      return l10n.scmFlowOutgoing;
  }
}

String supplyDateRangeLabel(AppLocalizations l10n, SupplyDateRange r) {
  switch (r) {
    case SupplyDateRange.allTime:
      return l10n.scmPeriodAllTime;
    case SupplyDateRange.thisMonth:
      return l10n.scmPeriodThisMonth;
    case SupplyDateRange.thisQuarter:
      return l10n.scmPeriodThisQuarter;
    case SupplyDateRange.thisYear:
      return l10n.scmPeriodThisYear;
  }
}

Color supplyStageColor(SupplyStage s) {
  switch (s) {
    case SupplyStage.source:
      return AppConstants.gold;
    case SupplyStage.program:
      return AppConstants.programPurple;
    case SupplyStage.offer:
      return AppConstants.midGreen;
    case SupplyStage.consumer:
      return AppConstants.buyerBlue;
    case SupplyStage.other:
      return AppConstants.mutedSlate;
  }
}

IconData supplyStageIcon(SupplyStage s) {
  switch (s) {
    case SupplyStage.source:
      return Icons.warehouse_rounded;
    case SupplyStage.program:
      return Icons.volunteer_activism_rounded;
    case SupplyStage.offer:
      return Icons.handshake_rounded;
    case SupplyStage.consumer:
      return Icons.local_shipping_rounded;
    case SupplyStage.other:
      return Icons.request_quote_rounded;
  }
}

String supplyTypeLabel(AppLocalizations l10n, SupplyRecordType t) {
  switch (t) {
    case SupplyRecordType.inventoryRestock:
      return l10n.scmTypeRestock;
    case SupplyRecordType.programDistribution:
      return l10n.scmTypeDistribution;
    case SupplyRecordType.harvestReturn:
      return l10n.scmTypeReturn;
    case SupplyRecordType.cooperativePurchase:
      return l10n.scmTypePurchase;
    case SupplyRecordType.cooperativeSale:
      return l10n.scmTypeCoopSale;
    case SupplyRecordType.marketplaceSale:
      return l10n.scmTypeMarketSale;
    case SupplyRecordType.loanIssue:
      return l10n.scmTypeLoan;
    case SupplyRecordType.unknown:
      return '—';
  }
}

String supplyRoleLabel(AppLocalizations l10n, String? role) {
  switch (role) {
    case 'supplier':
      return l10n.scmPartySupplier;
    case 'farmer':
      return l10n.scmPartyFarmer;
    case 'buyer':
      return l10n.scmPartyBuyer;
    case 'cooperative':
      return l10n.scmPartyCooperative;
    default:
      return l10n.scmPartyNotRecorded;
  }
}

/// The name of a party, or its role when only the role is known (the
/// Cooperative, or a record that never stored a name).
String supplyPartyText(AppLocalizations l10n, SupplyParty p) {
  if (p.isCooperative) return l10n.scmPartyCooperative;
  if (p.hasName) return p.name!;
  return p.role == null ? l10n.scmPartyNotRecorded : supplyRoleLabel(l10n, p.role);
}

String supplyFulfillmentLabel(AppLocalizations l10n, String? method) {
  switch (method) {
    case 'delivery':
      return l10n.scmDelivery;
    case 'pickup':
      return l10n.scmPickup;
    default:
      return '—';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Filter sheet (slides up; Date Range, Movement Type, Supply Chain Stage)
// ═════════════════════════════════════════════════════════════════════════════

/// Every option shows how many records it would give with the OTHER selections
/// in this sheet and the search text applied, so a count is never a surprise.
class _SupplyFilterSheet extends StatefulWidget {
  const _SupplyFilterSheet({
    required this.records,
    required this.query,
    required this.range,
    required this.stage,
    required this.flow,
  });

  final List<SupplyChainRecord> records;
  final String query;
  final SupplyDateRange range;
  final SupplyStageFilter stage;
  final SupplyFlowFilter flow;

  @override
  State<_SupplyFilterSheet> createState() => _SupplyFilterSheetState();
}

class _SupplyFilterSheetState extends State<_SupplyFilterSheet> {
  late SupplyDateRange _range = widget.range;
  late SupplyStageFilter _stage = widget.stage;
  /// Chosen with the movement chips on the main screen; here it only shapes the counts.
  SupplyFlowFilter get _flow => widget.flow;

  int _count({
    SupplyDateRange? range,
    SupplyStageFilter? stage,
  }) => filterSupplyRecords(
    widget.records,
    range: range ?? _range,
    stage: stage ?? _stage,
    flow: _flow,
    query: widget.query,
  ).length;

  Widget _section<T>({
    required String title,
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required int Function(T) count,
    required ValueChanged<T> onSelected,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: cs.outline,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in values)
                GestureDetector(
                  onTap: () => setState(() => onSelected(v)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: v == selected
                          ? cs.primary
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                    ),
                    child: Text(
                      '${label(v)} (${count(v)})',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: v == selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: v == selected
                            ? Colors.white
                            : cs.onSurfaceVariant,
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return ManagementModalShell(
      title: l10n.scmFilterTitle,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section<SupplyDateRange>(
            title: l10n.scmFilterDateRange,
            values: SupplyDateRange.values,
            selected: _range,
            label: (v) => supplyDateRangeLabel(l10n, v),
            count: (v) => _count(range: v),
            onSelected: (v) => _range = v,
          ),
          _section<SupplyStageFilter>(
            title: l10n.scmFilterStage,
            values: SupplyStageFilter.values,
            selected: _stage,
            label: (v) => supplyStageFilterLabel(l10n, v),
            count: (v) => _count(stage: v),
            onSelected: (v) => _stage = v,
          ),
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: cs.outline.withValues(alpha: 0.30)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              onPressed: () => setState(() {
                _range = SupplyDateRange.allTime;
                _stage = SupplyStageFilter.all;
              }),
              child: Text(
                l10n.farmerMgmtResetAll,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(
                _SupplyFilterResult(_range, _stage),
              ),
              child: Text(
                l10n.farmerMgmtApplyFilters,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Card
// ═════════════════════════════════════════════════════════════════════════════

/// A status pill: the order status for an order (it is being fulfilled), else
/// whether the supply came in or went out.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.record});

  final SupplyChainRecord record;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final r = record;
    if (r.isOrder && r.fulfillmentStatus != null) {
      return ReportStatusPill(
        label: buyerOrderStatusLabel(r.fulfillmentStatus!, l10n),
        color: orderStatusColor(r.fulfillmentStatus!),
      );
    }
    return ReportStatusPill(
      label: r.isIncoming ? l10n.scmFlowIncoming : l10n.scmFlowOutgoing,
      color: r.isIncoming ? AppConstants.successGreen : AppConstants.buyerBlue,
    );
  }
}

class _PartyCell extends StatelessWidget {
  const _PartyCell({required this.party, required this.style});

  final SupplyParty party;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Text(
        supplyPartyText(l10n, party),
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _SupplyCard extends StatelessWidget {
  const _SupplyCard({required this.record, required this.onTap});

  final SupplyChainRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final r = record;
    final color = supplyStageColor(r.stage);
    final dateFmt = DateFormat('MMM d, yyyy');

    final meta = <String>[
      dateFmt.format(r.occurredAt),
      if (r.reference != null) r.reference!,
      if (r.programName != null) r.programName!,
      if (r.batchNumber != null) formatBatchNumber(r.batchNumber),
      if (r.fulfillmentMethod != null)
        supplyFulfillmentLabel(l10n, r.fulfillmentMethod),
    ];

    return ReportRecordCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Icon(supplyStageIcon(r.stage), size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  supplyTypeLabel(l10n, r.type),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              _StatusPill(record: r),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  r.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${r.isIncoming ? '+' : '−'}${formatQuantityUnit(r.quantity, r.unit)}',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: r.isIncoming
                      ? AppConstants.successGreen
                      : AppConstants.buyerBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _RouteRow(record: r),
          const SizedBox(height: 10),
          _StageStepper(stage: r.stage),
          const SizedBox(height: 8),
          Text(
            meta.join('  ·  '),
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// From → To, each with its role above the name.
class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.record});

  final SupplyChainRecord record;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _Party(party: record.from)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward_rounded, size: 18, color: cs.outline),
        ),
        Expanded(child: _Party(party: record.to, alignEnd: true)),
      ],
    );
  }
}

class _Party extends StatelessWidget {
  const _Party({required this.party, this.alignEnd = false});

  final SupplyParty party;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          supplyRoleLabel(l10n, party.role).toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: cs.outline,
          ),
        ),
        Text(
          supplyPartyText(l10n, party),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Where a record sits on the journey: Source → Program → Purchase → Consumer.
/// A loan is another transaction type, outside that sequence, so it shows none.
class _StageStepper extends StatelessWidget {
  const _StageStepper({required this.stage});

  final SupplyStage stage;

  @override
  Widget build(BuildContext context) {
    if (stage == SupplyStage.other) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final steps = <(SupplyStage, String)>[
      (SupplyStage.source, l10n.scmStepSource),
      (SupplyStage.program, l10n.scmStepProgram),
      (SupplyStage.offer, l10n.scmStepPurchase),
      (SupplyStage.consumer, l10n.scmStepConsumer),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: cs.outline.withValues(alpha: 0.20),
              ),
            ),
          _StepDot(
            label: steps[i].$2,
            color: supplyStageColor(steps[i].$1),
            active: steps[i].$1 == stage,
          ),
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.label,
    required this.color,
    required this.active,
  });

  final String label;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: active ? 14 : 10,
          height: active ? 14 : 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? color : Colors.transparent,
            border: Border.all(
              color: active ? color : cs.outline.withValues(alpha: 0.40),
              width: 2,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? color : cs.outline,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Detail sheet
// ═════════════════════════════════════════════════════════════════════════════

class _SupplyDetailSheet extends StatelessWidget {
  const _SupplyDetailSheet({required this.record, required this.related});

  final SupplyChainRecord record;
  final List<SupplyChainRecord> related;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final r = record;
    final color = supplyStageColor(r.stage);
    final dateFmt = DateFormat('MMM d, yyyy · h:mm a');

    final details = <(String, String)>[
      (l10n.scmLabelDate, dateFmt.format(r.occurredAt)),
      (l10n.scmLabelStage, supplyRecordStageLabel(l10n, r)),
      (l10n.scmLabelType, supplyTypeLabel(l10n, r.type)),
      (l10n.scmLabelItem, r.itemName),
      if (r.category != null) (l10n.scmLabelCategory, r.category!),
      if (r.itemType != null) (l10n.invItemTypeLabel, itemTypeLabel(l10n, r.itemType)),
      if (r.cropName != null) (l10n.scmLabelCrop, r.cropName!),
      (l10n.scmLabelQuantity, formatQuantityUnit(r.quantity, r.unit)),
      // The stock the supply came from or left: a Cooperative Inventory item, or
      // (a Farmer Marketplace sale) the Farmer's own harvest batch.
      if (r.inventoryId != null)
        (l10n.scmLabelInventory, '${l10n.scmPartyCooperative} · ${r.itemName}')
      else if (r.type == SupplyRecordType.marketplaceSale)
        (l10n.scmLabelInventory, l10n.scmInventoryFarmerStock),
      if (r.itemSource != null) (l10n.scmLabelItemSource, r.itemSource!),
      if (r.farmerName != null) (l10n.scmLabelFarmer, r.farmerName!),
      if (r.programName != null) (l10n.scmLabelProgram, r.programName!),
      if (r.reference != null) (l10n.scmLabelReference, r.reference!),
      if (r.batchNumber != null)
        (l10n.scmLabelBatch, formatBatchNumber(r.batchNumber)),
      if (r.fulfillmentMethod != null)
        (
          l10n.scmLabelFulfillment,
          supplyFulfillmentLabel(l10n, r.fulfillmentMethod),
        ),
      if (r.isOrder && r.fulfillmentStatus != null)
        (
          l10n.scmLabelStatus,
          buyerOrderStatusLabel(r.fulfillmentStatus!, l10n),
        )
      else
        (
          l10n.scmLabelStatus,
          r.isConfirmed ? l10n.scmStateMoved : l10n.scmStateInProgress,
        ),
    ];

    // The movement of the same stock, oldest first, with this record in place.
    final movement = [...related, r]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXl),
          ),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Icon(supplyStageIcon(r.stage), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        supplyTypeLabel(l10n, r.type),
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      Text(
                        r.itemName,
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(record: r),
              ],
            ),
            const SizedBox(height: 16),
            _SectionTitle(l10n.scmJourneyTitle),
            _StageStepper(stage: r.stage),
            if (r.stage == SupplyStage.other)
              Text(
                l10n.scmStageFilterLoans,
                style: GoogleFonts.inter(fontSize: 12, color: cs.outline),
              ),
            const SizedBox(height: 16),
            _SectionTitle(l10n.scmRouteTitle),
            Container(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: _RouteRow(record: r),
            ),
            const SizedBox(height: 16),
            _SectionTitle(l10n.scmDetailsTitle),
            for (final d in details) _DetailRow(label: d.$1, value: d.$2),
            const SizedBox(height: 16),
            _SectionTitle(l10n.scmMovementTitle),
            Text(
              l10n.scmMovementSubtitle,
              style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
            ),
            const SizedBox(height: 8),
            if (related.isEmpty)
              Text(
                l10n.scmMovementEmpty,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              )
            else
              for (final m in movement)
                _MovementRow(record: m, isCurrent: m.key == r.key),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: cs.onSurfaceVariant,
        ),
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, color: cs.outline),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.record, required this.isCurrent});

  final SupplyChainRecord record;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final r = record;
    final color = supplyStageColor(r.stage);
    final who = r.isIncoming
        ? supplyPartyText(l10n, r.from)
        : supplyPartyText(l10n, r.to);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isCurrent ? color.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
        border: Border.all(
          color: isCurrent ? color : cs.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            r.isIncoming ? Icons.south_west_rounded : Icons.north_east_rounded,
            size: 16,
            color: r.isIncoming
                ? AppConstants.successGreen
                : AppConstants.buyerBlue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supplyTypeLabel(l10n, r.type),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  '${DateFormat('MMM d, yyyy').format(r.occurredAt)}  ·  $who'
                  '${isCurrent ? '  ·  ${l10n.scmThisRecord}' : ''}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${r.isIncoming ? '+' : '−'}${formatQuantityUnit(r.quantity, r.unit)}',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: r.isIncoming
                  ? AppConstants.successGreen
                  : AppConstants.buyerBlue,
            ),
          ),
        ],
      ),
    );
  }
}
