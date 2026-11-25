import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/l10n/app_localizations_en.dart';
import 'package:sagana/core/l10n/app_localizations_tl.dart';
import 'package:sagana/core/l10n/system_notification_text.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/activity_text.dart';
import 'package:sagana/data/models/admin_legacy_generated.dart';
import 'package:sagana/data/models/admin_log_message.dart';
import 'package:sagana/data/models/farmer_member_model.dart';
import 'package:sagana/data/models/farmer_profile_model.dart';
import 'package:sagana/data/models/inventory_batch_model.dart';
import 'package:sagana/data/models/marketplace_listing_model.dart';
import 'package:sagana/data/models/member_restriction.dart';
import 'package:sagana/data/models/shelf_life_model.dart';
import 'package:sagana/data/repositories/farmer_management_repository.dart';
import 'package:sagana/data/services/active_session_watcher.dart';
import 'package:sagana/data/services/app_event_service.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/presentation/widgets/member_profile_cards.dart';
import 'package:sagana/presentation/widgets/recent_activity_widgets.dart';
import 'package:sagana/presentation/widgets/restriction_dialogs.dart';

import 'support/ignore_font_errors.dart';

Widget _wrapWithL10n(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

FarmerMemberModel _member({
  required String id,
  required String name,
  required MemberStatus status,
  DateTime? joinedAt,
  double capital = 0,
}) {
  return FarmerMemberModel(
    userId: id,
    fullName: name,
    memberStatus: status,
    isVerified: status == MemberStatus.active || status == MemberStatus.inactive,
    primaryCrops: const ['Rice'],
    outstandingLoanBalance: 0,
    capitalContribution: capital,
    loanStatus: LoanStatusSummary.none,
    isSynced: true,
    joinedAt: joinedAt,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('sagana_8items_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => hiveDir.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
    await HiveService.init();
  });

  tearDownAll(() async {
    try {
      if (hiveDir.existsSync()) {
        hiveDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Best-effort cleanup on Windows while Hive handles settle.
    }
  });

  group('Item 1: Shelf-Life rotten sync, stock guards & SQL contracts', () {
    test('ListingShelfLife parses rotten_at and rotten_kg', () {
      final sl = ListingShelfLife.fromEmbed({
        'unavailable': true,
        'rotten_at': '2026-11-20T08:00:00Z',
        'rotten_kg': 12.5,
      });
      expect(sl, isNotNull);
      expect(sl!.isRotten, isTrue);
      expect(sl.rottenKg, 12.5);
    });

    test(
      'MarketplaceListingModel treats remainingKg <= 0 as not discounted and detects rotten',
      () {
        final zeroRemaining = MarketplaceListingModel.fromMap({
          'id': 'l1',
          'farmer_id': 'f1',
          'crop_name': 'Tomato',
          'price_per_kg': 50,
          'volume_kg': 20,
          'remaining_kg': 0,
          'unit': 'kg',
          'status': 'withdrawn',
          'created_at': '2026-11-18T00:00:00Z',
          'listing_shelf_life': {
            'unavailable': true,
            'discount_applied_on': '2026-11-19',
            'discount_percent': 25,
            'rotten_at': '2026-11-20T08:00:00Z',
            'rotten_kg': 20,
          },
        });
        expect(zeroRemaining.isShelfDiscounted, isFalse);
        expect(zeroRemaining.isShelfRotten, isTrue);
        expect(zeroRemaining.isUnavailableDueToRotten, isTrue);
      },
    );

    test(
      'InventoryBatchModel tracks isFinalizedRotten and hasCheckableStock',
      () {
        final finalized = InventoryBatchModel.fromMap({
          'id': 'b1',
          'farmer_id': 'f1',
          'harvest_record_id': 'h1',
          'crop_id': 'c1',
          'crop_name': 'Tomato',
          'batch_number': 'B-001',
          'quantity_kg': 10,
          'available_kg': 0,
          'reserved_kg': 0,
          'sold_kg': 0,
          'adjusted_kg': 10,
          'status': 'lost',
          'created_at': '2026-11-18T00:00:00Z',
          'batch_shelf_life': {'spoiled_kg': 10},
        });
        expect(finalized.isFinalizedRotten, isTrue);
        expect(finalized.hasCheckableStock, isFalse);

        final openWithReserved = InventoryBatchModel.fromMap({
          'id': 'b2',
          'farmer_id': 'f1',
          'harvest_record_id': 'h2',
          'crop_id': 'c1',
          'crop_name': 'Tomato',
          'batch_number': 'B-002',
          'quantity_kg': 10,
          'available_kg': 6,
          'reserved_kg': 2,
          'sold_kg': 2,
          'adjusted_kg': 0,
          'status': 'available',
          'created_at': '2026-11-18T00:00:00Z',
        });
        expect(openWithReserved.isFinalizedRotten, isFalse);
        expect(openWithReserved.hasCheckableStock, isTrue);
      },
    );

    test(
      'EN/TL localization + notification formatter include new shelf-life keys',
      () {
        final en = AppLocalizationsEn();
        final tl = AppLocalizationsTl();
        expect(en.shelfTagRottenLost, isNotEmpty);
        expect(tl.shelfTagRottenLost, isNotEmpty);
        expect(en.shelfInspectInInventory, isNotEmpty);
        expect(tl.shelfInspectInInventory, isNotEmpty);
        expect(en.shelfDisposalExpiredError, isNotEmpty);
        expect(tl.shelfDisposalExpiredError, isNotEmpty);
        expect(
          localizedNotificationTitle(
            en,
            'Order Cancelled — Produce Unavailable',
          ),
          en.snOrderCancelledProduceUnavailable,
        );
        expect(
          localizedNotificationTitle(
            tl,
            'Order Cancelled — Produce Unavailable',
          ),
          tl.snOrderCancelledProduceUnavailable,
        );
      },
    );

    test(
      'SQL script covers all selling channels and sagana.shelf_rotten guards',
      () {
        final sql = File(
          'supabase_schema/supabase_schema_shelf_life_s06_rotten_sync_and_channels.sql',
        ).readAsStringSync();
        expect(sql, contains("current_setting('sagana.shelf_rotten', true)"));
        expect(sql, contains('cooperative_purchase_offers'));
        expect(sql, contains('market_linking_programs'));
        expect(sql, contains('rotten_at'));
        expect(sql, contains('rotten_kg'));
        expect(sql, contains('Order Cancelled — Produce Unavailable'));
      },
    );
  });

  group('Item 2: Remember Me identifier persistence', () {
    test(
      'stores username/email only and keeps it on sign-out when enabled',
      () async {
        await HiveService.saveRememberMe(
          remember: true,
          identifier: 'juan.farmer',
        );
        expect(HiveService.getRememberMe(), isTrue);
        expect(HiveService.getRememberedIdentifier(), 'juan.farmer');

        await HiveService.clearUserSession();
        expect(HiveService.getRememberMe(), isTrue);
        expect(HiveService.getRememberedIdentifier(), 'juan.farmer');

        await HiveService.saveRememberMe(remember: false);
        expect(HiveService.getRememberMe(), isFalse);
        expect(HiveService.getRememberedIdentifier(), isNull);
      },
    );

    test(
      'router and splash skip Welcome screen when signed out with Remember Me',
      () {
        final splash = File(
          'lib/presentation/screens/splash_screen.dart',
        ).readAsStringSync();
        final router = File(
          'lib/presentation/navigation/app_router.dart',
        ).readAsStringSync();
        final pattern = RegExp(
          r'HiveService\.getRememberMe\(\)\s*\?\s*AppRoutes\.login\s*:\s*AppRoutes\.welcome',
        );
        expect(splash, matches(pattern));
        expect(router, matches(pattern));
      },
    );
  });

  group(
    'Item 3: Single Active Session parsing, activity localization & SQL',
    () {
      test(
        'extractSessionIdFromJwt parses session_id claim and handles invalid JWT',
        () {
          String encode(Map<String, dynamic> m) =>
              base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
          final jwt =
              '${encode({'alg': 'HS256'})}.${encode({'session_id': 'sess-123'})}.sig';
          expect(extractSessionIdFromJwt(jwt), 'sess-123');
          expect(extractSessionIdFromJwt('not-a-jwt'), isNull);
          expect(extractSessionIdFromJwt(null), isNull);
        },
      );

      test('parseSessionReplacedDevice extracts device name from server error', () {
        expect(
          parseSessionReplacedDevice(
            'SESSION_REPLACED: Your account was signed in on another device (Samsung Galaxy S24).',
          ),
          'Samsung Galaxy S24',
        );
        expect(
          parseSessionReplacedDevice(
            'SESSION_REPLACED: Your account was signed in on another device ().',
          ),
          'another device',
        );
        expect(parseSessionReplacedDevice('Permission denied'), isNull);
      });

      test(
        'activityDeviceLogin renders EN & TL with device name across all parsers',
        () {
          final en = AppLocalizationsEn();
          final tl = AppLocalizationsTl();
          const msg = AdminLogMessage('activityDeviceLogin', {
            'device': 'Pixel 8',
          });
          expect(
            renderActivityMessage(en, msg),
            'Signed in on Pixel 8 (previous device signed out)',
          );
          expect(
            renderActivityMessage(tl, msg),
            'Nag-sign in sa Pixel 8 (nai-sign out ang nakaraang device)',
          );

          final parsedProfile = parseLegacyActivity(
            'Signed in on Pixel 8 (previous device signed out)',
          );
          expect(parsedProfile?.key, 'activityDeviceLogin');
          expect(parsedProfile?.params['device'], 'Pixel 8');

          final parsedAdmin = parseLegacyAdminLog(
            'Signed in on Pixel 8 (previous device signed out)',
          );
          expect(parsedAdmin?.key, 'activityDeviceLogin');
          expect(parsedAdmin?.params['device'], 'Pixel 8');
        },
      );

      test(
        'recentActivityTime includes both date and clock time on prior days',
        () {
          final earlier = DateTime(2025, 1, 15, 14, 35);
          expect(recentActivityTime(earlier), 'Jan 15, 2:35 PM');
        },
      );

      test(
        'single_active_session SQL defines table, RPCs, staff gate & all 3 logs',
        () {
          final sql = File(
            'supabase_schema/supabase_schema_single_active_session.sql',
          ).readAsStringSync();
          expect(
            sql,
            contains('CREATE TABLE IF NOT EXISTS public.user_active_sessions'),
          );
          expect(sql, contains('claim_active_session'));
          expect(sql, contains('get_active_session_status'));
          expect(sql, contains('release_active_session'));
          expect(sql, contains('staff_permission_gate'));
          expect(sql, contains('farmer_profile_activity'));
          expect(sql, contains('buyer_profile_activity'));
          expect(sql, contains('admin_activity_log'));
          expect(sql, isNot(contains('trg_audit_staff_change')));
        },
      );
    },
  );

  group('Item 4: Account Sorting Order', () {
    test(
      'orders Pending newest-first -> Active -> Inactive/Suspended -> Disapproved',
      () {
        final oldPending = _member(
          id: 'p1',
          name: 'Zara Pending',
          status: MemberStatus.pending,
          joinedAt: DateTime(2026, 1, 1),
        );
        final newPending = _member(
          id: 'p2',
          name: 'Amy Pending',
          status: MemberStatus.pending,
          joinedAt: DateTime(2026, 5, 1),
        );
        final activeA = _member(
          id: 'a1',
          name: 'Alice Active',
          status: MemberStatus.active,
        );
        final activeB = _member(
          id: 'a2',
          name: 'Ben Active',
          status: MemberStatus.active,
        );
        final inactive = _member(
          id: 'i1',
          name: 'Carl Inactive',
          status: MemberStatus.inactive,
        );
        final suspended = _member(
          id: 's1',
          name: 'Bea Suspended',
          status: MemberStatus.suspended,
        );
        final rejected = _member(
          id: 'r1',
          name: 'Aaron Disapproved',
          status: MemberStatus.rejected,
        );

        final sorted = [
          rejected,
          inactive,
          activeB,
          oldPending,
          suspended,
          activeA,
          newPending,
        ].applyFilter(const FarmerFilterState(sortBy: FarmerSortOption.nameAZ), '');

        expect(sorted.map((m) => m.userId).toList(), [
          'p2',
          'p1',
          'a1',
          'a2',
          's1',
          'i1',
          'r1',
        ]);
      },
    );
  });

  group(
    'Item 5 & Item 6: Suspended details, Set Active & Restrict Lift button layout',
    () {
      testWidgets('MemberIdentityCard renders Suspended badge in EN & TL', (
        tester,
      ) async {
        await runIgnoringFontErrors(() async {
          const profile = FarmerProfileModel(
            userId: 'f1',
            fullName: 'Juan Farmer',
            capitalShares: 500,
            isVerified: true,
            accountStatus: 'suspended',
            suspensionReason: 'Unpaid obligations',
            primaryCrops: ['Rice'],
          );

          await tester.pumpWidget(
            _wrapWithL10n(const MemberIdentityCard(profile: profile)),
          );
          expect(find.text('Suspended'), findsOneWidget);
          expect(find.text('Active Member'), findsNothing);

          await tester.pumpWidget(
            _wrapWithL10n(
              const MemberIdentityCard(profile: profile),
              locale: const Locale('tl'),
            ),
          );
          expect(find.text('Suspindido'), findsOneWidget);
        });
      });

      testWidgets(
        'ManageRestrictionsSheet Lift button renders cleanly at 360px width without infinite width crash',
        (tester) async {
          await runIgnoringFontErrors(() async {
            tester.view.physicalSize = const Size(360, 780);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await tester.pumpWidget(
              _wrapWithL10n(
                ManageRestrictionsSheet(
                  title: 'Manage Restrictions',
                  memberId: 'f1',
                  loader: (_) async => [
                    MemberRestriction(
                      id: 'r1',
                      memberId: 'f1',
                      feature: RestrictableFeature.marketplaceListing,
                      reason: 'Policy breach',
                      status: 'active',
                      startsAt: DateTime(2026, 11, 1),
                    ),
                  ],
                  lifter: (_) async {},
                  onChanged: () {},
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(
              find.byKey(const ValueKey('lift-restriction-r1')),
              findsOneWidget,
            );
            expect(find.text('Lift'), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        },
      );

      test(
        'Members list places divider once before discipline group and confirms Set Active',
        () {
          final src = File(
            'lib/presentation/screens/admin/farmer_management_screen.dart',
          ).readAsStringSync();
          expect(src, contains('farmerMgmtConfirmActivateTitle'));
          expect(src, contains('farmerMgmtActivatedToast'));
          expect(src, contains('!entries.any((e) => e is PopupMenuDivider)'));
        },
      );
    },
  );

  group('Item 7: Crop Roster photo reuse across channels', () {
    test(
      'InventoryBatchModel parses display_image_url & category and preserves them on withPhoto',
      () {
        final batch = InventoryBatchModel.fromMap({
          'id': 'b-crop-1',
          'farmer_id': 'f1',
          'harvest_record_id': 'h1',
          'crop_id': 'crop-1',
          'crop_name': 'Ginger',
          'batch_number': 'B-100',
          'quantity_kg': 25,
          'available_kg': 25,
          'reserved_kg': 0,
          'sold_kg': 0,
          'adjusted_kg': 0,
          'status': 'available',
          'display_image_url': 'https://cdn.example/ginger.jpg',
          'category': 'Spices',
          'created_at': '2026-11-20T00:00:00Z',
        });

        expect(batch.hasPhoto, isTrue);
        expect(batch.displayImageUrl, 'https://cdn.example/ginger.jpg');
        expect(batch.category, 'Spices');

        final updated = batch.withPhoto('https://cdn.example/ginger-new.jpg');
        expect(updated.displayImageUrl, 'https://cdn.example/ginger-new.jpg');
        expect(updated.cropId, 'crop-1');
        expect(updated.category, 'Spices');
      },
    );

    test(
      'repository, Manage Inventory, and Create Listing wire crop photo hydration across selling channels',
      () {
        final repoSrc = File(
          'lib/data/repositories/inventory_repository.dart',
        ).readAsStringSync();
        final invSrc = File(
          'lib/presentation/screens/farmer/manage_inventory_screen.dart',
        ).readAsStringSync();
        final createSrc = File(
          'lib/presentation/screens/farmer/create_listing_screen.dart',
        ).readAsStringSync();

        expect(repoSrc, contains('fetchFarmerCropImageMap'));
        expect(invSrc, contains('_cropsById[batch.cropId]'));
        expect(createSrc, contains('fetchAvailableBatches()'));
      },
    );
  });

  group('Item 8: Reports Hub Recent Reports persistence across logout', () {
    test(
      'export_history_box survives clearUserSession for the owning admin and notifies listeners',
      () async {
        await HiveService.saveUserSession(
          userId: 'admin-1',
          email: 'admin@sagana.local',
          role: 'admin',
        );
        var notifications = 0;
        void onEvent() => notifications++;
        AppEventService.instance.addListener(onEvent);
        addTearDown(() => AppEventService.instance.removeListener(onEvent));

        await HiveService.addExportHistoryEntry({
          'id': 'exp-1',
          'format': 'pdf',
          'moduleNames': ['sales'],
          'moduleLabels': ['Sales Report'],
          'periodLabel': 'This Month',
          'generatedAt': DateTime(2026, 11, 25, 10, 0).toIso8601String(),
          'filePath': '/tmp/sales.pdf',
        });
        expect(notifications, 1);

        await HiveService.clearUserSession();
        expect(HiveService.getExportHistory(), isEmpty);

        await HiveService.saveUserSession(
          userId: 'admin-1',
          email: 'admin@sagana.local',
          role: 'admin',
        );
        final restored = HiveService.getExportHistory();
        expect(restored.length, 1);
        expect(restored.first['id'], 'exp-1');
      },
    );

    test(
      'OperationalReportsScreen wires Recent Reports section and refresh hooks',
      () {
        final src = File(
          'lib/presentation/screens/admin/operational_reports_screen.dart',
        ).readAsStringSync();
        expect(src, contains('_buildRecentReportsSection'));
        expect(src, contains('_refreshExports'));
        expect(
          src,
          contains('AppEventService.instance.addListener(_refreshExports)'),
        );
      },
    );
  });
}
