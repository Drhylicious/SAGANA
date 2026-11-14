import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/db_error_utils.dart';
import '../../core/utils/quantity_utils.dart';
import '../../data/models/inventory_batch_model.dart';
import '../../data/models/marketplace_listing_model.dart';
import '../../data/models/shelf_life_model.dart';
import '../../data/repositories/listing_repository.dart';
import '../../data/repositories/shelf_life_repository.dart';
import 'app_toast.dart';
import 'management_modal.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shelf-life display and the Farmer's "check your produce" sheet.
//
// Used by the Farmer (their own harvests and listings) and by the Manager /
// Officer (reviewing listings). Never imported by a Buyer screen: shelf-life
// information is not shown to Buyers.
// ─────────────────────────────────────────────────────────────────────────────

/// The colour a shelf-life stage is shown in.
Color shelfLifeColor(BuildContext context, ShelfLifeStage stage) {
  switch (stage) {
    case ShelfLifeStage.fresh:
      return AppConstants.successGreen;
    case ShelfLifeStage.nearExpiry:
    case ShelfLifeStage.expiresToday:
      return AppConstants.warningAmber;
    case ShelfLifeStage.expired:
    case ShelfLifeStage.hold:
      return AppConstants.errorRed;
    case ShelfLifeStage.untracked:
      return Theme.of(context).colorScheme.outline;
  }
}

/// One sentence for where a batch stands: "3 days left", "Ends today",
/// "Past its shelf life", "Confirm before selling", "Not tracked".
String shelfLifeStatusText(AppLocalizations l10n, BatchShelfLife? s) {
  final stage = s?.stage ?? ShelfLifeStage.untracked;
  switch (stage) {
    case ShelfLifeStage.untracked:
      return l10n.shelfNotTracked;
    case ShelfLifeStage.fresh:
      return l10n.shelfDaysLeft(s!.daysLeft!);
    case ShelfLifeStage.nearExpiry:
      return l10n.shelfOneDayLeft;
    case ShelfLifeStage.expiresToday:
      return l10n.shelfEndsToday;
    case ShelfLifeStage.expired:
      return l10n.shelfPast;
    case ShelfLifeStage.hold:
      return l10n.shelfOnHold;
  }
}

/// A compact shelf-life line for a card: icon, "Shelf life", the status, and the
/// expiry date. [dense] drops the date (for narrow rows).
class ShelfLifeLine extends StatelessWidget {
  final BatchShelfLife? shelfLife;
  final bool dense;

  const ShelfLifeLine({super.key, required this.shelfLife, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final s = shelfLife;
    final stage = s?.stage ?? ShelfLifeStage.untracked;
    final color = shelfLifeColor(context, stage);
    final until = s?.expiresOn == null || dense
        ? null
        : DateFormat('MMM d').format(s!.expiresOn!);

    return Row(
      children: [
        Icon(Icons.timelapse_rounded, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          '${l10n.shelfLifeLabel}: ',
          style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
        ),
        Flexible(
          child: Text(
            until == null
                ? shelfLifeStatusText(l10n, s)
                : '${shelfLifeStatusText(l10n, s)} · ${l10n.shelfUntil(until)}',
            maxLines: 1,
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

/// The price rule in one sentence: "Fixed at ₱50.00 per kg by the cooperative."
/// or "Allowed price: ₱50.00 to ₱80.00 per kg."
String listingPriceRuleText(BuildContext context, ListingPriceRule rule) {
  final l10n = AppLocalizations.of(context);
  return rule.isLocked
      ? l10n.listingPriceFixedNote(rule.max.toStringAsFixed(2), rule.unit)
      : l10n.listingPriceRangeNote(
          rule.lowest.toStringAsFixed(2),
          rule.max.toStringAsFixed(2),
          rule.unit,
        );
}

/// The small line under a listing's price field that states its price rule.
class ListingPriceRuleNote extends StatelessWidget {
  final ListingPriceRule rule;
  const ListingPriceRuleNote({super.key, required this.rule});

  @override
  Widget build(BuildContext context) {
    final color = rule.isLocked
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : AppConstants.warningAmber;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            rule.isLocked ? Icons.lock_outline_rounded : Icons.straighten_rounded,
            size: 11,
            color: color,
          ),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: Text(
            listingPriceRuleText(context, rule),
            style: GoogleFonts.inter(
              fontSize: 10,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// A small filled tag ("ROTTEN", "UNAVAILABLE", "DISCOUNTED").
class ShelfLifeTag extends StatelessWidget {
  final String label;
  final Color color;

  const ShelfLifeTag({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// A tinted note with an icon (a warning or an explanation inside a card).
class ShelfLifeNote extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  final Widget? action;

  const ShelfLifeNote({
    super.key,
    required this.text,
    required this.color,
    this.icon = Icons.info_outline_rounded,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The Farmer checks the produce: "still okay" or "already rotten"
// ─────────────────────────────────────────────────────────────────────────────

/// Opens the produce check for [batch]. Returns true when something changed
/// (the caller reloads). The two answers are the ones the near-expiry
/// notification offers.
Future<bool> showShelfLifeCheckSheet(
  BuildContext context, {
  required InventoryBatchModel batch,
  // 'good' or 'rotten' opens straight on that answer (the notification's two
  // buttons); anything else opens on the choice.
  String? answer,
}) async {
  final changed = await showManagementModal<bool>(
    context: context,
    builder: (_) => _ShelfLifeCheckSheet(batch: batch, answer: answer),
  );
  return changed == true;
}

enum _CheckStep { choose, stillGood, rotten }

class _ShelfLifeCheckSheet extends StatefulWidget {
  final InventoryBatchModel batch;
  final String? answer;
  const _ShelfLifeCheckSheet({required this.batch, this.answer});

  @override
  State<_ShelfLifeCheckSheet> createState() => _ShelfLifeCheckSheetState();
}

class _ShelfLifeCheckSheetState extends State<_ShelfLifeCheckSheet> {
  final _repo = ShelfLifeRepository();
  final _formKey = GlobalKey<FormState>();
  final _daysCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  late _CheckStep _step = switch (widget.answer) {
    'good' => _CheckStep.stillGood,
    'rotten' => _CheckStep.rotten,
    _ => _CheckStep.choose,
  };
  bool _saving = false;
  bool _loading = true;

  // A published listing of this batch that was already discounted or made
  // unavailable: confirming then needs the cooperative's approval, and the
  // Farmer may set the price to go with it.
  MarketplaceListingModel? _affectedListing;
  ListingPriceRule? _priceRule;

  InventoryBatchModel get batch => widget.batch;

  @override
  void initState() {
    super.initState();
    _loadListing();
  }

  @override
  void dispose() {
    _daysCtrl.dispose();
    _priceCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadListing() async {
    final listings = await ListingRepository().fetchListings();
    MarketplaceListingModel? affected;
    for (final l in listings) {
      if (l.inventoryBatchId == batch.id &&
          (l.isShelfUnavailable || l.isShelfDiscounted) &&
          l.remainingKg > 0) {
        affected = l;
        break;
      }
    }
    ListingPriceRule? rule;
    if (affected != null) {
      rule = await _repo.fetchPriceRule(batch.id, listingId: affected.id);
      final start = affected.shelfLife?.preDiscountPrice ?? affected.pricePerKg;
      _priceCtrl.text = (rule != null && rule.isLocked ? rule.max : start)
          .toStringAsFixed(2);
    }
    if (!mounted) return;
    setState(() {
      _affectedListing = affected;
      _priceRule = rule;
      _loading = false;
    });
  }

  Future<void> _confirmGood() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final result = await _repo.confirmStillGood(
        batchId: batch.id,
        days: int.parse(_daysCtrl.text.trim()),
        price: _affectedListing == null
            ? null
            : double.parse(_priceCtrl.text.trim()),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      PostActionFeedback.success(
        context,
        result == ShelfLifeConfirmResult.submitted
            ? l10n.shelfConfirmSubmitted
            : l10n.shelfConfirmApplied,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      PostActionFeedback.error(context, friendlyErrorMessage(e));
    }
  }

  Future<void> _reportRotten() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final lost = await _repo.reportRotten(
        batchId: batch.id,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      PostActionFeedback.success(
        context,
        l10n.shelfRottenRecorded(formatQuantityUnit(lost, batch.unit)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      PostActionFeedback.error(context, friendlyErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final subtitle = '${batch.cropName} • ${formatBatchNumber(batch.batchNumber)}';

    switch (_step) {
      case _CheckStep.choose:
        return ManagementModalShell(
          title: l10n.shelfCheckTitle(batch.cropName),
          subtitle: subtitle,
          body: _chooseBody(l10n),
        );
      case _CheckStep.stillGood:
        return ManagementModalShell(
          title: l10n.shelfStillGoodTitle,
          subtitle: subtitle,
          body: _stillGoodBody(l10n),
          footer: ManagementModalActions(
            cancelLabel: l10n.shelfBack,
            onCancel: _saving
                ? null
                : () => setState(() => _step = _CheckStep.choose),
            primaryLabel: _saving
                ? l10n.saving
                : _affectedListing != null
                ? l10n.shelfSubmitForApproval
                : l10n.shelfConfirmAction,
            isLoading: _saving,
            onPrimary: _confirmGood,
          ),
        );
      case _CheckStep.rotten:
        return ManagementModalShell(
          title: l10n.shelfRottenTitle,
          subtitle: subtitle,
          body: _rottenBody(l10n),
          footer: ManagementModalActions(
            cancelLabel: l10n.shelfBack,
            onCancel: _saving
                ? null
                : () => setState(() => _step = _CheckStep.choose),
            primaryLabel: _saving ? l10n.saving : l10n.shelfRottenAction,
            isLoading: _saving,
            isDestructive: true,
            onPrimary: _reportRotten,
          ),
        );
    }
  }

  Widget _chooseBody(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final s = batch.shelfLife;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.shelfCheckBody(batch.cropName),
          style: GoogleFonts.inter(
            fontSize: 13,
            height: 1.45,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShelfLifeLine(shelfLife: s),
              const SizedBox(height: 6),
              Text(
                l10n.shelfCheckStock(
                  formatQuantityUnit(batch.availableKg, batch.unit),
                  formatQuantityUnit(batch.reservedKg, batch.unit),
                ),
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => setState(() => _step = _CheckStep.stillGood),
          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: Text(
            l10n.shelfActionStillOkay(batch.cropName),
            textAlign: TextAlign.center,
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: AppConstants.primaryGreen,
            foregroundColor: Colors.white,
            textStyle: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => setState(() => _step = _CheckStep.rotten),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: Text(
            l10n.shelfActionRotten(batch.cropName),
            textAlign: TextAlign.center,
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: AppConstants.errorRed,
            side: BorderSide(
              color: AppConstants.errorRed.withValues(alpha: 0.5),
            ),
            textStyle: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _stillGoodBody(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final listing = _affectedListing;
    final rule = _priceRule;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.shelfStillGoodBody,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.45,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _daysCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            decoration: InputDecoration(
              labelText: l10n.shelfRemainingDaysLabel,
              suffixText: l10n.shelfDaysUnit,
              helperText: l10n.shelfRemainingDaysHelper,
              helperMaxLines: 2,
            ),
            validator: (v) {
              final days = int.tryParse((v ?? '').trim());
              if (days == null || days < 1 || days > 365) {
                return l10n.shelfRemainingDaysInvalid;
              }
              return null;
            },
          ),
          if (listing != null) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _priceCtrl,
              enabled: !(rule?.isLocked ?? false),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [DecimalInputFormatter()],
              decoration: InputDecoration(
                labelText: l10n.shelfListingPriceLabel(listing.unit),
                prefixText: '₱ ',
                helperText: rule == null
                    ? null
                    : rule.isLocked
                    ? l10n.listingPriceFixedNote(
                        rule.max.toStringAsFixed(2),
                        rule.unit,
                      )
                    : l10n.listingPriceRangeNote(
                        rule.lowest.toStringAsFixed(2),
                        rule.max.toStringAsFixed(2),
                        rule.unit,
                      ),
                helperMaxLines: 3,
              ),
              validator: (v) {
                final price = parseDecimal(v);
                if (price == null || price <= 0) {
                  return l10n.listingPriceInvalid;
                }
                if (rule != null && !rule.allows(price)) {
                  return l10n.listingPriceRangeNote(
                    rule.lowest.toStringAsFixed(2),
                    rule.max.toStringAsFixed(2),
                    rule.unit,
                  );
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            ShelfLifeNote(
              text: listing.isShelfUnavailable
                  ? l10n.shelfNeedsApprovalUnavailable
                  : l10n.shelfNeedsApprovalDiscounted,
              color: AppConstants.warningAmber,
              icon: Icons.verified_user_outlined,
            ),
          ],
        ],
      ),
    );
  }

  Widget _rottenBody(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ShelfLifeNote(
          text: l10n.shelfRottenBody(batch.cropName),
          color: AppConstants.errorRed,
          icon: Icons.warning_amber_rounded,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.shelfRottenScope,
          style: GoogleFonts.inter(
            fontSize: 12,
            height: 1.45,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _noteCtrl,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.shelfRottenNoteLabel,
            hintText: l10n.shelfRottenNoteHint,
          ),
        ),
      ],
    );
  }
}
