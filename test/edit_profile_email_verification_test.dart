import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/admin_profile_model.dart';
import 'package:sagana/data/models/buyer_profile_model.dart';
import 'package:sagana/data/models/farmer_profile_model.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/presentation/screens/admin/admin_edit_profile_screen.dart';
import 'package:sagana/presentation/screens/buyer/buyer_edit_profile_screen.dart';
import 'package:sagana/presentation/screens/farmer/farmer_edit_profile_screen.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

/// The Verified / Unverified line in Edit Profile for all four roles.

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: screen,
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

FarmerProfileModel _farmer({String? contact, String? verified}) => FarmerProfileModel(
  userId: 'u1',
  fullName: 'Ana Reyes',
  surname: 'Reyes',
  firstName: 'Ana',
  email: 'ana1@sagana.local',
  contactEmail: contact,
  verifiedContactEmail: verified,
  capitalShares: 0,
  isVerified: true,
  primaryCrops: const [],
);

BuyerProfileModel _buyer({String? contact, String? verified}) => BuyerProfileModel(
  userId: 'u1',
  fullName: 'Ben Cruz',
  surname: 'Cruz',
  firstName: 'Ben',
  email: 'ben1@sagana.local',
  contactEmail: contact,
  verifiedContactEmail: verified,
  memberSince: DateTime(2026, 1, 1),
  totalOrders: 0,
  completedOrders: 0,
  totalSpent: 0,
);

AdminProfileModel _manager({String? verified}) => AdminProfileModel(
  userId: 'u1',
  email: 'manager@coop.ph',
  fullName: 'Rosa Dela Cruz',
  surname: 'Dela Cruz',
  firstName: 'Rosa',
  verifiedContactEmail: verified,
);

AdminProfileModel _officer({String? contact, String? verified}) => AdminProfileModel(
  userId: 'u1',
  email: 'OFF-0001@sagana.local',
  fullName: 'Omar Santos',
  surname: 'Santos',
  firstName: 'Omar',
  contactEmail: contact,
  verifiedContactEmail: verified,
);

Finder _unverified() => find.byKey(const ValueKey('email-status-unverified'));
Finder _verified() => find.byKey(const ValueKey('email-status-verified'));
Finder _action() => find.byKey(const ValueKey('verify-email-action'));

Future<void> _setRole(String role) => HiveService.saveUserSession(
  userId: 'u1',
  email: 'x@y.z',
  role: role,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockStorageChannels();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final dir = Directory.systemTemp.createTempSync('sagana_edit_profile_email');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
    await HiveService.init();
    await Supabase.initialize(url: 'http://localhost:54321', publishableKey: 'test-key');
  });

  group('Farmer', () {
    testWidgets('an email nobody has verified: Unverified + Verify Email', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, FarmerEditProfileScreen(initialProfile: _farmer(contact: 'ana@gmail.com')));
        expect(_unverified(), findsOneWidget);
        expect(find.text('Verify Email'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a verified email: Verified, no action', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          FarmerEditProfileScreen(initialProfile: _farmer(contact: 'ana@gmail.com', verified: 'ana@gmail.com')),
        );
        expect(_verified(), findsOneWidget);
        expect(_action(), findsNothing);
      });
    });

    testWidgets('the saved email differs from the verified one: Unverified again', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          FarmerEditProfileScreen(initialProfile: _farmer(contact: 'new@gmail.com', verified: 'old@gmail.com')),
        );
        expect(_unverified(), findsOneWidget);
        expect(_action(), findsOneWidget);
      });
    });

    testWidgets('no email: no status line at all (email stays optional)', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, FarmerEditProfileScreen(initialProfile: _farmer()));
        expect(_unverified(), findsNothing);
        expect(_verified(), findsNothing);
        expect(_action(), findsNothing);
      });
    });
  });

  group('Buyer', () {
    testWidgets('unverified', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, BuyerEditProfileScreen(initialProfile: _buyer(contact: 'ben@gmail.com')));
        expect(_unverified(), findsOneWidget);
        expect(find.text('Verify Email'), findsOneWidget);
      });
    });

    testWidgets('verified', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          BuyerEditProfileScreen(initialProfile: _buyer(contact: 'ben@gmail.com', verified: 'BEN@gmail.com')),
        );
        expect(_verified(), findsOneWidget);
        expect(_action(), findsNothing);
      });
    });

    testWidgets('no email: nothing shown', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, BuyerEditProfileScreen(initialProfile: _buyer()));
        expect(_unverified(), findsNothing);
        expect(_action(), findsNothing);
      });
    });
  });

  group('Manager (the email is the sign-in address: locked)', () {
    setUp(() => _setRole('admin'));

    testWidgets('unverified: locked field, Unverified, Verify Email', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, AdminEditProfileScreen(initialProfile: _manager()));
        expect(find.text('manager@coop.ph'), findsOneWidget);
        // The email can be edited now (a change goes through verification).
        expect(find.text('Email address cannot be changed.'), findsNothing);
        final field = tester.widget<TextField>(
          find.descendant(of: find.widgetWithText(TextFormField, 'manager@coop.ph').first, matching: find.byType(TextField)).first,
        );
        expect(field.enabled, isTrue);
        expect(_unverified(), findsOneWidget);
        expect(find.text('Verify Email'), findsOneWidget);
      });
    });

    testWidgets('verified', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, AdminEditProfileScreen(initialProfile: _manager(verified: 'manager@coop.ph')));
        expect(_verified(), findsOneWidget);
        expect(_action(), findsNothing);
      });
    });
  });

  group('Officer (sign-in is a generated username; the contact email is separate)', () {
    setUp(() => _setRole('officer'));

    testWidgets('shows the contact email, never the generated sign-in address, and it is editable', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, AdminEditProfileScreen(initialProfile: _officer(contact: 'omar@gmail.com')));
        expect(find.text('omar@gmail.com'), findsOneWidget);
        expect(find.textContaining('sagana.local'), findsNothing);
        expect(find.text('Email address cannot be changed.'), findsNothing);
        expect(_unverified(), findsOneWidget);
        expect(find.text('Verify Email'), findsOneWidget);
      });
    });

    testWidgets('verified', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(
          tester,
          AdminEditProfileScreen(initialProfile: _officer(contact: 'omar@gmail.com', verified: 'omar@gmail.com')),
        );
        expect(_verified(), findsOneWidget);
      });
    });

    testWidgets('no contact email: empty field, no status (optional)', (tester) async {
      await runIgnoringFontErrors(() async {
        await _pump(tester, AdminEditProfileScreen(initialProfile: _officer()));
        expect(_unverified(), findsNothing);
        expect(find.textContaining('sagana.local'), findsNothing);
      });
    });
  });
}
