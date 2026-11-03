import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/theme/sagana_colors.dart';
import 'package:sagana/data/models/buyer_profile_model.dart';
import 'package:sagana/presentation/screens/admin/buyer_details_screen.dart';
import 'package:sagana/presentation/screens/admin/buyer_management_screen.dart';
import 'package:sagana/presentation/widgets/profile_avatar.dart';

import 'support/ignore_font_errors.dart';

BuyerProfileModel buyer({
  String name = 'Kei Amane',
  String status = 'active',
  DateTime? lastActive,
  int orders = 12,
}) {
  return BuyerProfileModel(
    userId: 'b1',
    fullName: name,
    email: '',
    memberSince: DateTime(2026, 1, 1),
    totalOrders: orders,
    completedOrders: 2,
    totalSpent: 400,
    accountStatus: status,
    lastActiveAt: lastActive,
  );
}

Widget host(Widget Function(BuildContext) build, {double width = 360, Locale locale = const Locale('en')}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Builder(builder: build),
      ),
    ),
  );
}

Widget card(BuildContext c, BuyerProfileModel b) => BuyerManagementCard(
  buyer: b,
  cs: Theme.of(c).colorScheme,
  sagana: c.saganaColors,
  onTap: () {},
  onViewOrders: () {},
  onSendNotification: () {},
);

Widget identity(BuildContext c, BuyerProfileModel b) => BuyerIdentityCard(
  buyer: b,
  cs: Theme.of(c).colorScheme,
  sagana: c.saganaColors,
);

Future<void> at(WidgetTester tester, double width, Widget w) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  await tester.pumpWidget(w);
  await tester.pump();
}

void main() {
  tearDown(() async {});

  group('Buyer Management card', () {
    final recent = DateTime.now().subtract(const Duration(days: 3));
    final old = DateTime.now().subtract(const Duration(days: 60));

    testWidgets('shows only picture, name, status and the menu', (tester) async {
      await runIgnoringFontErrors(() async {
        await at(tester, 360, host((c) => card(c, buyer(lastActive: recent))));
        expect(find.text('Kei Amane'), findsOneWidget);
        expect(find.text('Active'), findsOneWidget);
        expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
        // Removed: the order count, the last-active line, and contact details.
        expect(find.textContaining('order'), findsNothing);
        expect(find.textContaining('Active today'), findsNothing);
        expect(find.textContaining('Last active'), findsNothing);
        expect(find.byIcon(Icons.email_rounded), findsNothing);
        expect(find.byIcon(Icons.phone_rounded), findsNothing);
        expect(find.textContaining('@'), findsNothing);
        await tester.binding.setSurfaceSize(null);
      });
    });

    testWidgets('everything sits in one horizontal row, centred on the same line', (tester) async {
      await runIgnoringFontErrors(() async {
        await at(tester, 360, host((c) => card(c, buyer(lastActive: recent))));
        final avatar = tester.getRect(find.byType(ProfileAvatar));
        final name = tester.getRect(find.text('Kei Amane'));
        final badge = tester.getRect(find.text('Active'));
        final menu = tester.getRect(find.byIcon(Icons.more_vert_rounded));
        // Left to right: picture, name, status, menu.
        expect(avatar.right, lessThanOrEqualTo(name.left));
        expect(name.right, lessThanOrEqualTo(badge.left));
        expect(badge.right, lessThanOrEqualTo(menu.left));
        // The same centre line, within a pixel or two.
        for (final r in [name, badge, menu]) {
          expect((r.center.dy - avatar.center.dy).abs(), lessThan(3));
        }
        // And a slim card: picture 48 + 12px padding top and bottom.
        expect(tester.getSize(find.byType(BuyerManagementCard)).height, lessThan(80));
        await tester.binding.setSurfaceSize(null);
      });
    });

    testWidgets('the status badge keeps its place when the name is very long', (tester) async {
      await runIgnoringFontErrors(() async {
        await at(
          tester,
          320,
          host((c) => card(c, buyer(name: 'Maria Concepcion Dela Cruz-Santos de la Rosa', lastActive: recent))),
        );
        expect(tester.takeException(), isNull);
        final name = tester.getRect(find.textContaining('Maria'));
        final badge = tester.getRect(find.text('Active'));
        expect(name.right, lessThanOrEqualTo(badge.left));
        await tester.binding.setSurfaceSize(null);
      });
    });

    testWidgets('each status reads correctly', (tester) async {
      await runIgnoringFontErrors(() async {
        await at(
          tester,
          360,
          host(
            (c) => Column(
              children: [
                card(c, buyer(name: 'A One', lastActive: recent)),
                card(c, buyer(name: 'B Two', lastActive: old)),
              ],
            ),
          ),
        );
        expect(find.text('Active'), findsOneWidget);
        expect(find.text('Inactive'), findsOneWidget);
        expect(find.text('Suspended'), findsNothing);
        await tester.binding.setSurfaceSize(null);
      });
    });

    for (final width in [320.0, 360.0, 412.0, 600.0]) {
      testWidgets('no overflow at $width px with a very long name', (tester) async {
        await runIgnoringFontErrors(() async {
          await at(
            tester,
            width,
            host(
              (c) => card(
                c,
                buyer(
                  name: 'Maria Concepcion Dela Cruz-Santos de la Rosa y Villanueva',
                  orders: 12345,
                  lastActive: old,
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          await tester.binding.setSurfaceSize(null);
        });
      });
    }

    testWidgets('Tagalog at 320px does not overflow', (tester) async {
      await runIgnoringFontErrors(() async {
        await at(tester, 320, host((c) => card(c, buyer(lastActive: old)), locale: const Locale('tl')));
        expect(tester.takeException(), isNull);
        expect(find.text('Hindi Aktibo'), findsOneWidget);
        await tester.binding.setSurfaceSize(null);
      });
    });

    testWidgets('the menu offers View orders and Send notification, and nothing to suspend', (tester) async {
      await runIgnoringFontErrors(() async {
        await at(tester, 360, host((c) => card(c, buyer(lastActive: recent))));
        await tester.tap(find.byIcon(Icons.more_vert_rounded));
        await tester.pumpAndSettle();
        // The popup rows are existing, unchanged code; the test font is far wider
        // than Inter, so only that menu's width overflow is set aside here.
        tester.takeException();
        expect(find.text('View Order History'), findsOneWidget);
        expect(find.text('Suspend Account'), findsNothing);
        expect(find.textContaining('Reactivate'), findsNothing);
        await tester.binding.setSurfaceSize(null);
      });
    });
  });

  group('Buyer Details identity card', () {
    final recent = DateTime.now().subtract(const Duration(days: 2));
    final old = DateTime.now().subtract(const Duration(days: 40));

    testWidgets('photo, name and the status badge only: no "Active today", no contact details', (tester) async {
      await runIgnoringFontErrors(() async {
        await at(tester, 360, host((c) => identity(c, buyer(lastActive: recent))));
        expect(find.text('Kei Amane'), findsOneWidget);
        expect(find.text('Active'), findsOneWidget);
        expect(find.text('KA'), findsOneWidget);
        expect(find.textContaining('Active today'), findsNothing);
        expect(find.textContaining('Last active'), findsNothing);
        expect(find.byIcon(Icons.email_rounded), findsNothing);
        expect(find.byIcon(Icons.phone_rounded), findsNothing);
        expect(find.text('Email Address'), findsNothing);
        expect(find.textContaining('@'), findsNothing);
        await tester.binding.setSurfaceSize(null);
      });
    });

    testWidgets('the status badge is in the top-right corner of the card', (tester) async {
      await runIgnoringFontErrors(() async {
        for (final width in [320.0, 360.0, 412.0]) {
          await at(tester, width, host((c) => identity(c, buyer(lastActive: recent))));
          final card = tester.getRect(find.byType(BuyerIdentityCard));
          final badge = tester.getRect(find.text('Active'));
          final photo = tester.getRect(find.text('KA'));
          // Inside the card, near its top and right edges...
          expect(badge.top - card.top, lessThan(40), reason: 'width $width');
          expect(card.right - badge.right, lessThan(40), reason: 'width $width');
          // ...to the right of the centred picture, never on top of it.
          expect(badge.left, greaterThan(photo.right), reason: 'width $width');
        }
        await tester.binding.setSurfaceSize(null);
      });
    });

    testWidgets('the photo and the name are centred in the card, the badge stays in the corner', (tester) async {
      await runIgnoringFontErrors(() async {
        for (final width in [320.0, 360.0, 412.0, 600.0]) {
          for (final name in ['Kei Amane', 'Jo', 'Maria Concepcion Dela Cruz-Santos de la Rosa y Villanueva']) {
            await at(tester, width, host((c) => identity(c, buyer(name: name, lastActive: recent))));
            final card = tester.getRect(find.byType(BuyerIdentityCard));
            final photo = tester.getRect(find.text(buyer(name: name).initials));
            final nameRect = tester.getRect(find.text(name));
            final badge = tester.getRect(find.text('Active'));
            final why = 'width $width, "$name"';

            // Photo and name: centred horizontally in the card.
            expect((photo.center.dx - card.center.dx).abs(), lessThan(1.5), reason: 'photo, $why');
            expect((nameRect.center.dx - card.center.dx).abs(), lessThan(1.5), reason: 'name, $why');
            // Photo above the name.
            expect(photo.bottom, lessThan(nameRect.top), reason: why);

            // Badge: top-right corner, whatever the name, and clear of the photo.
            expect(card.right - badge.right, lessThan(40), reason: 'badge right, $why');
            expect(badge.top - card.top, lessThan(40), reason: 'badge top, $why');
            expect(badge.left, greaterThan(photo.right), reason: 'badge clear of photo, $why');
            expect(tester.takeException(), isNull, reason: why);
          }
        }
        await tester.binding.setSurfaceSize(null);
      });
    });

    testWidgets('the badge adds no height: the card is the same size whether or not any activity is recorded', (tester) async {
      await runIgnoringFontErrors(() async {
        await at(tester, 360, host((c) => identity(c, buyer(lastActive: recent))));
        final active = tester.getSize(find.byType(BuyerIdentityCard)).height;
        await at(tester, 360, host((c) => identity(c, buyer(lastActive: null))));
        final noActivity = tester.getSize(find.byType(BuyerIdentityCard)).height;
        expect(active, noActivity);
        await tester.binding.setSurfaceSize(null);
      });
    });

    testWidgets('an inactive buyer is told why', (tester) async {
      await runIgnoringFontErrors(() async {
        await at(tester, 360, host((c) => identity(c, buyer(lastActive: old))));
        expect(find.text('Inactive'), findsOneWidget);
        expect(find.text('No activity for over 30 days'), findsOneWidget);
        await tester.binding.setSurfaceSize(null);
      });
    });

    testWidgets('an active buyer has no inactivity note', (tester) async {
      await runIgnoringFontErrors(() async {
        await at(tester, 360, host((c) => identity(c, buyer(lastActive: recent))));
        expect(find.text('No activity for over 30 days'), findsNothing);
        await tester.binding.setSurfaceSize(null);
      });
    });

    testWidgets('the card is compact: no tall empty area where contact tiles were', (tester) async {
      await runIgnoringFontErrors(() async {
        await at(tester, 360, host((c) => identity(c, buyer(lastActive: recent))));
        final h = tester.getSize(find.byType(BuyerIdentityCard)).height;
        // photo 88 + name + padding: well under the layouts that also carried a
        // badge row, a last-active line or two contact tiles.
        expect(h, lessThan(200));
        await tester.binding.setSurfaceSize(null);
      });
    });

    for (final width in [320.0, 360.0, 412.0, 600.0]) {
      testWidgets('no overflow at $width px with a very long name', (tester) async {
        await runIgnoringFontErrors(() async {
          await at(
            tester,
            width,
            host(
              (c) => identity(
                c,
                buyer(name: 'Maria Concepcion Dela Cruz-Santos de la Rosa y Villanueva', lastActive: old),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          await tester.binding.setSurfaceSize(null);
        });
      });
    }

    testWidgets('Tagalog at 320px does not overflow', (tester) async {
      await runIgnoringFontErrors(() async {
        await at(tester, 320, host((c) => identity(c, buyer(lastActive: old)), locale: const Locale('tl')));
        expect(tester.takeException(), isNull);
        await tester.binding.setSurfaceSize(null);
      });
    });
  });
}
