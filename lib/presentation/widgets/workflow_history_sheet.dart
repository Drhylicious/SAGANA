import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/models/workflow_event_model.dart';
import '../../data/repositories/workflow_event_repository.dart';
import 'workflow_timeline.dart';

/// Opens the Manager / Officer's history of one order, Market Linking request or
/// enrollment (who did each step, with role, name and time) in a bottom sheet.
Future<void> showWorkflowHistorySheet(
  BuildContext context, {
  required String entityType,
  required String entityId,
  required String title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusXl)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (ctx, controller) => _HistorySheet(
        entityType: entityType,
        entityId: entityId,
        title: title,
        controller: controller,
      ),
    ),
  );
}

class _HistorySheet extends StatefulWidget {
  final String entityType;
  final String entityId;
  final String title;
  final ScrollController controller;
  const _HistorySheet({
    required this.entityType,
    required this.entityId,
    required this.title,
    required this.controller,
  });

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  late final Future<List<WorkflowEvent>> _future =
      WorkflowEventRepository().fetch(widget.entityType, widget.entityId);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
        const SizedBox(height: 14),
        Text(
          widget.title,
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: cs.onSurface),
        ),
        Text(
          l.wfActivityTitle,
          style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<WorkflowEvent>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return WorkflowTimeline(events: snapshot.data ?? const [], staffView: true);
          },
        ),
      ],
    );
  }
}

/// The same history, inline on a detail screen: a titled card listing every step
/// with the Manager / Officer who did it. Reloads when [refreshKey] changes (for
/// example after a status action on the screen).
class WorkflowActivityCard extends StatefulWidget {
  final String entityType;
  final String entityId;
  final Object? refreshKey;
  const WorkflowActivityCard({
    super.key,
    required this.entityType,
    required this.entityId,
    this.refreshKey,
  });

  @override
  State<WorkflowActivityCard> createState() => _WorkflowActivityCardState();
}

class _WorkflowActivityCardState extends State<WorkflowActivityCard> {
  List<WorkflowEvent>? _events;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WorkflowActivityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey ||
        oldWidget.entityId != widget.entityId) {
      _load();
    }
  }

  Future<void> _load() async {
    final events = await WorkflowEventRepository().fetch(widget.entityType, widget.entityId);
    if (!mounted) return;
    setState(() => _events = events);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                l.wfActivityTitle,
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_events == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            WorkflowTimeline(events: _events!, staffView: true),
        ],
      ),
    );
  }
}
