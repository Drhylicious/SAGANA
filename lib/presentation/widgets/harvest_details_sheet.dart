import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/localized_labels.dart';
import '../../core/utils/quantity_utils.dart';
import '../../data/models/farmer_crop_model.dart';
import '../../data/models/harvest_model.dart';
import '../../data/models/inventory_batch_model.dart';
import '../../data/models/shelf_life_model.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../data/repositories/shelf_life_repository.dart';
import 'management_modal.dart';
import 'shelf_life_widgets.dart';
import 'stock_widgets.dart';

/// Everything recorded about one harvest, read-only: the harvest itself, the crop
/// it came from in the Crop Roster, where its stock stands in Inventory Management,
/// and its shelf life with every change made to it.
///
/// ONE sheet for both sides: the Farmer's Harvest History and the Manager /
/// Officer's Farmer Details > Harvest open this same sheet, so the two always show
/// the same details. Nothing in it can change a record.
void showHarvestDetailsSheet(
  BuildContext context, {
  required HarvestModel harvest,
  FarmerCropModel? crop,
}) {
  showManagementModal<void>(
    context: context,
    builder: (_) => _HarvestDetailsSheet(harvest: harvest, crop: crop),
  );
}

class _HarvestDetailsSheet extends StatefulWidget {
  final HarvestModel harvest;
  final FarmerCropModel? crop;
  const _HarvestDetailsSheet({required this.harvest, this.crop});

  @override
  State<_HarvestDetailsSheet> createState() => _HarvestDetailsSheetState();
}

class _HarvestDetailsSheetState extends State<_HarvestDetailsSheet> {
  InventoryBatchModel? _batch;
  List<ShelfLifeEvent> _events = const [];
  String? _programName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final h = widget.harvest;
    // A harvest not synced yet has no batch, and no history, to read.
    if (!h.isSynced) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final results = await Future.wait([
      InventoryRepository().fetchBatchForHarvest(h.id),
      _programNameOf(h.sourceProgramId),
    ]);
    final batch = results[0] as InventoryBatchModel?;
    final events = batch == null
        ? const <ShelfLifeEvent>[]
        : (await ShelfLifeRepository().fetchEvents(batchId: batch.id)).reversed
              .toList();
    if (!mounted) return;
    setState(() {
      _batch = batch;
      _events = events;
      _programName = results[1] as String?;
      _loading = false;
    });
  }

  Future<String?> _programNameOf(String? programId) async {
    if (programId == null) return null;
    try {
      final row = await Supabase.instance.client
          .from('cooperative_programs')
          .select('program_name')
          .eq('id', programId)
          .maybeSingle();
      final n = row?['program_name'] as String?;
      return (n == null || n.isEmpty) ? null : n;
    } catch (_) {
      return null;
    }
  }

  // Shown when the crop has no photo: the default crop icon the list row uses.
  Widget _imagePlaceholder(BuildContext context) => Container(
    width: double.infinity,
    height: 140,
    color: AppConstants.primaryGreen.withValues(alpha: 0.10),
    child: Icon(
      Icons.eco_rounded,
      color: Theme.of(context).colorScheme.primary,
      size: 40,
    ),
  );

  String _rosterStatus(AppLocalizations l10n, FarmerCropModel crop) {
    if (crop.isFromProgram) return l10n.harvDetRosterFromProgram;
    if (crop.isRejected) return l10n.harvDetRosterRequestRejected;
    if (crop.isPendingApproval) return l10n.harvDetRosterRequestPending;
    if (crop.requestStatus == 'approved') return l10n.harvDetRosterRequestApproved;
    return l10n.harvDetRosterFromCatalog;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final h = widget.harvest;
    final crop = widget.crop;
    final date = DateFormat('MMM d, yyyy');

    return ManagementModalShell(
      title: h.cropName,
      subtitle: h.variety != null && h.variety!.isNotEmpty ? h.variety : null,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: crop?.hasDisplayImage == true
                ? Image.network(
                    crop!.displayImageUrl!,
                    width: double.infinity,
                    height: 140,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _imagePlaceholder(context),
                  )
                : _imagePlaceholder(context),
          ),
          const SizedBox(height: 14),

          // ── The harvest ───────────────────────────────────────────────────
          _SectionTitle(l10n.harvDetSectionHarvest),
          _DetailRow(
            label: l10n.issueLoanQuantity,
            value: formatQuantityUnit(h.quantityKg, h.unit),
          ),
          _DetailRow(
            label: l10n.buyerListingCategory,
            value: localizeBuiltinLabel(l10n, h.cropCategory),
          ),
          _DetailRow(label: l10n.enhBatchNumber, value: h.displayBatch),
          _DetailRow(
            label: l10n.enhStorageLocation,
            value: h.storageLocation ?? '—',
          ),
          _DetailRow(
            label: l10n.enhHarvestDate,
            value: DateFormat('MMM d, yyyy · h:mm a').format(h.harvestDate),
          ),
          _DetailRow(
            label: l10n.harvDetSource,
            value: h.isReceivedFromProgram
                ? l10n.harvDetSourceProgram
                : l10n.harvDetSourceOwn,
          ),
          if (h.isReceivedFromProgram && _programName != null)
            _DetailRow(label: l10n.harvDetProgram, value: _programName!),
          _DetailRow(
            label: l10n.enhSyncStatus,
            value: h.isSynced ? l10n.reportsSynced : l10n.reportsPendingSync,
          ),

          // ── The crop in the Crop Roster ───────────────────────────────────
          if (crop != null) ...[
            _SectionTitle(l10n.harvDetSectionRoster),
            if (crop.cropType != null)
              _DetailRow(
                label: l10n.harvDetMarketType,
                value: crop.marketTypeLabel,
              ),
            _DetailRow(
              label: l10n.harvDetRosterStatus,
              value: _rosterStatus(l10n, crop),
            ),
            _DetailRow(
              label: l10n.harvDetRosterAddedOn,
              value: date.format(crop.createdAt.toLocal()),
            ),
          ],

          // ── Stock in Inventory Management ─────────────────────────────────
          if (_batch != null) ...[
            _SectionTitle(l10n.harvDetSectionStock),
            _DetailRow(
              label: l10n.stockFigureTotal,
              value: formatQuantityUnit(_batch!.quantityKg, _batch!.unit),
            ),
            _DetailRow(
              label: l10n.stockFigureAvailable,
              value: formatQuantityUnit(_batch!.availableKg, _batch!.unit),
            ),
            _DetailRow(
              label: l10n.stockFigureReserved,
              value: formatQuantityUnit(_batch!.reservedKg, _batch!.unit),
            ),
            _DetailRow(
              label: l10n.stockFigureSold,
              value: formatQuantityUnit(_batch!.soldKg, _batch!.unit),
            ),
            if (_batch!.adjustedKg > 0)
              _DetailRow(
                label: l10n.stockFigureAdjusted,
                value: formatQuantityUnit(_batch!.adjustedKg, _batch!.unit),
              ),
            if (h.spoiledKg > 0)
              _DetailRow(
                label: l10n.harvDetStockLost,
                value: formatQuantityUnit(h.spoiledKg, h.unit),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showStockHistorySheet(context, batch: _batch!),
                icon: const Icon(Icons.history_rounded, size: 18),
                label: Text(l10n.harvDetStockHistoryButton),
              ),
            ),
          ],

          // ── Shelf life ────────────────────────────────────────────────────
          ..._shelfLifeSection(context, l10n, cs, date),

          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _shelfLifeSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    DateFormat date,
  ) {
    final h = widget.harvest;
    final s = _batch?.shelfLife;
    final days = s?.days ?? s?.defaultDays ?? h.shelfLifeDays;
    final stage = s?.stage ?? ShelfLifeStage.untracked;

    return [
      _SectionTitle(l10n.harvDetSectionShelf),
      _DetailRow(
        label: l10n.harvDetShelfDuration,
        value: days == null ? l10n.harvDetShelfNotSet : l10n.shelfDaysCount(days),
      ),
      if (s?.defaultDays != null && s?.days != null && s!.days != s.defaultDays)
        _DetailRow(
          label: l10n.harvDetShelfDefault,
          value: l10n.shelfDaysCount(s.defaultDays!),
        ),
      if (s?.startsOn != null)
        _DetailRow(
          label: l10n.harvDetShelfStarts,
          value: date.format(s!.startsOn!),
        ),
      if (s?.expiresOn != null)
        _DetailRow(
          label: l10n.harvDetShelfExpires,
          value: date.format(s!.expiresOn!),
        ),
      if (s != null)
        _DetailRow(
          label: l10n.harvDetShelfStatus,
          value: shelfLifeStatusText(l10n, s),
          valueColor: shelfLifeColor(context, stage),
        ),
      if (s?.confirmedAt != null)
        _DetailRow(
          label: l10n.harvDetShelfConfirmed,
          value: date.format(s!.confirmedAt!.toLocal()),
        ),
      if (s != null && s.hasLoss)
        _DetailRow(
          label: l10n.harvDetStockLost,
          value: [
            formatQuantityUnit(s.spoiledKg, h.unit),
            if (s.spoiledAt != null) date.format(s.spoiledAt!.toLocal()),
          ].join(' · '),
        ),
      if (_events.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          l10n.harvDetShelfHistory,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final e in _events) _EventRow(event: e, label: _eventLabel(l10n, e)),
      ],
    ];
  }

  String _eventLabel(AppLocalizations l10n, ShelfLifeEvent e) {
    switch (e.eventType) {
      case 'held_overdue':
        return l10n.harvDetEventHeld;
      case 'reminder_sent':
        return l10n.harvDetEventReminder;
      case 'confirmed_good':
        return l10n.harvDetEventConfirmed(e.days ?? 0);
      case 'reported_rotten':
        return l10n.harvDetEventRotten(formatQuantityUnit(e.quantity, e.unit));
      case 'discount_applied':
        return l10n.harvDetEventDiscount;
      case 'listing_unavailable':
        return l10n.harvDetEventUnavailable;
      case 'review_requested':
        return l10n.harvDetEventReviewRequested;
      case 'review_approved':
        return l10n.harvDetEventReviewApproved;
      default:
        return e.eventType;
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _DetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final ShelfLifeEvent event;
  final String label;
  const _EventRow({required this.event, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = event.isLoss
        ? AppConstants.errorRed
        : event.eventType == 'confirmed_good' ||
              event.eventType == 'review_approved'
        ? AppConstants.successGreen
        : AppConstants.warningAmber;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 10),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  DateFormat('MMM d, yyyy · h:mm a').format(event.createdAt),
                  style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
                ),
                if (event.note != null && event.note!.trim().isNotEmpty)
                  Text(
                    event.note!,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
