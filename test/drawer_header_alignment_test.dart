import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/presentation/widgets/app_navigation_drawer.dart';
import 'package:sagana/presentation/widgets/profile_avatar.dart';

import 'support/ignore_font_errors.dart';

/// The Navigation Drawer's profile header: the photo, and the name / email / phone
/// group centred beside it. A missing line takes no space.

Future<void> _openDrawer(
  WidgetTester tester, {
  String name = 'Ichika Nakano',
  String? email,
  String? phone,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey<ScaffoldState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        key: key,
        drawer: AppNavigationDrawer(
          photoUrl: null,
          displayName: name,
          contactEmail: email,
          phoneNumber: phone,
          onEditProfile: () {},
          onSignOut: () {},
          onAboutSagana: () {},
          onAboutOrganization: () {},
          onPrivacyPolicy: () {},
          onTermsOfUse: () {},
        ),
        body: const SizedBox.expand(),
      ),
    ),
  );
  key.currentState!.openDrawer();
  await tester.pumpAndSettle();
}

Rect _group(WidgetTester t) => t.getRect(find.byKey(const ValueKey('drawer-profile-info')));
Rect _avatar(WidgetTester t) => t.getRect(find.byType(ProfileAvatar));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('name only: the name is centred on the photo', (tester) async {
    await runIgnoringFontErrors(() async {
      await _openDrawer(tester);
      final name = tester.getRect(find.byKey(const ValueKey('drawer-profile-name')));
      expect((name.center.dy - _avatar(tester).center.dy).abs(), lessThan(1));
      // Nothing is kept for an email or phone that does not exist: the group is
      // exactly the name.
      expect((_group(tester).height - name.height).abs(), lessThan(0.5));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('name and email: the two are centred together on the photo', (tester) async {
    await runIgnoringFontErrors(() async {
      await _openDrawer(tester, email: 'ichika@gmail.com');
      expect((_group(tester).center.dy - _avatar(tester).center.dy).abs(), lessThan(1));
      expect(find.text('ichika@gmail.com'), findsOneWidget);
      // The name is above the email, and the group is taller than a lone name.
      final name = tester.getRect(find.byKey(const ValueKey('drawer-profile-name')));
      final email = tester.getRect(find.text('ichika@gmail.com'));
      expect(name.bottom, lessThanOrEqualTo(email.top));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('name, email and phone: all three are centred together on the photo', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await _openDrawer(tester, email: 'ichika@gmail.com', phone: '09171234567');
      expect((_group(tester).center.dy - _avatar(tester).center.dy).abs(), lessThan(1));
      final name = tester.getRect(find.byKey(const ValueKey('drawer-profile-name')));
      final email = tester.getRect(find.text('ichika@gmail.com'));
      final phone = tester.getRect(find.text('09171234567'));
      expect(name.bottom, lessThanOrEqualTo(email.top));
      expect(email.bottom, lessThanOrEqualTo(phone.top));
      // Even, compact spacing between the three.
      expect(((email.top - name.bottom) - (phone.top - email.bottom)).abs(), lessThan(4));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('phone only: the name and phone are centred together', (tester) async {
    await runIgnoringFontErrors(() async {
      await _openDrawer(tester, phone: '09171234567');
      expect((_group(tester).center.dy - _avatar(tester).center.dy).abs(), lessThan(1));
    });
  });

  testWidgets('blank email/phone count as missing and take no space', (tester) async {
    await runIgnoringFontErrors(() async {
      await _openDrawer(tester, email: '   ', phone: '');
      final name = tester.getRect(find.byKey(const ValueKey('drawer-profile-name')));
      expect((_group(tester).height - name.height).abs(), lessThan(0.5));
      expect((name.center.dy - _avatar(tester).center.dy).abs(), lessThan(1));
    });
  });

  testWidgets('the group stays beside the photo and inside the drawer on a narrow phone', (
    tester,
  ) async {
    await runIgnoringFontErrors(() async {
      await _openDrawer(
        tester,
        name: 'Maria Concepcion Alessandra Dela Cruz',
        email: 'maria.concepcion.alessandra@example-domain.com',
        phone: '09171234567',
        width: 320,
      );
      final group = _group(tester);
      expect(group.left, greaterThan(_avatar(tester).right));
      expect(group.right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    });
  });

  test('the rest of the header is unchanged: photo ring, spacing and text styles', () {
    final src = File('lib/presentation/widgets/app_navigation_drawer.dart').readAsStringSync();
    expect(src, contains('radius: 26'));
    expect(src, contains('const SizedBox(width: 10)'));
    expect(src, contains('const SizedBox(height: 3)'));
    expect(src, contains('crossAxisAlignment: CrossAxisAlignment.center'));
    expect(src, contains('mainAxisSize: MainAxisSize.min'));
  });
}
