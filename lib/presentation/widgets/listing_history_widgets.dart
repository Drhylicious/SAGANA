import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/quantity_utils.dart';
import '../../data/models/workflow_event_model.dart';
import 'listing_status_badge.dart';
import 'workflow_timeline.dart' show workflowActorLabel, workflowActionColor, workflowActionIcon;

/// What the history screen shows at the top: the listing as it is NOW.
class ListingHistoryHeader {
  final String name;
  final String? photoUrl;
  final String status;
  final double remainingKg;
  final double volumeKg;
  final double pricePerUnit;
  final String unit;
  final DateTime? createdAt;

  const ListingHistoryHeader({
    required this.name,
    this.photoUrl,
    required this.status,
    required this.remainingKg,
    required this.volumeKg,
    required this.pricePerUnit,
    required this.unit,
    this.createdAt,
  });
}

/// Which events a filter chip keeps.
enum ListingHistoryFilter { all, decisions, edits }

const _decisionActions = {
  'approved',
  'disapproved',
  'withdrawn',
  'edit_approved',
  'edit_rejected',
};
const _editActions = {
  'edited',
  'edit_requested',
  'edit_approved',
  'edit_rejected',
  'edit_cancelled',
};

bool listingHistoryMatches(ListingHistoryFilter filter, WorkflowEvent e) {
  switch (filter) {
    case ListingHistoryFilter.all:
      return true;
    case ListingHistoryFilter.decisions:
      return _decisionActions.contains(e.action);
    case ListingHistoryFilter.edits:
      return _editActions.contains(e.action);
  }
}

/// True while the latest edit submission has no answer yet (approved, disapproved
/// or cancelled): an edit is waiting for the Manager / Officer.
bool listingHistoryHasOpenEdit(List<WorkflowEvent> events) {
  final sorted = [...events]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  var open = false;
  for (final e in sorted) {
    if (e.action == 'edit_requested') open = true;
    if (e.action == 'edit_approved' || e.action == 'edit_rejected' || e.action == 'edit_cancelled') {
      open = false;
    }
  }
  return open;
}

/// The plain-language title and one-line explanation of a listing event.
({String title, String description}) listingHistoryText(AppLocalizations l, String action) {
  switch (action) {
    case 'submitted':
      return (title: l.lhTitleSubmitted, description: l.lhDescSubmitted);
    case 'approved':
      return (title: l.lhTitleApproved, description: l.lhDescApproved);
    case 'disapproved':
      return (title: l.lhTitleDisapproved, description: l.lhDescDisapproved);
    case 'withdrawn':
      return (title: l.lhTitleWithdrawn, description: l.lhDescWithdrawn);
    case 'edited':
      return (title: l.lhTitleEdited, description: l.lhDescEdited);
    case 'edit_requested':
      return (title: l.lhTitleEditSubmitted, description: l.lhDescEditSubmitted);
    case 'edit_approved':
      return (title: l.lhTitleEditApproved, description: l.lhDescEditApproved);
    case 'edit_rejected':
      return (title: l.lhTitleEditRejected, description: l.lhDescEditRejected);
    case 'edit_cancelled':
      return (title: l.lhTitleEditCancelled, description: l.lhDescEditCancelled);
    case 'sold_out':
      return (title: l.lhTitleSoldOut, description: l.lhDescSoldOut);
    case 'reopened':
      return (title: l.lhTitleReopened, description: l.lhDescReopened);
    default:
      return (title: l.lhTitleStatus, description: l.lhDescStatus);
  }
}

bool _isNegative(String action) =>
    action == 'disapproved' || action == 'edit_rejected' || action == 'withdrawn';

// ─── Header: the listing as it is now ───────────────────────────────────────

class ListingHistoryHeaderCard extends StatelessWidget {
  final ListingHistoryHeader header;
  final bool editWaiting;
  const ListingHistoryHeaderCard({super.key, required this.header, required this.editWaiting});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final photo = header.photoUrl;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: (photo == null || photo.isEmpty)
                      ? Container(
                          color: AppConstants.infoBlueBg,
                          child: const Icon(Icons.eco_rounded, color: AppConstants.primaryGreen),
                        )
                      : Image.network(
                          photo,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppConstants.infoBlueBg,
                            child: const Icon(Icons.eco_rounded, color: AppConstants.primaryGreen),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      header.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
                    ),
                    if (header.createdAt != null)
                      Text(
                        l.lhListedSince(DateFormat.yMMMd(locale).format(header.createdAt!)),
                        style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                l.lhCurrentStatus,
                style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              ListingStatusBadge.forListing(
                context,
                status: header.status,
                remainingKg: header.remainingKg,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _chip(context, Icons.scale_outlined, formatQuantityUnit(header.volumeKg, header.unit)),
              _chip(context, Icons.payments_outlined, formatPricePerUnit(header.pricePerUnit, header.unit)),
            ],
          ),
          if (editWaiting) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppConstants.buyerBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(color: AppConstants.buyerBlue.withValues(alpha: 0.30)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded, size: 16, color: AppConstants.buyerBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.lhEditWaiting,
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppConstants.buyerBlue),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(text, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecoration(ColorScheme cs) => BoxDecoration(
  color: cs.surface,
  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
  border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
);

// ─── Filter chips ───────────────────────────────────────────────────────────

class ListingHistoryFilterBar extends StatelessWidget {
  final ListingHistoryFilter selected;
  final List<WorkflowEvent> events;
  final ValueChanged<ListingHistoryFilter> onSelected;
  const ListingHistoryFilterBar({
    super.key,
    required this.selected,
    required this.events,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    String label(ListingHistoryFilter f) => switch (f) {
      ListingHistoryFilter.all => l.lhFilterAll,
      ListingHistoryFilter.decisions => l.lhFilterDecisions,
      ListingHistoryFilter.edits => l.lhFilterEdits,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in ListingHistoryFilter.values) ...[
            GestureDetector(
              onTap: () => onSelected(f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected == f ? cs.primary : cs.surface,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  border: Border.all(
                    color: selected == f ? cs.primary : cs.outline.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  '${label(f)} · ${events.where((e) => listingHistoryMatches(f, e)).length}',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected == f ? cs.onPrimary : cs.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

// ─── The timeline, grouped by day ───────────────────────────────────────────

class ListingHistoryTimeline extends StatelessWidget {
  final List<WorkflowEvent> events;
  final bool staffView;
  const ListingHistoryTimeline({super.key, required this.events, required this.staffView});

  String _dayLabel(AppLocalizations l, String locale, DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(day.year, day.month, day.day)).inDays;
    if (diff == 0) return l.lhToday;
    if (diff == 1) return l.lhYesterday;
    return DateFormat.yMMMMd(locale).format(day);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(l.lhEmptyFilter, style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)),
        ),
      );
    }
    final sorted = [...events]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final groups = <DateTime, List<WorkflowEvent>>{};
    for (final e in sorted) {
      final d = DateTime(e.createdAt.year, e.createdAt.month, e.createdAt.day);
      (groups[d] ??= []).add(e);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 14, 0, 10),
            child: Row(
              children: [
                Text(
                  _dayLabel(l, locale, entry.key),
                  style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
                Expanded(child: Divider(height: 1, color: cs.outline.withValues(alpha: 0.18))),
              ],
            ),
          ),
          for (var i = 0; i < entry.value.length; i++)
            _EventRow(
              event: entry.value[i],
              staffView: staffView,
              isLast: i == entry.value.length - 1,
            ),
        ],
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  final WorkflowEvent event;
  final bool staffView;
  final bool isLast;
  const _EventRow({required this.event, required this.staffView, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final color = workflowActionColor(event.action);
    final text = listingHistoryText(l, event.action);
    final actor = workflowActorLabel(l, event, staffView: staffView);
    final time = DateFormat.jm(locale).format(event.createdAt);
    final reason = (event.reason ?? '').trim();
    final negative = _isNegative(event.action);

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
                    color: color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
                  ),
                  child: Icon(workflowActionIcon(event.action), size: 15, color: color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: cs.outline.withValues(alpha: 0.18),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: _cardDecoration(cs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            text.title,
                            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(time, style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text.description,
                      style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    _ActorPill(label: actor, isYou: !staffView && event.by == 'you'),
                    ..._detailBlocks(context, l, cs),
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (negative ? AppConstants.errorRed : cs.onSurfaceVariant).withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                          border: Border(
                            left: BorderSide(
                              color: negative ? AppConstants.errorRed : cs.outline,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.lhReason,
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                color: negative ? AppConstants.errorRed : cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(reason, style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: cs.onSurface)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What the event carried: the figures a listing was submitted with, or the
  /// before / after of every field an edit changed.
  List<Widget> _detailBlocks(BuildContext context, AppLocalizations l, ColorScheme cs) {
    final d = event.details;
    final unit = d['unit'] as String?;
    num? n(Object? v) => v is num ? v : null;
    final blocks = <Widget>[];

    final changes = d['changes'];
    if (changes is Map) {
      final rows = <Widget>[];
      final q = changes['quantity'];
      if (q is Map && n(q['from']) != null && n(q['to']) != null) {
        rows.add(_diffRow(cs, l.lhQuantity, formatQuantityUnit(n(q['from'])!, unit), formatQuantityUnit(n(q['to'])!, unit)));
      }
      final p = changes['price'];
      if (p is Map && n(p['from']) != null && n(p['to']) != null) {
        rows.add(_diffRow(cs, l.editListingFieldPrice, formatPricePerUnit(n(p['from'])!, unit), formatPricePerUnit(n(p['to'])!, unit)));
      }
      final desc = changes['description'];
      if (desc is Map) {
        rows.add(_textDiff(cs, l, (desc['from'] as String?) ?? '', (desc['to'] as String?) ?? ''));
      }
      if (rows.isNotEmpty) {
        blocks.add(const SizedBox(height: 10));
        blocks.add(
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            ),
            child: Column(children: rows),
          ),
        );
      }
    } else if (event.action == 'submitted' && n(d['quantity']) != null && n(d['price']) != null) {
      blocks.add(const SizedBox(height: 10));
      blocks.add(
        Text(
          l.wfDetailPlaced(formatQuantityUnit(n(d['quantity'])!, unit), formatPricePerUnit(n(d['price'])!, unit)),
          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
      );
    }
    return blocks;
  }

  Widget _diffRow(ColorScheme cs, String label, String from, String to) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(label, style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant)),
        ),
        Flexible(
          child: Text(
            from,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: cs.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.arrow_forward_rounded, size: 14, color: AppConstants.primaryGreen),
        ),
        Flexible(
          child: Text(
            to,
            style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen),
          ),
        ),
      ],
    ),
  );

  Widget _textDiff(ColorScheme cs, AppLocalizations l, String from, String to) {
    Widget block(String caption, String text, bool highlight) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: highlight ? AppConstants.primaryGreen.withValues(alpha: 0.07) : cs.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption, style: GoogleFonts.inter(fontSize: 10.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(text.isEmpty ? '—' : text, style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: cs.onSurface)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.editListingFieldDescription, style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant)),
          block(l.lhBefore, from, false),
          block(l.lhAfter, to, true),
        ],
      ),
    );
  }
}

class _ActorPill extends StatelessWidget {
  final String label;
  final bool isYou;
  const _ActorPill({required this.label, required this.isYou});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = isYou ? AppConstants.primaryGreen : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isYou ? Icons.person_rounded : Icons.verified_user_outlined, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
