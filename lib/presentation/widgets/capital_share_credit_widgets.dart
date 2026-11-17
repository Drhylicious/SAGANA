import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/quantity_utils.dart';
import '../../data/models/contribution_model.dart';
import '../../data/models/program_model.dart';
import '../../data/repositories/capital_share_rates_repository.dart';
import 'management_modal.dart';
import 'report_ui_widgets.dart';

final _money = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
final _shortDate = DateFormat('MM/dd/yy');

Widget _row(String label, String value, ColorScheme cs, {bool bold = false}) => Padding(
  padding: const EdgeInsets.only(bottom: 2),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            height: 1.35,
            color: cs.onSurfaceVariant,
            fontWeight: bold ? FontWeight.w600 : null,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Text(
        value,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface),
      ),
    ],
  ),
);

/// The ONE rule for newly vs previous, used by the Manager/Officer report and the
/// Farmer's My Capital Share alike: credits made under the latest settings version
/// are newly credited; credits made under any earlier version are previous.
/// Each is [credited, base amount, discount earned].
({List<double> fresh, List<double> previous}) splitCreditsByVersion(
  Map<int, List<double>> byVersion,
  int latestVersion,
) {
  final fresh = [...(byVersion[latestVersion] ?? const [0.0, 0.0, 0.0])];
  final previous = [0.0, 0.0, 0.0];
  for (final e in byVersion.entries) {
    if (e.key == latestVersion) continue;
    for (var i = 0; i < 3 && i < e.value.length; i++) {
      previous[i] += e.value[i];
    }
  }
  return (fresh: fresh, previous: previous);
}

String creditRateText(double credited, double base) => _rate(credited, base);

String _rate(double credited, double base) {
  final v = base > 0 ? credited / base * 100 : 0.0;
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

/// A completed Cooperative Product purchase as a list item (newest-first lists).
CreditItem creditItemFromPurchase(ProgramPurchase p, AppLocalizations l10n) {
  final on = (p.completedAt ?? p.confirmedAt ?? p.requestedAt).toLocal();
  return CreditItem(
    id: p.id,
    title: p.itemName.isNotEmpty ? p.itemName : p.programName,
    subtitle: '${DateFormat('MMM d, y').format(on)} · ${formatQuantityUnit(p.quantity, p.unit)}',
    amount: p.totalAmount,
    date: on,
    note: p.discountAmount > 0 ? l10n.patDiscountLine(_money.format(p.discountAmount)) : null,
  );
}

/// A successful, completed offer to the cooperative as a list item.
CreditItem creditItemFromOffer(MemberSalesTransaction t) {
  final on = t.saleDate.toLocal();
  return CreditItem(
    id: t.id,
    title: t.cropName,
    subtitle: '${DateFormat('MMM d, y').format(on)} · ${formatQuantityUnit(t.quantityKg, t.unit)}',
    amount: t.amount,
    date: on,
  );
}

/// The history opens once the settings have been changed three times.
const historyAfterChanges = 3;

/// One purchase or offer shown in a list under a credit group.
class CreditItem {
  final String id;
  final String title;
  final String subtitle;
  final double amount;
  final DateTime date;

  /// A small green line under the amount (the purchase's program discount).
  final String? note;
  const CreditItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.date,
    this.note,
  });
}

/// What a source credited to the Capital Share, under the Cooperative Purchase or
/// Offer to Cooperative total, with the actual purchases / offers behind it. The
/// same widget is used by the Manager / Officer report and by the Farmer's My
/// Capital Share, so both follow one structure and one rule:
///
///  - Before the percentages were ever changed: one plain group.
///  - After a change: "Newly Credited" first (credits made under the CURRENT
///    settings), then "Previous" (credits made under any earlier settings). A credit
///    never moves between the two and is never recalculated.
///  - Under each group a collapsible list of the transactions behind it, newest
///    first. A transaction is "new" when its credit carries the latest version.
///  - From the third change on, "See History" opens every credit record.
///
/// The lists are loaded when the widget is first shown (once).
class CreditGroupsView extends StatefulWidget {
  final bool isPurchase;
  final String farmerId;
  final double made;
  final double discountEarned;
  final double credited;
  final double creditedBase;
  final Map<int, List<double>> byVersion;
  final int latestVersion;
  final int rateChanges;

  /// transaction id -> the version its credit was made under.
  final Map<String, int> creditVersions;
  final Future<List<CreditItem>> Function() loadItems;

  const CreditGroupsView({
    super.key,
    required this.isPurchase,
    required this.farmerId,
    required this.made,
    required this.discountEarned,
    required this.credited,
    required this.creditedBase,
    required this.byVersion,
    required this.latestVersion,
    required this.rateChanges,
    required this.creditVersions,
    required this.loadItems,
  });

  @override
  State<CreditGroupsView> createState() => _CreditGroupsViewState();
}

class _CreditGroupsViewState extends State<CreditGroupsView> {
  late final Future<List<CreditItem>> _future = widget.loadItems();

  Widget _kv(String label, String value, ColorScheme cs, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.35,
              fontWeight: bold ? FontWeight.w600 : null,
              color: bold ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface),
        ),
      ],
    ),
  );

  Widget _itemRow(CreditItem i, ColorScheme cs) => ReportRecordCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                i.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface),
              ),
              const SizedBox(height: 2),
              Text(i.subtitle, style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _money.format(i.amount),
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface),
            ),
            if (i.note != null) ...[
              const SizedBox(height: 2),
              Text(
                i.note!,
                style: GoogleFonts.inter(fontSize: 10.5, color: cs.primary),
              ),
            ],
          ],
        ),
      ],
    ),
  );

  Widget _group(
    ColorScheme cs, {
    required String? title,
    required List<(String, String, bool)> rows,
    required String listLabel,
    required List<CreditItem> items,
  }) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(
            title,
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
          const SizedBox(height: 6),
        ],
        for (final r in rows) _kv(r.$1, r.$2, cs, bold: r.$3),
        if (items.isNotEmpty)
          _Collapsible(label: listLabel, children: [for (final i in items) _itemRow(i, cs)]),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isPurchase = widget.isPurchase;

    TextStyle note() => GoogleFonts.inter(
      fontSize: 11.5,
      height: 1.35,
      fontStyle: FontStyle.italic,
      color: cs.onSurfaceVariant,
    );

    return FutureBuilder<List<CreditItem>>(
      future: _future,
      builder: (context, snap) {
        final items = snap.data ?? const <CreditItem>[];
        String listLabel(int n) =>
            isPurchase ? l10n.patProductsPurchased(n) : l10n.patOffersMade(n);
        final fresh = [for (final i in items) if (widget.creditVersions[i.id] == widget.latestVersion) i];
        final prev = [for (final i in items) if (widget.creditVersions[i.id] != widget.latestVersion) i];

        final children = <Widget>[];
        if (widget.rateChanges == 0) {
          // Plain: nothing has been changed yet.
          children.add(
            _group(
              cs,
              title: null,
              rows: [
                (l10n.patCreditedToCapital, _money.format(widget.credited), true),
                (isPurchase ? l10n.patPurchasesMadeLabel : l10n.patOffersCompletedLabel, _money.format(widget.made), false),
                if (isPurchase) (l10n.patDiscountEarned, _money.format(widget.discountEarned), false),
              ],
              listLabel: listLabel(items.length),
              items: items,
            ),
          );
          if (widget.creditedBase > 0) {
            children.add(
              Text(
                l10n.patCreditedLine(
                  _money.format(widget.credited),
                  _rate(widget.credited, widget.creditedBase),
                  _money.format(widget.creditedBase),
                ),
                style: GoogleFonts.inter(fontSize: 12, color: cs.onSurface),
              ),
            );
          } else if (widget.made > 0) {
            children.add(Text(l10n.patNothingCredited, style: note()));
          }
        } else {
          final split = splitCreditsByVersion(widget.byVersion, widget.latestVersion);
          final f = split.fresh;
          final p = split.previous;
          children.addAll([
            _group(
              cs,
              title: l10n.patGroupNewlyCredited,
              rows: [
                (l10n.patCreditedToCapital, _money.format(f[0]), true),
                (isPurchase ? l10n.patNewPurchasesMade : l10n.patNewOffers, _money.format(f[1]), false),
                if (isPurchase) (l10n.patNewDiscountEarned, _money.format(f[2]), false),
                (
                  f[1] > 0 ? l10n.patNewlyCreditedRate(_rate(f[0], f[1])) : l10n.patNewlyCredited,
                  _money.format(f[0]),
                  false,
                ),
              ],
              listLabel: listLabel(fresh.length),
              items: fresh,
            ),
            _group(
              cs,
              title: isPurchase ? l10n.patGroupPreviousPurchases : l10n.patGroupPreviousOffers,
              rows: [
                (l10n.patCreditedToCapital, _money.format(p[0]), true),
                (isPurchase ? l10n.patPrevPurchasesMade : l10n.patPrevOffers, _money.format(p[1]), false),
                if (isPurchase) (l10n.patPrevDiscountEarned, _money.format(p[2]), false),
                (l10n.patPrevCredited, _money.format(p[0]), false),
              ],
              listLabel: listLabel(prev.length),
              items: prev,
            ),
          ]);
        }
        if (widget.rateChanges >= historyAfterChanges) {
          children.add(
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => showCapitalShareHistory(
                  context,
                  farmerId: widget.farmerId,
                  isPurchase: isPurchase,
                ),
                child: Text(
                  l10n.patSeeHistory,
                  style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: cs.primary),
                ),
              ),
            ),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
      },
    );
  }
}

/// A button that opens and closes a list under it.
class _Collapsible extends StatefulWidget {
  final String label;
  final List<Widget> children;
  const _Collapsible({required this.label, required this.children});

  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: cs.primary),
                  ),
                ),
                Icon(
                  _open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: cs.primary,
                ),
              ],
            ),
          ),
        ),
        if (_open) ...widget.children,
      ],
    );
  }
}

/// The history of one source (Cooperative Purchase or Offer to Cooperative) for one
/// member, in a modal: every settings version (its date and rate) with the credit
/// records made under it, each dated with the day it was CREDITED.
Future<void> showCapitalShareHistory(
  BuildContext context, {
  required String farmerId,
  required bool isPurchase,
}) {
  return showManagementModal<void>(
    context: context,
    builder: (_) => _HistorySheet(farmerId: farmerId, isPurchase: isPurchase),
  );
}

class _Credit {
  final int version;
  final DateTime on;
  final double credited;
  final double base;
  final double discount;
  const _Credit(this.version, this.on, this.credited, this.base, this.discount);
}

class _HistoryData {
  final List<CapitalShareRateVersion> versions;
  final List<_Credit> credits;
  const _HistoryData(this.versions, this.credits);
}

class _HistorySheet extends StatefulWidget {
  final String farmerId;
  final bool isPurchase;
  const _HistorySheet({required this.farmerId, required this.isPurchase});

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  late final Future<_HistoryData> _future = _load();

  Future<_HistoryData> _load() async {
    final client = Supabase.instance.client;
    final versions = await CapitalShareRatesRepository().fetchVersions();
    final rows = await client
        .from('capital_contribution_events')
        .select('amount, base_amount, discount_amount, rate_version, credited_at, created_at')
        .eq('farmer_id', widget.farmerId)
        .eq('source', widget.isPurchase ? 'purchase_share' : 'offer_share')
        .order('created_at', ascending: false);
    final credits = [
      for (final r in rows)
        _Credit(
          (r['rate_version'] as num?)?.toInt() ?? 1,
          DateTime.parse((r['credited_at'] ?? r['created_at']) as String).toLocal(),
          (r['amount'] as num).toDouble(),
          (r['base_amount'] as num?)?.toDouble() ?? 0,
          (r['discount_amount'] as num?)?.toDouble() ?? 0,
        ),
    ]..sort((a, b) => b.on.compareTo(a.on));
    return _HistoryData(versions, credits);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    Widget body(_HistoryData d) {
      final versions = d.versions.reversed.toList(); // latest first
      if (versions.isEmpty && d.credits.isEmpty) {
        return Text(l10n.patHistoryNone, style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant));
      }
      final groups = <Widget>[];
      for (var i = 0; i < versions.length; i++) {
        final v = versions[i];
        final pct = widget.isPurchase ? v.purchasePercent : v.offerPercent;
        final pctText = pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct.toStringAsFixed(2);
        final until = i == 0 ? null : versions[i - 1].changedAt;
        final credits = d.credits.where((c) => c.version == v.version).toList();
        final total = credits.fold<double>(0, (t, c) => t + c.credited);
        groups.add(
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  until == null
                      ? l10n.patHistoryRate(pctText, _shortDate.format(v.changedAt))
                      : l10n.patHistoryRateUntil(pctText, _shortDate.format(v.changedAt), _shortDate.format(until)),
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.patHistoryCreditedTotal(_money.format(total)),
                  style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                if (credits.isEmpty)
                  Text(l10n.patHistoryNone, style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant))
                else
                  for (var k = 0; k < credits.length; k++) ...[
                    if (k > 0) Divider(height: 14, color: cs.outline.withValues(alpha: 0.12)),
                    _row('${_shortDate.format(credits[k].on)} – ${widget.isPurchase ? l10n.patHistoryPurchaseMade : l10n.patHistoryOfferMade}', _money.format(credits[k].base), cs),
                    if (widget.isPurchase)
                      _row('${_shortDate.format(credits[k].on)} – ${l10n.patHistoryDiscountEarned}', _money.format(credits[k].discount), cs),
                    _row('${_shortDate.format(credits[k].on)} – ${l10n.patHistoryCredited}', _money.format(credits[k].credited), cs, bold: true),
                  ],
              ],
            ),
          ),
        );
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: groups);
    }

    return ManagementModalShell(
      title: widget.isPurchase ? l10n.patHistoryTitlePurchase : l10n.patHistoryTitleOffer,
      body: FutureBuilder<_HistoryData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError || snap.data == null) {
            return Text(l10n.patHistoryLoadError, style: GoogleFonts.inter(fontSize: 13, color: cs.error));
          }
          return body(snap.data!);
        },
      ),
    );
  }
}
