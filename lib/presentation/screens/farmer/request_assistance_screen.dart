import '../../../core/theme/sagana_colors.dart';
import 'package:flutter/material.dart';
import '../../../core/utils/loan_capital_utils.dart';
import '../../../core/utils/quantity_utils.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../data/models/loan_capital_standing.dart';
import '../../../data/models/loan_request_model.dart';
import '../../../data/repositories/loan_repository.dart';
import '../../../data/repositories/program_assistance_repository.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/labeled_text_field.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/top_bar_spacer.dart';

/// A Farmer whose program outcome failed asks the cooperative for assistance.
/// Items come from the active Loan Item Catalog (loan-eligible and in stock).
/// Quantities are whole numbers only: the - and + buttons step by 1 and the number can be typed.
///
/// What can be requested is limited by the Farmer's Capital Share, as loans are:
/// no Capital Share, no assistance; each item can be worth no more than it. The
/// database enforces it (supabase_schema_assistance_capital_share.sql). Assistance
/// is not a loan: nothing is repaid, so the loan's overdue rule does not apply here.
/// Pops `true` once sent.
class RequestAssistanceScreen extends StatefulWidget {
  final String programMemberId;
  final String programName;

  const RequestAssistanceScreen({
    super.key,
    required this.programMemberId,
    required this.programName,
  });

  @override
  State<RequestAssistanceScreen> createState() =>
      _RequestAssistanceScreenState();
}

class _RequestAssistanceScreenState extends State<RequestAssistanceScreen> {
  final _loanRepo = LoanRepository();
  final _repo = ProgramAssistanceRepository();
  final _message = TextEditingController();
  final _search = TextEditingController();
  List<LoanableItem> _items = [];

  /// The Farmer's Capital Share. Null when it could not be read: no limit is shown
  /// and the database still decides.
  LoanCapitalStanding? _capital;
  final Map<String, double> _qty = {}; // inventory item id -> quantity (up to 2 decimals)
  final Map<String, TextEditingController> _ctrls = {};
  String _query = '';
  bool _loading = true;
  bool _failed = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(
      () => setState(() => _query = _search.text.trim().toLowerCase()),
    );
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    _search.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items = await _loanRepo.fetchLoanableItems();
      final capital = await _loanRepo.fetchMyCapitalStanding();
      if (!mounted) return;
      setState(() {
        _items = items;
        _capital = capital;
        // What was chosen cannot be more than is allowed now.
        _qty.removeWhere((id, q) {
          final i = items.where((x) => x.inventoryItemId == id).firstOrNull;
          return i == null || _max(i) <= 0;
        });
        for (final id in _qty.keys.toList()) {
          final i = items.firstWhere((x) => x.inventoryItemId == id);
          if (_qty[id]! > _max(i)) _qty[id] = _max(i);
        }
        _loading = false;
      });
    } catch (e, st) {
      friendlyError(
        AppLocalizations.of(context),
        e,
        st,
      ); // logged for developers
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  /// The most that can be requested: never more than the stock on hand (2 decimals,
  /// rounded down), and never more than fits within the Capital Share.
  double _max(LoanableItem item) {
    final stock = (item.quantityOnHand * 100).floor() / 100;
    final capital = _capital;
    if (capital == null) return stock;
    final fits = maxQuantityWithinCapital(
      capitalShare: capital.maxItemValue,
      unitPrice: item.unitPrice,
    );
    return fits < stock ? fits : stock;
  }

  /// In stock, but nothing of it fits within the Capital Share.
  bool _aboveCapital(LoanableItem item) =>
      _capital != null && item.quantityOnHand > 0 && _max(item) <= 0;

  TextEditingController _ctrlFor(LoanableItem item) => _ctrls.putIfAbsent(
    item.inventoryItemId,
    () => TextEditingController(text: '0'),
  );

  /// Sets the quantity (up to 2 decimals, within the stock) and keeps the field in step.
  void _setQty(LoanableItem item, double value, {bool rewriteField = true}) {
    final next = roundQuantity(value.clamp(0.0, _max(item)));
    setState(() {
      if (next <= 0) {
        _qty.remove(item.inventoryItemId);
      } else {
        _qty[item.inventoryItemId] = next;
      }
    });
    if (rewriteField) {
      final c = _ctrlFor(item);
      final text = formatQuantity(next);
      if (c.text != text) {
        c.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
  }

  int get _selectedCount => _qty.length;

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    if (_qty.isEmpty) {
      AppToast.show(context, l10n.assistPickItems, isError: true);
      return;
    }
    setState(() => _sending = true);
    try {
      await _repo.submit(
        programMemberId: widget.programMemberId,
        items: [
          for (final e in _qty.entries)
            {'inventoryItemId': e.key, 'quantity': e.value},
        ],
        message: _message.text.trim().isEmpty ? null : _message.text.trim(),
      );
      if (!mounted) return;
      AppToast.show(context, l10n.assistSent);
      Navigator.of(context).pop(true);
    } catch (e, st) {
      if (!mounted) return;
      AppToast.show(context, friendlyError(l10n, e, st), isError: true);
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const TopBarSpacer(height: 64),
              Expanded(
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: SkeletonList(),
                      )
                    : _failed
                    ? _stateMessage(
                        icon: Icons.cloud_off_rounded,
                        text: l10n.assistLoadFailed,
                        action: OutlinedButton(
                          onPressed: _load,
                          child: Text(l10n.retry),
                        ),
                      )
                    : _content(l10n, cs),
              ),
              if (!_loading && !_failed) _footer(l10n, cs),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: l10n.assistTitle,
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
        ],
      ),
    );
  }

  /// The Capital Share and what it allows. Red when it is 0: no assistance can be
  /// requested then, and Send is switched off.
  Widget _capitalBanner(
    AppLocalizations l10n,
    ColorScheme cs,
    LoanCapitalStanding capital,
  ) {
    final money = NumberFormat('#,##0.00');
    final zero = capital.isZero;
    final color = zero ? AppConstants.errorRed : AppConstants.primaryGreen;
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
            zero ? Icons.block_rounded : Icons.account_balance_wallet_outlined,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  zero
                      ? l10n.assistCapZeroTitle
                      : l10n.loanCapTitle('₱${money.format(capital.capitalShare)}'),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: zero ? AppConstants.errorRed : cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  zero
                      ? l10n.assistCapZero
                      : l10n.assistCapBody('₱${money.format(capital.maxItemValue)}'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.4,
                    color: zero ? AppConstants.errorRed : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stateMessage({
    required IconData icon,
    required String text,
    Widget? action,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.45,
                color: cs.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 14), action],
          ],
        ),
      ),
    );
  }

  Widget _content(AppLocalizations l10n, ColorScheme cs) {
    final shown = _items
        .where(
          (i) => _query.isEmpty || i.itemName.toLowerCase().contains(_query),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        // Which program, and what this request is.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppConstants.programPurple.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(
              color: AppConstants.programPurple.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppConstants.programPurple.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.volunteer_activism_rounded,
                      size: 18,
                      color: AppConstants.programPurple,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.programName,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                l10n.assistInfo,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.45,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_capital != null) ...[
          const SizedBox(height: 12),
          _capitalBanner(l10n, cs, _capital!),
        ],
        const SizedBox(height: 20),
        Text(
          l10n.assistChooseItems,
          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (_items.isNotEmpty) ...[
          TextField(
            controller: _search,
            style: GoogleFonts.inter(fontSize: 14),
            decoration: InputDecoration(
              hintText: l10n.assistSearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: context.saganaColors.cardBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_items.isEmpty)
          _stateMessage(
            icon: Icons.inventory_2_outlined,
            text: l10n.assistNoItems,
          )
        else if (shown.isEmpty)
          _stateMessage(icon: Icons.search_off_rounded, text: l10n.assistNoMatch)
        else
          for (final item in shown) _itemCard(l10n, cs, item),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: 8),
          LabeledTextField(
            controller: _message,
            label: l10n.assistMessageLabel,
            hint: '',
            maxLines: 3,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ],
    );
  }

  Widget _itemCard(AppLocalizations l10n, ColorScheme cs, LoanableItem item) {
    final max = _max(item);
    final available = max > 0;
    final qty = _qty[item.inventoryItemId] ?? 0;
    final selected = qty > 0;
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    final placeholder = Container(
      width: 52,
      height: 52,
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.inventory_2_outlined, color: cs.onSurfaceVariant),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected
            ? AppConstants.primaryGreen.withValues(alpha: 0.05)
            : context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: selected
              ? AppConstants.primaryGreen
              : cs.outline.withValues(alpha: 0.18),
          width: selected ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                child: hasImage
                    ? Image.network(
                        item.imageUrl!,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => placeholder,
                      )
                    : placeholder,
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
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.category.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.category,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      available
                          ? l10n.assistInStock(
                              formatQuantity(
                                (item.quantityOnHand * 100).floor() / 100,
                              ),
                              item.unit,
                            )
                          : _aboveCapital(item)
                          ? l10n.loanCapAbove
                          : l10n.assistOutOfStock,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: available
                            ? AppConstants.successGreen
                            : AppConstants.errorRed,
                      ),
                    ),
                    // The Capital Share, not the stock, is what limits this item.
                    if (available &&
                        _capital != null &&
                        max < (item.quantityOnHand * 100).floor() / 100 - 1e-9)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          l10n.loanCapQtyNote(formatQuantityUnit(max, item.unit)),
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: AppConstants.warningAmber,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (available) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${l10n.assistQtyLabel} (${item.unit})',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                _stepper(item, max, qty),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// - N +  : the number can be typed (up to 2 decimals); the buttons step by 1.
  Widget _stepper(LoanableItem item, double max, double qty) {
    final cs = Theme.of(context).colorScheme;
    Widget roundButton(IconData icon, VoidCallback? onTap) => SizedBox(
      width: 38,
      height: 38,
      child: Material(
        color: onTap == null
            ? cs.surfaceContainerHighest
            : AppConstants.primaryGreen.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(
            icon,
            size: 20,
            color: onTap == null
                ? cs.outline
                : Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        roundButton(
          Icons.remove_rounded,
          qty > 0 && !_sending ? () => _setQty(item, qty - 1) : null,
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 76,
          child: Focus(
            // Leaving the field with nothing typed counts as 0.
            onFocusChange: (focused) {
              if (!focused && _ctrlFor(item).text.trim().isEmpty) {
                _setQty(item, 0);
              }
            },
            child: TextField(
              key: Key('assistQty_${item.inventoryItemId}'),
              controller: _ctrlFor(item),
              enabled: !_sending,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              // Digits and one decimal point (2 decimals at most), never more than the stock.
              inputFormatters: [DecimalInputFormatter(max: max)],
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
                filled: true,
                fillColor: context.saganaColors.cardBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              onChanged: (v) {
                final n = double.tryParse(v) ?? 0;
                // The formatter already stops anything above the stock; the field is left as typed.
                _setQty(item, n, rewriteField: false);
              },
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        roundButton(
          Icons.add_rounded,
          qty < max - 1e-9 && !_sending ? () => _setQty(item, qty + 1) : null,
        ),
      ],
    );
  }

  /// Fixed at the bottom: how many items are chosen, and the send button.
  Widget _footer(AppLocalizations l10n, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.12))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.assistSelectedCount(_selectedCount),
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _selectedCount > 0
                    ? Theme.of(context).colorScheme.primary
                    : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              label: l10n.assistSend,
              icon: Icons.volunteer_activism_rounded,
              isLoading: _sending,
              onPressed:
                  _sending ||
                      _items.isEmpty ||
                      _selectedCount == 0 ||
                      (_capital?.isZero ?? false)
                  ? null
                  : _send,
            ),
          ],
        ),
      ),
    );
  }
}
