import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/quantity_utils.dart';
import '../../data/models/cooperative_inventory_history.dart';
import '../../data/repositories/cooperative_inventory_history_repository.dart';
import 'management_modal.dart';

/// Both tabs paginate; an error is never presented as an empty audit trail.
class CooperativeInventoryHistory extends StatefulWidget {
  const CooperativeInventoryHistory({
    super.key,
    required this.inventoryId,
    required this.itemName,
    this.loadHistory,
    this.loadBatches,
  });
  final String inventoryId, itemName;
  final Future<List<CooperativeInventoryEvent>> Function(int)? loadHistory;
  final Future<List<CooperativeHarvestBatch>> Function(int)? loadBatches;

  @override
  State<CooperativeInventoryHistory> createState() =>
      _CooperativeInventoryHistoryState();
}

class _CooperativeInventoryHistoryState
    extends State<CooperativeInventoryHistory> {
  late final CooperativeInventoryHistoryRepository? _repo =
      widget.loadHistory == null || widget.loadBatches == null
      ? CooperativeInventoryHistoryRepository()
      : null;
  final List<CooperativeInventoryEvent> _history = [];
  final List<CooperativeHarvestBatch> _batches = [];
  bool _loading = false,
      _error = false,
      _batchTab = false,
      _moreHistory = true,
      _moreBatches = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      if (_batchTab) {
        final rows =
            await (widget.loadBatches?.call(_batches.length) ??
                _repo!.batches(widget.inventoryId, _batches.length));
        _batches.addAll(rows);
        _moreBatches =
            rows.length == CooperativeInventoryHistoryRepository.pageSize;
      } else {
        final rows =
            await (widget.loadHistory?.call(_history.length) ??
                _repo!.history(widget.inventoryId, _history.length));
        _history.addAll(rows);
        _moreHistory =
            rows.length == CooperativeInventoryHistoryRepository.pageSize;
      }
    } catch (_) {
      _error = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  String _date(DateTime date, {bool time = false}) {
    final locale = Localizations.localeOf(context).toString();
    return time
        ? DateFormat.yMMMd(locale).add_Hms().format(date.toLocal())
        : DateFormat.yMMMd(locale).format(date);
  }

  Widget _detail(String label, String? value) => value == null || value.isEmpty
      ? const SizedBox.shrink()
      : SelectableText(
          '$label: $value',
          style: Theme.of(context).textTheme.bodySmall,
        );

  Widget _batch(CooperativeHarvestBatch b, AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (b.isManualAddition)
        Text(
          l.coopInvManualAddition,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      _detail(
        l.coopInvOriginalQuantity,
        '${formatQuantity(b.originalQuantity)} ${b.unit}',
      ),
      _detail(l.coopInvFarmer, b.farmerName),
      _detail(l.coopInvBatch, b.sourceBatchNumber ?? b.id),
      _detail(
        l.coopInvHarvestDate,
        b.harvestDate == null ? l.coopInvNotRecorded : _date(b.harvestDate!),
      ),
      _detail(l.coopInvStorage, b.storageLocation ?? l.coopInvNotRecorded),
      _detail(l.coopInvOffer, b.offerId),
      _detail(l.coopInvTransaction, b.sourceTransactionId),
    ],
  );

  String _action(String action, AppLocalizations l) =>
      {
        'created': l.coopInvCreated,
        'edited': l.coopInvEdited,
        'archived': l.coopInvArchived,
        'restored': l.coopInvRestored,
        'published': l.coopInvPublished,
        'unpublished': l.coopInvUnpublished,
        'restock': l.adminInvTxnRestock,
        'harvest_received': l.adminInvTxnHarvestIn,
        'adjustment': l.adminInvTxnAdjustment,
        'written_off': l.adminInvTxnWriteOff,
        'loan_issued': l.adminInvTxnLoanIssued,
        'sold': l.adminInvTxnSold,
        'returned': l.adminInvTxnReturned,
        'program_distribution': l.coopInvDistributed,
      }[action] ??
      action;

  Widget _event(CooperativeInventoryEvent e, AppLocalizations l) {
    final q = e.quantityChange;
    final fields = {
      'item_name': l.coopInvCrop,
      'source': l.adminInvSourceLabel,
      'category': l.reportsCategories,
      'unit': l.adminInvUnitLabel,
      'unit_cost': l.coopInvUnitCost,
      'reorder_level': l.adminInvReorderAt,
      'image_url': l.coopInvPhoto,
      'is_active': l.coopInvActive,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.isManualAddition
                ? l.coopInvManualAddition
                : _action(e.action, l),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(_date(e.occurredAt, time: true)),
          _detail(
            l.coopInvResponsible,
            e.actorName ?? e.actorId ?? l.coopInvNotRecorded,
          ),
          _detail(l.coopInvFarmer, e.farmerName),
          if (q != null)
            Text(
              '${q > 0 ? '+' : ''}${formatQuantity(q)} ${e.unit}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: q < 0 ? Colors.red : Colors.green,
              ),
            ),
          if (e.action == 'edited')
            for (final key in e.changedFields.where(fields.containsKey))
              _detail(
                fields[key]!,
                '${(e.details['before'] as Map?)?[key] ?? '—'} → ${(e.details['after'] as Map?)?[key] ?? '—'}',
              ),
          _detail(l.issueLoanNotes, e.details['notes'] as String?),
          if (e.batch != null) _batch(e.batch!, l),
          _detail(l.coopInvTransaction, e.transactionId),
          _detail(l.coopInvReference, e.referenceId),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final empty = _batchTab ? _batches.isEmpty : _history.isEmpty;
    final more = _batchTab ? _moreBatches : _moreHistory;
    return ManagementModalShell(
      title: l.adminInvHistoryAction,
      subtitle: widget.itemName,
      bodyIsScrollable: true,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                for (final batch in [false, true])
                  ChoiceChip(
                    label: Text(
                      batch ? l.coopInvBatches : l.adminInvHistoryAction,
                    ),
                    selected: _batchTab == batch,
                    onSelected: _loading
                        ? null
                        : (_) {
                            setState(() {
                              _batchTab = batch;
                              _error = false;
                            });
                            if ((_batchTab && _batches.isEmpty) ||
                                (!_batchTab && _history.isEmpty)) {
                              _load();
                            }
                          },
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                if (_batchTab) ...[
                  Text(l.coopInvBatchExplanation),
                  for (final b in _batches)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _batch(b, l),
                    ),
                ] else
                  for (final e in _history) _event(e, l),
                if (empty && !_loading && !_error)
                  Text(l.adminInvNoTransactionsYet),
                if (_error) ...[
                  Text(l.coopInvLoadError),
                  TextButton(onPressed: _load, child: Text(l.coopInvRetry)),
                ] else if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (more)
                  TextButton(onPressed: _load, child: Text(l.coopInvLoadMore)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
