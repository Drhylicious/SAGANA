import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/quantity_utils.dart';
import '../../data/models/farmer_profile_model.dart';
import '../../data/models/program_model.dart';
import '../../data/models/program_outcome_model.dart';
import '../../data/models/program_return_model.dart';
import '../../data/repositories/farmer_details_repository.dart';
import '../../data/repositories/program_repository.dart';
import '../../routes/app_routes.dart';
import 'management_modal.dart';
import 'program_return_panel.dart';
import 'request_card.dart';

/// One member's participation in one program, opened from Manage Members. Read-only:
/// the actions (distribute, review, receive a return) stay on the member's card.
///
/// What it shows depends on the program:
///  * every program: who the Farmer is (contact, farm), when they asked to join and who
///    approved it, and a link to the full Farmer profile (which Managers and Officers
///    can already open);
///  * Distribution: what was given (the Inventory item's unit), the outcome the Farmer
///    reported, its evidence review and field verification, and the Harvest Return or
///    the cooperative's decision for a failed one;
///  * Product Sales: the member discount, how many orders, the total spent, what the
///    discount saved, and the latest purchases.
Future<void> showProgramMemberDetails(
  BuildContext context, {
  required CooperativeProgram program,
  required ProgramMember member,
  OutcomeReport? report,
  ProgramReturn? ret,
  FailedResolution? resolution,
  String? itemUnit,
  String? itemName,
  ProgramRepository? repo,
  FarmerDetailsRepository? farmerRepo,
}) {
  return showManagementModal<void>(
    context: context,
    builder: (ctx) => ManagementModalShell(
      title: AppLocalizations.of(ctx).memDetailsTitle,
      body: ProgramMemberDetails(
        program: program,
        member: member,
        report: report,
        ret: ret,
        resolution: resolution,
        itemUnit: itemUnit,
        itemName: itemName,
        repo: repo ?? ProgramRepository(),
        farmerRepo: farmerRepo ?? FarmerDetailsRepository(),
      ),
    ),
  );
}

class ProgramMemberDetails extends StatefulWidget {
  final CooperativeProgram program;
  final ProgramMember member;
  final OutcomeReport? report;
  final ProgramReturn? ret;
  final FailedResolution? resolution;
  final String? itemUnit;
  final String? itemName;
  final ProgramRepository repo;
  final FarmerDetailsRepository farmerRepo;

  const ProgramMemberDetails({
    super.key,
    required this.program,
    required this.member,
    required this.repo,
    required this.farmerRepo,
    this.report,
    this.ret,
    this.resolution,
    this.itemUnit,
    this.itemName,
  });

  @override
  State<ProgramMemberDetails> createState() => _ProgramMemberDetailsState();
}

class _ProgramMemberDetailsState extends State<ProgramMemberDetails> {
  bool _loading = true;
  FarmerProfileModel? _profile;
  MemberJoinInfo? _join;
  List<ProgramPurchase> _purchases = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Each part loads on its own, so one that fails leaves the rest on screen (and the
  // view never stays on its spinner).
  Future<T> _safe<T>(Future<T> Function() load, T fallback) async {
    try {
      return await load();
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _load() async {
    final m = widget.member;
    final profile = _safe<FarmerProfileModel?>(() => widget.farmerRepo.fetchFarmerProfile(m.farmerId), null);
    final join = _safe<MemberJoinInfo?>(() => widget.repo.fetchMemberJoinInfo(widget.program.id, m.farmerId), null);
    final purchases = widget.program.isSalesProgram
        ? _safe<List<ProgramPurchase>>(() => widget.repo.fetchMemberPurchases(widget.program.id, m.farmerId), const [])
        : Future<List<ProgramPurchase>>.value(const []);
    final p = await profile;
    final j = await join;
    final pu = await purchases;
    if (!mounted) return;
    setState(() {
      _profile = p;
      _join = j;
      _purchases = pu;
      _loading = false;
    });
  }

  static String _date(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _role(AppLocalizations l10n, String? role) =>
      role == 'officer' ? l10n.staffRoleOfficer : l10n.staffRoleManager;

  Widget _section(String title, List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 12,
            height: 1.4,
            fontStyle: FontStyle.italic,
            color: AppConstants.onSurfaceVariant,
          ),
        ),
      );

  // ── sections ──────────────────────────────────────────────────────────────

  Widget _header(AppLocalizations l10n) {
    final m = widget.member;
    final cs = Theme.of(context).colorScheme;
    final initials = m.farmerName
        .trim()
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0])
        .take(2)
        .join()
        .toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppConstants.primaryContainer,
            child: Text(
              initials.isEmpty ? '?' : initials,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.farmerName,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  widget.program.programName,
                  style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactAndJoining(AppLocalizations l10n) {
    final m = widget.member;
    final p = _profile;
    final j = _join;
    final phone = (p?.phoneNumber ?? '').trim();
    final farm = (p?.farmAddress ?? '').trim();
    // The e-mail is shown only when it has been verified (the same rule the profile uses:
    // the contact e-mail equals the last address proven with a code). Unverified: not shown.
    final email = (p != null && p.isContactEmailVerified) ? (p.contactEmail ?? '').trim() : '';
    return _section(l10n.memDetailsJoining, [
      RequestDetailRow(label: l10n.memDetailsContact, value: phone.isEmpty ? l10n.memDetailsNone : phone),
      if (email.isNotEmpty) RequestDetailRow(key: const Key('memberVerifiedEmail'), label: l10n.memDetailsEmail, value: email),
      RequestDetailRow(label: l10n.memDetailsFarm, value: farm.isEmpty ? l10n.memDetailsNone : farm),
      if (j?.requestedAt != null)
        RequestDetailRow(label: l10n.memDetailsRequestedOn, value: _date(j!.requestedAt!)),
      RequestDetailRow(label: l10n.reqEnrolledOn, value: _date(m.enrolledAt)),
      if (j != null && j.reviewedAt != null)
        RequestDetailRow(
          label: l10n.memDetailsApprovedBy,
          value: j.reviewerName == null
              ? _date(j.reviewedAt!)
              : l10n.memDetailsByLine(j.reviewerName!, _role(l10n, j.reviewerRole), _date(j.reviewedAt!)),
        )
      else if (j == null)
        _note(l10n.reqEnrolledDirect),
    ]);
  }

  Widget _distribution(AppLocalizations l10n) {
    final m = widget.member;
    final unit = (m.distributedUnit ?? widget.itemUnit)?.trim();
    final name = m.distributedItemName ?? widget.itemName;
    final what = [
      if (m.quantityGiven != null) formatQuantityGrouped(m.quantityGiven!),
      if (unit != null && unit.isNotEmpty) unit,
      if (name != null && name.isNotEmpty) name,
    ].join(' ');
    return _section(l10n.memDetailsDistribution, [
      if (!m.isDistributed)
        _note(l10n.memDetailsNotYetReceived)
      else
        RequestDetailRow(
          label: l10n.memDetailsReceived,
          value: '$what · ${_date(m.distributedAt!)}',
          emphasize: true,
        ),
    ]);
  }

  Widget _outcome(AppLocalizations l10n) {
    final r = widget.report;
    final m = widget.member;
    if (r == null) {
      return _section(l10n.memDetailsOutcome, [_note(l10n.memDetailsNoReport)]);
    }
    String qty(double? q, String? u) =>
        q == null ? '' : '${formatQuantity(q)} ${u ?? ''}'.trim();
    String by(String? n, DateTime? at) => n == null
        ? (at == null ? '' : _date(at))
        : l10n.memDetailsDoneBy(n, at == null ? '' : _date(at));
    return _section(l10n.memDetailsOutcome, [
      RequestDetailRow(
        label: l10n.memDetailsReported,
        value: r.isSuccessfulReport ? l10n.memDetailsOutcomeSuccessful : l10n.memDetailsOutcomeFailed,
        valueColor: r.isSuccessfulReport ? AppConstants.successGreen : AppConstants.errorRed,
        emphasize: true,
      ),
      if (r.isSuccessfulReport && r.quantityHarvested != null)
        RequestDetailRow(label: l10n.outcFarmerReported, value: qty(r.quantityHarvested, r.quantityUnit)),
      RequestDetailRow(
        label: l10n.memDetailsEvidence,
        value: r.isReviewed ? by(r.reviewedByName, r.reviewedAt) : l10n.memDetailsPending,
      ),
      RequestDetailRow(
        label: l10n.memDetailsFieldCheck,
        value: r.isVerified
            ? [
                if (r.verifiedQuantity != null) qty(r.verifiedQuantity, r.verifiedUnit),
                by(r.verifiedByName, r.verifiedAt),
              ].where((s) => s.isNotEmpty).join(' · ')
            : l10n.memDetailsPending,
      ),
      if (m.isOutcomeRecorded)
        RequestDetailRow(
          label: l10n.outcFinalOutcome,
          value: m.isThriving ? l10n.memDetailsOutcomeSuccessful : l10n.memDetailsOutcomeFailed,
          valueColor: m.isThriving ? AppConstants.successGreen : AppConstants.errorRed,
        ),
    ]);
  }

  Widget _afterOutcome(AppLocalizations l10n) {
    final ret = widget.ret;
    final res = widget.resolution;
    if (widget.member.isThriving && ret != null) {
      return _section(l10n.memDetailsHarvestReturn, [
        RequestDetailRow(
          label: ret.cropName,
          value: l10n.memDetailsReturnLine(
            '${formatQuantity(ret.receivedQuantity)} ${ret.unit}'.trim(),
            '${formatQuantity(ret.dueQuantity)} ${ret.unit}'.trim(),
          ),
          emphasize: true,
        ),
      ]);
    }
    if (widget.member.isFailed && res != null) {
      return _section(l10n.memDetailsDecision, [
        RequestDetailRow(label: l10n.memDetailsDecision, value: resolutionLabel(l10n, res.resolution)),
        if (res.note != null && res.note!.trim().isNotEmpty) _note('"${res.note}"'),
      ]);
    }
    return const SizedBox.shrink();
  }

  Widget _purchasesSection(AppLocalizations l10n) {
    final all = _purchases;
    // Only completed orders count as spent (handed over, cash recorded, confirmed).
    final paid = all.where((p) => p.status == 'completed').toList();
    final spent = paid.fold<double>(0, (s, p) => s + p.totalAmount);
    final saved = paid.fold<double>(0, (s, p) => s + p.discountAmount);
    final last = all.isEmpty ? null : all.first;
    String peso(double v) => '₱${v.toStringAsFixed(2)}';
    return _section(l10n.memDetailsPurchases, [
      if (widget.program.hasMemberDiscount)
        RequestDetailRow(
          label: l10n.reqMembership,
          value: l10n.catMemberBenefitEnrolled(formatQuantity(widget.program.memberDiscountPercent)),
        ),
      if (all.isEmpty)
        _note(l10n.memDetailsNoPurchases)
      else ...[
        RequestDetailRow(label: l10n.memDetailsOrders, value: '${all.length}'),
        RequestDetailRow(label: l10n.memDetailsSpent, value: peso(spent), emphasize: true),
        if (saved > 0) RequestDetailRow(label: l10n.memDetailsSaved, value: peso(saved)),
        if (last != null) RequestDetailRow(label: l10n.memDetailsLastPurchase, value: _date(last.requestedAt)),
        const SizedBox(height: 8),
        Text(
          l10n.memDetailsRecent,
          style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
        ),
        for (final p in all.take(5))
          RequestDetailRow(
            label: '${formatQuantity(p.quantity)} ${p.unit} ${p.itemName}'.trim(),
            value: '${peso(p.netAmount)} · ${_statusLabel(l10n, p.status)}',
          ),
      ],
    ]);
  }

  String _statusLabel(AppLocalizations l10n, String s) => adminOrderStatusLabel(l10n, s);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isSales = widget.program.isSalesProgram;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(l10n),
        _contactAndJoining(l10n),
        if (isSales) ...[
          _purchasesSection(l10n),
        ] else ...[
          _distribution(l10n),
          if (widget.member.isDistributed) _outcome(l10n),
          _afterOutcome(l10n),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('memberViewProfile'),
            icon: const Icon(Icons.person_outline_rounded, size: 18),
            label: Text(l10n.memDetailsViewProfile),
            onPressed: () {
              final id = widget.member.farmerId;
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              router.push(AppRoutes.farmerDetails, extra: id);
            },
          ),
        ),
      ],
    );
  }
}
