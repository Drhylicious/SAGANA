import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../core/utils/quantity_utils.dart';
import 'quantity_stepper.dart';
import 'shared_widgets.dart';

/// The Buy Now sliding sheet shared by a Marketplace listing and a Cooperative Product, so the
/// two look and behave the same: the photo, the price, how much is left, the market pill, the
/// order quantity and a Buy Now button.
///
/// It places nothing itself. Buy Now closes the sheet and hands the chosen quantity to
/// [onConfirm], which goes on to the checkout.
class ProductBuyNowSheet extends StatefulWidget {
  final String? photoUrl;
  final double price;
  final String unit;

  /// What is left to buy: the most the quantity can be.
  final double available;

  /// The small pill under the price ("Public Market", "Cooperative Product").
  final String pillLabel;

  /// The quantity the sheet opens with.
  final double initialQuantity;
  final ValueChanged<double> onConfirm;

  const ProductBuyNowSheet({
    super.key,
    required this.photoUrl,
    required this.price,
    required this.unit,
    required this.available,
    required this.pillLabel,
    required this.initialQuantity,
    required this.onConfirm,
  });

  /// A real bottom sheet (flush to the screen edges, native slide-up), not a centred card.
  static Future<void> show(
    BuildContext context, {
    required String? photoUrl,
    required double price,
    required String unit,
    required double available,
    required String pillLabel,
    required double initialQuantity,
    required ValueChanged<double> onConfirm,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProductBuyNowSheet(
        photoUrl: photoUrl,
        price: price,
        unit: unit,
        available: available,
        pillLabel: pillLabel,
        initialQuantity: initialQuantity,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<ProductBuyNowSheet> createState() => _ProductBuyNowSheetState();
}

class _ProductBuyNowSheetState extends State<ProductBuyNowSheet> {
  late double _quantity;

  @override
  void initState() {
    super.initState();
    _quantity = widget.initialQuantity;
  }

  void _confirm() {
    // A number still being typed is tidied (and reported) when the field loses
    // focus, so let it do that first: Buy Now must use what the field shows.
    FocusManager.instance.primaryFocus?.unfocus();
    final quantity = _quantity;
    Navigator.of(context).pop();
    widget.onConfirm(quantity);
  }

  Widget _pill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppConstants.primaryGreen,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        widget.pillLabel,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = unitOrDefault(widget.unit);

    // The quantity is typed, so the on-screen keyboard opens over the sheet:
    // the sheet is lifted by the keyboard's height (viewInsets) and can scroll,
    // otherwise the keyboard would hide the number and the Buy Now button.
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Material(
          color: context.saganaColors.cardBackground,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusMd,
                        ),
                        child: SizedBox(
                          width: 76,
                          height: 76,
                          child: widget.photoUrl != null
                              ? Image.network(
                                  widget.photoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Container(color: AppConstants.limeGreen),
                                )
                              : Container(color: AppConstants.limeGreen),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  formatPesos(widget.price),
                                  style: GoogleFonts.poppins(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: AppConstants.primaryGreen,
                                  ),
                                ),
                                Text(
                                  '/$unit',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppConstants.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.buyerListingMaxAvailable(
                                formatQuantityUnit(
                                  widget.available,
                                  widget.unit,
                                ),
                              ),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppConstants.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _pill(),
                  const SizedBox(height: 28),
                  // One row: the label on the left, the stepper on the right.
                  // The label takes the space the stepper leaves (Expanded), so
                  // the two never overflow; a long label (Tagalog, a long unit)
                  // wraps onto a second line instead of being cut off or pushing
                  // the stepper down.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.buyerListingOrderQty(unit),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Editable: type a quantity (up to 2 decimals), or use - / +.
                      // The value is reported as it is typed, so Buy Now always
                      // uses what shows.
                      QuantityStepper(
                        value: _quantity,
                        max: widget.available,
                        onChanged: (v) => setState(() => _quantity = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton(
                    key: const Key('buyNowConfirm'),
                    label: l10n.buyerListingBuyNow,
                    onPressed: _confirm,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
