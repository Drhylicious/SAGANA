import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/client_id.dart';
import '../../../core/utils/db_error_utils.dart';
import '../../../core/utils/loan_capital_utils.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/loan_capital_standing.dart';
import '../../../data/models/loan_request_model.dart';
import '../../../data/repositories/loan_repository.dart';
import '../../../data/services/server_only.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../../data/services/feature_restriction_service.dart';

/// Request a Loan — the Farmer picks inputs from the cooperative's loan item
/// catalog and sends a request. The catalog, its prices and the stock shown come
/// from the database (LoanRepository.fetchLoanableItems), an item with no stock
/// cannot be chosen, and a quantity above the stock on hand cannot be entered.
/// The database checks it all again when the request is sent. A Manager or
/// Officer then approves (which issues the loan) or disapproves it.
///
/// Needs a connection: the stock has to be the live one, so this is not queued
/// offline.
class RequestLoanScreen extends StatefulWidget {
  const RequestLoanScreen({super.key});

  @override
  State<RequestLoanScreen> createState() => _RequestLoanScreenState();
}

class _RequestLoanScreenState extends State<RequestLoanScreen> {
  final _repo = LoanRepository();
  final _searchCtrl = TextEditingController();

  List<LoanableItem> _items = [];

  /// The Farmer's Capital Share and the most one loan item may be worth (the
  /// Capital Share loan rule). Null when it could not be read: no limit is shown
  /// and the database still decides.
  LoanCapitalStanding? _capital;
  bool _loading = true;
  bool _offline = false;
  bool _failed = false;

  /// inventory item id -> requested quantity (only items with a quantity).
  final Map<String, double> _quantities = {};
  String _search = '';
  String? _category;

  /// One key per screen visit, so a retried send (a lost connection) returns the
  /// request it already created instead of making a second one.
  final String _submitKey = newClientId();

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _offline = false;
      _failed = false;
    });
    try {
      final items = await _repo.fetchLoanableItems();
      final capital = await _repo.fetchMyCapitalStanding();
      if (!mounted) return;
      setState(() {
        _items = items;
        _capital = capital;
        // Drop anything that is no longer in stock, no longer offered or no longer
        // within the Capital Share, and cap the rest at the most that is allowed
        // now (stock on hand, and the Capital Share).
        final byId = {for (final i in items) i.inventoryItemId: i};
        _quantities.removeWhere((id, qty) {
          final item = byId[id];
          return item == null || !item.inStock || _maxQuantityFor(item) <= 0;
        });
        for (final id in _quantities.keys.toList()) {
          final most = _maxQuantityFor(byId[id]!);
          if (_quantities[id]! > most) _quantities[id] = most;
        }
        _loading = false;
      });
    } on ServerOnlyException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  List<String> get _categories {
    final set = <String>{
      for (final i in _items)
        if (i.category.isNotEmpty) i.category,
    };
    return set.toList()..sort();
  }

  List<LoanableItem> get _visible {
    final q = _search.trim().toLowerCase();
    return _items.where((i) {
      if (_category != null && i.category != _category) return false;
      return q.isEmpty || i.itemName.toLowerCase().contains(q);
    }).toList();
  }

  LoanableItem? _item(String id) {
    for (final i in _items) {
      if (i.inventoryItemId == id) return i;
    }
    return null;
  }

  /// The most of [item] that can be requested: the stock on hand, and no more
  /// than fits within the Capital Share (a loan item cannot be worth more than
  /// it). The stock alone when the Capital Share is not known.
  double _maxQuantityFor(LoanableItem item) {
    final capital = _capital;
    if (capital == null) return item.quantityOnHand;
    // An overdue loan that is not paid in full allows no request at all.
    if (capital.hasOverdue) return 0;
    final fits = maxQuantityWithinCapital(
      capitalShare: capital.maxItemValue,
      unitPrice: item.unitPrice,
    );
    return fits < item.quantityOnHand ? fits : item.quantityOnHand;
  }

  double get _total => _quantities.entries.fold<double>(0, (sum, e) {
    final item = _item(e.key);
    return item == null ? sum : sum + moneyOf(e.value, item.unitPrice);
  });

  Future<void> _editQuantity(LoanableItem item) async {
    final result = await showManagementModal<double>(
      context: context,
      builder: (_) => _QuantitySheet(
        item: item,
        capital: _capital,
        initial: _quantities[item.inventoryItemId],
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result <= 0) {
        _quantities.remove(item.inventoryItemId);
      } else {
        _quantities[item.inventoryItemId] = result;
      }
    });
  }

  Future<void> _review() async {
    final sent = await showManagementModal<String>(
      context: context,
      builder: (_) => _ReviewSheet(
        repo: _repo,
        submitKey: _submitKey,
        items: _items,
        capital: _capital,
        quantities: Map.of(_quantities),
        onQuantitiesChanged: (updated) {
          if (!mounted) return;
          setState(() {
            _quantities
              ..clear()
              ..addAll(updated);
          });
        },
        onStockChanged: _load,
      ),
    );
    if (sent == null || !mounted) return;
    AppToast.show(context, AppLocalizations.of(context).loanReqSent(sent));
    // The request is sent: start a clean selection (the stock has moved on) and
    // show the Farmer's requests, where the new one is waiting as Pending.
    setState(_quantities.clear);
    _load();
    await context.pushRoute<void>(AppRoutes.myLoanRequests);
  }

  Future<void> _openMyRequests() =>
      context.pushRoute<void>(AppRoutes.myLoanRequests);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final visible = _visible;

    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const TopBarSpacer(height: 64),
              Expanded(
                child: RefreshIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      20,
                      16,
                      20,
                      _quantities.isEmpty ? 32 : 120,
                    ),
                    children: [
                      if (_loading)
                        const SkeletonList()
                      else if (_offline)
                        _Notice(
                          icon: Icons.wifi_off_rounded,
                          title: l10n.youAreOffline,
                          body: l10n.loanReqOffline,
                          actionLabel: l10n.retry,
                          onAction: _load,
                        )
                      else if (_failed)
                        _Notice(
                          icon: Icons.error_outline_rounded,
                          title: l10n.loanReqLoadFailed,
                          body: l10n.loanReqLoadFailedBody,
                          actionLabel: l10n.retry,
                          onAction: _load,
                        )
                      else if (_items.isEmpty)
                        _Notice(
                          icon: Icons.inventory_2_outlined,
                          title: l10n.loanReqNoItems,
                          body: l10n.loanReqNoItemsBody,
                        )
                      else ...[
                        if (_capital != null) ...[
                          _CapitalBanner(capital: _capital!),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: _searchCtrl,
                          style: GoogleFonts.inter(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: l10n.loanReqSearchHint,
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: context.saganaColors.cardBackground,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusLg,
                              ),
                              borderSide: BorderSide(
                                color: cs.outline.withValues(alpha: 0.2),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusLg,
                              ),
                              borderSide: BorderSide(
                                color: cs.outline.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                        ),
                        if (_categories.length > 1) ...[
                          const SizedBox(height: 10),
                          _CategoryChips(
                            categories: _categories,
                            selected: _category,
                            allLabel: l10n.loanReqAll,
                            total: _items.length,
                            counts: {
                              for (final c in _categories)
                                c: _items.where((i) => i.category == c).length,
                            },
                            onSelected: (c) => setState(() => _category = c),
                          ),
                        ],
                        const SizedBox(height: 14),
                        if (visible.isEmpty)
                          _Notice(
                            icon: Icons.search_off_rounded,
                            title: l10n.loanReqNoMatch,
                            body: l10n.loanReqNoMatchBody,
                          )
                        else
                          for (final item in visible)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _LoanableItemCard(
                                item: item,
                                quantity: _quantities[item.inventoryItemId],
                                overdueLocked: _capital?.hasOverdue ?? false,
                                aboveCapital:
                                    item.inStock &&
                                    !(_capital?.hasOverdue ?? false) &&
                                    _maxQuantityFor(item) <= 0,
                                onTap: item.inStock && _maxQuantityFor(item) > 0
                                    ? () => _editQuantity(item)
                                    : null,
                              ),
                            ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: l10n.loanReqTitle,
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
              trailing: [
                Tooltip(
                  message: l10n.loanReqHistoryTooltip,
                  child: GestureDetector(
                    onTap: _openMyRequests,
                    child: Icon(
                      Icons.assignment_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 26,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_quantities.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _SummaryBar(
                count: _quantities.length,
                total: _total,
                onReview: _review,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Notice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Notice({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: context.adaptiveSurface(const Color(0xFFDBF1FE)),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 32,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final String allLabel;
  final int total;
  final Map<String, int> counts;
  final ValueChanged<String?> onSelected;

  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.allLabel,
    required this.total,
    required this.counts,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool active, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: active
                ? Colors.white
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        selected: active,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        selectedColor: AppConstants.primaryGreen,
        backgroundColor: context.saganaColors.cardBackground,
        side: BorderSide(
          color: active ? AppConstants.primaryGreen : Colors.transparent,
        ),
        shape: const StadiumBorder(),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('$allLabel ($total)', selected == null, () => onSelected(null)),
          for (final c in categories)
            chip(
              '$c (${counts[c] ?? 0})',
              selected == c,
              () => onSelected(c),
            ),
        ],
      ),
    );
  }
}

/// The Farmer's Capital Share and what it allows: each loan item can be worth up
/// to it. Red when it is zero, since nothing can be requested then.
class _CapitalBanner extends StatelessWidget {
  final LoanCapitalStanding capital;
  const _CapitalBanner({required this.capital});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final money = NumberFormat('#,##0.00');
    final zero = capital.isZero;
    final blocked = capital.isBlocked;
    final color = blocked
        ? AppConstants.errorRed
        : Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            blocked
                ? Icons.block_rounded
                : Icons.account_balance_wallet_outlined,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Not eligible: say so, and what has to happen first. The items
                // below are switched off, and the database refuses a request.
                Text(
                  blocked
                      ? l10n.loanBlockedTitle
                      : l10n.loanCapTitle(
                          '₱${money.format(capital.capitalShare)}',
                        ),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: blocked ? AppConstants.errorRed : cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                if (!blocked)
                  Text(
                    l10n.loanCapBody('₱${money.format(capital.maxItemValue)}'),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      height: 1.4,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                if (zero)
                  Text(
                    l10n.loanBlockedZeroCapital,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      height: 1.4,
                      color: AppConstants.errorRed,
                    ),
                  ),
                if (capital.hasOverdue)
                  Padding(
                    padding: EdgeInsets.only(top: zero ? 4 : 0),
                    child: Text(
                      l10n.loanBlockedOverdue(
                        '₱${money.format(capital.overdueBalance)}',
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.4,
                        color: AppConstants.errorRed,
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

/// One catalog item: photo, name, price, the stock on hand, and the quantity
/// chosen so far. Three clear states: available (Add), in the request (green
/// border, quantity, line total and Edit), and out of stock (greyed, no action).
class _LoanableItemCard extends StatelessWidget {
  final LoanableItem item;
  final double? quantity;
  final VoidCallback? onTap;

  /// In stock, but not even the smallest quantity fits within the Capital Share.
  final bool aboveCapital;

  /// The Farmer has an overdue loan that is not paid in full: nothing can be
  /// requested.
  final bool overdueLocked;

  const _LoanableItemCard({
    required this.item,
    required this.quantity,
    required this.onTap,
    this.aboveCapital = false,
    this.overdueLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final selected = quantity != null && quantity! > 0;
    final enabled = item.inStock && !aboveCapital && !overdueLocked;
    final stockColor = enabled
        ? AppConstants.successGreen
        : AppConstants.errorRed;
    final radius = BorderRadius.circular(AppConstants.radiusLg);

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Material(
        color: selected
            ? Color.alphaBlend(
                AppConstants.primaryGreen.withValues(alpha: 0.05),
                context.saganaColors.cardBackground,
              )
            : context.saganaColors.cardBackground,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 92),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? AppConstants.primaryGreen.withValues(alpha: 0.6)
                    : cs.outline.withValues(alpha: 0.12),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                            ? Image.network(
                                item.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const _ItemPlaceholder(),
                              )
                            : const _ItemPlaceholder(),
                      ),
                    ),
                    if (selected)
                      Positioned(
                        top: -6,
                        left: -6,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: AppConstants.primaryGreen,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: context.saganaColors.cardBackground,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.itemName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatPricePerUnit(item.unitPrice, item.unit),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            enabled
                                ? Icons.inventory_2_outlined
                                : Icons.block_rounded,
                            size: 13,
                            color: stockColor,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              enabled
                                  ? l10n.loanReqInStock(
                                      formatQuantityUnit(
                                        item.quantityOnHand,
                                        item.unit,
                                      ),
                                    )
                                  : overdueLocked
                                  ? l10n.loanBlockedItem
                                  : aboveCapital
                                  ? l10n.loanCapAbove
                                  : l10n.loanReqOutOfStock,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: stockColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (selected) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${formatQuantityUnit(quantity!, item.unit)} · ₱${NumberFormat('#,##0.00').format(moneyOf(quantity!, item.unitPrice))}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (enabled) _ActionPill(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The trailing Add / Edit pill of an item card. Same size in both states so
/// every card keeps the same layout.
class _ActionPill extends StatelessWidget {
  final bool selected;
  const _ActionPill({required this.selected});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 76),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? Colors.transparent
            : AppConstants.primaryGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        border: Border.all(
          color: AppConstants.primaryGreen.withValues(alpha: selected ? 0.6 : 0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            selected ? Icons.edit_outlined : Icons.add_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            selected ? l10n.loanReqEdit : l10n.loanReqAdd,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemPlaceholder extends StatelessWidget {
  const _ItemPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    color: AppConstants.primaryGreen.withValues(alpha: 0.08),
    child: Icon(
      Icons.grass_rounded,
      color: Theme.of(context).colorScheme.primary,
      size: 28,
    ),
  );
}

class _SummaryBar extends StatelessWidget {
  final int count;
  final double total;
  final VoidCallback onReview;

  const _SummaryBar({
    required this.count,
    required this.total,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        14 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(
          top: BorderSide(color: cs.outline.withValues(alpha: 0.12)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppConstants.primaryGreen.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.shopping_basket_outlined, color: cs.primary),
                Positioned(
                  top: -5,
                  right: -5,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.loanReqItemCount(count),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '₱${NumberFormat('#,##0.00').format(total)}',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onReview,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            child: Text(l10n.loanReqReview),
          ),
        ],
      ),
    );
  }
}

// ─── Quantity sheet ──────────────────────────────────────────────────────────

class _QuantitySheet extends StatefulWidget {
  final LoanableItem item;
  final LoanCapitalStanding? capital;
  final double? initial;
  const _QuantitySheet({
    required this.item,
    required this.capital,
    required this.initial,
  });

  @override
  State<_QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<_QuantitySheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial == null ? '' : formatQuantity(widget.initial!),
  );
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double? get _value => double.tryParse(_ctrl.text.trim());

  /// The most that can be requested of this item: the stock on hand, and no more
  /// than fits within the Capital Share (a loan item cannot be worth more).
  double get _maxQty {
    final stock = widget.item.quantityOnHand;
    final capital = widget.capital;
    if (capital == null) return stock;
    final fits = maxQuantityWithinCapital(
      capitalShare: capital.maxItemValue,
      unitPrice: widget.item.unitPrice,
    );
    return fits < stock ? fits : stock;
  }

  /// Sets the field to [v] (clamped to 0..the most allowed) and moves the cursor
  /// to the end.
  void _set(double v) {
    final c = v.clamp(0.0, _maxQty).toDouble();
    final text = c <= 0 ? '' : formatQuantity(roundQuantity(c));
    setState(() {
      _error = null;
      _ctrl.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final v = _value;
    if (v == null || v <= 0) {
      setState(() => _error = l10n.loanReqQtyRequired);
      return;
    }
    if (v > widget.item.quantityOnHand + 1e-9) {
      setState(
        () => _error = l10n.loanReqQtyTooMuch(
          formatQuantityUnit(widget.item.quantityOnHand, widget.item.unit),
        ),
      );
      return;
    }
    final capital = widget.capital;
    if (capital != null && v > _maxQty + 1e-9) {
      final money = NumberFormat('#,##0.00');
      setState(
        () => _error = l10n.loanCapQtyTooMuch(
          '₱${money.format(moneyOf(v, widget.item.unitPrice))}',
          '₱${money.format(capital.maxItemValue)}',
          formatQuantityUnit(_maxQty, widget.item.unit),
        ),
      );
      return;
    }
    Navigator.pop(context, roundQuantity(v));
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) {
    return SizedBox(
      width: 48,
      height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
        ),
        child: Icon(icon, size: 22),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final item = widget.item;
    final value = _value ?? 0;
    final lineTotal = moneyOf(value, item.unitPrice);
    final atMax = value >= _maxQty - 1e-9;

    return ManagementModalShell(
      title: item.itemName,
      subtitle: formatPricePerUnit(item.unitPrice, item.unit),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 16,
                color: AppConstants.successGreen,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.loanReqQtyAvailable(
                    formatQuantityUnit(item.quantityOnHand, item.unit),
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.successGreen,
                  ),
                ),
              ),
              TextButton(
                onPressed: atMax ? null : () => _set(_maxQty),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(l10n.loanReqMax),
              ),
            ],
          ),
          if (widget.capital != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 16,
                  color: _maxQty < item.quantityOnHand
                      ? AppConstants.warningAmber
                      : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.loanCapQtyNote(
                      formatQuantityUnit(_maxQty, item.unit),
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stepButton(
                Icons.remove_rounded,
                value > 0 ? () => _set(value - 1) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    DecimalInputFormatter(max: item.quantityOnHand),
                  ],
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _save(),
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.loanReqQtyLabel(item.unit),
                    hintText: '0',
                    errorText: _error,
                    errorMaxLines: 2,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _stepButton(
                Icons.add_rounded,
                atMax ? null : () => _set(value + 1),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppConstants.primaryGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.loanReqTotal,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '₱${NumberFormat('#,##0.00').format(lineTotal)}',
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
          if (widget.initial != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.pop(context, 0.0),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(l10n.loanReqRemove),
                style: TextButton.styleFrom(
                  foregroundColor: AppConstants.errorRed,
                ),
              ),
            ),
          ],
        ],
      ),
      footer: ManagementModalActions(primaryLabel: l10n.save, onPrimary: _save),
    );
  }
}

// ─── Review sheet ────────────────────────────────────────────────────────────

class _ReviewSheet extends StatefulWidget {
  final LoanRepository repo;
  final String submitKey;
  final LoanCapitalStanding? capital;
  final List<LoanableItem> items;
  final Map<String, double> quantities;
  final ValueChanged<Map<String, double>> onQuantitiesChanged;
  final Future<void> Function() onStockChanged;

  const _ReviewSheet({
    required this.repo,
    required this.submitKey,
    required this.capital,
    required this.items,
    required this.quantities,
    required this.onQuantitiesChanged,
    required this.onStockChanged,
  });

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late final Map<String, double> _qty = Map.of(widget.quantities);
  final _notesCtrl = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  LoanableItem? _item(String id) {
    for (final i in widget.items) {
      if (i.inventoryItemId == id) return i;
    }
    return null;
  }

  double get _total => _qty.entries.fold<double>(0, (sum, e) {
    final item = _item(e.key);
    return item == null ? sum : sum + moneyOf(e.value, item.unitPrice);
  });

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    if (_qty.isEmpty) {
      Navigator.pop(context);
      return;
    }
    // A line worth more than the Capital Share is not sent: say which one. The
    // database checks it again with the Capital Share at the moment of sending.
    final capital = widget.capital;
    if (capital != null) {
      for (final e in _qty.entries) {
        final item = _item(e.key);
        if (item != null &&
            !lineWithinCapital(moneyOf(e.value, item.unitPrice), capital.maxItemValue)) {
          final money = NumberFormat('#,##0.00');
          setState(
            () => _error = l10n.loanCapQtyTooMuch(
              '₱${money.format(moneyOf(e.value, item.unitPrice))}',
              '₱${money.format(capital.maxItemValue)}',
              formatQuantityUnit(
                maxQuantityWithinCapital(
                  capitalShare: capital.maxItemValue,
                  unitPrice: item.unitPrice,
                ),
                item.unit,
              ),
            ),
          );
          return;
        }
      }
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final no = await widget.repo.submitLoanRequest(
        lines: [
          for (final e in _qty.entries)
            (inventoryItemId: e.key, quantity: e.value),
        ],
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        idempotencyKey: widget.submitKey,
      );
      if (mounted) Navigator.pop(context, no.isEmpty ? '—' : no);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        final raw = e.toString();
        _error = restrictionMessageOf(e) ??
            (raw.contains('LOAN_REFERRAL_ALREADY_REQUESTED')
            ? l10n.errLoanReferralAlreadyRequested
            : raw.contains('LOAN_REFERRAL_INVALID')
            ? l10n.errLoanReferralInvalid
            : readableDatabaseMessage(e) ??
            (e is ServerOnlyException ? e.toString() : l10n.loanReqFailed));
      });
      // The stock may have changed: show the catalog as it is now.
      unawaited(widget.onStockChanged());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final money = NumberFormat('#,##0.00');

    return ManagementModalShell(
      title: l10n.loanReqReviewTitle,
      subtitle: l10n.loanReqItemCount(_qty.length),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in _qty.entries)
            if (_item(e.key) != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _item(e.key)!.itemName,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            '${formatQuantityUnit(e.value, _item(e.key)!.unit)} × ${formatPricePerUnit(_item(e.key)!.unitPrice, _item(e.key)!.unit)}',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₱${money.format(moneyOf(e.value, _item(e.key)!.unitPrice))}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    IconButton(
                      onPressed: _sending
                          ? null
                          : () {
                              setState(() => _qty.remove(e.key));
                              widget.onQuantitiesChanged(_qty);
                              if (_qty.isEmpty) Navigator.pop(context);
                            },
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: l10n.loanReqRemove,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
          const Divider(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.loanReqTotal,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '₱${money.format(_total)}',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            maxLength: 200,
            enabled: !_sending,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.loanReqNotesLabel,
              hintText: l10n.loanReqNotesHint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.loanReqPaymentNote,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              height: 1.4,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppConstants.errorRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Text(
                _error!,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: AppConstants.errorRed,
                ),
              ),
            ),
          ],
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: l10n.loanReqSubmit,
        isLoading: _sending,
        onPrimary: _send,
      ),
    );
  }
}
