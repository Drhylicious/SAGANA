import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/app_error_message.dart';
import '../../core/utils/item_type_utils.dart';
import '../../core/utils/life_duration.dart';
import '../../core/utils/quantity_utils.dart';
import '../../data/models/cooperative_inventory_item.dart';
import '../../data/repositories/coop_shelf_life_repository.dart';
import 'app_toast.dart';
import 'management_modal.dart';

/// "Shelf Life" for Harvested Produce, "Storage Life" for Planting Materials.
String coopLifeLabel(AppLocalizations l10n, String? itemType) =>
    itemType == kItemTypeSeeds
    ? l10n.cropMgmtStorageLifeLabel
    : l10n.shelfLifeLabel;

Color coopShelfColor(CoopShelfState state, ColorScheme cs) => switch (state) {
  CoopShelfState.good => AppConstants.successGreen,
  CoopShelfState.needsInspection => AppConstants.warningAmber,
  CoopShelfState.onHold || CoopShelfState.rottenLost => AppConstants.errorRed,
  CoopShelfState.none => cs.onSurfaceVariant,
};

/// The one-line standing of an item: days left and the end date, that it must
/// be inspected, or the quantity recorded as Rotten/Lost.
String coopShelfText(
  AppLocalizations l10n,
  InventoryItem item,
  CoopItemShelfLife shelf,
) {
  final label = coopLifeLabel(l10n, item.itemType);
  final lot = shelf.next;
  switch (shelf.state) {
    case CoopShelfState.none:
      return '';
    case CoopShelfState.rottenLost:
      return l10n.coopLifeRotten(
        formatQuantityUnit(shelf.rottenQuantity, item.unit),
      );
    case CoopShelfState.onHold:
      return l10n.coopLifeHold(label);
    case CoopShelfState.needsInspection:
      return l10n.coopLifeEndsTomorrow(label);
    case CoopShelfState.good:
      // From one year up the time left is also given in years, and the end
      // date always carries its year when it is not this year.
      return l10n.coopLifeLeft(
        label,
        lifeDurationText(l10n, lot!.daysLeft()),
        DateFormat(
          lot.expiresOn.year == DateTime.now().year ? 'MMM d' : 'MMM d, yyyy',
        ).format(lot.expiresOn),
      );
  }
}

/// The life a crop-linked item is given by Crop Management, shown when the item
/// has no stock being counted down (nothing on hand yet): "Storage Life: 365
/// days", or that it is not set. [days] is the crop's Shelf Life for Harvested
/// Produce and its Storage Life for Planting Materials.
class CoopLifeInfoLine extends StatelessWidget {
  final InventoryItem item;
  final int? days;
  const CoopLifeInfoLine({super.key, required this.item, required this.days});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final label = coopLifeLabel(l10n, item.itemType);
    final color = days == null ? AppConstants.errorRed : cs.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.timelapse_rounded, size: 14, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            days == null
                ? l10n.coopLifeNotSet(label)
                : '$label: ${lifeDurationText(l10n, days!)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// The shelf-life line of an inventory card. Nothing for an untracked item.
class CoopShelfLine extends StatelessWidget {
  final InventoryItem item;
  final CoopItemShelfLife shelf;
  const CoopShelfLine({super.key, required this.item, required this.shelf});

  @override
  Widget build(BuildContext context) {
    final state = shelf.state;
    if (state == CoopShelfState.none) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final color = coopShelfColor(state, Theme.of(context).colorScheme);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          switch (state) {
            CoopShelfState.rottenLost => Icons.delete_outline_rounded,
            CoopShelfState.onHold => Icons.block_rounded,
            CoopShelfState.needsInspection => Icons.error_outline_rounded,
            _ => Icons.timelapse_rounded,
          },
          size: 14,
          color: color,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            coopShelfText(l10n, item, shelf),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Check Produce for a cooperative inventory item: the same two answers the
/// Farmer has in Manage Inventory. "Still okay" gives the stock new remaining
/// days; "already rotten" records a quantity as Rotten/Lost. Works on the lot
/// that ends first. Returns true when something was saved.
Future<bool> showCoopCheckSheet(
  BuildContext context, {
  required InventoryItem item,
  required CoopItemShelfLife shelf,
}) async {
  if (shelf.next == null) return false;
  final changed = await showManagementModal<bool>(
    context: context,
    builder: (_) => _CoopCheckSheet(item: item, shelf: shelf),
  );
  return changed == true;
}

enum _Step { choose, stillGood, rotten }

class _CoopCheckSheet extends StatefulWidget {
  final InventoryItem item;
  final CoopItemShelfLife shelf;
  const _CoopCheckSheet({required this.item, required this.shelf});

  @override
  State<_CoopCheckSheet> createState() => _CoopCheckSheetState();
}

class _CoopCheckSheetState extends State<_CoopCheckSheet> {
  final _repo = CoopShelfLifeRepository();
  final _formKey = GlobalKey<FormState>();
  final _daysCtrl = TextEditingController();
  late final _qtyCtrl = TextEditingController(text: _plain(_lot.remaining));
  final _noteCtrl = TextEditingController();
  _Step _step = _Step.choose;
  bool _saving = false;

  CoopStockLot get _lot => widget.shelf.next!;

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void dispose() {
    _daysCtrl.dispose();
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      if (_step == _Step.stillGood) {
        await _repo.confirmStillGood(_lot.id, int.parse(_daysCtrl.text.trim()));
      } else {
        await _repo.reportRotten(
          _lot.id,
          double.parse(_qtyCtrl.text.trim()),
          note: _noteCtrl.text,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      PostActionFeedback.success(
        context,
        _step == _Step.stillGood
            ? l10n.coopCheckDoneGood
            : l10n.coopCheckDoneRotten,
      );
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _saving = false);
      PostActionFeedback.error(context, friendlyError(l10n, e, st));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final item = widget.item;
    final label = coopLifeLabel(l10n, item.itemType);
    final state = widget.shelf.state;
    final color = coopShelfColor(state, cs);

    final info = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoopShelfLine(item: item, shelf: widget.shelf),
          const SizedBox(height: 4),
          Text(
            l10n.coopCheckStock(formatQuantityUnit(_lot.remaining, item.unit)),
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );

    Widget body;
    Widget? footer;
    switch (_step) {
      case _Step.choose:
        body = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.coopCheckBody(item.itemName, label.toLowerCase()),
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.45,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 14),
            info,
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _step = _Step.stillGood),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: Text(
                  l10n.coopCheckGood(item.itemName),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _step = _Step.rotten),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.errorRed,
                  side: const BorderSide(color: AppConstants.errorRed),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(
                  l10n.coopCheckRotten(item.itemName),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        );
      case _Step.stillGood:
        body = Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              info,
              const SizedBox(height: 16),
              TextFormField(
                controller: _daysCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                decoration: InputDecoration(
                  labelText: l10n.coopCheckDaysLabel,
                  suffixText: l10n.shelfDaysUnit,
                ),
                validator: (v) {
                  final days = int.tryParse((v ?? '').trim());
                  return days == null || days < 1
                      ? l10n.coopCheckDaysInvalid
                      : null;
                },
              ),
            ],
          ),
        );
      case _Step.rotten:
        body = Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              info,
              const SizedBox(height: 16),
              TextFormField(
                controller: _qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d{0,9}(\.\d{0,2})?$'),
                  ),
                ],
                decoration: InputDecoration(
                  labelText: l10n.coopCheckQtyLabel,
                  suffixText: item.unit,
                ),
                validator: (v) {
                  final qty = double.tryParse((v ?? '').trim());
                  return qty == null ||
                          qty <= 0 ||
                          qty > _lot.remaining + 0.0001
                      ? l10n.coopCheckQtyInvalid(
                          formatQuantityUnit(_lot.remaining, item.unit),
                        )
                      : null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _noteCtrl,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: l10n.coopCheckNoteLabel,
                ),
              ),
            ],
          ),
        );
    }

    if (_step != _Step.choose) {
      final rotten = _step == _Step.rotten;
      footer = Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving
                  ? null
                  : () => setState(() => _step = _Step.choose),
              child: Text(l10n.shelfBack),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: rotten
                  ? ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.errorRed,
                      foregroundColor: Colors.white,
                    )
                  : null,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      rotten ? l10n.coopCheckSaveRotten : l10n.coopCheckSaveGood,
                    ),
            ),
          ),
        ],
      );
    }

    return ManagementModalShell(
      title: l10n.coopCheckTitle(item.itemName),
      subtitle: '${item.category} • ${itemTypeLabel(l10n, item.itemType)}',
      body: body,
      footer: footer,
    );
  }
}
