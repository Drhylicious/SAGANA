import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/models/notification_model.dart';
import 'notification_day_groups.dart';

/// Shared by every notification screen (Manager, Officer, Farmer, Buyer and the
/// Pending Applicant tab): the time shown on a notification, the three-dot menu
/// that changes read status, the per-notification read/unread sheet, and the
/// card the Farmer and Pending Applicant screens use.

/// When a notification happened, in the words that suit its day group:
///   Today      "Just now", "5m ago", "3h ago"
///   Yesterday  "Yesterday"
///   Earlier    the date ("Oct 21" this year, "Oct 21, 2025" before that)
String notificationTimeLabel(
  AppLocalizations l10n,
  DateTime createdAt, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  switch (notificationDayOf(createdAt, now: current)) {
    case NotificationDay.today:
      final diff = current.difference(createdAt);
      if (diff.inMinutes < 1) return l10n.broadcastJustNow;
      if (diff.inMinutes < 60) return l10n.buyerNotifTimeMinutesAgo(diff.inMinutes);
      return l10n.buyerNotifTimeHoursAgo(diff.inHours);
    case NotificationDay.yesterday:
      return l10n.buyerNotifTimeYesterday;
    case NotificationDay.earlier:
      final format = createdAt.year == current.year
          ? DateFormat.MMMd(l10n.localeName)
          : DateFormat.yMMMd(l10n.localeName);
      return format.format(createdAt);
  }
}

/// The top-right three-dot menu. Offers what applies to the list as it is now:
/// mark all as read (something is unread), mark all as unread (something is
/// read), and, where a screen has it, clear all. Nothing to offer, no button.
class NotificationMenuButton extends StatelessWidget {
  final bool hasUnread;
  final bool hasRead;
  final VoidCallback onMarkAllRead;
  final VoidCallback onMarkAllUnread;
  final VoidCallback? onClearAll;

  const NotificationMenuButton({
    super.key,
    required this.hasUnread,
    required this.hasRead,
    required this.onMarkAllRead,
    required this.onMarkAllUnread,
    this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!hasUnread && !hasRead && onClearAll == null) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      key: const ValueKey('notification-menu'),
      // Opens below the icon instead of over the screen title.
      position: PopupMenuPosition.under,
      tooltip: l10n.notifMenuTooltip,
      icon: const Icon(
        Icons.more_vert_rounded,
        color: AppConstants.primaryGreen,
      ),
      onSelected: (value) {
        switch (value) {
          case 'read_all':
            onMarkAllRead();
          case 'unread_all':
            onMarkAllUnread();
          case 'clear_all':
            onClearAll?.call();
        }
      },
      itemBuilder: (context) => [
        if (hasUnread)
          PopupMenuItem(
            value: 'read_all',
            child: Text(l10n.buyerNotifMenuMarkAllRead),
          ),
        if (hasRead)
          PopupMenuItem(
            value: 'unread_all',
            child: Text(l10n.notifMenuMarkAllUnread),
          ),
        if (onClearAll != null)
          PopupMenuItem(
            value: 'clear_all',
            child: Text(l10n.buyerNotifMenuClearAll),
          ),
      ],
    );
  }
}

/// Long-press on a notification: one action, the opposite of its current state.
Future<void> showNotificationReadSheet(
  BuildContext context, {
  required bool isRead,
  required VoidCallback onToggle,
}) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListTile(
        key: const ValueKey('notification-toggle-read'),
        leading: Icon(
          isRead ? Icons.mark_email_unread_outlined : Icons.drafts_outlined,
          color: AppConstants.primaryGreen,
        ),
        title: Text(
          isRead ? l10n.notifItemMarkUnread : l10n.notifItemMarkRead,
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        onTap: () {
          Navigator.of(sheetContext).pop();
          onToggle();
        },
      ),
    ),
  );
}

/// The icon and colour a notification type is drawn with.
({IconData icon, Color color}) notificationStyle(NotificationType type) {
  switch (type) {
    case NotificationType.order:
      return (icon: Icons.shopping_bag_outlined, color: AppConstants.buyerBlue);
    case NotificationType.listing:
      return (
        icon: Icons.storefront_outlined,
        color: AppConstants.primaryGreen,
      );
    case NotificationType.loan:
      return (
        icon: Icons.eco_outlined,
        color: AppConstants.tertiaryContainer,
      );
    case NotificationType.price:
      return (icon: Icons.show_chart_rounded, color: AppConstants.amber);
    case NotificationType.sync:
      return (icon: Icons.sync_rounded, color: AppConstants.successGreen);
    case NotificationType.cropRequest:
      return (
        icon: Icons.local_florist_outlined,
        color: AppConstants.primaryGreen,
      );
    case NotificationType.cooperativeOffer:
      return (icon: Icons.groups_outlined, color: AppConstants.successGreen);
    case NotificationType.program:
      return (
        icon: Icons.volunteer_activism_outlined,
        color: AppConstants.tertiaryContainer,
      );
    case NotificationType.capital:
      return (icon: Icons.savings_outlined, color: AppConstants.amber);
    case NotificationType.memberApproved:
      return (icon: Icons.verified_outlined, color: AppConstants.successGreen);
    case NotificationType.memberRejected:
      return (icon: Icons.info_outline_rounded, color: AppConstants.errorRed);
    case NotificationType.system:
    case NotificationType.listingSubmitted:
    case NotificationType.loanOverdue:
    case NotificationType.memberPending:
    case NotificationType.memberRegistered:
    case NotificationType.memberUpdated:
    case NotificationType.lowStock:
    case NotificationType.stockDepleted:
      return (
        icon: Icons.info_outline_rounded,
        color: AppConstants.onSurfaceVariant,
      );
  }
}

/// The notification card of the Farmer screen, shared with the Pending
/// Applicant tab. Swipe to delete when [onDelete] is given; long-press for the
/// read/unread action when [onLongPress] is given.
class NotificationCard extends StatelessWidget {
  final NotificationModel item;
  final String timeLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;

  const NotificationCard({
    super.key,
    required this.item,
    required this.timeLabel,
    required this.onTap,
    this.onLongPress,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final style = notificationStyle(item.type);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final card = GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: item.isRead
              ? sagana.cardBackground.withValues(alpha: 0.85)
              : cs.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: item.isRead
                ? cs.outlineVariant.withValues(alpha: 0.30)
                : cs.primary.withValues(alpha: 0.15),
          ),
          boxShadow: [
            BoxShadow(color: cs.shadow.withValues(alpha: 0.05), blurRadius: 8),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(style.icon, color: style.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: item.isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                            color: AppConstants.onSurface,
                          ),
                        ),
                      ),
                      if (item.isUnread)
                        Container(
                          key: const ValueKey('notification-unread-dot'),
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppConstants.primaryGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppConstants.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    timeLabel,
                    style: GoogleFonts.inter(fontSize: 10, color: cs.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (onDelete == null) return card;
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppConstants.errorRed.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: AppConstants.errorRed,
        ),
      ),
      onDismissed: (_) => onDelete!(),
      child: card,
    );
  }
}
