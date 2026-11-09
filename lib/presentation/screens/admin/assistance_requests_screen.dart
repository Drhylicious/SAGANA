import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../data/models/program_assistance_model.dart';
import '../../../data/repositories/program_assistance_repository.dart';
import '../../../data/services/staff_permission_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/view_only_banner.dart';

/// Failed-program assistance requests, reached from Loan Requests. They are not
/// loans: approving one deducts the stock and issues an LRN reference, nothing
/// else. Route: /admin/loans/assistance
class AssistanceRequestsScreen extends StatefulWidget {
  const AssistanceRequestsScreen({super.key});

  @override
  State<AssistanceRequestsScreen> createState() => _AssistanceRequestsScreenState();
}

class _AssistanceRequestsScreenState extends State<AssistanceRequestsScreen> {
  final _repo = ProgramAssistanceRepository();
  List<AssistanceRequest> _all = [];
  String? _filter = 'pending'; // null = all
  bool _loading = true;
  bool _failed = false;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await _repo.fetchAll();
      if (!mounted) return;
      setState(() {
        _all = rows;
        _loading = false;
      });
    } catch (e, st) {
      friendlyError(AppLocalizations.of(context), e, st); // logged for developers
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  List<AssistanceRequest> get _visible =>
      _filter == null ? _all : _all.where((r) => r.status == _filter).toList();

  int _count(String? s) => s == null ? _all.length : _all.where((r) => r.status == s).length;

  String _qty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  String _itemsText(AssistanceRequest r) =>
      r.items.map((i) => '${_qty(i.quantity)} ${i.unit} ${i.itemName}').join(', ');

  Future<void> _approve(AssistanceRequest r) async {
    if (!requireManage(context, StaffModule.loans)) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.assistApproveTitle),
        content: Text(l10n.assistApproveBody(_itemsText(r))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.retCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.assistApprove)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyId = r.id);
    try {
      final ref = await _repo.review(requestId: r.id, approve: true);
      if (!mounted) return;
      AppToast.show(context, l10n.assistApproved(ref ?? ''));
      await _load();
    } catch (e, st) {
      if (mounted) AppToast.show(context, friendlyError(l10n, e, st), isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reject(AssistanceRequest r) async {
    if (!requireManage(context, StaffModule.loans)) return;
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController();
    String? error;
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(l10n.assistRejectTitle),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            maxLength: 300,
            decoration: InputDecoration(
              labelText: l10n.assistRejectReason,
              errorText: error,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.retCancel)),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isEmpty) {
                  setLocal(() => error = l10n.retReasonRequired);
                  return;
                }
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: Text(l10n.assistReject),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (note == null || !mounted) return;
    setState(() => _busyId = r.id);
    try {
      await _repo.review(requestId: r.id, approve: false, note: note);
      if (!mounted) return;
      AppToast.show(context, l10n.assistRejected);
      await _load();
    } catch (e, st) {
      if (mounted) AppToast.show(context, friendlyError(l10n, e, st), isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final filters = <({String? status, String label})>[
      (status: 'pending', label: l10n.assistFilterPending(_count('pending'))),
      (status: 'approved', label: l10n.assistFilterApproved(_count('approved'))),
      (status: 'rejected', label: l10n.assistFilterRejected(_count('rejected'))),
      (status: null, label: l10n.assistFilterAll(_count(null))),
    ];
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(title: l10n.assistStaffTitle, onBack: () => context.pop()),
          SizedBox(
            height: 54,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              itemCount: filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => Center(
                child: ChoiceChip(
                  label: Text(filters[i].label),
                  selected: _filter == filters[i].status,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = filters[i].status),
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Padding(padding: EdgeInsets.all(20), child: SkeletonList())
                  : _failed
                      ? ListView(children: [
                          const SizedBox(height: 80),
                          Center(child: Text(l10n.assistLoadFailed)),
                          Center(child: TextButton(onPressed: _load, child: Text(l10n.retry))),
                        ])
                      : _visible.isEmpty
                          ? ListView(children: [
                              const SizedBox(height: 80),
                              Icon(Icons.inbox_outlined, size: 44, color: cs.onSurfaceVariant),
                              const SizedBox(height: 10),
                              Center(child: Text(l10n.assistStaffEmpty)),
                            ])
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                              itemCount: _visible.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (_, i) => _card(l10n, cs, _visible[i]),
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(AppLocalizations l10n, ColorScheme cs, AssistanceRequest r) {
    final color = r.isApproved
        ? AppConstants.successGreen
        : r.isRejected
            ? AppConstants.errorRed
            : r.isPending
                ? AppConstants.warningAmber
                : AppConstants.onSurfaceVariant;
    final busy = _busyId == r.id;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Not a loan: the badge says so.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppConstants.programPurple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  l10n.assistBadge,
                  style: GoogleFonts.inter(
                      fontSize: 10, fontWeight: FontWeight.w700, color: AppConstants.programPurple),
                ),
              ),
              const Spacer(),
              Text(
                switch (r.status) {
                  'approved' => l10n.assistStatusApproved,
                  'rejected' => l10n.assistStatusRejected,
                  'cancelled' => l10n.assistStatusCancelled,
                  _ => l10n.assistStatusPending,
                },
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(r.farmerName ?? '',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
          Text(
            [r.requestNumber, if (r.assistanceReference != null) r.assistanceReference!].join('  ·  '),
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          if ((r.programName ?? '').isNotEmpty)
            Text(l10n.assistAfterProgram(r.programName!),
                style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(_itemsText(r), style: GoogleFonts.inter(fontSize: 13, height: 1.35)),
          if ((r.message ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(r.message!,
                style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant)),
          ],
          if ((r.reviewNote ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(r.reviewNote!, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
          if (r.isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => _reject(r),
                    child: Text(l10n.assistReject),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : () => _approve(r),
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(l10n.assistApprove),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
