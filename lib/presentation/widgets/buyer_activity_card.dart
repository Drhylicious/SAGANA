import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/models/buyer_activity_model.dart';
import 'recent_activity_widgets.dart';

/// Buyer's Recent Activity presentation. The card and date group are the
/// shared Recent Activity widgets (recent_activity_widgets.dart), so Buyer
/// looks like Farmer, Admin and Officer. This file only maps Buyer data onto
/// them. BuyerAccountScreen's inline preview and the full
/// BuyerRecentActivityScreen both use it, so they can't drift apart.

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
    return RecentActivityDateGroup(
      label: label,
      cards: [for (final item in items) BuyerActivityCard(item: item)],
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
    case 'pending':   return l10n.buyerOrdersStatusPending;
    case 'approved':  return l10n.buyerOrderDetailStepApproved;
    case 'completed': return l10n.buyerOrderDetailStepCompleted;
    case 'cancelled': return l10n.buyerActivityStatusCancelled;
    case 'rejected':  return l10n.orderStatusRejected;
    default:          return status ?? '';
  }
}

// Tone comes from the order status code, not the translated label, so the
// colour holds in every language.
RecentActivityTone _orderStatusTone(String? status) {
  switch (status) {
    case 'approved':  return RecentActivityTone.success;
    case 'completed': return RecentActivityTone.neutral;
    case 'cancelled':
    case 'rejected':  return RecentActivityTone.alert;
    default:          return RecentActivityTone.warning; // pending
  }
}

// Derives a badge for profile-type entries from the description's leading
// verb. BuyerActivityItem carries plain description text rather than a
// structured sub-type.
class _ProfileBadge {
  final String label;
  final RecentActivityTone tone;
  final IconData icon;
  final RecentActivityIconTone iconTone;
  const _ProfileBadge(this.label, this.tone, this.icon, this.iconTone);
}

// Keyed by the activity key, so the badge is right in every language.
_ProfileBadge _profileBadge(String? messageKey, AppLocalizations l10n) {
  switch (messageKey) {
    case 'activityAddressAdded':
      return _ProfileBadge(l10n.buyerActivityBadgeAdded, RecentActivityTone.success,
          Icons.add_location_alt_rounded, RecentActivityIconTone.primary);
    case 'activityAddressDeleted':
      return _ProfileBadge(l10n.buyerActivityBadgeRemoved, RecentActivityTone.alert,
          Icons.delete_outline_rounded, RecentActivityIconTone.alert);
    case 'activityAddressDefault':
      return _ProfileBadge(l10n.buyerActivityBadgeDefault, RecentActivityTone.neutral,
          Icons.location_on_rounded, RecentActivityIconTone.info);
    case 'activityPasswordChanged':
    return _ProfileBadge(l10n.buyerActivityBadgeSecurity, RecentActivityTone.neutral,
        Icons.lock_outline_rounded, RecentActivityIconTone.primary);
  }
  return _ProfileBadge(l10n.buyerActivityBadgeUpdated, RecentActivityTone.neutral,
      Icons.person_outline_rounded, RecentActivityIconTone.primary);
}

class BuyerActivityCard extends StatelessWidget {
  final BuyerActivityItem item;
  const BuyerActivityCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isOrder = item.type == BuyerActivityType.order;
    final title = isOrder ? activityOrderTitle(item.orderStatus, l10n) : item.title;
    final subtitle = isOrder ? item.subtitle : l10n.buyerActivityFilterProfile;
    final badge = isOrder ? null : _profileBadge(item.messageKey, l10n);
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;

    final icon = isOrder ? Icons.receipt_long_rounded : badge!.icon;
    final iconTone = isOrder ? RecentActivityIconTone.info : badge!.iconTone;

    return RecentActivityCard(
      icon: icon,
      iconTone: iconTone,
      title: title,
      subtitle: subtitle,
      timestamp: item.timestamp,
      valueLabel: isOrder ? item.valueLabel : null,
      statusLabel: isOrder ? _orderStatusLabel(item.orderStatus, l10n) : badge!.label,
      statusTone: isOrder ? _orderStatusTone(item.orderStatus) : badge!.tone,
      leading: hasImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              child: Image.network(
                item.imageUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => RecentActivityIcon(icon: icon, tone: iconTone),
              ),
            )
          : null,
    );
  }
}
