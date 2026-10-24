import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/data/repositories/account_management_repository.dart';
import 'package:sagana/presentation/widgets/account_card.dart';

Widget _host(Widget child, {double width = 360, String locale = 'en'}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(locale),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: SingleChildScrollView(child: child)),
        ),
      ),
    );

AccountEntry _account({
  String name = 'John Harvey',
  String role = 'farmer',
  String status = 'active',
  String? email,
  String? phone,
  DateTime? lastActiveAt,
}) => AccountEntry(
  userId: 'u1',
  name: name,
  username: 'harvey02',
  role: role,
  status: status,
  email: email,
  phone: phone,
  lastActiveAt: lastActiveAt,
);

void main() {
  testWidgets('shows name, status, e-mail and phone on separate lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AccountCard(
          account: _account(email: 'john@example.com', phone: '09171234567'),
          onTap: () {},
        ),
      ),
    );

    expect(find.text('John Harvey'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('APPROVED'), findsNothing);
    expect(find.text('john@example.com'), findsOneWidget);
    expect(find.text('09171234567'), findsOneWidget);
    expect(find.text('Not set'), findsNothing);
    // No photo: the initials stand in for the picture.
    expect(find.text('JH'), findsOneWidget);

    // E-mail above phone, each on its own line.
    final email = tester.getTopLeft(find.text('john@example.com')).dy;
    final phone = tester.getTopLeft(find.text('09171234567')).dy;
    expect(phone, greaterThan(email));
  });

  testWidgets('a missing e-mail or phone reads "Not set"', (tester) async {
    await tester.pumpWidget(
      _host(AccountCard(account: _account(), onTap: () {})),
    );
    expect(find.text('Not set'), findsNWidgets(2));
  });

  testWidgets('a blank e-mail or phone also reads "Not set"', (tester) async {
    await tester.pumpWidget(
      _host(
        AccountCard(account: _account(email: '   ', phone: ''), onTap: () {}),
      ),
    );
    expect(find.text('Not set'), findsNWidgets(2));
  });

  testWidgets('the badge follows the stored status and the last activity', (
    tester,
  ) async {
    final now = DateTime.now();
    Future<void> badge(AccountEntry a, String expected, {String? reason}) async {
      await tester.pumpWidget(_host(AccountCard(account: a, onTap: () {})));
      expect(find.text(expected), findsOneWidget, reason: reason);
    }

    // Stored 'active', recently active (or never signed in): ACTIVE.
    await badge(_account(lastActiveAt: now.subtract(const Duration(days: 2))),
        'ACTIVE', reason: 'active 2 days ago');
    await badge(_account(), 'ACTIVE', reason: 'never signed in stays Active');
    await badge(_account(role: 'officer', lastActiveAt: now), 'ACTIVE',
        reason: 'officer active now');
    // Stored 'active' but no activity for more than 30 days: INACTIVE.
    await badge(
        _account(lastActiveAt: now.subtract(const Duration(days: 35))),
        'INACTIVE', reason: 'farmer last active 35 days ago');
    await badge(
        _account(role: 'officer', lastActiveAt: now.subtract(const Duration(days: 35))),
        'INACTIVE', reason: 'officer last active 35 days ago');
    // Exactly the edge: 29 days is still Active.
    await badge(
        _account(lastActiveAt: now.subtract(const Duration(days: 29))),
        'ACTIVE', reason: '29 days is within the 30-day window');
    // Suspended wins over everything, even a long absence.
    await badge(_account(status: 'suspended'), 'SUSPENDED');
    await badge(
        _account(role: 'officer', status: 'suspended',
            lastActiveAt: now.subtract(const Duration(days: 90))),
        'SUSPENDED', reason: 'suspended is never shown as Inactive');
  });

  testWidgets('long names and addresses wrap instead of being cut off', (
    tester,
  ) async {
    const longEmail = 'a.very.long.email.address.for.testing@some-long-domain-name.example.com';
    const longName = 'Maria Cristina Dela Cruz-Santos de la Fuente Alvarez';
    await tester.pumpWidget(
      _host(
        AccountCard(
          account: _account(name: longName, email: longEmail, phone: '09171234567'),
          onTap: () {},
        ),
        width: 260,
      ),
    );

    expect(tester.takeException(), isNull, reason: 'no overflow at 260 px wide');
    expect(find.text(longName), findsOneWidget);
    expect(find.text(longEmail), findsOneWidget);
    // Wrapped, not clipped: the text is allowed more than one line.
    final text = tester.widget<Text>(find.text(longEmail));
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('tapping the card calls onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(AccountCard(account: _account(), onTap: () => taps++)),
    );
    await tester.tap(find.text('John Harvey'));
    expect(taps, 1);
  });

  testWidgets('Tagalog labels are used when the language is Tagalog', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AccountCard(account: _account(), onTap: () {}),
        locale: 'tl',
      ),
    );
    expect(find.text('AKTIBO'), findsOneWidget);
    expect(find.text('Wala pa'), findsNWidgets(2));
  });
}
