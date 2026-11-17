import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../data/models/workflow_event_model.dart';
import '../../../data/repositories/admin_listing_repository.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../data/repositories/workflow_event_repository.dart';
import '../../widgets/listing_history_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

/// The history of one listing: its submission, every approval or disapproval (with
/// the reason), each edit and what it changed, and the date and time of all of it.
///
/// A header shows the listing as it is now, and a filter narrows the history to
/// decisions or edits. [staffView] (Manager / Officer) shows who did each step;
/// the Farmer's copy shows only "You" or "SP3 Cooperative" and carries no staff
/// identity at all.
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
  ListingHistoryHeader? _header;
  ListingHistoryFilter _filter = ListingHistoryFilter.all;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      widget.staffView
          ? WorkflowEventRepository().fetch("listing", widget.listingId)
          : ListingRepository().fetchMyHistory(widget.listingId),
      _loadHeader(),
    ]);
    if (!mounted) return;
    setState(() {
      _events = results[0] as List<WorkflowEvent>;
      _header = results[1] as ListingHistoryHeader?;
      _loading = false;
    });
  }

  Future<ListingHistoryHeader?> _loadHeader() async {
    if (widget.staffView) {
      final l = await AdminListingRepository().fetchListingById(
        widget.listingId,
      );
      if (l == null) return null;
      return ListingHistoryHeader(
        name: l.canonicalCropName ?? l.cropName,
        photoUrl: l.listingPhotoUrl,
        status: l.status,
        remainingKg: l.remainingKg,
        volumeKg: l.volumeKg,
        pricePerUnit: l.pricePerKg,
        unit: l.unit,
        createdAt: l.createdAt,
      );
    }
    final l = await ListingRepository().fetchListing(widget.listingId);
    if (l == null) return null;
    return ListingHistoryHeader(
      name: l.displayName,
      photoUrl: l.photoUrl,
      status: l.status,
      remainingKg: l.remainingKg,
      volumeKg: l.volumeKg,
      pricePerUnit: l.pricePerKg,
      unit: l.unit,
      createdAt: l.createdAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final shown = _events
        .where((e) => listingHistoryMatches(_filter, e))
        .toList();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(
            title: l.leHistoryTitle,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: _load,
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SkeletonList(),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      children: [
                        if (_header != null) ...[
                          ListingHistoryHeaderCard(
                            header: _header!,
                            editWaiting: listingHistoryHasOpenEdit(_events),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_events.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.history_rounded,
                                  size: 44,
                                  color: cs.outline.withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  l.leHistoryEmpty,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          ListingHistoryFilterBar(
                            selected: _filter,
                            events: _events,
                            onSelected: (f) => setState(() => _filter = f),
                          ),
                          ListingHistoryTimeline(
                            events: shown,
                            staffView: widget.staffView,
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
