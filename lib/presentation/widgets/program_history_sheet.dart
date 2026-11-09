import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import 'program_return_panel.dart' show resolutionLabel;
import '../../data/models/program_model.dart';
import '../../data/repositories/program_repository.dart';
import 'management_modal.dart';
import 'skeleton.dart';

/// Opens the per-program accountability History (Manager and Officer).
///
/// Reads get_program_history(), which sits on top of the existing
/// accountability trail — this screen keeps no history of its own.
Future<void> showProgramHistory(
  BuildContext context, {
  required CooperativeProgram program,
  ProgramRepository? repo,
}) {
  final r = repo ?? ProgramRepository();
  return showManagementModal(
    context: context,
    builder: (ctx) => ManagementModalShell(
      title: AppLocalizations.of(ctx).programHistoryTitle,
      subtitle: program.programName,
      bodyIsScrollable: true,
      body: _ProgramHistoryBody(program: program, repo: r),
    ),
  );
}

class _ProgramHistoryBody extends StatefulWidget {
  final CooperativeProgram program;
  final ProgramRepository repo;
  const _ProgramHistoryBody({required this.program, required this.repo});

  @override
  State<_ProgramHistoryBody> createState() => _ProgramHistoryBodyState();
}

class _ProgramHistoryBodyState extends State<_ProgramHistoryBody> {
  List<ProgramHistoryEntry> _entries = [];
  bool _loading = true;
  bool _failed = false;

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
      final rows = await widget.repo.fetchProgramHistory(widget.program.id);
      if (!mounted) return;
      setState(() {
        _entries = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    Widget content;
    if (_loading) {
      content = const Padding(
        padding: EdgeInsets.all(16),
        child: SkeletonList(),
      );
    } else if (_failed) {
      content = _Message(
        icon: Icons.cloud_off_rounded,
        text: l10n.programHistoryLoadFailed,
        actionLabel: l10n.programHistoryRetry,
        onAction: _load,
      );
    } else if (_entries.isEmpty) {
      content = _Message(
        icon: Icons.history_rounded,
        text: l10n.programHistoryEmpty,
      );
    } else {
      content = ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        itemCount: _entries.length,
        itemBuilder: (_, i) => _HistoryTile(
          entry: _entries[i],
          isLast: i == _entries.length - 1,
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          child: Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.programHistoryNote,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _Message({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final ProgramHistoryEntry entry;
  final bool isLast;
  const _HistoryTile({required this.entry, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final style = ProgramHistoryText.styleFor(entry.type);
    final changes = ProgramHistoryText.changeLines(l10n, entry);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(style.icon, size: 15, color: style.color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: cs.outline.withValues(alpha: 0.18),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ProgramHistoryText.headline(l10n, entry),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ProgramHistoryText.byLine(l10n, entry),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    ProgramHistoryText.formatStamp(entry.at),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (changes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final c in changes)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: Text(
                                c,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProgramHistoryEventStyle {
  final IconData icon;
  final Color color;
  const ProgramHistoryEventStyle(this.icon, this.color);
}

/// Wording for history rows. Static + pure so it can be unit-tested.
class ProgramHistoryText {
  static ProgramHistoryEventStyle styleFor(String type) {
    switch (type) {
      case 'program_created':
        return const ProgramHistoryEventStyle(Icons.add_circle_outline_rounded, AppConstants.primaryGreen);
      case 'program_updated':
        return const ProgramHistoryEventStyle(Icons.edit_outlined, AppConstants.buyerBlue);
      case 'enrollment_requested':
        return const ProgramHistoryEventStyle(Icons.how_to_reg_outlined, AppConstants.warningAmber);
      case 'enrollment_declined':
      case 'member_removed':
      case 'activity_deleted':
        return const ProgramHistoryEventStyle(Icons.remove_circle_outline_rounded, AppConstants.errorRed);
      case 'member_enrolled':
        return const ProgramHistoryEventStyle(Icons.person_add_alt_1_outlined, AppConstants.primaryGreen);
      case 'benefit_distributed':
        return const ProgramHistoryEventStyle(Icons.inventory_2_outlined, AppConstants.programPurple);
      case 'outcome_recorded':
      case 'return_confirmed':
        return const ProgramHistoryEventStyle(Icons.fact_check_outlined, AppConstants.buyerBlue);
      case 'converted_to_loan':
        return const ProgramHistoryEventStyle(Icons.request_quote_outlined, AppConstants.programPurple);
      case 'activity_created':
      case 'activity_updated':
        return const ProgramHistoryEventStyle(Icons.event_outlined, AppConstants.buyerBlue);
      case 'outcome_submitted':
        return const ProgramHistoryEventStyle(Icons.assignment_outlined, AppConstants.warningAmber);
      case 'outcome_reviewed':
        return const ProgramHistoryEventStyle(Icons.rule_rounded, AppConstants.buyerBlue);
      case 'outcome_verified':
        return const ProgramHistoryEventStyle(Icons.agriculture_outlined, AppConstants.programPurple);
      case 'outcome_finalized':
        return const ProgramHistoryEventStyle(Icons.flag_outlined, AppConstants.successGreen);
      case 'return_opened':
      case 'return_adjusted':
      case 'return_receipt':
        return const ProgramHistoryEventStyle(Icons.agriculture_rounded, AppConstants.primaryGreen);
      case 'return_closed':
        return const ProgramHistoryEventStyle(Icons.task_alt_rounded, AppConstants.onSurfaceVariant);
      case 'resolution_recorded':
        return const ProgramHistoryEventStyle(Icons.gavel_rounded, AppConstants.programPurple);
      case 'assistance_requested':
        return const ProgramHistoryEventStyle(Icons.volunteer_activism_rounded, AppConstants.warningAmber);
      case 'assistance_approved':
        return const ProgramHistoryEventStyle(Icons.volunteer_activism_rounded, AppConstants.successGreen);
      case 'assistance_rejected':
      case 'assistance_cancelled':
        return const ProgramHistoryEventStyle(Icons.volunteer_activism_rounded, AppConstants.errorRed);
      default:
        return const ProgramHistoryEventStyle(Icons.circle_outlined, AppConstants.outline);
    }
  }

  static String _name(ProgramHistoryEntry e) => e.subjectName ?? '—';

  static String headline(AppLocalizations l10n, ProgramHistoryEntry e) {
    final d = e.details;
    switch (e.type) {
      case 'program_created':
        return l10n.programHistCreated;
      case 'program_updated':
        return l10n.programHistUpdated;
      case 'enrollment_requested':
        return l10n.programHistEnrollRequested(_name(e));
      case 'enrollment_declined':
        return l10n.programHistEnrollDeclined(_name(e));
      case 'member_enrolled':
        return d['re_enrolled'] == true
            ? l10n.programHistReEnrolled(_name(e))
            : l10n.programHistEnrolled(_name(e));
      case 'member_removed':
        return l10n.programHistRemoved(_name(e));
      case 'benefit_distributed':
        final qty = d['quantity'];
        final item = d['item'] as String?;
        return (qty != null && item != null)
            ? l10n.programHistDistributed('${_num(qty)} $item', _name(e))
            : l10n.programHistDistributedPlain(_name(e));
      case 'outcome_recorded':
        return l10n.programHistOutcome(
          _name(e),
          d['outcome'] == 'failed'
              ? l10n.programMgmtStageFailed
              : d['outcome'] == 'thriving'
                  ? l10n.programMgmtThriving
                  : '${d['outcome']}',
        );
      case 'return_confirmed':
        return l10n.programHistReturnConfirmed(_name(e));
      case 'converted_to_loan':
        return l10n.programHistConverted(_name(e));
      case 'outcome_submitted':
        return l10n.programHistOutcomeSubmitted(
          _name(e),
          d['outcome'] == 'failed'
              ? l10n.outcStatusFailed
              : l10n.outcStatusSuccessful,
        );
      case 'outcome_reviewed':
        return d['decision'] == 'returned'
            ? l10n.programHistOutcomeReturned(_name(e))
            : l10n.programHistOutcomeValidated(_name(e));
      case 'outcome_verified':
        return l10n.programHistOutcomeVerified(
          _name(e),
          d['finding'] == 'disputes'
              ? l10n.outcFindingDisputes
              : l10n.outcFindingConfirms,
        );
      case 'outcome_finalized':
        return l10n.programHistOutcomeFinalized(
          _name(e),
          d['outcome'] == 'failed'
              ? l10n.outcStatusFailed
              : l10n.outcStatusSuccessful,
        );
      case 'return_opened':
        return l10n.programHistReturnOpened(_name(e), _qtyText(d['after'], d));
      case 'return_adjusted':
        return l10n.programHistReturnAdjusted(_name(e));
      case 'return_receipt':
        return l10n.programHistReturnReceipt(_name(e), _qtyText(d['quantity'], d));
      case 'return_closed':
        return l10n.programHistReturnClosed(_name(e));
      case 'resolution_recorded':
        final res = resolutionLabel(l10n, '${d['resolution']}');
        return d['default'] == true
            ? l10n.programHistResolutionDefault(_name(e), res)
            : l10n.programHistResolution(_name(e), res);
      case 'assistance_requested':
        return l10n.programHistAssistRequested(_name(e), '${d['request_number'] ?? ''}');
      case 'assistance_approved':
        return l10n.programHistAssistApproved(_name(e), '${d['reference'] ?? ''}');
      case 'assistance_rejected':
        return l10n.programHistAssistRejected(_name(e));
      case 'assistance_cancelled':
        return l10n.programHistAssistCancelled(_name(e));
      case 'activity_created':
        return l10n.programHistActivityCreated(_activityTitle(e));
      case 'activity_updated':
        return l10n.programHistActivityUpdated(_activityTitle(e));
      case 'activity_deleted':
        return l10n.programHistActivityDeleted(_activityTitle(e));
      default:
        return e.type;
    }
  }

  /// "4 kg Peanut" for a return event.
  static String _qtyText(Object? qty, Map<String, dynamic> d) =>
      '${_num(qty)} ${d['unit'] ?? ''} ${d['crop'] ?? ''}'.trim();

  static String _activityTitle(ProgramHistoryEntry e) {
    final n = (e.details['new'] as Map?)?['title'] as String?;
    final o = (e.details['old'] as Map?)?['title'] as String?;
    return n ?? o ?? e.subjectName ?? '—';
  }

  static String roleLabel(AppLocalizations l10n, String? role) {
    switch (role) {
      case 'admin':
        return l10n.programHistRoleManager;
      case 'officer':
        return l10n.programHistRoleOfficer;
      case 'farmer':
        return l10n.programHistRoleFarmer;
      default:
        return '';
    }
  }

  static String byLine(AppLocalizations l10n, ProgramHistoryEntry e) {
    if (e.actorName == null || e.actorName!.trim().isEmpty) {
      return l10n.programHistActorUnrecorded;
    }
    final role = roleLabel(l10n, e.actorRole);
    return role.isEmpty
        ? l10n.programHistBy(e.actorName!, '')
        : l10n.programHistBy(e.actorName!, ' ($role)');
  }

  /// "Nov 4, 2026 · 3:05 PM"
  static String formatStamp(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $h:$m $ap';
  }

  static String _num(Object? v) {
    final n = v is num ? v : num.tryParse('$v');
    if (n == null) return '$v';
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  }

  static String _fieldLabel(AppLocalizations l10n, String key) {
    switch (key) {
      case 'program_name':
        return l10n.programMgmtFieldName;
      case 'program_type':
        return l10n.programMgmtFieldType;
      case 'image_url':
        return l10n.programMgmtFieldPhoto;
      case 'description':
        return l10n.programMgmtFieldDescription;
      case 'budget':
        return l10n.programMgmtFieldBudget;
      case 'distribution_item_id':
        return l10n.programMgmtFieldItem;
      case 'source_categories':
        return l10n.programMgmtFieldSources;
      case 'return_crop_id':
        return l10n.programMgmtFieldReturnCrop;
      case 'return_quantity':
        return l10n.programMgmtFieldReturnQuantity;
      case 'return_unit':
        return l10n.programMgmtFieldReturnUnit;
      case 'status':
        return l10n.programHistFieldStatus;
      case 'benefit_type':
        return l10n.programHistFieldBenefit;
      default:
        return key.replaceAll('_', ' ');
    }
  }

  static String _value(AppLocalizations l10n, String key, Object? v) {
    if (v == null || (v is String && v.trim().isEmpty)) {
      return l10n.programHistValueEmpty;
    }
    switch (key) {
      case 'budget':
        return '₱${_num(v)}';
      case 'benefit_type':
        return v == 'revenue_share'
            ? l10n.programMgmtBenefitReturnChip
            : l10n.programMgmtBenefitFreeChip;
      case 'status':
        switch (v) {
          case 'active':
            return l10n.programMgmtStatusActiveTc;
          case 'completed':
            return l10n.programMgmtStatusCompletedTc;
        }
        return '$v';
      case 'source_categories':
        return v is List ? v.join(', ') : '$v';
      case 'image_url':
      case 'distribution_item_id':
      case 'return_crop_id':
        // A URL / id means nothing to a reader; "changed" is the fact.
        return l10n.programHistValueSet;
      default:
        return '$v';
    }
  }

  /// "Budget: ₱5000 → ₱8000" lines for a program edit; the staff note for a
  /// review, verification or final decision.
  static List<String> changeLines(AppLocalizations l10n, ProgramHistoryEntry e) {
    if (e.type == 'outcome_reviewed' ||
        e.type == 'outcome_verified' ||
        e.type == 'outcome_finalized') {
      final note = (e.details['note'] as String?)?.trim() ?? '';
      return [
        if (e.type == 'outcome_verified' && e.details['quantity'] != null)
          l10n.programHistMeasured(
            '${_num(e.details['quantity'])} ${e.details['unit'] ?? ''}'.trim(),
          ),
        if (note.isNotEmpty) '"$note"',
      ];
    }
    final d = e.details;
    if (e.type == 'return_adjusted' || e.type == 'return_closed') {
      final reason = (d['reason'] as String?)?.trim() ?? '';
      return [
        if (e.type == 'return_adjusted')
          l10n.programHistQtyChange(_num(d['before']), _num(d['after']), '${d['unit'] ?? ''}'),
        if (e.type == 'return_closed')
          l10n.programHistReceivedOfDue(_num(d['after']), _num(d['before']), '${d['unit'] ?? ''}'),
        if (reason.isNotEmpty) '"$reason"',
      ];
    }
    if (e.type == 'return_receipt' || e.type == 'resolution_recorded' || e.type == 'assistance_rejected') {
      final note = ((d['reason'] ?? d['note']) as String?)?.trim() ?? '';
      return [if (note.isNotEmpty) '"$note"'];
    }
    if (e.type == 'assistance_requested') {
      final items = (d['items'] as String?)?.trim() ?? '';
      return [if (items.isNotEmpty) items];
    }
    if (e.type != 'program_updated') return const [];
    final oldV = (e.details['old'] as Map?)?.cast<String, dynamic>() ?? const {};
    final newV = (e.details['new'] as Map?)?.cast<String, dynamic>() ?? const {};
    return [
      for (final k in newV.keys)
        if (k != 'updated_at' && k != 'distribution_category')
          l10n.programHistChanged(
            _fieldLabel(l10n, k),
            _value(l10n, k, oldV[k]),
            _value(l10n, k, newV[k]),
          ),
    ];
  }
}
