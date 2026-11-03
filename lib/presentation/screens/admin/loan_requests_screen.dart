import '../../widgets/view_only_banner.dart';
import '../../../data/services/staff_permission_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/bod_schedule_utils.dart';
import '../../../core/utils/db_error_utils.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/loan_request_model.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/table_change_watcher.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/loan_choice_chip.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/workflow_history_sheet.dart';

/// Loan Requests — Manager / Officer.
///
/// The requests Farmers send from Farm Records > Input Loans > Request a Loan.
/// Each shows what was asked for, the stock on hand right now, and — once decided —
/// which Manager or Officer decided, when, and why. Approving issues the loan
/// through the same issue_loan() every loan uses (stock, inventory log, reference
/// number and the Farmer's notice are unchanged); disapproving needs a reason the
/// Farmer is shown. Deciding needs a connection: the stock and the rules are
/// checked on the server at that moment.
///
/// Route: /admin/loans/requests (also where the "New Loan Request" notice goes).
class LoanRequestsScreen extends StatefulWidget {
  const LoanRequestsScreen({super.key});

  @override
  State<LoanRequestsScreen> createState() => _LoanRequestsScreenState();
}

class _LoanRequestsScreenState extends State<LoanRequestsScreen> {
  final _repo = AdminLoanRepository();
  final _searchCtrl = TextEditingController();
  TableChangeWatcher? _watcher;

  List<LoanRequestModel> _all = [];
  String _search = '';
  String? _statusFilter = 'pending'; // null = All
  bool _loading = true;
  bool _failed = false;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _load();
    // A request arriving or being decided elsewhere appears without a refresh.
    _watcher = TableChangeWatcher(
      tables: const ['loan_requests'],
      onChange: () {
        if (mounted) _load(silent: true);
      },
    )..start();
  }

  @override
  void dispose() {
    _watcher?.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final rows = await _repo.fetchLoanRequests();
      if (!mounted) return;
      setState(() {
        _all = rows;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _failed = true;
      });
    }
  }

  /// The requests that match the search box. A request the Farmer withdrew
  /// (cancelled) is not listed: there is nothing left to decide on, and its history
  /// stays on record. The search looks at the Farmer's name and phone, the request
  /// and loan numbers, the items, and the staff member who decided.
  List<LoanRequestModel> get _searched {
    final q = _search.trim().toLowerCase();
    return _all.where((r) {
      if (r.isCancelled) return false;
      if (q.isEmpty) return true;
      final haystack = [
        r.farmerName,
        r.farmerPhone,
        r.requestNo,
        r.loanReference,
        r.reviewerName,
        for (final i in r.items) i.itemName,
      ].whereType<String>().join(' ').toLowerCase();
      return q.split(RegExp(r's+')).where((w) => w.isNotEmpty).every(haystack.contains);
    }).toList();
  }

  List<LoanRequestModel> get _visible => _statusFilter == null
      ? _searched
      : _searched.where((r) => r.status == _statusFilter).toList();

  /// The number on a chip: how many of the searched requests it would show, so the
  /// counts always match the list.
  int _count(String? status) => status == null
      ? _searched.length
      : _searched.where((r) => r.status == status).length;

  Future<void> _approve(LoanRequestModel request) async {
    if (!requireManage(context, StaffModule.loans)) return;
    final l10n = AppLocalizations.of(context);
    final ref = await showManagementModal<String>(
      context: context,
      builder: (_) => _ApproveSheet(request: request, repo: _repo),
    );
    if (ref == null || !mounted) return;
    AppToast.show(context, l10n.loanReqApprovedDone(ref));
    _load(silent: true);
  }

  Future<void> _disapprove(LoanRequestModel request) async {
    if (!requireManage(context, StaffModule.loans)) return;
    final l10n = AppLocalizations.of(context);
    final done = await showManagementModal<bool>(
      context: context,
      builder: (_) => _DisapproveSheet(request: request, repo: _repo),
    );
    if (done != true || !mounted) return;
    AppToast.show(context, l10n.loanReqDisapprovedDone);
    _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final visible = _visible;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(title: l10n.loanReqAdminTitle, onBack: () => context.pop()),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              style: GoogleFonts.inter(fontSize: 14, color: cs.onSurface),
              decoration: InputDecoration(
                hintText: l10n.loanReqAdminSearchHint,
                hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
                prefixIcon: Icon(Icons.search_rounded, color: cs.outline, size: 22),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded, color: cs.outline, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
          SizedBox(
            height: 54,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = <({String? status, String label})>[
                  (status: null, label: l10n.loanReqFilterAllCount(_count(null))),
                  (status: 'pending', label: l10n.loanReqFilterPendingCount(_count('pending'))),
                  (status: 'approved', label: l10n.loanReqFilterApprovedCount(_count('approved'))),
                  (status: 'disapproved', label: l10n.loanReqFilterDisapprovedCount(_count('disapproved'))),
                ][i];
                return Center(
                  child: LoanChoiceChip(
                    label: f.label,
                    selected: _statusFilter == f.status,
                    selectedColor: AppConstants.primaryGreen,
                    showCheckmark: false,
                    onTap: () => setState(() => _statusFilter = f.status),
                  ),
                );
              },
            ),
          ),
          if (!_isOnline)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppConstants.warningAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded, size: 16, color: AppConstants.snackbarWarning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.loanReqNeedsOnline,
                      style: GoogleFonts.inter(fontSize: 12, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Padding(padding: EdgeInsets.all(20), child: SkeletonList())
                  : _failed
                  ? _Message(
                      icon: Icons.error_outline_rounded,
                      title: l10n.loanReqAdminLoadFailed,
                      body: l10n.loanReqLoadFailedBody,
                      actionLabel: l10n.retry,
                      onAction: _load,
                    )
                  : visible.isEmpty
                  ? _Message(
                      icon: Icons.inbox_outlined,
                      title: l10n.loanReqAdminEmpty,
                      body: l10n.loanReqAdminEmptyBody,
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _RequestCard(
                        request: visible[i],
                        canDecide: _isOnline,
                        onApprove: () => _approve(visible[i]),
                        onDisapprove: () => _disapprove(visible[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 40),
        Icon(icon, size: 44, color: cs.outline),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: cs.onSurfaceVariant),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 14),
          Center(child: OutlinedButton(onPressed: onAction, child: Text(actionLabel!))),
        ],
      ],
    );
  }
}

({String label, Color color}) _statusStyle(AppLocalizations l10n, LoanRequestModel r) {
  if (r.isApproved) return (label: l10n.loanReqStatusApproved, color: AppConstants.successGreen);
  if (r.isDisapproved) return (label: l10n.loanReqStatusDisapproved, color: AppConstants.errorRed);
  if (r.isCancelled) return (label: l10n.loanReqStatusCancelled, color: AppConstants.outline);
  return (label: l10n.loanReqStatusPending, color: AppConstants.warningAmber);
}

class _RequestCard extends StatelessWidget {
  final LoanRequestModel request;
  final bool canDecide;
  final VoidCallback onApprove;
  final VoidCallback onDisapprove;

  const _RequestCard({
    required this.request,
    required this.canDecide,
    required this.onApprove,
    required this.onDisapprove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final r = request;
    final style = _statusStyle(l10n, r);
    final money = NumberFormat('#,##0.00');
    final date = DateFormat('MMM d, yyyy');
    final reviewer = (r.reviewerName ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: r.isPending && r.hasStockShortage
              ? AppConstants.errorRed.withValues(alpha: 0.35)
              : cs.outline.withValues(alpha: 0.12),
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (r.farmerName ?? '').isEmpty ? '—' : r.farmerName!,
                      style: GoogleFonts.poppins(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      [
                        r.requestNo,
                        if ((r.farmerPhone ?? '').isNotEmpty) r.farmerPhone!,
                      ].join(' · '),
                      style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  style.label,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: style.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final i in r.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i.itemName} × ${formatQuantityUnit(i.quantity, i.unit)}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        if (r.isPending && i.stockOnHand != null)
                          Text(
                            i.shortOnStock
                                ? l10n.loanReqStockShort(formatQuantityUnit(i.stockOnHand!, i.unit))
                                : l10n.loanReqInStock(formatQuantityUnit(i.stockOnHand!, i.unit)),
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: i.shortOnStock
                                  ? AppConstants.errorRed
                                  : AppConstants.successGreen,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '₱${money.format(i.lineTotal)}',
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                ],
              ),
            ),
          const Divider(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.loanReqRequestedOn(date.format(r.requestedAt)),
                  style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ),
              Text(
                '₱${money.format(r.totalValue)}',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.primaryGreen,
                ),
              ),
            ],
          ),
          if ((r.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${l10n.loanReqFarmerNote}: ${r.notes!.trim()}',
              style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: cs.onSurface),
            ),
          ],
          if (r.isPending && r.hasStockShortage) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: AppConstants.errorRed),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.loanReqStockWarning,
                    style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: AppConstants.errorRed),
                  ),
                ),
              ],
            ),
          ],
          if (r.isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: canDecide ? onDisapprove : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppConstants.errorRed,
                      side: BorderSide(
                        color: canDecide
                            ? AppConstants.errorRed.withValues(alpha: 0.6)
                            : cs.outline.withValues(alpha: 0.3),
                      ),
                      minimumSize: const Size.fromHeight(44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(l10n.loanReqDisapprove, maxLines: 1),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: canDecide && !r.hasStockShortage ? onApprove : null,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(l10n.loanReqApprove, maxLines: 1),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Decided (or withdrawn): who, when and why — for staff only.
            const SizedBox(height: 10),
            if (r.isApproved || r.isDisapproved)
              Text(
                (r.isApproved ? l10n.loanReqApprovedBy : l10n.loanReqDisapprovedBy)(
                  reviewer.isEmpty ? '—' : reviewer,
                  r.decidedAt == null ? '' : date.format(r.decidedAt!),
                ),
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface),
              ),
            if (r.isApproved && (r.loanReference ?? '').isNotEmpty)
              Text(
                l10n.loanReqLoanIssuedRef(r.loanReference!),
                style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            if ((r.decisionNote ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${l10n.loanReqDecisionReason}: ${r.decisionNote!.trim()}',
                  style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
                ),
              ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => showWorkflowHistorySheet(
                context,
                entityType: 'loan_request',
                entityId: r.id,
                title: r.requestNo,
              ),
              icon: const Icon(Icons.history_rounded, size: 16),
              label: Text(l10n.wfHistoryAction),
              style: TextButton.styleFrom(
                foregroundColor: AppConstants.primaryGreen,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Approve ─────────────────────────────────────────────────────────────────

class _ApproveSheet extends StatefulWidget {
  final LoanRequestModel request;
  final AdminLoanRepository repo;
  const _ApproveSheet({required this.request, required this.repo});

  @override
  State<_ApproveSheet> createState() => _ApproveSheetState();
}

class _ApproveSheetState extends State<_ApproveSheet> {
  final _monthlyCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _error;
  String? _fieldError;
  bool _saving = false;

  // The first payment falls on the next BOD Saturday, exactly as when a loan is
  // issued by hand (Issue New Loan does the same).
  final DateTime _firstPayment = BodSchedule.upcoming();

  @override
  void dispose() {
    _monthlyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final monthly = double.tryParse(_monthlyCtrl.text.trim()) ?? 0;
    if (monthly <= 0 || monthly > widget.request.totalValue + 0.004) {
      setState(() => _fieldError = l10n.loanReqMonthlyInvalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldError = null;
    });
    try {
      final result = await widget.repo.approveLoanRequest(
        request: widget.request,
        monthlyPayment: monthly,
        nextPaymentDate: _firstPayment,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, result.referenceNo);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final r = widget.request;
    return ManagementModalShell(
      title: l10n.loanReqApproveTitle,
      subtitle: '${r.farmerName ?? ''} · ${r.requestNo}',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final i in r.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• ${i.itemName} × ${formatQuantityUnit(i.quantity, i.unit)}',
                style: GoogleFonts.inter(fontSize: 12.5, color: cs.onSurface),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '${l10n.loanReqTotal}: ₱${NumberFormat('#,##0.00').format(r.totalValue)}',
            style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _monthlyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}(\.\d{0,2})?$'))],
            enabled: !_saving,
            onChanged: (_) => setState(() => _fieldError = null),
            decoration: InputDecoration(
              labelText: l10n.loanReqMonthlyLabel,
              prefixText: '₱ ',
              errorText: _fieldError,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.loanReqFirstPayment(DateFormat('MMMM d, yyyy').format(_firstPayment)),
            style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            maxLength: 200,
            enabled: !_saving,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.loanReqApproveNote,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.loanReqApproveHint,
            style: GoogleFonts.inter(fontSize: 11.5, height: 1.4, color: cs.onSurfaceVariant),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppConstants.errorRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Text(_error!, style: GoogleFonts.inter(fontSize: 12.5, color: AppConstants.errorRed)),
            ),
          ],
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: l10n.loanReqApprove,
        isLoading: _saving,
        onPrimary: _save,
      ),
    );
  }
}

// ─── Disapprove ──────────────────────────────────────────────────────────────

class _DisapproveSheet extends StatefulWidget {
  final LoanRequestModel request;
  final AdminLoanRepository repo;
  const _DisapproveSheet({required this.request, required this.repo});

  @override
  State<_DisapproveSheet> createState() => _DisapproveSheetState();
}

class _DisapproveSheetState extends State<_DisapproveSheet> {
  final _reasonCtrl = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final reason = _reasonCtrl.text.trim();
    if (reason.length < 3) {
      setState(() => _error = l10n.loanReqReasonRequired);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repo.disapproveLoanRequest(request: widget.request, reason: reason);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ManagementModalShell(
      title: l10n.loanReqDisapproveTitle,
      subtitle: '${widget.request.farmerName ?? ''} · ${widget.request.requestNo}',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _reasonCtrl,
            maxLines: 3,
            maxLength: 300,
            autofocus: true,
            enabled: !_saving,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              labelText: l10n.loanReqDisapproveReasonLabel,
              errorText: _error,
              errorMaxLines: 3,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
            ),
          ),
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: l10n.loanReqDisapprove,
        isDestructive: true,
        isLoading: _saving,
        onPrimary: _save,
      ),
    );
  }
}
