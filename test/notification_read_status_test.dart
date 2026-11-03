import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/notification_model.dart';
import 'package:sagana/presentation/widgets/notification_day_groups.dart';
import 'package:sagana/presentation/widgets/notification_ui.dart';

import 'support/ignore_font_errors.dart';

/// Date groups, time labels and the read/unread actions, for every role that has
/// notifications: Manager and Officer (one screen), Farmer, Buyer, and the
/// Pending Applicant tab.

String _read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

Future<AppLocalizations> _l10n(WidgetTester tester, {String locale = 'en'}) async {
  late AppLocalizations l10n;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(locale),
      home: Builder(
        builder: (context) {
          l10n = AppLocalizations.of(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return l10n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('which day a notification belongs to (from its real timestamp)', () {
    final now = DateTime(2026, 10, 27, 15, 30);

    test('today, yesterday, earlier', () {
      expect(notificationDayOf(DateTime(2026, 10, 27, 0, 1), now: now), NotificationDay.today);
      expect(notificationDayOf(DateTime(2026, 10, 26, 23, 59), now: now), NotificationDay.yesterday);
      expect(notificationDayOf(DateTime(2026, 10, 26, 0, 0), now: now), NotificationDay.yesterday);
      expect(notificationDayOf(DateTime(2026, 10, 25, 23, 59), now: now), NotificationDay.earlier);
      expect(notificationDayOf(DateTime(2025, 10, 27), now: now), NotificationDay.earlier);
    });

    test('month and year boundaries', () {
      final first = DateTime(2026, 11, 1, 8);
      expect(notificationDayOf(DateTime(2026, 10, 31, 20), now: first), NotificationDay.yesterday);
      final newYear = DateTime(2027, 1, 1, 8);
      expect(notificationDayOf(DateTime(2026, 12, 31, 20), now: newYear), NotificationDay.yesterday);
    });
  });

  group('the time shown on a notification', () {
    final now = DateTime(2026, 10, 27, 15, 30);

    testWidgets('today is relative, yesterday says so, older shows the date', (tester) async {
      final l10n = await _l10n(tester);
      String label(DateTime t) => notificationTimeLabel(l10n, t, now: now);
      expect(label(now.subtract(const Duration(seconds: 20))), 'Just now');
      expect(label(now.subtract(const Duration(minutes: 5))), '5m ago');
      expect(label(DateTime(2026, 10, 27, 9, 0)), '6h ago');
      expect(label(DateTime(2026, 10, 26, 23, 0)), 'Yesterday');
      expect(label(DateTime(2026, 10, 21, 10, 0)), 'Oct 21');
      expect(label(DateTime(2025, 10, 21, 10, 0)), 'Oct 21, 2025');
    });

    testWidgets('the label agrees with the group it sits in', (tester) async {
      final l10n = await _l10n(tester);
      // 20 hours ago crosses midnight: it is Yesterday's group, and says so.
      final t = DateTime(2026, 10, 26, 19, 30);
      expect(notificationDayOf(t, now: now), NotificationDay.yesterday);
      expect(notificationTimeLabel(l10n, t, now: now), 'Yesterday');
    });

    testWidgets('in Tagalog too', (tester) async {
      final l10n = await _l10n(tester, locale: 'tl');
      expect(notificationTimeLabel(l10n, DateTime(2026, 10, 26, 19), now: now), 'Kahapon');
      expect(notificationTimeLabel(l10n, DateTime(2026, 10, 21), now: now), isNotEmpty);
    });
  });

  group('the three-dot menu', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool hasUnread,
      required bool hasRead,
      VoidCallback? onClearAll,
      List<String>? log,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            appBar: AppBar(
              actions: [
                NotificationMenuButton(
                  hasUnread: hasUnread,
                  hasRead: hasRead,
                  onMarkAllRead: () => log?.add('read'),
                  onMarkAllUnread: () => log?.add('unread'),
                  onClearAll: onClearAll == null ? null : () => log?.add('clear'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('offers only what applies', (tester) async {
      await runIgnoringFontErrors(() async {
        await pump(tester, hasUnread: true, hasRead: false);
        await tester.tap(find.byKey(const ValueKey('notification-menu')));
        await tester.pumpAndSettle();
        expect(find.text('Mark all as read'), findsOneWidget);
        expect(find.text('Mark all as unread'), findsNothing);
      });
    });

    testWidgets('nothing to offer, no button', (tester) async {
      await runIgnoringFontErrors(() async {
        await pump(tester, hasUnread: false, hasRead: false);
        expect(find.byKey(const ValueKey('notification-menu')), findsNothing);
      });
    });

    testWidgets('Clear all (Buyer) comes after the read actions and still works', (tester) async {
      await runIgnoringFontErrors(() async {
        final log = <String>[];
        await pump(tester, hasUnread: true, hasRead: true, onClearAll: () {}, log: log);
        await tester.tap(find.byKey(const ValueKey('notification-menu')));
        await tester.pumpAndSettle();
        final read = tester.getTopLeft(find.text('Mark all as read')).dy;
        final unread = tester.getTopLeft(find.text('Mark all as unread')).dy;
        final clear = tester.getTopLeft(find.text('Clear all')).dy;
        expect(read, lessThan(unread));
        expect(unread, lessThan(clear));
        await tester.tap(find.text('Clear all'));
        await tester.pumpAndSettle();
        expect(log, ['clear']);
      });
    });
  });

  group('the card', () {
    testWidgets('read and unread look different and the dot follows the real state', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        NotificationModel n(bool read) => NotificationModel(
          id: 'x',
          userId: 'u',
          type: NotificationType.memberApproved,
          title: 'Approved',
          body: 'Welcome',
          isRead: read,
          createdAt: DateTime.now(),
        );
        for (final read in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: NotificationCard(item: n(read), timeLabel: 'Just now', onTap: () {}),
              ),
            ),
          );
          expect(
            find.byKey(const ValueKey('notification-unread-dot')),
            read ? findsNothing : findsOneWidget,
          );
        }
      });
    });
  });

  group('every role: same grouping, same menu, same actions', () {
    // Manager and Officer share one screen (the router sends both to it).
    final roles = <String, String>{
      'Manager / Officer': 'lib/presentation/screens/admin/admin_notifications_screen.dart',
      'Farmer': 'lib/presentation/screens/farmer/farmer_notifications_screen.dart',
      'Buyer': 'lib/presentation/screens/buyer/buyer_notifications_screen.dart',
      'Pending Applicant': 'lib/presentation/screens/farmer/pending_applicant_screen.dart',
    };

    test('each groups by day, shows the three-dot menu and can mark one or all as unread', () {
      for (final e in roles.entries) {
        final src = _read(e.value);
        final views = e.key == 'Pending Applicant'
            ? _read('lib/presentation/widgets/pending_applicant_views.dart')
            : '';
        final all = src + views;
        expect(all, contains('notificationGroupChildren<'), reason: '${e.key}: day groups');
        expect(all, contains('NotificationMenuButton('), reason: '${e.key}: menu');
        expect(all, contains('notificationTimeLabel('), reason: '${e.key}: time label');
        expect(all, contains('showNotificationReadSheet('), reason: '${e.key}: long-press');
        expect(src, contains('markAllAsUnread('), reason: '${e.key}: mark all unread');
        expect(src, contains('markAsUnread('), reason: '${e.key}: mark one unread');
        expect(src, contains('markAllAsRead('), reason: '${e.key}: mark all read');
        expect(src, contains('markAsRead('), reason: '${e.key}: mark one read');
      }
    });

    test('the router points Manager and Officer at the same screen', () {
      final router = _read('lib/presentation/navigation/app_router.dart');
      expect('const AdminNotificationsScreen()'.allMatches(router).length, 1);
    });

    test('nobody keeps a private copy of the time label', () {
      for (final e in roles.entries) {
        final src = _read(e.value);
        expect(src.contains('_buyerNotifTimeAgo'), isFalse, reason: e.key);
        expect(src.contains('String _timeLabel('), isFalse, reason: e.key);
        expect(src.contains('item.timeAgo'), isFalse, reason: e.key);
      }
    });

    test('existing behaviour is kept: tap opens the linked screen, swipe deletes, Buyer can clear all', () {
      expect(_read(roles['Farmer']!), contains('context.push(n.routeOnTap!'));
      expect(_read(roles['Buyer']!), contains('context.push(n.routeOnTap!'));
      expect(_read(roles['Manager / Officer']!), contains('context.push(notif.routeOnTap!'));
      for (final key in ['Buyer', 'Manager / Officer']) {
        expect(_read(roles[key]!), contains('Dismissible('), reason: key);
      }
      // The Farmer's swipe lives in the shared card now; it is still wired to delete.
      expect(_read(roles['Farmer']!), contains('onDelete: () => _delete(n.id)'));
      expect(_read('lib/presentation/widgets/notification_ui.dart'), contains('Dismissible('));
      expect(_read(roles['Buyer']!), contains('onClearAll: _clearAll'));
    });

    test('the Buyer still blocks changes while offline; the others queue them for Sync', () {
      final buyer = _read(roles['Buyer']!);
      expect(buyer, contains('queueWhenOffline: false'));
      expect(buyer, contains('_offlineBlocked()'));
    });
  });

  group('marking unread really changes the stored row', () {
    final repo = _read('lib/data/repositories/notification_repository.dart');

    test('one: is_read = false for this user\'s row', () {
      final a = repo.indexOf('Future<void> markAsUnreadOnline');
      final body = repo.substring(a, repo.indexOf('}\n\n', a));
      expect(body, contains(".from('notifications')"));
      expect(body, contains(".update({'is_read': false})"));
      expect(body, contains(".eq('id', notificationId)"));
      expect(body, contains(".eq('user_id', _userId)"));
    });

    test('all: only this user\'s read rows are set back to unread', () {
      final a = repo.indexOf('Future<void> markAllAsUnreadOnline');
      final body = repo.substring(a, repo.indexOf('}\n\n', a));
      expect(body, contains(".update({'is_read': false})"));
      expect(body, contains(".eq('user_id', _userId)"));
      expect(body, contains(".eq('is_read', true)"));
    });

    test('offline: queued like mark-as-read, and replayed on Sync', () {
      expect(repo, contains("kind: 'notification_unread'"));
      expect(repo, contains("kind: 'notification_unread_all'"));
      final replay = _read('lib/data/services/offline_action_replay.dart');
      expect(replay, contains("case 'notification_unread':"));
      expect(replay, contains('markAsUnreadOnline(p[\'id\'] as String)'));
      expect(replay, contains("case 'notification_unread_all':"));
      expect(replay, contains('markAllAsUnreadOnline()'));
    });

    test('the Sync card names these queued actions as notifications', () {
      final sync = _read('lib/presentation/widgets/sync_status_card.dart');
      expect(sync, contains("actionKind.startsWith('notification_')"));
    });
  });
}
