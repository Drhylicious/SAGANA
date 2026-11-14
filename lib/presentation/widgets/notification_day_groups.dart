import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/l10n/app_localizations.dart';
import 'recent_activity_widgets.dart';

/// The day a notification falls on, for the shared grouping used by every
/// notification screen (Farmer, Buyer, Manager, and Officer).
enum NotificationDay { today, yesterday, earlier }

NotificationDay notificationDayOf(DateTime when, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final yesterday = today.subtract(const Duration(days: 1));
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  if (sameDay(when, today)) return NotificationDay.today;
  if (sameDay(when, yesterday)) return NotificationDay.yesterday;
  return NotificationDay.earlier;
}

/// The notification list body, newest first: "Today", "Yesterday", then one
/// group per older date labelled like Recent Activity ("November 12", with the
/// year only when it is not the current one). Empty groups are skipped. Items keep
/// the order the repository returned them in.
List<Widget> notificationGroupChildren<T>({
  required List<T> items,
  required DateTime Function(T item) timeOf,
  required Widget Function(T item) buildItem,
  required AppLocalizations l10n,
  double itemGap = 8,
}) {
  final now = DateTime.now();
  final sorted = [...items]..sort((a, b) => timeOf(b).compareTo(timeOf(a)));

  // Group key -> items. Insertion order is newest first because of the sort.
  final groups = <String, List<T>>{};
  final labels = <String, String>{};
  for (final item in sorted) {
    final when = timeOf(item);
    final String key;
    final String label;
    switch (notificationDayOf(when, now: now)) {
      case NotificationDay.today:
        key = 'today';
        label = l10n.notifGroupToday;
      case NotificationDay.yesterday:
        key = 'yesterday';
        label = l10n.notifGroupYesterday;
      case NotificationDay.earlier:
        // "November 12", or "November 12, 2025" when the year is not this one.
        label = activityDateLabel(when, l10n.localeName, now: now);
        key = label;
    }
    labels[key] = label;
    (groups[key] ??= []).add(item);
  }

  final children = <Widget>[];
  groups.forEach((key, group) {
    children.add(NotificationGroupLabel(label: labels[key]!));
    for (final item in group) {
      children.add(buildItem(item));
      children.add(SizedBox(height: itemGap));
    }
  });
  return children;
}

/// Small caps label above a day group.
class NotificationGroupLabel extends StatelessWidget {
  final String label;
  const NotificationGroupLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.outline,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
