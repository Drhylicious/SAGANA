import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/presentation/screens/admin/farmer_management_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

/// The Members list tags an applicant an Officer created ("Created by ..."), so
/// the Manager can tell it from a Farmer who registered on their own. In its own
/// file because the Members screen writes the offline cache (real file IO), and
/// that must not share a process with the other widget tests that do the same.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_members_source');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    await HiveService.init();
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-key',
      httpClient: fake,
    );
  });

  setUp(fake.reset);

  Map<String, Object?> role(String id, String status) => {
    'user_id': id, 'status': status, 'created_at': '2026-11-01T01:00:00Z',
    'application_attempts': 1,
    'rejection_reason': status == 'rejected' ? 'Incomplete' : null,
    'suspension_reason': null,
  };

  testWidgets('an Officer-created applicant says who created it; a self-registered one has no tag',
      (t) => runIgnoringFontErrors(() async {
    await t.runAsync(
      () => HiveService.saveUserSession(userId: 'u-admin', email: 'x@y.z', role: 'admin'),
    );
    fake.on('GET /rest/v1/user_roles', (r) => r.url.queryParameters['role'] == 'eq.farmer'
        ? [role('p1', 'pending'), role('p2', 'pending'), role('r1', 'rejected')]
        : <Object?>[]);
    fake.on('GET /rest/v1/user_information', (_) => [
      for (final id in ['p1', 'p2', 'r1'])
        {'user_id': id, 'full_name': 'Name $id', 'profile_photo_url': null,
         'last_active_at': null, 'contact_email': null, 'phone_number': null},
    ]);
    fake.on('GET /rest/v1/farmer_profiles', (_) => [
      for (final id in ['p1', 'p2', 'r1']) {'user_id': id, 'is_verified': false},
    ]);
    fake.on('GET /rest/v1/account_creation_sources', (_) => [
      {'user_id': 'p1', 'requested_by_name': 'Olivia One', 'requested_at': '2026-11-02T01:00:00Z'},
      {'user_id': 'r1', 'requested_by_name': 'Omar Two', 'requested_at': '2026-11-02T02:00:00Z'},
    ]);

    t.view.physicalSize = const Size(420, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
      GoRoute(path: '/screen', builder: (_, __) => const FarmerManagementScreen()),
    ]);
    await t.pumpWidget(MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ));
    await t.pump();
    router.push('/screen');
    await t.pump();
    for (var i = 0; i < 30 && find.byIcon(Icons.more_vert_rounded).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 150))); // the cache write is real file IO
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pump(const Duration(milliseconds: 700));
    t.takeException(); // test-font overflow only

    expect(find.text('Created by Olivia One'), findsOneWidget);
    expect(find.text('Created by Omar Two'), findsOneWidget, reason: 'a disapproved one keeps its source');
    expect(find.textContaining('Created by'), findsNWidgets(2), reason: 'the self-registered one has no tag');
    expect(find.text('Name p2'), findsOneWidget);
  }));
}
