import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/presentation/widgets/app_navigation_drawer.dart';
import 'package:sagana/data/models/cooperative_delivery_model.dart';
import 'package:sagana/data/services/cooperative_address_service.dart';
import 'package:sagana/presentation/widgets/dashboard_cards.dart';
import 'package:sagana/presentation/widgets/fulfillment_info_card.dart';
import 'package:sagana/presentation/widgets/filter_icon_button.dart';

import 'support/ignore_font_errors.dart';
import 'support/stand_in_fonts.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// The revision after the first review: one shared filter button, Cooperative Details in the
/// drawer, Delivery Settings behind a settings icon in Order Management, six square dashboard
/// cards, a separate Pickup switch, the cooperative location in data, and no staff phone numbers.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadStandInFonts();
  });

  Future<void> openDrawer(
    WidgetTester tester, {
    VoidCallback? onCooperativeDetails,
  }) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          key: key,
          drawer: AppNavigationDrawer(
            photoUrl: null,
            displayName: 'Manager',
            contactEmail: null,
            phoneNumber: null,
            onEditProfile: () {},
            onCooperativeDetails: onCooperativeDetails,
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

  group('navigation drawer', () {
    testWidgets(
      'the Manager / Officer drawer has Cooperative Details, and it opens it',
      (tester) async {
        await runIgnoringFontErrors(() async {
          var opened = 0;
          await openDrawer(tester, onCooperativeDetails: () => opened++);
          final l10n = AppLocalizations.of(
            tester.element(find.byType(Scaffold).first),
          );
          expect(find.text(l10n.cdTitle), findsOneWidget);
          await tester.tap(find.text(l10n.cdTitle));
          expect(opened, 1);
        });
      },
    );

    testWidgets('the Farmer and Buyer drawers never show it', (tester) async {
      await runIgnoringFontErrors(() async {
        await openDrawer(
          tester,
        ); // no callback, as the Farmer and Buyer shells pass none
        final l10n = AppLocalizations.of(
          tester.element(find.byType(Scaffold).first),
        );
        expect(find.text(l10n.cdTitle), findsNothing);
      });
    });

    test('only the Manager / Officer shell wires it', () {
      expect(
        _read('lib/presentation/shell/role_drawers.dart'),
        contains('onCooperativeDetails'),
      );
      final src = _read('lib/presentation/shell/role_drawers.dart');
      final farmer = src.substring(
        src.indexOf('class FarmerShellDrawer'),
        src.indexOf('class AdminShellDrawer'),
      );
      expect(farmer.contains('onCooperativeDetails'), isFalse);
      final buyer = src.substring(src.indexOf('class BuyerShellDrawer'));
      expect(buyer.contains('onCooperativeDetails'), isFalse);
    });
  });

  group('Marketplace dashboard uses the main Dashboard cards', () {
    final src = _read(
      'lib/presentation/screens/admin/marketplace_dashboard_screen.dart',
    );
    final main = _read(
      'lib/presentation/screens/admin/admin_dashboard_screen.dart',
    );
    final shared = _read('lib/presentation/widgets/dashboard_cards.dart');
    final grid = src.substring(src.indexOf('class _QuickActionsGrid'));

    test(
      'six module cards only: Cooperative Details and Delivery Settings are not here',
      () {
        expect(RegExp(r'DashboardModuleItem\(').allMatches(grid).length, 6);
        expect(grid.contains('cdTitle'), isFalse);
        expect(grid.contains('dsTitle'), isFalse);
        expect(src.contains('adminCooperativeDetails'), isFalse);
        expect(src.contains('adminDeliverySettings'), isFalse);
      },
    );

    test('every module card has a subtitle of its own', () {
      for (final k in [
        'ListingsSub',
        'PendingSub',
        'BuyersSub',
        'OrdersSub',
        'LinkingSub',
        'OffersSub',
      ]) {
        expect(grid, contains('marketDashMod$k'), reason: k);
      }
    });

    test(
      'both dashboards build their cards from the SAME shared widgets (one design)',
      () {
        expect(main, contains('DashboardKpiStrip('));
        expect(main, contains('DashboardModuleGrid('));
        expect(src, contains('DashboardKpiStrip('));
        expect(src, contains('DashboardModuleGrid('));
        // No second copy of the card design is left in either screen.
        for (final s in [main, src]) {
          expect(s.contains('class _KpiCard'), isFalse);
        }
        expect(
          src.contains('SliverGridDelegateWithFixedCrossAxisCount'),
          isFalse,
        );
        expect(shared, contains('return 128 * textScale;'));
        expect(
          shared,
          contains('mainAxisExtent: dashboardModuleCardExtent(context)'),
        );
        expect(shared, contains('width: 128'));
        expect(shared, contains('height: 96'));
      },
    );

    test(
      'every KPI card carries a caption like the main Dashboard (label, value, caption)',
      () {
        final kpi = src.substring(
          src.indexOf('class _KpiStrip'),
          src.indexOf('class _QuickActionsGrid'),
        );
        expect(RegExp(r'DashboardKpiTile\(').allMatches(kpi).length, 6);
        expect(RegExp(r'sub: l10n\.').allMatches(kpi).length, 6);
      },
    );

    test('the page still scrolls and the cards keep the two-column grid', () {
      expect(shared, contains('crossAxisCount: 2'));
      expect(
        shared,
        contains('NeverScrollableScrollPhysics'),
      ); // the grid sits in the page's own scroll view
      expect(src, contains('SliverList('));
    });
  });

  group('shared dashboard cards (rendered)', () {
    testWidgets(
      'six module cards lay out in two columns and three rows, with titles and subtitles',
      (tester) async {
        await runIgnoringFontErrors(() async {
          tester.view.physicalSize = const Size(390, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var tapped = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: DashboardModuleGrid(
                    items: [
                      for (var i = 0; i < 6; i++)
                        DashboardModuleItem(
                          key: Key('m$i'),
                          icon: Icons.list_alt_rounded,
                          title: 'Title $i',
                          subtitle: 'Subtitle $i',
                          badge: i == 1 ? '3 pending' : '',
                          onTap: () => tapped++,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
          final xs = {
            for (var i = 0; i < 6; i++)
              tester.getTopLeft(find.byKey(Key('m$i'))).dx,
          };
          final ys = {
            for (var i = 0; i < 6; i++)
              tester.getTopLeft(find.byKey(Key('m$i'))).dy,
          };
          expect(xs.length, 2);
          expect(ys.length, 3);
          expect(tester.getSize(find.byKey(const Key('m0'))).height, 128);
          expect(find.text('Subtitle 4'), findsOneWidget);
          expect(find.text('3 pending'), findsOneWidget);
          await tester.tap(find.byKey(const Key('m3')));
          expect(tapped, 1);
        });
      },
    );

    testWidgets('a KPI card shows its label, value and caption', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: DashboardKpiStrip(
                tiles: [
                  DashboardKpiTile(
                    label: 'Orders',
                    value: '12',
                    sub: 'all orders',
                    color: Colors.purple,
                    icon: Icons.shopping_bag_rounded,
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.text('Orders'), findsOneWidget);
        expect(find.text('12'), findsOneWidget);
        expect(find.text('all orders'), findsOneWidget);
        expect(
          tester.getSize(find.byType(DashboardKpiCard)),
          const Size(128, 96),
        );
      });
    });
  });

  group('Order Management', () {
    final src = _read(
      'lib/presentation/screens/admin/order_management_screen.dart',
    );

    test(
      'one filter button beside the search bar, through the shared button and modal',
      () {
        expect(src, contains('FilterIconButton('));
        expect(src, contains('showChoiceFilterModal<String?>'));
        expect(
          src.contains("Key('sourceFilter')"),
          isFalse,
        ); // the separate source chips are gone
        expect(src, contains("Key('statusFilter')")); // the status chips stay
      },
    );

    test('Members uses the very same filter button (one design, not two)', () {
      final members = _read('lib/presentation/widgets/members_controls.dart');
      expect(members, contains('FilterIconButton('));
      expect(members.contains('class _FilterButton'), isFalse);
    });

    test('a settings icon at the top right opens Delivery Settings', () {
      expect(src, contains("Key('orderSettings')"));
      expect(src, contains('AppRoutes.adminDeliverySettings'));
    });
  });

  group('shared filter button', () {
    testWidgets('shows a dot only when a filter is active and reports taps', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        var taps = 0;
        Future<void> show(bool active) => tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Center(
                child: FilterIconButton(
                  buttonKey: const Key('b'),
                  dotKey: const Key('d'),
                  active: active,
                  onTap: () => taps++,
                ),
              ),
            ),
          ),
        );
        await show(false);
        expect(find.byKey(const Key('d')), findsNothing);
        await tester.tap(find.byKey(const Key('b')));
        expect(taps, 1);
        await show(true);
        expect(find.byKey(const Key('d')), findsOneWidget);
        expect(tester.getSize(find.byKey(const Key('b'))), const Size(48, 48));
      });
    });
  });

  group('Cooperative Details and Delivery Settings are plain', () {
    test('no Delivery area description, no Service area rows', () {
      final settings = _read(
        'lib/presentation/screens/admin/delivery_settings_screen.dart',
      );
      expect(settings.contains('dsCoverage'), isFalse);
      final details = _read(
        'lib/presentation/screens/admin/cooperative_details_screen.dart',
      );
      for (final gone in [
        'cdAreaTitle',
        'cdRegion',
        'cdProvince',
        'cdMunicipality',
        'cdPostal',
        'cdAreaNote',
      ]) {
        expect(details.contains(gone), isFalse, reason: gone);
      }
    });

    test('both use the same card component', () {
      expect(
        _read('lib/presentation/screens/admin/delivery_settings_screen.dart'),
        contains('AddressSectionCard'),
      );
      expect(
        _read('lib/presentation/screens/admin/cooperative_details_screen.dart'),
        contains('AddressSectionCard'),
      );
    });

    test(
      'the Manager edits; an Officer, even with Marketplace = Manage, only views',
      () {
        for (final f in [
          'cooperative_details_screen',
          'delivery_settings_screen',
        ]) {
          final src = _read('lib/presentation/screens/admin/$f.dart');
          expect(src, contains('signedInIsManager()'), reason: f);
        }
      },
    );
  });

  group('Pickup address comes from Cooperative Details', () {
    tearDown(() => CooperativeAddressService.instance.reset());

    Future<void> showPickupCard(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: FulfillmentInfoCard(fulfillmentMethod: 'pickup'),
        ),
      ),
    );

    testWidgets(
      'an order screen shows the saved address, and a change the Manager saves shows next time',
      (tester) async {
        await runIgnoringFontErrors(() async {
          var postal = '4903';
          CooperativeAddressService.instance.reset();
          CooperativeAddressService.fetcherOverride = () async =>
              CooperativeDetails(
                cooperativeName: 'SP3 Agriculture Cooperative',
                postalCode: postal,
              );
          await showPickupCard(tester);
          await tester.pump();
          expect(
            find.text(
              'SP3 Agriculture Cooperative, Barangay Payanas, Torrijos, Marinduque, MIMAROPA Region, 4903',
            ),
            findsOneWidget,
          );
          // The Manager saves a change: the service forgets its copy, the next screen reads the record again.
          postal = '4999';
          CooperativeAddressService.instance.invalidate();
          await tester.pumpWidget(const SizedBox());
          await showPickupCard(tester);
          await tester.pump();
          expect(find.textContaining('4999'), findsOneWidget);
        });
      },
    );

    testWidgets(
      'when the record cannot be read, nothing invented is shown: the address is said to be unavailable',
      (tester) async {
        await runIgnoringFontErrors(() async {
          CooperativeAddressService.instance.reset();
          CooperativeAddressService.fetcherOverride = () async =>
              throw Exception('offline');
          await showPickupCard(tester);
          await tester.pump();
          await tester.pump();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(Scaffold)),
          );
          expect(find.text(l10n.cdAddressUnavailable), findsOneWidget);
          expect(find.textContaining('Payanas'), findsNothing);
        });
      },
    );

    test('no screen carries its own copy of the cooperative address', () {
      final hits = <String>[];
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart') || e.path.contains('l10n'))
          continue;
        final src = e.readAsStringSync();
        if (src.contains('cooperativeLocation')) hits.add(e.path);
      }
      expect(hits, isEmpty);
      expect(
        _read(
          'lib/core/constants/app_constants.dart',
        ).contains('cooperativeLocation'),
        isFalse,
      );
      // The three places that show a pickup address all read the record.
      expect(
        _read('lib/presentation/widgets/fulfillment_info_card.dart'),
        contains('CooperativeAddressText'),
      );
      expect(
        _read('lib/presentation/screens/buyer/listing_details_screen.dart'),
        contains('CooperativeAddressText'),
      );
      expect(
        _read('lib/presentation/screens/buyer/checkout_screen.dart'),
        contains('_coopDetails?.addressLine'),
      );
    });
  });

  group('Marketplace cards carry live counts', () {
    final src = _read(
      'lib/presentation/screens/admin/marketplace_dashboard_screen.dart',
    );
    final grid = src.substring(src.indexOf('class _QuickActionsGrid'));

    test('each card shows the count the Manager asked for', () {
      // All Listings, Pending Approval (new + edited), Buyers, Orders (both sources),
      // Market Linking (requests, not quantity), Offers (all of them).
      expect(grid, contains("badge: '\${stats.total}'"));
      expect(grid, contains("badge: '\${stats.pending + pendingEditCount}'"));
      expect(grid, contains("badge: '\$buyerCount'"));
      expect(grid, contains("badge: '\${orderStats.total}'"));
      expect(grid, contains("badge: '\$marketLinkingCount'"));
      expect(grid, contains("badge: '\$totalOffersCount'"));
      // No old text badges are left ("N pending", "DA-AMAD", "N need action").
      expect(grid.contains('marketDashPendingBadge'), isFalse);
      expect(grid.contains('marketDashNeedActionBadge'), isFalse);
      expect(grid.contains("'DA-AMAD'"), isFalse);
    });

    test('the counts come from the database, and follow the data', () {
      expect(src, contains('fetchPendingEditCount()'));
      expect(src, contains('fetchTotalCount()'));
      expect(
        src,
        contains('marketLinkingStats.total'),
      ); // requests, never kg or quantity sold
      for (final t in [
        'program_product_purchases',
        'listing_edit_requests',
        'cooperative_purchase_offers',
        'market_linking_programs',
        'user_roles',
      ]) {
        expect(src, contains("'$t'"), reason: t);
      }
      expect(
        _read('lib/data/repositories/admin_listing_repository.dart'),
        contains(
          "from('listing_edit_requests').count().eq('status', 'pending')",
        ),
      );
      expect(
        _read('lib/data/repositories/cooperative_offer_repository.dart'),
        contains("from('cooperative_purchase_offers').count();"),
      );
      // Orders: one count over Marketplace and Cooperative orders.
      final orders = _read('lib/data/repositories/admin_order_repository.dart');
      expect(orders, contains("n('program_product_purchases'"));
      expect(orders, contains("n('orders'"));
    });

    test(
      'the indicator is the SAME pill as the Management Modules (font, size, colours)',
      () {
        final shared = _read('lib/presentation/widgets/dashboard_cards.dart');
        expect(shared, contains('fontSize: 8'));
        expect(shared, contains('FontWeight.w700'));
        expect(
          grid.contains('GoogleFonts'),
          isFalse,
        ); // no private badge style on the Marketplace screen
      },
    );

    testWidgets('a card shows its count in the shared pill, zero included', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: DashboardModuleGrid(
                items: [
                  DashboardModuleItem(
                    icon: Icons.list,
                    title: 'A',
                    subtitle: 'a',
                    badge: '30',
                    onTap: () {},
                  ),
                  DashboardModuleItem(
                    icon: Icons.list,
                    title: 'B',
                    subtitle: 'b',
                    badge: '0',
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.text('30'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
        expect(tester.widget<Text>(find.text('30')).style!.fontSize, 8);
      });
    });
  });

  group('Pending Approval screen', () {
    final src = _read(
      'lib/presentation/screens/admin/pending_approvals_screen.dart',
    );

    test(
      'search with the shared filter button beside it, like Order Management',
      () {
        expect(src, contains('FilterIconButton('));
        expect(src, contains('showChoiceFilterModal<int>'));
        expect(src, contains("Key('approvalFilterButton')"));
        expect(
          src.contains('_tabSelector'),
          isFalse,
        ); // the All / New / Edited tab bar is gone
      },
    );

    test(
      'the modal offers All, New Listings and Edited Listings, with short labels',
      () {
        expect(src, contains('l10n.lePendingTabAll'));
        expect(src, contains('l10n.lePendingTabNew'));
        expect(src, contains('l10n.lePendingTabEdits'));
      },
    );

    test(
      'terminology is the same everywhere: New Listings, Edited Listings, short statuses',
      () {
        final en = _read('lib/core/l10n/app_en.arb');
        String v(String k) =>
            RegExp('"$k": "([^"]*)"').firstMatch(en)!.group(1)!;
        expect(v('lePendingTabNew'), 'New Listings');
        expect(v('lePendingTabEdits'), 'Edited Listings');
        expect(v('leEditRequestBadge'), 'Edited Listing');
        expect(
          v('leStatusPendingEdit'),
          'Pending',
        ); // not "Edit Pending Approval"
        for (final k in [
          'lePendingTabAll',
          'lePendingTabNew',
          'lePendingTabEdits',
          'leStatusPendingEdit',
          'leEditRequestBadge',
        ]) {
          expect(v(k).length, lessThan(16), reason: k);
        }
      },
    );
  });

  group('Farmer can cancel their own edited-listing request', () {
    test(
      'the Farmer screen offers it, after a confirmation, and only offline-safe',
      () {
        final src = _read(
          'lib/presentation/screens/farmer/farmer_listing_detail_screen.dart',
        );
        expect(src, contains('_cancelRequest(r)'));
        expect(src, contains('cancelEditRequest(request.id)'));
        expect(src, contains('_requireOnline()'));
      },
    );

    test(
      'the database function is the Farmer\'s own, pending-only, and logged',
      () {
        final sql = _read(
          'supabase_schema/supabase_schema_listing_edit_approval.sql',
        );
        final fn = sql.substring(
          sql.indexOf('FUNCTION public.cancel_listing_edit_request'),
          sql.indexOf('FUNCTION public._listing_close_edit_requests'),
        );
        expect(fn, contains('farmer_id = v_uid'));
        expect(fn, contains("r.status <> 'pending'"));
        expect(fn, contains("'edit_cancelled'"));
      },
    );
  });

  group('Delivery Settings wording', () {
    test(
      'the checklist link says "Complete Cooperative Details", never "Fix"',
      () {
        expect(
          _read('lib/presentation/screens/admin/delivery_settings_screen.dart'),
          contains("Key('dsCompleteDetails')"),
        );
        final en = _read('lib/core/l10n/app_en.arb');
        expect(en, contains('"dsCheckAction": "Complete Cooperative Details"'));
        final tl = _read('lib/core/l10n/app_tl.arb');
        expect(
          tl,
          contains('"dsCheckAction": "Kumpletuhin ang Detalye ng Kooperatiba"'),
        );
        for (final m in RegExp(
          r'"(ds|cd)[A-Za-z]*": "([^"]*)"',
        ).allMatches(en)) {
          expect(
            RegExp(r'\bfix\b', caseSensitive: false).hasMatch(m.group(2)!),
            isFalse,
            reason: m.group(0),
          );
        }
      },
    );
  });

  group('m07 (read from the script)', () {
    final sql = _read(
      'supabase_schema/supabase_schema_unify_m07_pickup_switch_location_guards.sql',
    );
    final code = sql
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('--'))
        .join('\n');

    test(
      'Pickup is its own switch, ON by default, changed only by the Manager',
      () {
        expect(
          code,
          contains(
            'ADD COLUMN IF NOT EXISTS pickup_enabled BOOLEAN NOT NULL DEFAULT TRUE',
          ),
        );
        final fn = code.substring(
          code.indexOf('FUNCTION public.set_pickup_enabled'),
          code.indexOf('FUNCTION public.set_delivery_enabled'),
        );
        expect(fn, contains('public.is_manager()'));
        expect(code, contains("('rpc', 'set_pickup_enabled', 'marketplace')"));
      },
    );

    test(
      'at least one method stays on: refused in both functions and forced by a trigger',
      () {
        expect(code, contains('ONE_METHOD_REQUIRED'));
        expect(RegExp('ONE_METHOD_REQUIRED').allMatches(code).length, 2);
        final trig = code.substring(
          code.indexOf('FUNCTION public._delivery_settings_one_method'),
          code.indexOf('CREATE OR REPLACE FUNCTION public.set_pickup_enabled'),
        );
        expect(trig, contains('NEW.pickup_enabled := TRUE'));
      },
    );

    test(
      'the switches hold for every order, Marketplace and Cooperative, in the database',
      () {
        expect(code, contains('BEFORE INSERT ON public.orders'));
        expect(
          code,
          contains('BEFORE INSERT ON public.program_product_purchases'),
        );
        final fn = code.substring(
          code.indexOf('FUNCTION public._order_method_allowed'),
          code.indexOf('DROP TRIGGER IF EXISTS trg_orders_method_allowed'),
        );
        expect(fn, contains("'PICKUP_OFF"));
        expect(
          fn,
          contains("v_method = 'delivery' AND NEW.checkout_group_id IS NULL"),
        );
      },
    );

    test(
      'the cooperative location is data: Payanas, only when none is stored, editable afterwards',
      () {
        expect(
          code,
          contains(
            'UPDATE public.cooperative_details SET latitude = 13.3213, longitude = 122.0392',
          ),
        );
        expect(code, contains('WHERE latitude IS NULL AND longitude IS NULL'));
      },
    );

    test(
      'the cooperative number is refused when it is a Manager\'s or Officer\'s own phone',
      () {
        final fn = code.substring(
          code.indexOf('FUNCTION public.save_cooperative_details'),
        );
        expect(fn, contains("ur.role IN ('admin', 'officer')"));
        expect(fn, contains('ui.phone_number'));
        expect(fn, contains('PERSONAL_NUMBER'));
      },
    );

    test('the status carries the Pickup switch, and the app reads it', () {
      expect(code, contains("'pickup_enabled', s.pickup_enabled"));
      expect(
        _read('lib/data/models/cooperative_delivery_model.dart'),
        contains("m['pickup_enabled']"),
      );
    });

    test('the new refusals are translated', () {
      final err = _read('lib/core/utils/app_error_message.dart');
      for (final c in [
        'PICKUP_OFF',
        'ONE_METHOD_REQUIRED',
        'PERSONAL_NUMBER',
      ]) {
        expect(err, contains("'$c'"));
      }
    });
  });
}
