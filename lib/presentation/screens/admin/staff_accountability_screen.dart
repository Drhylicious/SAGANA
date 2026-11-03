import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/member_activity_label.dart';
import '../../../core/utils/staff_log_filters.dart';
import '../../../data/models/staff_action_model.dart';
import '../../../data/repositories/admin_activity_repository.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import 'admin_activity_screen.dart' show moduleColor, moduleIcon;

/// Staff Accountability: every change a Manager or Officer made to an audited
/// table — who (name and role), what, which record, the values before and
/// after, and when. Read from admin_activity_log rows the database itself wrote
/// (source 'db'), so it is complete whichever screen made the change and cannot
/// be edited from the app.
class StaffAccountabilityScreen extends StatefulWidget {
  const StaffAccountabilityScreen({super.key});

  @override
  State<StaffAccountabilityScreen> createState() =>
      _StaffAccountabilityScreenState();
}

class _StaffAccountabilityScreenState extends State<StaffAccountabilityScreen> {
  static const _pageSize = 30;
  // The "All staff" choice in the dropdown (a real value, so the field stays bound).
  static const _allStaff = '__all__';

  final _repo = AdminActivityRepository();
  final List<StaffActionEntry> _entries = [];
  List<StaffOption> _staff = const [];
  String? _staffId;
  // The tab (or Broadcast / System) and, inside a tab, one of its features.
  StaffLogGroup? _group;
  StaffLogFeature? _feature;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _loadStaff();
    _reload();
  }

  Future<void> _loadStaff() async {
    try {
      final staff = await _repo.fetchStaffOptions();
      if (mounted) setState(() => _staff = staff);
    } catch (_) {
      // The filter is a convenience; the log still loads without it.
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await _repo.fetchStaffActions(
        limit: _pageSize,
        staffId: _staffId,
        scope: StaffLogScope.of(_group, _feature),
      );
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(page);
        _hasMore = page.length == _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.fetchStaffActions(
        limit: _pageSize,
        offset: _entries.length,
        staffId: _staffId,
        scope: StaffLogScope.of(_group, _feature),
      );
      if (!mounted) return;
      setState(() {
        _entries.addAll(page);
        _hasMore = page.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(
            title: l10n.staffAccountabilityTitle,
            onBack: () => context.pop(),
          ),
          _filters(l10n, cs),
          Expanded(child: _body(l10n, cs)),
        ],
      ),
    );
  }

  void _pickGroup(StaffLogGroup? group) {
    if (group?.key == _group?.key && _feature == null) return;
    setState(() {
      _group = group;
      _feature = null;
    });
    _reload();
  }

  void _pickFeature(StaffLogFeature? feature) {
    if (feature?.key == _feature?.key) return;
    setState(() => _feature = feature);
    _reload();
  }

  void _pickStaff(String? id) {
    final next = id == _allStaff ? null : id;
    if (next == _staffId) return;
    setState(() => _staffId = next);
    _reload();
  }

  Widget _filters(AppLocalizations l10n, ColorScheme cs) {
    final group = _group;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppDropdownField<String>(
              key: const ValueKey('staff-filter'),
              value: _staffId ?? _allStaff,
              hintText: l10n.staffAccountabilityAllStaff,
              items: [_allStaff, for (final s in _staff) s.id],
              itemLabel: (id) {
                if (id == _allStaff) return l10n.staffAccountabilityAllStaff;
                final s = _staff.firstWhere((s) => s.id == id);
                return '${s.name} · ${_roleLabel(l10n, s.role)}';
              },
              onChanged: _pickStaff,
            ),
          ),
          const SizedBox(height: 12),
          // One row to swipe: the five tabs, then (after a divider) Broadcast and System.
          _ChipRow(
            key: const ValueKey('log-chip-row'),
            children: [
              _FilterPill(
                key: const ValueKey('log-chip-all'),
                label: l10n.staffAccountabilityAllModules,
                selected: group == null,
                onTap: () => _pickGroup(null),
              ),
              for (final g in staffLogPrimaryGroups)
                _FilterPill(
                  key: ValueKey('log-chip-${g.key}'),
                  label: staffLogGroupLabel(l10n, g.key),
                  selected: group?.key == g.key,
                  onTap: () => _pickGroup(g),
                ),
              Container(
                width: 1,
                height: 22,
                color: cs.outline.withValues(alpha: 0.35),
              ),
              for (final g in staffLogSecondaryGroups)
                _FilterPill(
                  key: ValueKey('log-chip-${g.key}'),
                  label: staffLogGroupLabel(l10n, g.key),
                  selected: group?.key == g.key,
                  onTap: () => _pickGroup(g),
                ),
            ],
          ),
          // The features of the chosen tab: a second row to swipe.
          if (group != null && group.features.length > 1) ...[
            const SizedBox(height: 8),
            _ChipRow(
              key: const ValueKey('log-feature-row'),
              children: [
                _FilterPill(
                  key: const ValueKey('log-feature-all'),
                  label: l10n.staffLogFeatureAll,
                  selected: _feature == null,
                  small: true,
                  onTap: () => _pickFeature(null),
                ),
                for (final f in group.features)
                  _FilterPill(
                    key: ValueKey('log-feature-${f.key}'),
                    label: staffLogFeatureLabel(l10n, f.key),
                    selected: _feature?.key == f.key,
                    small: true,
                    onTap: () => _pickFeature(f),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(AppLocalizations l10n, ColorScheme cs) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(16), child: SkeletonList());
    }
    if (_failed) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                l10n.staffAccountabilityLoadError,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                l10n.staffAccountabilityEmpty,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _entries.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i == _entries.length) {
            _loadMore();
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return _EntryCard(entry: _entries[i]);
        },
      ),
    );
  }
}

String _roleLabel(AppLocalizations l10n, String? role) => role == 'admin'
    ? l10n.staffRoleManager
    : role == 'system'
        ? l10n.staffLogSystem
        : l10n.staffRoleOfficer;

/// The name of a tab (or Broadcast / System) as the filter chip shows it.
String staffLogGroupLabel(AppLocalizations l10n, String key) {
  switch (key) {
    case 'dashboard':
      return l10n.adminNavDashboard;
    case 'members':
      return l10n.adminNavMembers;
    case 'marketplace':
      return l10n.navMarketplace;
    case 'loans':
      return l10n.adminNavLoans;
    case 'reports':
      return l10n.adminNavReports;
    case 'broadcast':
      return l10n.staffLogBroadcast;
    case 'system':
      return l10n.staffLogSystem;
  }
  return key;
}

/// The name of one feature of a tab, as the second row of chips shows it.
String staffLogFeatureLabel(AppLocalizations l10n, String key) {
  switch (key) {
    case 'inventory':
      return l10n.adminInvManagementTitle;
    case 'crops':
      return l10n.cropMgmtTitle;
    case 'programs':
      return l10n.programMgmtTitle;
    case 'prices':
      return l10n.buyerNavPrices;
    case 'loanItems':
      return l10n.loanItemCatalogTitle;
    case 'accounts':
      return l10n.staffLogFeatureAccounts;
    case 'contributions':
      return l10n.staffLogFeatureContributions;
    case 'officerAccess':
      return l10n.staffLogFeatureOfficerAccess;
    case 'listings':
      return l10n.adminNavListings;
    case 'orders':
      return l10n.statOrders;
    case 'offers':
      return l10n.offerCoopTitle;
    case 'marketLinking':
      return l10n.marketLinkTitle;
    case 'loansIssued':
      return l10n.staffLogFeatureLoansIssued;
    case 'payments':
      return l10n.staffLogFeaturePayments;
    case 'loanRequests':
      return l10n.staffLogFeatureLoanRequests;
    case 'loanPolicy':
      return l10n.staffLogFeatureLoanPolicy;
    case 'balik':
      return l10n.reportsBalikTangkilikManagement;
    case 'exports':
      return l10n.reportsExportCenter;
  }
  return key;
}

/// A row of chips that scrolls sideways (swipe, or drag with a mouse). The first
/// chip lines up with the page edge; the last one can scroll clear of it.
class _ChipRow extends StatelessWidget {
  const _ChipRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
        scrollbars: false,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// A tappable filter chip: filled when chosen, outlined otherwise. A plain
/// InkWell, so one tap always selects it (no horizontal scrolling to find it).
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.small = false,
  });

  final String label;
  final bool selected;
  final bool small;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? AppConstants.primaryGreen : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? AppConstants.primaryGreen : cs.outline.withValues(alpha: 0.35),
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: small ? 12 : 14, vertical: small ? 6 : 8),
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: small ? 11.5 : 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _operationLabel(AppLocalizations l10n, String operation) {
  switch (operation) {
    case 'created':
      return l10n.staffAccountabilityActionCreated;
    case 'deleted':
      return l10n.staffAccountabilityActionDeleted;
    default:
      return l10n.staffAccountabilityActionUpdated;
  }
}

class _EntryCard extends StatefulWidget {
  const _EntryCard({required this.entry});

  final StaffActionEntry entry;

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final e = widget.entry;
    final accent = moduleColor(e.module, cs);
    final when = MaterialLocalizations.of(context).formatMediumDate(
      e.timestamp.toLocal(),
    );
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(e.timestamp.toLocal()),
    );

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: AppConstants.cardBorder,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(moduleIcon(e.module), size: 18, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          staffActionHeadline(e, l10n),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: cs.onSurface,
                          ),
                        ),
                        if (staffActionDetail(e, l10n) != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            staffActionDetail(e, l10n)!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              height: 1.35,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          e.staffRole == 'system'
                              ? l10n.staffLogSystem
                              : '${e.staffName ?? '—'} · ${_roleLabel(l10n, e.staffRole)}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$when · $time · ${staffLogGroupLabel(l10n, staffLogGroupKeyOf(e.tableName, e.module))}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
              if (_open) ...[
                const SizedBox(height: 10),
                Divider(color: cs.outline.withValues(alpha: 0.15), height: 1),
                const SizedBox(height: 10),
                _detail(l10n, cs, e),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(AppLocalizations l10n, ColorScheme cs, StaffActionEntry e) {
    final style = GoogleFonts.inter(fontSize: 12, color: cs.onSurface);
    final dim = GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_operationLabel(l10n, e.operation)} · ${e.tableName ?? ''}',
          style: dim,
        ),
        if ((e.reference ?? e.recordId) != null) ...[
          const SizedBox(height: 6),
          Text('${l10n.staffAccountabilityRecord}: ${e.reference ?? e.recordId}',
              style: style),
        ],
        const SizedBox(height: 8),
        for (final c in e.changes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.column, style: dim),
                if (e.operation == 'updated')
                  Text(
                    '${l10n.staffAccountabilityBefore}: ${_show(c.before)}\n'
                    '${l10n.staffAccountabilityAfter}: ${_show(c.after)}',
                    style: style,
                  )
                else
                  Text(_show(e.operation == 'deleted' ? c.before : c.after),
                      style: style),
              ],
            ),
          ),
      ],
    );
  }

  static String _show(Object? v) {
    if (v == null) return '—';
    final s = v.toString();
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }
}
