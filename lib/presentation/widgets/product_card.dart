import '../../core/theme/sagana_colors.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import 'animated_pressable.dart';

/// The one product card every SAGANA product grid uses: Buyer Browse, the
/// Farmer's Marketplace pane and the Product Sales program catalog.
///
/// It only draws what it is given. Each screen keeps its own data, rules and
/// tap behaviour, so sharing the card changes how a product LOOKS and nothing
/// about how it is sold.
///
/// Layout (top to bottom):
///   photo (takes whatever height the details leave) with an optional badge
///   name
///   price per unit  ·  number of buyers
///   [optional hint line, e.g. the Product Sales member price]
///   [optional market type]
///   quantity available  ·  quantity sold
///
/// Quantities and prices arrive already formatted with their own unit
/// (`₱45.00/sack`, `90 sack available`), so no unit logic lives here.
class ProductCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final IconData placeholderIcon;

  /// `₱45.00/sack`.
  final String priceText;
  final Color priceColor;

  /// `1 buyer` / `12 buyers`.
  final String buyersText;

  /// Optional line under the price (Product Sales: the member price / saving).
  final String? hintText;
  final Color? hintColor;

  /// Optional market type (`Public Market`). Product Sales has none.
  final String? marketTypeText;

  /// `90 sack available`.
  final String availableText;

  /// `10 sack sold`.
  final String soldText;

  /// Greys the card out when nothing is left to buy.
  final bool soldOut;

  final String? badgeLabel;
  final Color? badgeColor;
  final VoidCallback? onTap;

  const ProductCard({
    super.key,
    required this.name,
    required this.priceText,
    required this.buyersText,
    required this.availableText,
    required this.soldText,
    this.imageUrl,
    this.placeholderIcon = Icons.eco_rounded,
    this.priceColor = AppConstants.primaryGreen,
    this.hintText,
    this.hintColor,
    this.marketTypeText,
    this.soldOut = false,
    this.badgeLabel,
    this.badgeColor,
    this.onTap,
  });

  /// Two cards per row, the same size on every screen that shows products.
  static const SliverGridDelegateWithFixedCrossAxisCount gridDelegate =
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.66,
      );

  @override
  Widget build(BuildContext context) {
    final small = GoogleFonts.inter(
      fontSize: 11,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final priceStyle = GoogleFonts.poppins(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      color: priceColor,
    );

    return AnimatedPressable(
      onTap: onTap,
      scaleDown: 0.97,
      child: Opacity(
        opacity: soldOut ? 0.55 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: context.saganaColors.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: AppConstants.cardBorder,
            boxShadow: AppConstants.cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The photo takes whatever height the details leave, so the text
              // is never clipped, whatever the phone's font size.
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _photo(),
                    if (badgeLabel != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _Badge(
                          label: badgeLabel!,
                          color: badgeColor ?? AppConstants.primaryGreen,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _PairRow(
                      left: priceText,
                      leftStyle: priceStyle,
                      right: buyersText,
                      rightStyle: small,
                    ),
                    if (hintText != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        hintText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color:
                              hintColor ??
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (marketTypeText != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        marketTypeText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small,
                      ),
                    ],
                    const SizedBox(height: 1),
                    _PairRow(
                      left: availableText,
                      leftStyle: small,
                      right: soldText,
                      rightStyle: small,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photo() {
    final placeholder = Container(
      color: AppConstants.limeGreen,
      child: Icon(placeholderIcon, size: 32),
    );
    final url = imageUrl;
    if (url == null || url.isEmpty) return placeholder;
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
}

/// Two short texts on one line, the second right after the first. When both do
/// not fit they are scaled down together, so a long figure such as
/// `1,250 sack available` is never cut off with "…" (the card must stay
/// readable), and a short pair keeps its normal size.
class _PairRow extends StatelessWidget {
  final String left;
  final TextStyle leftStyle;
  final String right;
  final TextStyle rightStyle;

  const _PairRow({
    required this.left,
    required this.leftStyle,
    required this.right,
    required this.rightStyle,
  });

  // Each side's share of the line is its approximate width, so both shrink by
  // the same factor and neither is squeezed more than the other.
  int _weight(String text, TextStyle style) =>
      math.max(1, (text.length * (style.fontSize ?? 11)).round());

  Widget _side(String text, TextStyle style) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Text(text, maxLines: 1, softWrap: false, style: style),
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(flex: _weight(left, leftStyle), child: _side(left, leftStyle)),
        const SizedBox(width: 6),
        Flexible(
          flex: _weight(right, rightStyle),
          child: _side(right, rightStyle),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
