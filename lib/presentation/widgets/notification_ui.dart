import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/system_notification_text.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/models/notification_model.dart';
import 'notification_day_groups.dart';
import 'recent_activity_widgets.dart';

/// Shared by every notification screen (Manager, Officer, Farmer, Buyer and the
/// Pending Applicant tab): the time shown on a notification, the selection
/// state, the single-action three-dot menu (Mark as Read / Mark as Unread, only
/// while selecting), and the one notification card.

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
      if (diff.inMinutes < 60) {
        return l10n.buyerNotifTimeMinutesAgo(diff.inMinutes);
      }
      return l10n.buyerNotifTimeHoursAgo(diff.inHours);
    case NotificationDay.yesterday:
      return l10n.buyerNotifTimeYesterday;
    case NotificationDay.earlier:
      // Same format as Recent Activity: "November 12" this year,
      // "November 12, 2025" in an earlier year.
      return activityDateLabel(createdAt, l10n.localeName, now: current);
  }
}

/// Which notifications are selected (SMS-style). Long-press starts it, a tap
/// toggles while it is active, and it ends when the last one is unselected.
/// Screens keep one of these and call setState around its changes.
class NotificationSelection {
  final Set<String> _ids = {};

  bool get isActive => _ids.isNotEmpty;
  int get count => _ids.length;
  bool contains(String id) => _ids.contains(id);

  void toggle(String id) {
    if (!_ids.add(id)) _ids.remove(id);
  }

  void clear() => _ids.clear();

  /// The selected notifications, in list order.
  List<NotificationModel> picked(List<NotificationModel> all) =>
      all.where((n) => _ids.contains(n.id)).toList();

  /// The one action to offer: "Mark as Read" only when every selected
  /// notification is unread, otherwise "Mark as Unread".
  bool offersMarkRead(List<NotificationModel> all) {
    final selected = picked(all);
    return selected.isNotEmpty && selected.every((n) => n.isUnread);
  }
}

/// The top-right three-dot menu. Screens show it only while a selection is
/// active; it offers a single action chosen by [markRead].
class NotificationSelectionMenu extends StatelessWidget {
  /// True: "Mark as Read". False: "Mark as Unread".
  final bool markRead;
  final VoidCallback onApply;

  const NotificationSelectionMenu({
    super.key,
    required this.markRead,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<bool>(
      key: const ValueKey('notification-menu'),
      // Opens below the icon instead of over the screen title.
      position: PopupMenuPosition.under,
      tooltip: l10n.notifMenuTooltip,
      icon: Icon(
        Icons.more_vert_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
      onSelected: (_) => onApply(),
      itemBuilder: (context) => [
        PopupMenuItem<bool>(
          key: const ValueKey('notification-toggle-read'),
          value: markRead,
          child: Text(
            markRead ? l10n.notifItemMarkRead : l10n.notifItemMarkUnread,
          ),
        ),
      ],
    );
  }
}

/// The top bar title: the screen's own title, or "N selected" while selecting.
String notificationTopBarTitle(
  AppLocalizations l10n,
  String title,
  NotificationSelection selection,
) => selection.isActive ? l10n.notifSelectedCount(selection.count) : title;

/// The icon and colour a notification type is drawn with.
({IconData icon, Color color}) notificationStyle(
  NotificationType type, {
  ColorScheme? colorScheme,
}) {
  switch (type) {
    case NotificationType.order:
      return (icon: Icons.shopping_bag_outlined, color: AppConstants.buyerBlue);
    case NotificationType.listing:
      return (
        icon: Icons.storefront_outlined,
        color: colorScheme?.primary ?? AppConstants.primaryGreen,
      );
    case NotificationType.loan:
      return (
        icon: Icons.eco_outlined,
        color: colorScheme?.primary ?? AppConstants.tertiaryContainer,
      );
    case NotificationType.price:
      return (icon: Icons.show_chart_rounded, color: AppConstants.amber);
    case NotificationType.sync:
      return (icon: Icons.sync_rounded, color: AppConstants.successGreen);
    case NotificationType.cropRequest:
      return (
        icon: Icons.local_florist_outlined,
        color: colorScheme?.primary ?? AppConstants.primaryGreen,
      );
    case NotificationType.cooperativeOffer:
      return (icon: Icons.groups_outlined, color: AppConstants.successGreen);
    case NotificationType.program:
      return (
        icon: Icons.volunteer_activism_outlined,
        color: colorScheme?.primary ?? AppConstants.tertiaryContainer,
      );
    case NotificationType.capital:
      return (icon: Icons.savings_outlined, color: AppConstants.amber);
    case NotificationType.memberApproved:
      return (icon: Icons.verified_outlined, color: AppConstants.successGreen);
    case NotificationType.memberRejected:
      return (
        icon: Icons.info_outline_rounded,
        color: colorScheme?.error ?? AppConstants.errorRed,
      );
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
        color: colorScheme?.onSurfaceVariant ?? AppConstants.onSurfaceVariant,
      );
  }
}

/// One button under a notification's message.
class NotificationAction {
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const NotificationAction({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
}

/// The notification card every role uses. Long-press (or, once selecting, tap)
/// selects it: the type icon becomes a check, SMS-style. No swipe actions.
class NotificationCard extends StatelessWidget {
  final NotificationModel item;
  final String timeLabel;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Buttons shown under the message, for a notice the reader answers (the
  /// shelf-life check: "still okay" / "already rotten"). Empty for the rest.
  final List<NotificationAction> actions;

  const NotificationCard({
    super.key,
    required this.item,
    required this.timeLabel,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = notificationStyle(item.type, colorScheme: cs);
    final sagana = context.saganaColors;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppConstants.primaryGreen.withValues(alpha: 0.12)
              : item.isRead
              ? sagana.cardBackground.withValues(alpha: 0.85)
              : cs.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: selected
                ? AppConstants.primaryGreen.withValues(alpha: 0.55)
                : item.isRead
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
            AnimatedContainer(
              key: selected
                  ? const ValueKey('notification-selected-check')
                  : null,
              duration: const Duration(milliseconds: 150),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? AppConstants.primaryGreen
                    : style.color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                selected ? Icons.check_rounded : style.icon,
                color: selected ? Colors.white : style.color,
                size: 20,
              ),
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
                          localizedNotificationTitle(
                            AppLocalizations.of(context),
                            item.title,
                          ),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: item.isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
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
                    localizedNotificationBody(
                      AppLocalizations.of(context),
                      item.title,
                      item.body,
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  if (actions.isNotEmpty && !selected) ...[
                    const SizedBox(height: 10),
                    for (final action in actions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SizedBox(
                          width: double.infinity,
                          child: action.destructive
                              ? OutlinedButton(
                                  onPressed: action.onTap,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppConstants.errorRed,
                                    side: BorderSide(
                                      color: AppConstants.errorRed.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    textStyle: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  child: Text(
                                    action.label,
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : FilledButton(
                                  onPressed: action.onTap,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppConstants.primaryGreen,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    textStyle: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  child: Text(
                                    action.label,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                        ),
                      ),
                  ],
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
  }
}
