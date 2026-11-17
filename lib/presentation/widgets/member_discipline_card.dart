import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/app_utils.dart';
import '../../data/models/member_restriction.dart';
import '../../data/repositories/member_restriction_repository.dart';
import 'address_map_widgets.dart' show AddressSectionCard;
import 'feature_restriction_notice.dart' show restrictionReasonText;

/// A member's restrictions and suspensions on Member Details: what is in force
/// now, then the full history (newest first) with the reason, the dates, how each
/// one ended and who acted. Read-only: restricting and lifting happen from the
/// ⋯ menu on the Members list, the one place staff act on a member.
class MemberDisciplineCard extends StatefulWidget {
  final String memberId;
  const MemberDisciplineCard({super.key, required this.memberId});

  @override
  State<MemberDisciplineCard> createState() => _MemberDisciplineCardState();
}

class _MemberDisciplineCardState extends State<MemberDisciplineCard> {
  final _repo = MemberRestrictionRepository();
  List<DisciplineEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await _repo.fetchHistory(widget.memberId);
      if (mounted) setState(() => _entries = entries);
    } catch (_) {
      if (mounted) setState(() => _entries = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final entries = _entries;
    final active = [
      for (final e in entries ?? const <DisciplineEntry>[])
        if (e.isRestriction && e.status == 'active') e,
    ];

    return AddressSectionCard(
      title: l10n.restrictHistoryTitle,
      child: entries == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : entries.isEmpty
          ? Text(
              l10n.restrictHistoryEmpty,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (active.isNotEmpty) ...[
                  Text(
                    l10n.restrictCurrentTitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in active)
                        if (e.feature != null)
                          _pill(
                            e.feature!.label(l10n),
                            AppConstants.warningAmber,
                          ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
                  const SizedBox(height: 14),
                ],
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) ...[
                    const SizedBox(height: 12),
                    Divider(
                      height: 1,
                      color: cs.outline.withValues(alpha: 0.12),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _EntryRow(
                    key: ValueKey('discipline-entry-$i'),
                    entry: entries[i],
                  ),
                ],
              ],
            ),
    );
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
    ),
    child: Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.onSecondaryContainer
            : const Color(0xFF8A5A00),
      ),
    ),
  );
}

class _EntryRow extends StatelessWidget {
  final DisciplineEntry entry;
  const _EntryRow({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final e = entry;

    final (IconData icon, Color color, String title) = switch (e.kind) {
      'suspension' => (
        Icons.block_rounded,
        AppConstants.errorRed,
        l10n.restrictHistorySuspended,
      ),
      'reactivation' => (
        Icons.check_circle_outline_rounded,
        AppConstants.successGreen,
        l10n.restrictHistoryReactivated,
      ),
      _ => (
        Icons.lock_outline_rounded,
        AppConstants.warningAmber,
        e.feature?.label(l10n) ?? '',
      ),
    };

    String date(DateTime d) => AppUtils.formatDate(d, l10n.localeName);
    final statusText = e.isRestriction
        ? switch (e.status) {
            'active' => l10n.restrictStatusActive,
            'lifted' => l10n.restrictStatusLifted,
            'ended' => l10n.restrictStatusEnded,
            'closed' => l10n.restrictStatusClosed,
            _ => e.status,
          }
        : null;

    final lines = <String>[
      if (e.reason.isNotEmpty) restrictionReasonText(l10n, e.reason),
      if (e.isRestriction) ...[
        l10n.restrictHistoryStarted(date(e.startedAt)),
        if (e.status == 'active' && e.endsAt != null)
          l10n.restrictHistoryEnds(date(e.endsAt!)),
        if (e.status != 'active' && e.endedAt != null)
          l10n.restrictHistoryEnded(date(e.endedAt!)),
      ] else
        date(e.startedAt),
      if ((e.actorName ?? '').trim().isNotEmpty)
        l10n.restrictHistoryBy(e.actorName!.trim()),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  if (statusText != null)
                    Text(
                      statusText,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: e.status == 'active'
                            ? (Theme.of(context).brightness == Brightness.dark
                                  ? cs.onSecondaryContainer
                                  : const Color(0xFF8A5A00))
                            : cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    line,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      height: 1.35,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
