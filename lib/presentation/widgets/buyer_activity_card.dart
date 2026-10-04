import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/models/buyer_activity_model.dart';

/// Shared building blocks for Buyer's Recent Activity presentation — used
/// by both BuyerAccountScreen's inline preview section and the full
/// BuyerRecentActivityScreen, so the two surfaces can never visually drift
/// apart (same reasoning as order_result_pieces.dart/FulfillmentInfoCard).

// ─── Group by date label ─────────────────────────────────────────────────

Map<String, List<BuyerActivityItem>> groupBuyerActivityByDate(
  List<BuyerActivityItem> items,
  AppLocalizations l10n,
) {
  final Map<String, List<BuyerActivityItem>> groups = {};
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  for (final item in items) {
    final itemDate = DateTime(item.timestamp.year, item.timestamp.month, item.timestamp.day);
    String label;
    if (itemDate == today) {
      label = l10n.buyerActivityToday;
    } else if (itemDate == yesterday) {
      label = l10n.buyerActivityYesterday;
    } else {
      label = DateFormat('MMMM d', l10n.localeName).format(item.timestamp);
    }
    groups.putIfAbsent(label, () => []).add(item);
  }
  return groups;
}

// ─── Date Group ─────────────────────────────────────────────────────────

class BuyerActivityDateGroup extends StatelessWidget {
  final String label;
  final List<BuyerActivityItem> items;
  const BuyerActivityDateGroup({super.key, required this.label, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 4),
          child: Text(label.toUpperCase(),
              style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: AppConstants.outline, letterSpacing: 1.2)),
        ),
        ...items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 10), child: BuyerActivityCard(item: item))),
      ],
    );
  }
}

// ─── Activity Card ──────────────────────────────────────────────────────

String activityOrderTitle(String? status, AppLocalizations l10n) {
  switch (status) {
    case 'pending':   return l10n.buyerOrderDetailStepPlaced;
    case 'approved':  return l10n.buyerActivityOrderApproved;
    case 'completed': return l10n.buyerActivityOrderCompleted;
    case 'cancelled': return l10n.buyerActivityOrderCancelled;
    default:          return l10n.buyerActivityOrderUpdated;
  }
}

String _orderStatusLabel(String? status, AppLocalizations l10n) {
  switch (status) {
    case 'pending':   return l10n.buyerOrderDetailPendingTimestamp;
    case 'approved':  return l10n.buyerOrderDetailStepApproved;
    case 'completed': return l10n.buyerOrderDetailStepCompleted;
    case 'cancelled': return l10n.buyerActivityStatusCancelled;
    default:          return status ?? '';
  }
}

Color _orderStatusColor(String? status) {
  switch (status) {
    case 'approved':  return AppConstants.successGreen;
    case 'completed': return AppConstants.primaryGreen;
    case 'cancelled': return AppConstants.errorRed;
    default:          return AppConstants.warningAmber; // pending
  }
}

// Derives a small badge for profile-type entries from the description's
// leading verb — same badge-driven presentation FarmerRecentActivityScreen
// uses for its own non-order categories, computed here since
// BuyerActivityItem/buyer_profile_activity carries plain description text
// rather than a structured sub-type.
class _ProfileBadge {
  final String label;
  final Color color;
  final IconData icon;
  const _ProfileBadge(this.label, this.color, this.icon);
}

_ProfileBadge _profileBadge(String description, AppLocalizations l10n) {
  final d = description.toLowerCase();
  if (d.startsWith('added')) {
    return _ProfileBadge(l10n.buyerActivityBadgeAdded, AppConstants.successGreen, Icons.add_location_alt_rounded);
  }
  if (d.startsWith('deleted')) {
    return _ProfileBadge(l10n.buyerActivityBadgeRemoved, AppConstants.errorRed, Icons.delete_outline_rounded);
  }
  if (d.startsWith('set "')) {
    return _ProfileBadge(l10n.buyerActivityBadgeDefault, AppConstants.buyerBlue, Icons.location_on_rounded);
  }
  if (d.startsWith('changed password')) {
    return _ProfileBadge(l10n.buyerActivityBadgeSecurity, AppConstants.primaryGreen, Icons.lock_outline_rounded);
  }
  return _ProfileBadge(l10n.buyerActivityBadgeUpdated, AppConstants.primaryGreen, Icons.person_outline_rounded);
}

class BuyerActivityCard extends StatelessWidget {
  final BuyerActivityItem item;
  const BuyerActivityCard({super.key, required this.item});

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDay = DateTime(dt.year, dt.month, dt.day);
    return itemDay == today ? DateFormat('h:mm a').format(dt) : DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isOrder = item.type == BuyerActivityType.order;
    final title = isOrder ? activityOrderTitle(item.orderStatus, l10n) : item.title;
    final subtitle = isOrder ? item.subtitle : l10n.buyerActivityFilterProfile;
    final badge = isOrder ? null : _profileBadge(item.title, l10n);
    final fallbackIcon = isOrder ? Icons.receipt_long_rounded : badge!.icon;
    final iconColor = isOrder ? AppConstants.buyerBlue : badge!.color;
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(hasImage ? AppConstants.radiusSm : 22),
            child: hasImage
                ? Image.network(
                    item.imageUrl!,
                    width: 44, height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _iconCircle(fallbackIcon, iconColor),
                  )
                : _iconCircle(fallbackIcon, iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(title,
                          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppConstants.onSurface)),
                    ),
                    const SizedBox(width: 8),
                    Text(_formatTime(item.timestamp), style: GoogleFonts.inter(fontSize: 11, color: AppConstants.outline)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (isOrder && item.valueLabel != null)
                      Text(item.valueLabel!,
                          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppConstants.onSurface))
                    else
                      const SizedBox.shrink(),
                    _StatusBadge(
                      label: isOrder ? _orderStatusLabel(item.orderStatus, l10n) : badge!.label,
                      color: isOrder ? _orderStatusColor(item.orderStatus) : badge!.color,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconCircle(IconData icon, Color color) {
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), shape: BoxShape.circle),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(4)),
      child: Text(label.toUpperCase(),
          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.5)),
    );
  }
}
