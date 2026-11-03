import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../data/models/workflow_event_model.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../data/repositories/workflow_event_repository.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/workflow_timeline.dart';

/// The history of one listing: every submission, approval, disapproval (with its
/// reason), edit request and change, with the time of each.
///
/// [staffView] (Manager / Officer) shows who did each step; the Farmer's copy
/// shows only "You" or "SP3 Cooperative" and carries no staff identity at all.
class ListingHistoryScreen extends StatefulWidget {
  final String listingId;
  final String? title;
  final bool staffView;
  const ListingHistoryScreen({
    super.key,
    required this.listingId,
    this.title,
    required this.staffView,
  });

  @override
  State<ListingHistoryScreen> createState() => _ListingHistoryScreenState();
}

class _ListingHistoryScreenState extends State<ListingHistoryScreen> {
  List<WorkflowEvent> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final events = widget.staffView
        ? await WorkflowEventRepository().fetch('listing', widget.listingId)
        : await ListingRepository().fetchMyHistory(widget.listingId);
    if (!mounted) return;
    setState(() {
      _events = events;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(
            title: widget.title == null ? l.leHistoryTitle : '${widget.title} · ${l.leHistoryTitle}',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppConstants.primaryGreen,
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      children: [
                        WorkflowTimeline(
                          events: _events,
                          staffView: widget.staffView,
                          emptyText: l.leHistoryEmpty,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
