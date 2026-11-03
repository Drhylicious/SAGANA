import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/quantity_utils.dart';
import '../../data/repositories/market_linking_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Market Linking — shared building blocks
//
// The Farmer's My Market Linking screen and the Manager/Officer Market Linking
// screen are built from these same pieces, so both roles read a request the
// same way: the crop and its photo, one plain-language status, how much has
// sold and what is left, and the sales recorded so far.
// ─────────────────────────────────────────────────────────────────────────────

/// The one plain-language status of a request, with its colour and icon.
class MarketLinkingStatusInfo {
  final String label;
  final Color color;
  final IconData icon;
  const MarketLinkingStatusInfo(this.label, this.color, this.icon);
}

MarketLinkingStatusInfo marketLinkingStatusInfo(
  AppLocalizations l10n,
  MarketLinkingModel entry,
) {
  // A cancellation waiting for the Manager/Officer outranks the stage the
  // request is at: it is the thing that needs attention.
  if (entry.isCancellationRequested) {
    return MarketLinkingStatusInfo(
      l10n.mlkStatusCancellationRequested,
      AppConstants.errorRed,
      Icons.pending_actions_rounded,
    );
  }
  switch (entry.status) {
    case MarketLinkingStatus.requested:
    case MarketLinkingStatus.submitted:
      return MarketLinkingStatusInfo(
        l10n.mlkStatusWaiting,
        AppConstants.warningAmber,
        Icons.hourglass_top_rounded,
      );
    case MarketLinkingStatus.buyerFound:
      return MarketLinkingStatusInfo(
        l10n.mlkStatusBuyerFound,
        AppConstants.buyerBlue,
        Icons.handshake_outlined,
      );
    case MarketLinkingStatus.completed:
      // "Completed", the same word every selling channel uses for a finished
      // transaction (what happened to any unsold quantity shows in the progress).
      return MarketLinkingStatusInfo(
        l10n.statCompleted,
        AppConstants.successGreen,
        Icons.check_circle_rounded,
      );

    case MarketLinkingStatus.cancelled:
      return MarketLinkingStatusInfo(
        l10n.mlkStatusCancelled,
        AppConstants.outline,
        Icons.cancel_outlined,
      );
  }
}

/// A small coloured pill with the request's status.
class MarketLinkingStatusChip extends StatelessWidget {
  final MarketLinkingModel entry;
  const MarketLinkingStatusChip({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final info = marketLinkingStatusInfo(AppLocalizations.of(context), entry);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(info.icon, size: 12, color: info.color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              info.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: info.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Farmer's actual photo of the crop (never a catalog image). Tap to
/// enlarge. With no photo it shows [fallback] (initials or a crop icon).
class MarketLinkingEntryPhoto extends StatelessWidget {
  final MarketLinkingModel entry;
  final double size;
  final bool useInitials;
  const MarketLinkingEntryPhoto({
    super.key,
    required this.entry,
    this.size = 52,
    this.useInitials = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppConstants.primaryGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Center(
        child: useInitials
            ? Text(
                entry.initials,
                style: GoogleFonts.poppins(
                  fontSize: size * 0.32,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.primaryGreen,
                ),
              )
            : Icon(Icons.eco_rounded, size: size * 0.5, color: AppConstants.primaryGreen),
      ),
    );

    final photo = entry.cropPhotoUrl;
    if (photo == null || photo.isEmpty) return fallback;

    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InteractiveViewer(
                child: Image.network(
                  photo,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Icon(Icons.broken_image_outlined, size: 40),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  l10n.mlkPhotoCaption(entry.cropName, entry.farmerName),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Image.network(
          photo,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}

/// Progress bar plus "Sold 50 of 80 kg" and what is left to sell (or, once the
/// request is closed, what went back to the Farmer's stock).
class MarketLinkingSaleProgress extends StatelessWidget {
  final MarketLinkingModel entry;
  final EdgeInsetsGeometry padding;
  const MarketLinkingSaleProgress({
    super.key,
    required this.entry,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final total = entry.volumeKg ?? 0;
    final sold = entry.soldKg;
    final fraction = total > 0 ? (sold / total).clamp(0.0, 1.0) : 0.0;
    final unsold = roundQuantity(total - sold);
    final String right;
    if (entry.isActive) {
      right = l10n.mlkLeftToSell(formatQuantityUnit(entry.remainingKg, entry.unit));
    } else if (unsold > 0) {
      right = l10n.mlkReturnedToStock(formatQuantityUnit(unsold, entry.unit));
    } else {
      right = l10n.mlkFullySold;
    }

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  l10n.mlkSoldOfTotal(
                    formatQuantityUnit(sold, entry.unit),
                    formatQuantityUnit(total, entry.unit),
                  ),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  right,
                  textAlign: TextAlign.end,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: entry.isActive ? AppConstants.buyerBlue : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: cs.outline.withValues(alpha: 0.15),
              color: AppConstants.successGreen,
            ),
          ),
        ],
      ),
    );
  }
}

/// Every sale recorded against a request — buyer, quantity, price, total — with
/// the sum received. Long lists show the first two sales and a "Show all"
/// toggle, so a request with many sales stays compact.
class MarketLinkingSalesList extends StatefulWidget {
  final MarketLinkingModel entry;
  final EdgeInsetsGeometry padding;
  const MarketLinkingSalesList({
    super.key,
    required this.entry,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<MarketLinkingSalesList> createState() => _MarketLinkingSalesListState();
}

class _MarketLinkingSalesListState extends State<MarketLinkingSalesList> {
  static const _collapsedCount = 2;
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  bool _expanded = false;

  static String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  /// True when [sale]'s buyer is not already shown in the request's Buyer
  /// Details, so the name is worth putting on that line: either this sale went to
  /// someone else (a request can be sold in parts to different buyers) or the
  /// request shows no buyer at all. The same name (ignoring case and spacing) is
  /// never repeated.
  static bool _isOtherBuyer(MarketLinkingModel entry, MarketLinkingSale sale) {
    String norm(String? v) => (v ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final saleBuyer = norm(sale.buyerName);
    if (saleBuyer.isEmpty) return false;
    final requestBuyer = norm(entry.buyerName);
    return requestBuyer.isEmpty || saleBuyer != requestBuyer;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final entry = widget.entry;
    final sales = entry.sales;
    if (sales.isEmpty) return const SizedBox.shrink();

    final collapsible = sales.length > _collapsedCount;
    // Newest first, so the latest sale is always visible.
    final ordered = sales.reversed.toList();
    final visible = (!collapsible || _expanded) ? ordered : ordered.take(_collapsedCount).toList();

    return Padding(
      padding: widget.padding,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppConstants.successGreen.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: AppConstants.successGreen.withValues(alpha: 0.20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.mlkSalesCount(sales.length),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  l10n.mlkReceivedAmount(formatPesos(entry.soldValue)),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.successGreen,
                  ),
                ),
              ],
            ),
            for (final s in visible) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The sale itself: quantity and unit, price, date. The
                        // buyer is already shown once in Buyer Details above, so
                        // it is named here only when this sale went to someone
                        // else (a request can be sold in parts to different buyers).
                        Text(
                          '${formatQuantityUnit(s.quantityKg, s.unit)} × ${formatPricePerUnit(s.pricePerKg, s.unit)}',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          [
                            _date(s.completedAt),
                            if (_isOtherBuyer(entry, s)) s.buyerName,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatPesos(s.totalAmount),
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ],
            if (collapsible) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    _expanded ? l10n.mlkShowLess : l10n.mlkShowAllSales(sales.length),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.primaryGreen,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The four stages the Manager/Officer works through, with where this request is:
/// Request -> Buyer Details -> Complete Sale -> Completed. Done stages are
/// ticked, the stage to work on now is highlighted.
class MarketLinkingStageBar extends StatelessWidget {
  final MarketLinkingModel entry;
  const MarketLinkingStageBar({super.key, required this.entry});

  /// How many stages are finished: 0 none, 1 the request exists, 2 buyer saved,
  /// 4 completed. (The stage being worked on is the one right after.)
  int get _done {
    switch (entry.status) {
      case MarketLinkingStatus.requested:
        return 0;
      case MarketLinkingStatus.submitted:
        return 1;
      case MarketLinkingStatus.buyerFound:
        return 2;
      case MarketLinkingStatus.completed:
        return 4;
      case MarketLinkingStatus.cancelled:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final labels = [
      l10n.mlkStageRequest,
      l10n.mlkStageBuyer,
      l10n.mlkStageSale,
      l10n.statCompleted,
    ];
    final done = _done;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i == 0
                            ? Colors.transparent
                            : (i < done
                                  ? AppConstants.successGreen.withValues(alpha: 0.5)
                                  : cs.outline.withValues(alpha: 0.18)),
                      ),
                    ),
                    _Dot(done: i < done, current: i == done),
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i == labels.length - 1
                            ? Colors.transparent
                            : (i + 1 < done
                                  ? AppConstants.successGreen.withValues(alpha: 0.5)
                                  : cs.outline.withValues(alpha: 0.18)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: (i == done) ? FontWeight.w700 : FontWeight.w500,
                    color: (i < done || i == done)
                        ? cs.onSurface
                        : cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final bool done;
  final bool current;
  const _Dot({required this.done, required this.current});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (done) {
      return Container(
        width: 18,
        height: 18,
        decoration: const BoxDecoration(
          color: AppConstants.successGreen,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
      );
    }
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: current ? AppConstants.primaryGreen : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: current ? AppConstants.primaryGreen : cs.outline.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: current
          ? const Center(
              child: SizedBox(
                width: 6,
                height: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            )
          : null,
    );
  }
}

/// The saved Buyer Details (stage 2): full name, contact number, and the email
/// when given. The Manager/Officer edits it; the Farmer who submitted the request
/// sees the very same details, read-only.
class MarketLinkingBuyerBlock extends StatelessWidget {
  final MarketLinkingModel entry;
  const MarketLinkingBuyerBlock({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!entry.hasBuyer) return const SizedBox.shrink();

    Widget line(IconData icon, String text, {bool strong = false}) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: strong ? 13 : 12,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                color: strong ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.buyerBlue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppConstants.buyerBlue.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).mlkStageBuyer,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          line(Icons.person_outline_rounded, entry.buyerName!.trim(), strong: true),
          if ((entry.buyerContact ?? '').trim().isNotEmpty)
            line(Icons.phone_outlined, entry.buyerContact!.trim()),
          if ((entry.buyerEmail ?? '').trim().isNotEmpty)
            line(Icons.mail_outline_rounded, entry.buyerEmail!.trim()),

        ],
      ),
    );
  }
}

/// The four figures on the Farmer's summary card, worked out from the Farmer's
/// real requests and sales (nothing is typed in or estimated).
class MarketLinkingSummary {
  /// Active requests (waiting for a buyer, or buyer found).
  final int inProgress;

  /// Kilograms sold across every sale recorded for the Farmer (requests measured
  /// in kg only: another unit is never added to a kilogram figure).
  final double kgSold;

  /// Kilograms still unsold inside the active requests (kg requests only).
  final double kgRemaining;

  /// What was sold / is still unsold, in each request's own unit, added per
  /// unit and never mixed: `12.5 kg`, or `12.5 kg + 3 sack`.
  final String soldText;
  final String remainingText;

  /// Requests that finished (Completed). Cancelled requests are not counted.
  final int completed;

  const MarketLinkingSummary({
    required this.inProgress,
    required this.kgSold,
    required this.kgRemaining,
    required this.soldText,
    required this.remainingText,
    required this.completed,
  });

  factory MarketLinkingSummary.of(List<MarketLinkingModel> entries) {
    return MarketLinkingSummary(
      inProgress: entries.where((e) => e.isActive).length,
      kgSold: roundQuantity(
        entries.where((e) => isKg(e.unit)).fold<double>(0, (sum, e) => sum + e.soldKg),
      ),
      kgRemaining: roundQuantity(
        entries
            .where((e) => e.isActive && isKg(e.unit))
            .fold<double>(0, (sum, e) => sum + e.remainingKg),
      ),
      soldText: formatQuantitiesByUnit([
        for (final e in entries.where((e) => e.soldKg > 0))
          (quantity: e.soldKg, unit: e.unit),
      ]),
      remainingText: formatQuantitiesByUnit([
        for (final e in entries.where((e) => e.isActive && e.remainingKg > 0))
          (quantity: e.remainingKg, unit: e.unit),
      ]),
      completed: entries.where((e) => e.status == MarketLinkingStatus.completed).length,
    );
  }
}

/// A label above an input, in a box of a fixed minimum height with the label
/// sitting at its bottom: two fields side by side keep their input boxes level
/// even when one label wraps to two lines and the other does not.
class AlignedLabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const AlignedLabeledField({super.key, required this.label, required this.child});

  /// Room for a label of two lines.
  static const double labelHeight = 34;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: labelHeight),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
