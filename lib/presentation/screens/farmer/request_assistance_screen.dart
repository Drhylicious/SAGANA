import '../../../core/theme/sagana_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../data/models/loan_request_model.dart';
import '../../../data/repositories/loan_repository.dart';
import '../../../data/repositories/program_assistance_repository.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/top_bar_spacer.dart';

/// A Farmer whose program outcome failed asks the cooperative for assistance.
/// Items come from the active Loan Item Catalog (loan-eligible and in stock).
/// This is NOT a loan: it creates no debt and no repayment. Pops `true` once sent.
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
  List<LoanableItem> _items = [];
  final Map<String, double> _qty = {}; // inventory item id -> quantity
  bool _loading = true;
  bool _failed = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items = await _loanRepo.fetchLoanableItems();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  void _step(LoanableItem item, double delta) {
    final next = ((_qty[item.inventoryItemId] ?? 0) + delta)
        .clamp(0, item.quantityOnHand)
        .toDouble();
    setState(() {
      if (next <= 0) {
        _qty.remove(item.inventoryItemId);
      } else {
        _qty[item.inventoryItemId] = next;
      }
    });
  }

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
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const TopBarSpacer(height: 64),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _failed
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.assistLoadFailed,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: _load,
                                child: Text(l10n.retry),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        children: [
                          Text(
                            widget.programName,
                            style: GoogleFonts.poppins(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppConstants.programPurple.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusMd,
                              ),
                            ),
                            child: Text(
                              l10n.assistInfo,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                height: 1.45,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.assistChooseItems,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_items.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                l10n.assistNoItems,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          else
                            for (final item in _items) _itemRow(l10n, item),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _message,
                            maxLines: 3,
                            maxLength: 300,
                            enabled: !_sending,
                            decoration: InputDecoration(
                              labelText: l10n.assistMessageLabel,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          PrimaryButton(
                            label: l10n.assistSend,
                            icon: Icons.volunteer_activism_rounded,
                            isLoading: _sending,
                            onPressed: _sending || _items.isEmpty
                                ? null
                                : _send,
                          ),
                        ],
                      ),
              ),
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

  Widget _itemRow(AppLocalizations l10n, LoanableItem item) {
    final qty = _qty[item.inventoryItemId] ?? 0;
    final available = item.inStock;
    // Whole units for countable items; kilos and litres may be halved.
    final step =
        (item.unit.toLowerCase() == 'kg' || item.unit.toLowerCase() == 'l')
        ? 0.5
        : 1.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: qty > 0
              ? AppConstants.primaryGreen
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  available
                      ? l10n.assistInStock(_n(item.quantityOnHand), item.unit)
                      : l10n.assistOutOfStock,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: available
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : AppConstants.errorRed,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: available && qty > 0 && !_sending
                ? () => _step(item, -step)
                : null,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          SizedBox(
            width: 38,
            child: Text(
              _n(qty),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: available && !_sending ? () => _step(item, step) : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
    );
  }
}
