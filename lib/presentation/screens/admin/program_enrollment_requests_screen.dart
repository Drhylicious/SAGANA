import '../../widgets/view_only_banner.dart';
import '../../../data/services/staff_permission_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/program_enrollment_request_model.dart';
import '../../../data/repositories/program_repository.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/request_card.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

/// Manager / Officer review of Program Join Requests, laid out like Market Linking:
/// two tabs (Pending, Joined), a tappable card per request with the essentials up
/// front, and the full details — and, for a pending request, Approve — inside the
/// opened card. A request is approved, never declined: it closes by itself only when
/// its program is completed. Requests declined in the past stay visible as history.
class ProgramEnrollmentRequestsScreen extends StatefulWidget {
  const ProgramEnrollmentRequestsScreen({super.key});

  @override
  State<ProgramEnrollmentRequestsScreen> createState() =>
      _ProgramEnrollmentRequestsScreenState();
}

class _ProgramEnrollmentRequestsScreenState
    extends State<ProgramEnrollmentRequestsScreen>
    with SingleTickerProviderStateMixin {
  final _repo = ProgramRepository();
  late final TabController _tabController;

  bool _isLoading = true;
  bool _loadFailed = false;
  List<ProgramEnrollmentRequest> _pending = [];
  List<ProgramEnrollmentRequest> _enrolled = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final results = await Future.wait([
        _repo.fetchPendingEnrollmentRequests(),
        // Everyone enrolled now, in every program: the active members.
        _repo.fetchEnrolledMembers(),
      ]);
      if (!mounted) return;
      setState(() {
        _pending = results[0];
        _enrolled = results[1];
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _isLoading = false;
      });
    }
  }

  Future<bool> _approve(ProgramEnrollmentRequest item) async {
    if (!requireManage(context, StaffModule.dashboard)) return false;
    final l10n = AppLocalizations.of(context);
    final ok = await _repo.approveEnrollmentRequest(id: item.id);
    if (!mounted) return ok;
    if (ok) _load();
    AppToast.show(
      context,
      ok ? l10n.reqApproved : l10n.reqFailed,
      isError: !ok,
    );
    return ok;
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

  String _title(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _card(
    ProgramEnrollmentRequest item,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final color = item.isApproved
        ? AppConstants.successGreen
        : item.isRejected
        ? AppConstants.errorRed
        : AppConstants.amber;
    final statusLabel = item.isApproved
        ? l10n.reqStatusEnrolled
        : item.isRejected
        ? l10n.reqStatusDeclined
        : l10n.reqStatusPending;
    final summary = item.isPending
        ? l10n.reqRequestedOn(_formatDate(item.submittedAt))
        : !item.hasRequest
        ? l10n.reqEnrolledSummary(
            _formatDate(item.enrolledAt ?? item.submittedAt),
          )
        : l10n.reqDecidedOn(_formatDate(item.reviewedAt ?? item.submittedAt));

    final details = <Widget>[
      RequestDetailRow(label: l10n.reqProgram, value: item.programName),
      if (item.programType != null && item.programType!.isNotEmpty)
        RequestDetailRow(
          label: l10n.reqProgramType,
          value: _title(item.programType!),
        ),
      // A member enrolled without a request has no request dates to show.
      if (item.hasRequest)
        RequestDetailRow(
          label: l10n.reqRequested,
          value: _formatDate(item.submittedAt),
        )
      else
        RequestDetailRow(
          label: l10n.reqStatusEnrolled,
          value: l10n.reqEnrolledDirect,
        ),
      if (item.hasRequest && item.reviewedAt != null)
        RequestDetailRow(
          label: l10n.reqDecided,
          value: _formatDate(item.reviewedAt!),
        ),
      if (item.isApproved) ...[
        RequestDetailRow(
          label: l10n.reqMembership,
          value: switch (item.memberStatus) {
            'withdrawn' => l10n.reqMemberWithdrawn,
            'completed' => l10n.reqMemberCompleted,
            'active' => l10n.reqMemberActive,
            _ => l10n.reqMemberUnknown,
          },
          valueColor: item.memberStatus == 'withdrawn'
              ? AppConstants.errorRed
              : AppConstants.successGreen,
        ),
        if (item.enrolledAt != null)
          RequestDetailRow(
            label: l10n.reqEnrolledOn,
            value: _formatDate(item.enrolledAt!),
          ),
        if (item.programPurpose != 'sales')
          RequestDetailRow(
            label: l10n.reqReceived,
            value: item.distributedAt != null
                ? '${item.quantityGiven != null ? formatQuantity(item.quantityGiven!) : ''} '
                          '${item.distributedItemName ?? ''}'
                      .trim()
                : l10n.reqNoDistributionYet,
          ),
      ],
      if (item.adminNotes != null && item.adminNotes!.trim().isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          l10n.reqNote,
          style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          '"${item.adminNotes}"',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontStyle: FontStyle.italic,
            color: cs.onSurface,
          ),
        ),
      ],
    ];

    return RequestCard(
      leading:
          (item.programImageUrl != null && item.programImageUrl!.isNotEmpty)
          ? ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Image.network(
                  item.programImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      RequestAvatar(name: item.farmerName ?? '?', color: color),
                ),
              ),
            )
          : RequestAvatar(name: item.farmerName ?? '?', color: color),
      title: item.farmerName ?? l10n.reqFarmerFallback,
      subtitle: item.programName,
      summary: summary,
      statusLabel: statusLabel,
      statusColor: color,
      details: details,
      actions: item.isPending
          ? _EnrollmentActions(onApprove: () => _approve(item))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            SubPageTopBar(
              title: l10n.reqEnrollTitle,
              onBack: () => Navigator.of(context).pop(),
            ),
            TabBar(
              controller: _tabController,
              labelColor: AppConstants.primaryGreen,
              unselectedLabelColor: cs.onSurfaceVariant,
              indicatorColor: AppConstants.primaryGreen,
              tabs: [
                Tab(text: l10n.reqTabPending(_pending.length)),
                Tab(text: l10n.reqTabEnrolled(_enrolled.length)),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SkeletonList(),
                    )
                  : _loadFailed
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 40,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.reqLoadFailed,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: Text(l10n.programHistoryRetry),
                          ),
                        ],
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _list(_pending, l10n, cs, empty: l10n.reqEmptyPending),
                        _list(
                          _enrolled,
                          l10n,
                          cs,
                          empty: l10n.reqEmptyEnrolled,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(
    List<ProgramEnrollmentRequest> items,
    AppLocalizations l10n,
    ColorScheme cs, {
    required String empty,
  }) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            Icon(Icons.inbox_outlined, size: 44, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Center(
              child: Text(
                empty,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _card(items[i], l10n, cs),
      ),
    );
  }
}

/// Approve for a pending request, inside the opened card. There is no Decline: these
/// programs and opportunities are benefits for Farmers, so a request is approved. A second
/// tap while saving is ignored.
class _EnrollmentActions extends StatefulWidget {
  final Future<bool> Function() onApprove;
  const _EnrollmentActions({required this.onApprove});

  @override
  State<_EnrollmentActions> createState() => _EnrollmentActionsState();
}

class _EnrollmentActionsState extends State<_EnrollmentActions> {
  bool _saving = false;

  Future<void> _approve() async {
    if (_saving) return;
    setState(() => _saving = true);
    await widget.onApprove();
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.reqApproveNote,
          style: GoogleFonts.inter(
            fontSize: 11,
            height: 1.4,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            key: const Key('approveJoinRequest'),
            onPressed: _saving ? null : _approve,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(l10n.reqApprove),
          ),
        ),
      ],
    );
  }
}
