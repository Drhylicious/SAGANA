import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/quantity_utils.dart';
import '../../data/models/inventory_batch_model.dart';
import '../../data/models/stock_movement_model.dart';
import '../../data/repositories/stock_movement_repository.dart';

/// Shared stock display for a Farmer's harvest batch: the figures a batch is made
/// of, and its movement history. available + reserved + sold (+ adjusted) is
/// always the harvested total, so the row reads as a breakdown of it.

/// Available / Reserved / Sold of one batch (and Adjusted when the Farmer has
/// taken some out), in the batch's own unit.
class StockFiguresRow extends StatelessWidget {
  final InventoryBatchModel batch;
  const StockFiguresRow({super.key, required this.batch});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget cell(String label, double qty, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 9,
              letterSpacing: 0.5,
              color: AppConstants.outline,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            formatQuantityUnit(qty, batch.unit),
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cell(l10n.stockFigureAvailable, batch.availableKg, AppConstants.successGreen),
        cell(l10n.stockFigureReserved, batch.reservedKg, AppConstants.warningAmber),
        cell(l10n.stockFigureSold, batch.soldKg, AppConstants.primaryGreen),
        if (batch.adjustedKg > 0)
          cell(l10n.stockFigureAdjusted, batch.adjustedKg, AppConstants.outline),
      ],
    );
  }
}

String _movementLabel(AppLocalizations l10n, String type) {
  switch (type) {
    case 'harvested':
      return l10n.stockMovHarvested;
    case 'reserved':
      return l10n.stockMovReserved;
    case 'released':
      return l10n.stockMovReleased;
    case 'sold':
      return l10n.stockMovSold;
    case 'sale_reversed':
      return l10n.stockMovSaleReversed;
    case 'adjusted':
      return l10n.stockMovAdjusted;
    case 'adjustment_reversed':
      return l10n.stockMovAdjustmentReversed;
    case 'quantity_changed':
      return l10n.stockMovQuantityChanged;
    default:
      return type;
  }
}

String _channelLabel(AppLocalizations l10n, String? channel) {
  switch (channel) {
    case 'marketplace':
      return l10n.stockChanMarketplace;
    case 'cooperative_offer':
      return l10n.stockChanCoopOffer;
    case 'informal_sale':
      return l10n.stockChanInformal;
    case 'market_linking':
      return l10n.stockChanMarketLinking;
    default:
      return l10n.stockChanManual;
  }
}

IconData _movementIcon(String type) {
  switch (type) {
    case 'harvested':
      return Icons.agriculture_rounded;
    case 'reserved':
      return Icons.lock_outline_rounded;
    case 'released':
      return Icons.lock_open_rounded;
    case 'sold':
      return Icons.sell_rounded;
    case 'sale_reversed':
    case 'adjustment_reversed':
      return Icons.undo_rounded;
    case 'adjusted':
    case 'quantity_changed':
      return Icons.tune_rounded;
    default:
      return Icons.swap_vert_rounded;
  }
}

Color _movementColor(String type) {
  switch (type) {
    case 'harvested':
      return AppConstants.primaryGreen;
    case 'reserved':
      return AppConstants.warningAmber;
    case 'released':
      return AppConstants.buyerBlue;
    case 'sold':
      return AppConstants.successGreen;
    default:
      return AppConstants.outline;
  }
}

/// Opens the stock history of [batch] in a bottom sheet.
Future<void> showStockHistorySheet(
  BuildContext context, {
  required InventoryBatchModel batch,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _StockHistorySheet(batch: batch),
  );
}

class _StockHistorySheet extends StatefulWidget {
  final InventoryBatchModel batch;
  const _StockHistorySheet({required this.batch});

  @override
  State<_StockHistorySheet> createState() => _StockHistorySheetState();
}

class _StockHistorySheetState extends State<_StockHistorySheet> {
  final _repo = StockMovementRepository();
  late Future<List<StockMovementModel>> _future = _repo.fetchForBatch(
    widget.batch.id,
  );

  void _retry() => setState(() => _future = _repo.fetchForBatch(widget.batch.id));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final batch = widget.batch;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outline.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.stockHistoryTitle,
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '${batch.cropName} • ${formatBatchNumber(batch.batchNumber)}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${l10n.stockFigureTotal}: ${formatQuantityUnit(batch.quantityKg, batch.unit)}',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: StockFiguresRow(batch: batch),
          ),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
          Expanded(
            child: FutureBuilder<List<StockMovementModel>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.stockHistoryLoadError,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        TextButton(
                          onPressed: _retry,
                          child: Text(l10n.retry),
                        ),
                      ],
                    ),
                  );
                }
                final rows = snap.data ?? const <StockMovementModel>[];
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      l10n.stockHistoryEmpty,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: cs.outline.withValues(alpha: 0.08),
                  ),
                  itemBuilder: (_, i) => _MovementTile(movement: rows[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  final StockMovementModel movement;
  const _MovementTile({required this.movement});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final m = movement;
    final color = _movementColor(m.movementType);
    // The harvest itself and manual updates carry no selling channel.
    final source = m.movementType == 'harvested'
        ? null
        : _channelLabel(l10n, m.channel);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(_movementIcon(m.movementType), size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _movementLabel(l10n, m.movementType),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      formatQuantityUnit(m.quantity, m.unit),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
                if (source != null)
                  Text(
                    source,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  l10n.stockBalanceLine(
                    formatQuantityUnit(m.availableAfter, m.unit),
                    formatQuantityUnit(m.reservedAfter, m.unit),
                    formatQuantityUnit(m.soldAfter, m.unit),
                  ),
                  style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
                ),
                Text(
                  DateFormat('MMM d, yyyy · h:mm a').format(m.createdAt),
                  style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
                ),
                if (m.note != null && m.note!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      m.note!,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant,
                      ),
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
