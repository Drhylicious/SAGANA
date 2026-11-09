import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/cart_item_model.dart';
import 'package:sagana/data/models/cooperative_product_model.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/presentation/screens/farmer/cooperative_product_details_screen.dart';
import 'package:sagana/presentation/screens/farmer/farmer_marketplace_tab.dart';
import 'package:sagana/presentation/screens/farmer/farmer_program_order_detail_screen.dart';
import 'package:sagana/presentation/widgets/product_buy_now_sheet.dart';
import 'package:sagana/presentation/widgets/quantity_stepper.dart';
import 'package:sagana/presentation/widgets/sub_page_top_bar.dart';
import 'package:sagana/routes/app_routes.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/ignore_font_errors.dart';
import 'support/stand_in_fonts.dart';
import 'support/test_storage_mocks.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// The Farmer's side of the unified purchasing: Cooperative Products in the Marketplace, the
/// product page, and their own Cooperative orders. And the Buyer never sees any of it.

Map<String, Object?> _productRow({
  String id = 'pp1',
  num price = 50,
  num allocated = 20,
  num reserved = 5,
  bool on = true,
  String program = 'prog-1',
  String name = 'Peanut Cookies',
}) => {
  'id': id,
  'program_id': program,
  'unit_price': price,
  'is_available': on,
  'stock_allocated': allocated,
  'stock_reserved': reserved,
  'cooperative_inventory': {
    'item_name': name,
    'category': 'Harvest Stock',
    'unit': 'pack',
    'image_url': null,
  },
  'cooperative_programs': {
    'program_name': 'Peanut Cookies Sale',
    'member_discount_percent': 10,
    'status': 'active',
    'program_purpose': 'sales',
  },
};

Map<String, Object?> _order({
  String status = 'pending',
  String method = 'pickup',
  String payment = 'unpaid',
  String? completion,
  String? reason,
}) => {
  'id': 'c1',
  'program_id': 'prog-1',
  'program_name': 'Peanut Cookies Sale',
  'product_id': 'pp1',
  'item_name': 'Peanut Cookies',
  'unit': 'pack',
  'farmer_id': 'f1',
  'quantity': 2,
  'unit_price': 45,
  'total_amount': 90,
  'regular_unit_price': 50,
  'discount_percent': 10,
  'discount_amount': 10,
  'is_member_price': true,
  'status': status,
  'requested_at': '2026-11-06T10:00:00Z',
  'order_number': 'PSO-20261106-A001',
  'fulfillment_method': method,
  'payment_status': payment,
  'completion_method': completion,
  'staff_completion_reason': reason,
  'staff_completed_by_name': 'Ana Reyes',
  'staff_completed_by_role': 'officer',
  'payment_recorded_by_name': 'Ana Reyes',
  'payment_recorded_by_role': 'officer',
  'amount_collected': payment == 'paid' ? 90 : null,
};

CooperativeProduct _coopProduct({
  bool member = true,
  num allocated = 20,
  num reserved = 5,
}) => CooperativeProduct.fromRow(
  _productRow(allocated: allocated, reserved: reserved),
  isMember: member,
)!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_farmer_side');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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
    await loadStandInFonts();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(420, 2000),
    GoRouter? router,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (router != null) {
      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      );
    } else {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      );
    }
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  // ── Cooperative Products in the Farmer's Marketplace ──────────────────────
  group('Farmer Marketplace: Cooperative Products', () {
    Future<void> openTab(
      WidgetTester tester, {
      List<Map<String, Object?>>? products,
      bool member = true,
    }) async {
      fake.reset();
      // The Marketplace listings are read through the offline snapshot (real file storage); they are
      // not the subject here, so that read is answered with an error and only Cooperative Products show.
      fake.on(
        'GET /rest/v1/marketplace_listings',
        (_) => const FakeError(500, 'not part of this test'),
      );
      fake.on(
        'GET /rest/v1/program_products',
        (_) =>
            products ??
            [
              _productRow(),
              _productRow(
                id: 'pp2',
                name: 'Coconut Jam',
                price: 80,
                allocated: 4,
                reserved: 4,
              ),
            ],
      );
      fake.on(
        'GET /rest/v1/program_members',
        (_) => member
            ? [
                {'program_id': 'prog-1'},
              ]
            : [],
      );
      fake.on(
        'POST /rest/v1/rpc/get_program_product_stats',
        (_) => [
          {'product_id': 'pp1', 'buyers': 3, 'quantity_sold': 12},
        ],
      );
      await tester.runAsync(
        () => HiveService.saveUserSession(
          userId: 'f1',
          email: 'f@x.y',
          role: 'farmer',
        ),
      );
      await pump(
        tester,
        const Scaffold(
          body: SingleChildScrollView(child: FarmerMarketplaceTab()),
        ),
      );
    }

    testWidgets(
      'a Cooperative Product is a card in the Marketplace, labelled with its source and program',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openTab(tester);
          final l10n = l10nOf(tester);
          expect(find.byKey(const Key('coopProduct_pp1')), findsOneWidget);
          expect(find.text('Peanut Cookies'), findsOneWidget);
          expect(
            find.text('${l10n.cpSourceLabel} · Peanut Cookies Sale'),
            findsNWidgets(2),
          );
          expect(
            find.text('15 pack ${l10n.buyerBrowseAvailableSuffix}'),
            findsOneWidget,
          ); // 20 set aside - 5 reserved
          expect(find.text(l10n.catBuyers(3)), findsOneWidget);
        });
      },
    );

    testWidgets(
      'an enrolled member sees the member price, with the regular price beneath',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openTab(tester, member: true);
          final l10n = l10nOf(tester);
          expect(
            find.text('₱45.00/pack'),
            findsOneWidget,
          ); // Peanut Cookies: 10% off for a member
          expect(find.text(l10n.prodRegularPrice('₱50.00')), findsOneWidget);
          expect(
            find.text('₱72.00/pack'),
            findsOneWidget,
          ); // Coconut Jam, same program discount
        });
      },
    );

    testWidgets('anyone else sees the regular price and what members pay', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await openTab(tester, member: false);
        final l10n = l10nOf(tester);
        expect(find.text('₱50.00/pack'), findsOneWidget); // the regular price
        expect(find.text(l10n.cpMemberPriceHint('₱45.00')), findsOneWidget);
      });
    });

    testWidgets('a product with nothing left set aside shows as sold out', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await openTab(tester);
        final l10n = l10nOf(tester);
        expect(
          find.text(l10n.buyerBrowseSoldOut),
          findsOneWidget,
        ); // Coconut Jam: 4 set aside, 4 reserved
      });
    });

    testWidgets('a product that is switched off is not shown', (tester) async {
      await runIgnoringFontErrors(() async {
        await openTab(
          tester,
          products: [
            _productRow(id: 'off', on: false),
            _productRow(),
          ],
        );
        expect(find.byKey(const Key('coopProduct_off')), findsNothing);
        expect(find.byKey(const Key('coopProduct_pp1')), findsOneWidget);
      });
    });

    testWidgets(
      'source chips (All / Marketplace / Cooperative Products) let a Farmer browse one kind',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openTab(tester);
          final l10n = l10nOf(tester);
          expect(find.byKey(const Key('source_all')), findsOneWidget);
          await tester.tap(find.byKey(const Key('source_marketplace')));
          await tester.pump();
          expect(find.byKey(const Key('coopProduct_pp1')), findsNothing);
          await tester.tap(find.byKey(const Key('source_cooperative')));
          await tester.pump();
          expect(find.byKey(const Key('coopProduct_pp1')), findsOneWidget);
          expect(find.text(l10n.cpFilterCooperative), findsOneWidget);
        });
      },
    );

    testWidgets(
      'a Farmer with no Cooperative Products sees no source chips (the Marketplace looks as before)',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openTab(tester, products: []);
          expect(find.byKey(const Key('source_all')), findsNothing);
        });
      },
    );

    testWidgets('My Orders is one tap away from the Marketplace', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await openTab(tester);
        expect(find.byKey(const Key('myOrdersShortcut')), findsOneWidget);
      });
    });
  });

  // ── the Buyer never reaches Cooperative Products ─────────────────────────
  group('Buyers never see, add or buy a Cooperative Product', () {
    test('the Buyer screens do not read Cooperative Products at all', () {
      for (final f in [
        'lib/presentation/screens/buyer/marketplace_browse_screen.dart',
        'lib/presentation/screens/buyer/listing_details_screen.dart',
      ]) {
        final src = _read(f);
        expect(src.contains('fetchCooperativeProducts'), isFalse, reason: f);
        expect(src.contains('CooperativeProduct'), isFalse, reason: f);
        expect(src.contains('place_program_order'), isFalse, reason: f);
      }
    });

    test(
      'a Buyer\'s cart drops any Cooperative line instead of showing or placing it',
      () {
        final cart = _read('lib/presentation/screens/buyer/cart_screen.dart');
        expect(
          cart,
          contains(
            '!widget.isFarmerContext && items.any((i) => i.isCooperative)',
          ),
        );
      },
    );

    test(
      'the database call is for Farmers only (the Buyer\'s checkout never has such a line)',
      () {
        final sql = _read(
          'supabase_schema/supabase_schema_unify_m04_cooperative_order_engine.sql',
        );
        final fn = sql.substring(
          sql.indexOf('FUNCTION public.place_program_order'),
        );
        expect(fn, contains("role = 'farmer'"));
      },
    );
  });

  // ── the product page ──────────────────────────────────────────────────────
  group('Cooperative Product page (laid out like a Marketplace listing)', () {
    Future<void> openPage(
      WidgetTester tester,
      CooperativeProduct product,
      List<Object?> pushed, {
      List<CooperativeProduct> related = const [],
    }) async {
      final router = GoRouter(
        initialLocation: '/page',
        routes: [
          GoRoute(
            path: '/page',
            builder: (c, s) => CooperativeProductDetailsScreen(
              product: product,
              loadRelated: () async => related,
            ),
          ),
          GoRoute(
            path: AppRoutes.farmerMarketplaceCheckout,
            builder: (c, s) {
              pushed.add(s.extra);
              return const Scaffold(body: Text('CHECKOUT'));
            },
          ),
        ],
      );
      await pump(tester, const SizedBox(), router: router);
    }

    Finder stepperField() => find.descendant(
      of: find.byType(QuantityStepper),
      matching: find.byType(TextField),
    );

    testWidgets(
      'no title bar: the photo fills the top with the back button over it, like a listing',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openPage(tester, _coopProduct(member: true), []);
          final l10n = l10nOf(tester);
          expect(find.byType(SubPageTopBar), findsNothing);
          // 400 high, edge to edge, exactly like the Marketplace photo.
          final photo = find.byWidgetPredicate(
            (w) =>
                w is SizedBox && w.height == 400 && w.width == double.infinity,
          );
          expect(photo, findsOneWidget);
          expect(find.byType(SubPageBackButton), findsOneWidget);
          // The pill sits on the photo, the same as the market type on a listing.
          expect(find.text(l10n.cpTitle), findsOneWidget);
          expect(find.text(l10n.buyerBrowseSoldOut), findsNothing);
        });
      },
    );

    testWidgets(
      'price and unit, what was sold, the name, then the cooperative card and the program',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openPage(tester, _coopProduct(member: true), []);
          final l10n = l10nOf(tester);
          expect(
            tester.widget<Text>(find.byKey(const Key('cpMemberPrice'))).data,
            '₱45.00',
          ); // what this member pays
          expect(find.text('/pack'), findsOneWidget);
          expect(find.byKey(const Key('cpSold')), findsOneWidget);
          expect(
            find.text('₱50.00/pack'),
            findsOneWidget,
          ); // the regular price, struck through
          expect(find.text(l10n.cpYouPayMember('10')), findsOneWidget);
          expect(find.text('SP3 Agriculture Cooperative'), findsWidgets);
          expect(
            find.text(l10n.cpFromProgram('Peanut Cookies Sale')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('cpMembersPay')), findsNothing);
          // Top to bottom, like a listing: price, name, card.
          final price = tester
              .getTopLeft(find.byKey(const Key('cpMemberPrice')))
              .dy;
          final name = tester.getTopLeft(find.byKey(const Key('cpName'))).dy;
          final card = tester.getTopLeft(find.byKey(const Key('cpProgram'))).dy;
          expect(price, lessThan(name));
          expect(name, lessThan(card));
        });
      },
    );

    testWidgets('anyone else is told what members pay and how to get it', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await openPage(tester, _coopProduct(member: false), []);
        final l10n = l10nOf(tester);
        expect(
          tester.widget<Text>(find.byKey(const Key('cpPrice'))).data,
          '₱50.00',
        );
        expect(find.byKey(const Key('cpMemberPrice')), findsNothing);
        expect(
          find.text(l10n.cpMembersPay('₱45.00', '10', 'Peanut Cookies Sale')),
          findsOneWidget,
        );
      });
    });

    testWidgets(
      '"More from SP3" lists the other Cooperative Products, never this one',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final here = _coopProduct(member: true);
          await openPage(tester, here, [], related: [here]);
          expect(
            find.byKey(const Key('cpRelated')),
            findsNothing,
          ); // only itself: nothing to show
          final other = CooperativeProduct.fromRow({
            ..._productRow(allocated: 20, reserved: 5),
            'id': 'pp2',
          }, isMember: true)!;
          await openPage(tester, here, [], related: [here, other]);
          expect(
            find.text(l10nOf(tester).buyerListingMoreFromSp3),
            findsOneWidget,
          );
          expect(find.byKey(const Key('cpRelated_pp2')), findsOneWidget);
          expect(find.byKey(Key('cpRelated_${here.productId}')), findsNothing);
        });
      },
    );

    testWidgets(
      'Buy Now opens the sliding sheet (it does not go straight to checkout)',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final pushed = <Object?>[];
          await openPage(
            tester,
            _coopProduct(member: true, allocated: 6, reserved: 3), // 3 left
            pushed,
          );
          await tester.tap(find.byKey(const Key('cpBuyNow')));
          await tester.pumpAndSettle();
          final l10n = l10nOf(tester);
          expect(find.byType(ProductBuyNowSheet), findsOneWidget);
          expect(pushed, isEmpty);
          expect(find.text('₱45.00'), findsWidgets);
          expect(
            find.text(l10n.buyerListingMaxAvailable('3 pack')),
            findsOneWidget,
          );
          expect(find.text(l10n.buyerListingOrderQty('pack')), findsOneWidget);
          // More than what is left cannot be typed (the field refuses the digit).
          await tester.enterText(stepperField(), '9');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();
          expect(
            double.parse(
              tester.widget<TextField>(stepperField()).controller!.text,
            ),
            lessThanOrEqualTo(3),
          );
        });
      },
    );

    testWidgets('a decimal quantity (1.25) goes through to checkout as typed', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final pushed = <Object?>[];
        await openPage(tester, _coopProduct(member: true), pushed);
        await tester.tap(find.byKey(const Key('cpBuyNow')));
        await tester.pumpAndSettle();
        await tester.enterText(stepperField(), '1.25');
        await tester.pump();
        await tester.tap(find.byKey(const Key('buyNowConfirm')));
        await tester.pumpAndSettle();
        expect(pushed.length, 1);
        final line =
            ((pushed.single! as Map)['items'] as List).single as CartItemModel;
        expect(line.quantityKg, 1.25);
      });
    });

    testWidgets(
      'stepping down from a fraction never jumps up (0.5 - 1 stays at the smallest)',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openPage(tester, _coopProduct(member: true), []);
          await tester.tap(find.byKey(const Key('cpBuyNow')));
          await tester.pumpAndSettle();
          await tester.enterText(stepperField(), '0.5');
          await tester.pump();
          await tester.tap(find.byIcon(Icons.remove).last);
          await tester.pump();
          final shown = double.parse(
            tester.widget<TextField>(stepperField()).controller!.text,
          );
          expect(
            shown,
            lessThanOrEqualTo(0.5),
          ); // the old control jumped UP to 1
          expect(shown, greaterThan(0));
        });
      },
    );

    testWidgets(
      'a sold-out product has no buy buttons, a Sold Out pill and a notice',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openPage(tester, _coopProduct(allocated: 5, reserved: 5), []);
          expect(find.byKey(const Key('cpBuyNow')), findsNothing);
          expect(find.byKey(const Key('cpAddToCart')), findsNothing);
          expect(find.byKey(const Key('cpSoldOutNotice')), findsOneWidget);
          expect(find.text(l10nOf(tester).buyerBrowseSoldOut), findsWidgets);
        });
      },
    );

    testWidgets(
      'Buy Now goes to the same checkout with a Cooperative line carrying the program and a request id',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final pushed = <Object?>[];
          await openPage(tester, _coopProduct(member: true), pushed);
          await tester.tap(find.byKey(const Key('cpBuyNow')));
          await tester.pumpAndSettle();
          await tester.enterText(stepperField(), '2');
          await tester.pump();
          await tester.tap(find.byKey(const Key('buyNowConfirm')));
          await tester.pumpAndSettle();
          expect(pushed.length, 1);
          final extra = pushed.single! as Map;
          expect(extra['isCartCheckout'], false);
          final line = (extra['items'] as List).single as CartItemModel;
          expect(line.isCooperative, isTrue);
          expect(line.listingId, 'pp1'); // the PRODUCT id
          expect(line.programId, 'prog-1');
          expect(line.quantityKg, 2);
          expect(line.pricePerKg, 45); // the price this member pays
          expect(line.requestId, isNotEmpty);
        });
      },
    );
  });

  // ── a Farmer's own Cooperative order ──────────────────────────────────────
  group('Farmer: a Cooperative order', () {
    Future<void> openOrder(
      WidgetTester tester,
      Map<String, Object?> order,
    ) async {
      fake.reset();
      fake.on('GET /rest/v1/program_product_purchases', (_) => [order]);
      await tester.runAsync(
        () => HiveService.saveUserSession(
          userId: 'f1',
          email: 'f@x.y',
          role: 'farmer',
        ),
      );
      await pump(
        tester,
        FarmerProgramOrderDetailScreen(key: UniqueKey(), orderId: 'c1'),
      );
    }

    testWidgets('Pending: the Farmer can cancel it, and only then', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await openOrder(tester, _order(status: 'pending'));
        expect(find.byKey(const Key('farmerCancel')), findsOneWidget);
        expect(find.byKey(const Key('farmerConfirmReceived')), findsNothing);
        await openOrder(tester, _order(status: 'approved'));
        expect(find.byKey(const Key('farmerCancel')), findsNothing);
      });
    });

    testWidgets(
      'Ready for Pickup with the cash not recorded: waiting for payment, no Confirm Receipt',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openOrder(tester, _order(status: 'ready_for_pickup'));
          expect(find.byKey(const Key('waitingForPayment')), findsOneWidget);
          expect(find.byKey(const Key('farmerConfirmReceived')), findsNothing);
        });
      },
    );

    testWidgets(
      'once the cash is recorded the Farmer can confirm receipt, and the confirmation is sent for that order',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openOrder(
            tester,
            _order(status: 'ready_for_pickup', payment: 'paid'),
          );
          expect(find.byKey(const Key('waitingForPayment')), findsNothing);
          expect(
            find.byKey(const Key('farmerConfirmReceived')),
            findsOneWidget,
          );
          await tester.ensureVisible(
            find.byKey(const Key('farmerConfirmReceived')),
          );
          await tester.tap(find.byKey(const Key('farmerConfirmReceived')));
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 300));
          final calls = fake.calls(
            'POST /rest/v1/rpc/confirm_program_order_received',
          );
          expect(calls.length, 1);
          expect(calls.single.jsonMap['p_order_id'], 'c1');
          await tester.pump(const Duration(seconds: 4));
        });
      },
    );

    testWidgets(
      'the Farmer never sees which staff member recorded the cash or completed the order',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openOrder(
            tester,
            _order(
              status: 'completed',
              payment: 'paid',
              completion: 'staff',
              reason: 'No phone signal',
            ),
          );
          expect(find.textContaining('Ana Reyes'), findsNothing);
          expect(find.textContaining('Officer'), findsNothing);
          expect(find.byKey(const Key('staffCompletionCard')), findsOneWidget);
          expect(find.textContaining('No phone signal'), findsOneWidget);
          expect(find.byKey(const Key('orderPaymentCard')), findsOneWidget);
        });
      },
    );

    testWidgets(
      'the order shows the program, the quantity and the member price paid',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openOrder(tester, _order());
          expect(find.text('Peanut Cookies Sale'), findsOneWidget);
          expect(find.text('2 pack'), findsOneWidget);
          expect(find.text('₱45.00'), findsOneWidget);
          expect(find.text('₱90.00'), findsWidgets);
        });
      },
    );
  });
}
