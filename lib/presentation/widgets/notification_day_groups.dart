import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';

/// The day a notification falls on, for the shared grouping used by every
/// notification screen (Farmer, Buyer, Admin, and Officer).
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

/// The notification list body: a label for each non-empty day group (Today,
/// Yesterday, Earlier), then that group's items. Items keep the order the
/// repository returned them in (newest first).
List<Widget> notificationGroupChildren<T>({
  required List<T> items,
  required DateTime Function(T item) timeOf,
  required Widget Function(T item) buildItem,
  required AppLocalizations l10n,
  double itemGap = 8,
}) {
  final now = DateTime.now();
  final groups = <NotificationDay, List<T>>{
    NotificationDay.today: [],
    NotificationDay.yesterday: [],
    NotificationDay.earlier: [],
  };
  for (final item in items) {
    groups[notificationDayOf(timeOf(item), now: now)]!.add(item);
  }

  final children = <Widget>[];
  for (final day in NotificationDay.values) {
    final group = groups[day]!;
    if (group.isEmpty) continue;
    children.add(NotificationGroupLabel(label: _dayLabel(l10n, day)));
    for (final item in group) {
      children.add(buildItem(item));
      children.add(SizedBox(height: itemGap));
    }
  }
  return children;
}

String _dayLabel(AppLocalizations l10n, NotificationDay day) {
  return switch (day) {
    NotificationDay.today => l10n.notifGroupToday,
    NotificationDay.yesterday => l10n.notifGroupYesterday,
    NotificationDay.earlier => l10n.notifGroupEarlier,
  };
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
          color: AppConstants.outline,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
