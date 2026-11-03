import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/constants/app_constants.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/utils/activity_throttle.dart';
import 'package:sagana/data/models/buyer_profile_model.dart';
import 'package:sagana/presentation/widgets/buyer_status_badge.dart';

import 'support/ignore_font_errors.dart';

final _now = DateTime(2026, 10, 26, 12);

BuyerProfileModel buyer({
  String status = 'active',
  DateTime? lastActive,
  int orders = 3,
}) {
  return BuyerProfileModel(
    userId: 'b1',
    fullName: 'Kei Amane',
    email: '',
    memberSince: DateTime(2026, 1, 1),
    totalOrders: orders,
    completedOrders: 2,
    totalSpent: 400,
    accountStatus: status,
    lastActiveAt: lastActive,
  );
}

Widget host(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: AppTheme.lightTheme,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: Center(child: child)),
);

String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('the 30-day inactivity rule', () {
    test('the threshold is 30 days, the same as Members', () {
      expect(BuyerProfileModel.inactiveAfter, const Duration(days: 30));
      expect(read('lib/data/models/farmer_member_model.dart'), contains('Duration(days: 30)'));
    });

    test('active up to and including exactly 30 days, inactive after', () {
      bool inactive(Duration ago) => buyer(lastActive: _now.subtract(ago)).isInactiveAt(_now);
      expect(inactive(Duration.zero), isFalse);
      expect(inactive(const Duration(days: 1)), isFalse);
      expect(inactive(const Duration(days: 29, hours: 23)), isFalse);
      expect(inactive(const Duration(days: 30)), isFalse);
      expect(inactive(const Duration(days: 30, minutes: 1)), isTrue);
      expect(inactive(const Duration(days: 31)), isTrue);
      expect(inactive(const Duration(days: 365)), isTrue);
    });

    test('a Buyer is only ever Active or Inactive', () {
      expect(BuyerStatus.values, [BuyerStatus.active, BuyerStatus.inactive]);
    });

    test('no recorded activity yet is treated as Active, as before', () {
      expect(buyer(lastActive: null).isInactiveAt(_now), isFalse);
      expect(buyerStatusOf(buyer(lastActive: null), now: _now), BuyerStatus.active);
    });

    test('status buckets: Active or Inactive, and every buyer is in exactly one', () {
      final buyers = [
        buyer(lastActive: _now.subtract(const Duration(days: 2))),
        buyer(lastActive: _now.subtract(const Duration(days: 45))),
        buyer(lastActive: _now),
        buyer(lastActive: null),
      ];
      final statuses = buyers.map((b) => buyerStatusOf(b, now: _now)).toList();
      expect(statuses, [BuyerStatus.active, BuyerStatus.inactive, BuyerStatus.active, BuyerStatus.active]);
    });

    test('the default isInactive uses the real clock with the same rule', () {
      expect(buyer(lastActive: DateTime.now().subtract(const Duration(days: 31))).isInactive, isTrue);
      expect(buyer(lastActive: DateTime.now().subtract(const Duration(days: 29))).isInactive, isFalse);
    });
  });

  group('recording activity (what the status is based on)', () {
    test('the first chance records, then at most once an hour', () {
      final t = ActivityThrottle();
      final start = DateTime(2026, 10, 26, 8);
      expect(t.shouldStamp(start), isTrue);
      t.markStamped(start);
      expect(t.shouldStamp(start.add(const Duration(minutes: 5))), isFalse);
      expect(t.shouldStamp(start.add(const Duration(minutes: 59))), isFalse);
      expect(t.shouldStamp(start.add(const Duration(hours: 1))), isTrue);
    });

    test('a sign-in always records', () {
      final t = ActivityThrottle()..markStamped(DateTime(2026, 10, 26, 8));
      expect(t.shouldStamp(DateTime(2026, 10, 26, 8, 1), force: true), isTrue);
    });

    test('a failed attempt (offline) is retried at the next chance', () {
      final t = ActivityThrottle();
      final start = DateTime(2026, 10, 26, 8);
      t.markStamped(start);
      t.markFailed();
      expect(t.shouldStamp(start.add(const Duration(minutes: 1))), isTrue);
    });

    test('someone who stays signed in for 40 days is recorded every day, so never goes Inactive', () {
      final t = ActivityThrottle();
      var day = DateTime(2026, 9, 1, 9);
      DateTime? lastRecorded;
      for (var i = 0; i < 40; i++) {
        // One app open per day, with no sign-in.
        if (t.shouldStamp(day)) {
          t.markStamped(day);
          lastRecorded = day;
        }
        day = day.add(const Duration(days: 1));
      }
      expect(lastRecorded, isNotNull);
      final b = buyer(lastActive: lastRecorded);
      expect(b.isInactiveAt(day), isFalse);
    });

    test('the app records on sign-in, on start with a saved session, and on resume', () {
      final auth = read('lib/data/services/auth_service.dart');
      expect(auth, contains('static void touchLastActive({bool force = false})'));
      expect(auth, contains('touchLastActive(force: true);'));
      expect(auth, contains("_client.rpc('touch_last_active')"));
      expect(auth, contains('if (!isLoggedIn) return;'));

      final main = read('lib/main.dart');
      // Start with a saved session...
      expect(main.indexOf('AuthService.touchLastActive();'), greaterThan(main.indexOf('if (AuthService.isLoggedIn) {')));
      // ...and return to the foreground.
      expect(main.split('AuthService.touchLastActive();').length - 1, 2);
      expect(main.indexOf('AuthService.touchLastActive();', main.indexOf('didChangeAppLifecycleState')), greaterThan(0));
    });
  });

  group('status wording', () {
    testWidgets('Tagalog has the inactivity note, and the removed lines are gone', (tester) async {
      await runIgnoringFontErrors(() async {
        late AppLocalizations tl;
        await tester.pumpWidget(host(Builder(builder: (c) {
          tl = AppLocalizations.of(c);
          return const SizedBox();
        }), locale: const Locale('tl')));
        expect(tl.buyerStatusInactiveNote, isNotEmpty);
        expect(tl.buyerStatusInactiveNote, isNot('No activity for over 30 days'));
      });
    });

    test('no "Active today" / "N orders" strings are left to show', () {
      final en = read('lib/core/l10n/app_en.arb');
      expect(en.contains('buyerLastActive'), isFalse);
      expect(en.contains('buyerMgmtOrdersCount'), isFalse);
      expect(read('lib/presentation/widgets/buyer_status_badge.dart').contains('buyerLastActiveLabel'), isFalse);
    });
  });

  group('status badge', () {
    testWidgets('shows the word and uses the Members colours', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(
            const Column(
              children: [
                BuyerStatusBadge(status: BuyerStatus.active),
                BuyerStatusBadge(status: BuyerStatus.inactive),
              ],
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Active'), findsOneWidget);
        expect(find.text('Inactive'), findsOneWidget);
        expect(find.text('Suspended'), findsNothing);
      });
    });

    testWidgets('Active green, Inactive grey', (tester) async {
      await runIgnoringFontErrors(() async {
        late ColorScheme cs;
        late Map<BuyerStatus, Color> colors;
        await tester.pumpWidget(
          host(Builder(builder: (c) {
            cs = Theme.of(c).colorScheme;
            colors = {for (final s in BuyerStatus.values) s: buyerStatusColor(c, s)};
            return const SizedBox();
          })),
        );
        expect(colors[BuyerStatus.active], AppConstants.successGreen);
        expect(colors[BuyerStatus.inactive], cs.outline);
        expect(colors.values.toSet().length, 2);
      });
    });

    test('the same colours as Members', () {
      final members = read('lib/presentation/screens/admin/farmer_management_screen.dart');
      final fn = members.substring(members.indexOf('Color _statusColor(MemberStatus'));
      expect(fn, contains('MemberStatus.active:\n      return AppConstants.successGreen'));
      expect(fn, contains('MemberStatus.inactive:\n      return cs.outline'));
      expect(fn, contains('MemberStatus.suspended:\n      return AppConstants.errorRed'));
    });
  });

  group('no contact details on the Manager\'s Buyer screens', () {
    const screens = [
      'lib/presentation/screens/admin/buyer_management_screen.dart',
      'lib/presentation/screens/admin/buyer_details_screen.dart',
    ];

    test('neither screen mentions e-mail or phone', () {
      for (final f in screens) {
        final src = read(f);
        for (final word in ['contactEmail', 'phoneNumber', 'emailAddress', 'adminProfilePhoneNumber', 'Icons.email', 'Icons.phone']) {
          expect(src.contains(word), isFalse, reason: '$f still uses $word');
        }
      }
    });

    test('the two Manager queries no longer read phone or e-mail (they stay stored)', () {
      final repo = read('lib/data/repositories/buyer_profile_repository.dart');
      final adminView = repo.substring(repo.indexOf('Future<BuyerProfileModel?> fetchAdminView'), repo.indexOf('Future<List<BuyerProfileModel>> fetchAllBuyers'));
      final allBuyers = repo.substring(repo.indexOf('Future<List<BuyerProfileModel>> fetchAllBuyers'), repo.indexOf('Future<int> fetchBuyerCount'));
      for (final part in [adminView, allBuyers]) {
        expect(part.contains("'phone_number'"), isFalse);
        expect(part.contains("contact_email"), isFalse);
        expect(part.contains('phone_number,'), isFalse);
      }
      // The Buyer's own profile still reads them.
      final own = repo.substring(0, repo.indexOf('Future<BuyerProfileModel?> fetchAdminView'));
      expect(own, contains('contact_email'));
    });

    test('search no longer matches a phone number, and the hint says so', () {
      expect(read(screens.first).contains('phoneNumber'), isFalse);
      final en = lookupAppLocalizations(const Locale('en'));
      expect(en.buyerMgmtSearchHint.toLowerCase().contains('phone'), isFalse);
    });

    test('nothing is deleted from the database by this change', () {
      for (final f in Directory('supabase_schema').listSync().whereType<File>()) {
        if (!f.path.contains('order_number') && !f.path.contains('buyer_status')) continue;
        expect(f.readAsStringSync().toLowerCase().contains('drop column'), isFalse, reason: f.path);
      }
    });
  });

  group('Buyers cannot be suspended', () {
    test('Buyer Management has no Suspended filter, suspend flow or toggle', () {
      final src = read('lib/presentation/screens/admin/buyer_management_screen.dart');
      expect(src, isNot(contains('_suspendOrReactivate')));
      expect(src, isNot(contains('promptSuspension')));
      expect(src, isNot(contains('setBuyerStatus')));
      expect(src, isNot(contains("'suspended'")));
      expect(src, isNot(contains('onToggleStatus')));
      expect(src, isNot(contains('farmerMgmtSuspendAccountAction')));
      expect(src, isNot(contains('buyerMgmtReactivateAccount')));
    });

    test('Buyer Details is read-only: no Suspend, Reactivate or Notify buttons', () {
      final src = read('lib/presentation/screens/admin/buyer_details_screen.dart');
      expect(src, isNot(contains('_suspendOrReactivate')));
      expect(src, isNot(contains('setBuyerStatus')));
      expect(src, isNot(contains('promptSuspension')));
    });

    test('Buyer Details still shows the buyer, the stats and the orders', () {
      final src = read('lib/presentation/screens/admin/buyer_details_screen.dart');
      expect(src, contains('BuyerIdentityCard('));
      expect(src, contains('_StatsRow('));
      expect(src, contains('_RecentOrdersSection('));
      expect(src, contains('AppRoutes.buyerOrderHistory'));
    });

    test('the Buyer Management three-dot menu keeps View Orders and Send Notification', () {
      final src = read('lib/presentation/screens/admin/buyer_management_screen.dart');
      expect(src, contains("case 'notify':"));
      expect(src, contains('l10n.farmerMgmtActionSendNotification'));
      expect(src, contains('onSendNotification'));
      expect(src, contains('onViewOrders'));
    });

    test('the repository has no suspend path for Buyers', () {
      final repo = read('lib/data/repositories/buyer_profile_repository.dart');
      expect(repo, isNot(contains("'suspend_member'")));
      expect(repo, isNot(contains("'reactivate_member'")));
      expect(repo, isNot(contains('setBuyerStatus')));
    });

    test('a suspended Buyer can no longer be blocked at login (farmers still can)', () {
      final auth = read('lib/data/services/auth_service.dart');
      expect(auth, contains("role == 'farmer' && memberStatus == 'suspended'"));
      expect(auth, isNot(contains("role == 'farmer' || role == 'buyer'")));
    });

    test('the database script keeps Farmer suspension and blocks Buyer suspension', () {
      final sql = read('supabase_schema/supabase_schema_buyer_suspension_removal.sql');
      expect(sql, contains("CHECK (NOT (role = 'buyer' AND status = 'suspended'))"));
      expect(sql, contains("WHERE role = 'buyer' AND status = 'suspended'"));
      expect(sql, isNot(contains('DROP FUNCTION')));
    });
  });
}
