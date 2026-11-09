import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/buyer_address_model.dart';
import 'package:sagana/data/models/cart_item_model.dart';
import 'package:sagana/data/models/cooperative_delivery_model.dart';
import 'package:sagana/data/repositories/buyer_address_repository.dart';
import 'package:sagana/data/repositories/buyer_marketplace_repository.dart';
import 'package:sagana/data/repositories/cooperative_delivery_repository.dart';
import 'package:sagana/data/repositories/cooperative_order_repository.dart';
import 'package:sagana/data/services/cart_service.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/presentation/screens/buyer/checkout_screen.dart';
import 'package:sagana/presentation/widgets/shared_widgets.dart'
    show PrimaryButton;
import 'package:sagana/routes/app_routes.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/ignore_font_errors.dart';
import 'support/stand_in_fonts.dart';
import 'support/test_storage_mocks.dart';

/// Checkout with the unified cart: one cart, each line placed through its own source, one delivery
/// group per checkout, a request id per line, and the Buyer's checkout unchanged.
/// The data layer is replaced by fakes that record what the screen asks of it.

class _Market extends BuyerMarketplaceRepository {
  final calls = <Map<String, Object?>>[];
  Object? failFirst;
  @override
  Future<String> placeOrder({
    required String listingId,
    required double quantityKg,
    String fulfillmentMethod = 'pickup',
    String? deliveryAddress,
    double? deliveryLatitude,
    double? deliveryLongitude,
    String? deliveryContactNumber,
    String? deliveryNotes,
    String? deliveryRecipientName,
    String? deliveryLabel,
    String? requestId,
    String? groupId,
  }) async {
    calls.add({
      'listing': listingId,
      'qty': quantityKg,
      'method': fulfillmentMethod,
      'address': deliveryAddress,
      'requestId': requestId,
      'groupId': groupId,
    });
    if (failFirst != null) {
      final e = failFirst!;
      failFirst = null;
      throw e;
    }
    return 'order-$listingId';
  }
}

class _Coop extends CooperativeOrderRepository {
  final calls = <Map<String, Object?>>[];
  @override
  Future<PlacedProgramOrder> placeOrder({
    required String programId,
    required String productId,
    required double quantity,
    required String fulfillmentMethod,
    required String requestId,
    String? groupId,
  }) async {
    calls.add({
      'program': programId,
      'product': productId,
      'qty': quantity,
      'method': fulfillmentMethod,
      'requestId': requestId,
      'groupId': groupId,
    });
    return PlacedProgramOrder(
      orderId: 'coop-$productId',
      orderNumber: 'PSO-20261106-A001',
      totalAmount: 90,
      existing: false,
    );
  }
}

class _Delivery extends CooperativeDeliveryRepository {
  _Delivery({
    this.status = DeliveryStatus.off,
    this.quote,
    this.quoteError,
    this.details = const CooperativeDetails(
      cooperativeName: 'SP3 Agriculture Cooperative',
    ),
  });
  final CooperativeDetails details;
  final DeliveryStatus status;
  final DeliveryQuote? quote;
  final Object? quoteError;
  final groupCalls = <Map<String, String>>[];
  @override
  Future<DeliveryStatus> fetchDeliveryStatus() async => status;
  @override
  Future<CooperativeDetails> fetchDetails() async => details;
  @override
  Future<DeliveryQuote> fetchQuote(String addressId) async {
    if (quoteError != null) throw quoteError!;
    return quote!;
  }

  @override
  Future<CheckoutGroupResult> createCheckoutGroup({
    required String addressId,
    required String requestId,
  }) async {
    groupCalls.add({'addressId': addressId, 'requestId': requestId});
    return CheckoutGroupResult(
      groupId: 'group-1',
      deliveryFee: quote?.fee ?? 0,
      distanceKm: quote?.distanceKm ?? 0,
    );
  }
}

class _Addresses extends BuyerAddressRepository {
  _Addresses(this.list);
  final List<BuyerAddressModel> list;
  @override
  Future<List<BuyerAddressModel>> fetchAddresses() async => list;
}

class _Cart extends CartService {
  final removed = <String>[];
  @override
  Future<void> removeItem(String listingId) async => removed.add(listingId);
}

BuyerAddressModel _address({bool pin = true}) => BuyerAddressModel(
  id: 'addr-1',
  userId: 'u1',
  label: 'Home',
  recipientName: 'Maria Santos',
  contactNumber: '09171234567',
  addressLine: 'Purok 2, Payanas, Torrijos, Marinduque',
  latitude: pin ? 13.32 : null,
  longitude: pin ? 122.04 : null,
  isDefault: true,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
);

CartItemModel _market({String id = 'l1', double qty = 2}) => CartItemModel(
  listingId: id,
  cropName: 'Tomato',
  pricePerKg: 30,
  unit: 'kg',
  availableKgSnapshot: 50,
  quantityKg: qty,
  marketType: 'public',
);

CartItemModel _coopLine({String id = 'pp1', double qty = 2}) => CartItemModel(
  listingId: id,
  cropName: 'Peanut Cookies',
  pricePerKg: 45,
  unit: 'pack',
  availableKgSnapshot: 20,
  quantityKg: qty,
  source: kCartSourceCooperative,
  programId: 'prog-1',
  programName: 'Peanut Cookies Sale',
  regularPrice: 50,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_checkout');
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
    // Letters take real room (not the solid blocks tests draw), so lines wrap as on a phone.
    await loadStandInFonts();
  });

  Object? successExtra;
  String? landedOn;

  Future<void> open(
    WidgetTester tester, {
    required List<CartItemModel> items,
    required bool cart,
    bool farmer = false,
    required _Market market,
    required _Coop coop,
    required _Delivery delivery,
    required _Cart cartService,
    BuyerAddressModel? address,
  }) async {
    successExtra = null;
    landedOn = null;
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/checkout',
      routes: [
        GoRoute(
          path: '/checkout',
          builder: (c, s) => CheckoutScreen(
            items: items,
            isCartCheckout: cart,
            isFarmerContext: farmer,
            marketRepo: market,
            addressRepo: _Addresses([address ?? _address()]),
            deliveryRepo: delivery,
            coopRepo: coop,
            cartService: cartService,
          ),
        ),
        for (final path in [
          AppRoutes.orderSuccess,
          AppRoutes.farmerMarketplaceOrderSuccess,
          AppRoutes.cartCheckoutResult,
          AppRoutes.farmerMarketplaceCartResult,
        ])
          GoRoute(
            path: path,
            builder: (c, s) {
              successExtra = s.extra;
              landedOn = path;
              return const Scaffold(body: Text('RESULT'));
            },
          ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  Future<void> placeOrder(WidgetTester tester) async {
    final l10n = l10nOf(tester);
    final button = find.text(l10n.checkoutPlaceOrder);
    await tester.tap(button);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  PrimaryButton placeButton(WidgetTester tester) =>
      tester.widget<PrimaryButton>(
        find
            .ancestor(
              of: find.text(l10nOf(tester).checkoutPlaceOrder),
              matching: find.byType(PrimaryButton),
            )
            .first,
      );

  group('the Buyer\'s checkout is unchanged', () {
    testWidgets(
      'Delivery switched OFF: a Buyer is offered Pickup only, with a note, and the order is a pickup order',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final market = _Market();
          final delivery = _Delivery(); // Delivery off
          final line = _market();
          await open(
            tester,
            items: [line],
            cart: false,
            market: market,
            coop: _Coop(),
            delivery: delivery,
            cartService: _Cart(),
          );
          final l10n = l10nOf(tester);
          expect(find.byKey(const Key('deliveryOffNote')), findsOneWidget);
          expect(find.text(l10n.uoCheckoutDeliveryOff), findsOneWidget);
          await tester.tap(find.text(l10n.checkoutFulfillmentDelivery));
          await tester.pump();
          expect(find.byKey(const Key('deliveryFeeRow')), findsNothing);
          expect(find.byKey(const Key('quoteCard')), findsNothing);
          expect(
            find.text(l10n.checkoutPickupAt),
            findsOneWidget,
          ); // still Pickup
          await placeOrder(tester);
          expect(market.calls.single['method'], 'pickup');
          expect(market.calls.single['address'], isNull);
          expect(market.calls.single['groupId'], isNull);
          expect(market.calls.single['requestId'], line.requestId);
          expect(delivery.groupCalls, isEmpty);
          expect(landedOn, AppRoutes.orderSuccess);
          expect(successExtra, ['order-l1']);
        });
      },
    );

    testWidgets(
      'Pickup switched OFF (Delivery on): only Delivery is offered, selected for you, with a note',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final market = _Market();
          final delivery = _Delivery(
            status: DeliveryStatus.fromMap({
              'enabled': true,
              'ready': true,
              'pickup_enabled': false,
              'missing': [],
            }),
            quote: const DeliveryQuote(
              distanceKm: 1,
              fee: 20,
              bandMinKm: 0,
              bandMaxKm: 2,
            ),
          );
          await open(
            tester,
            items: [_market()],
            cart: false,
            market: market,
            coop: _Coop(),
            delivery: delivery,
            cartService: _Cart(),
          );
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
          final l10n = l10nOf(tester);
          expect(find.byKey(const Key('pickupOffNote')), findsOneWidget);
          expect(find.text(l10n.uoCheckoutPickupOff), findsOneWidget);
          expect(
            find.byKey(const Key('quoteCard')),
            findsOneWidget,
          ); // Delivery was selected for them
          await tester.tap(find.text(l10n.checkoutFulfillmentPickup));
          await tester.pump();
          expect(
            find.byKey(const Key('quoteCard')),
            findsOneWidget,
          ); // the Pickup chip does nothing
          await placeOrder(tester);
          expect(market.calls.single['method'], 'delivery');
          expect(market.calls.single['groupId'], 'group-1');
        });
      },
    );

    testWidgets('Pickup is always available and has no fee', (tester) async {
      await runIgnoringFontErrors(() async {
        final market = _Market();
        await open(
          tester,
          items: [_market()],
          cart: false,
          market: market,
          coop: _Coop(),
          delivery: _Delivery(),
          cartService: _Cart(),
        );
        await placeOrder(tester);
        expect(market.calls.single['method'], 'pickup');
        expect(market.calls.single['address'], isNull);
      });
    });

    testWidgets(
      'a Marketplace-only cart never calls the Cooperative order function',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final market = _Market();
          final coop = _Coop();
          final cart = _Cart();
          await open(
            tester,
            items: [
              _market(id: 'l1'),
              _market(id: 'l2'),
            ],
            cart: true,
            market: market,
            coop: coop,
            delivery: _Delivery(),
            cartService: cart,
          );
          await placeOrder(tester);
          expect(market.calls.map((c) => c['listing']), ['l1', 'l2']);
          expect(coop.calls, isEmpty);
          expect(cart.removed, ['l1', 'l2']);
          expect(successExtra, ['order-l1', 'order-l2']);
        });
      },
    );
  });

  group('a Farmer\'s mixed cart', () {
    testWidgets(
      'each line goes through its own source with the line\'s own request id; the cart empties',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final market = _Market();
          final coop = _Coop();
          final cart = _Cart();
          final a = _market();
          final b = _coopLine();
          await open(
            tester,
            items: [a, b],
            cart: true,
            farmer: true,
            market: market,
            coop: coop,
            delivery: _Delivery(),
            cartService: cart,
          );
          await placeOrder(tester);
          expect(market.calls.length, 1);
          expect(market.calls.single['requestId'], a.requestId);
          expect(coop.calls.length, 1);
          expect(coop.calls.single['program'], 'prog-1');
          expect(coop.calls.single['product'], 'pp1');
          expect(coop.calls.single['qty'], 2);
          expect(coop.calls.single['method'], 'pickup');
          expect(coop.calls.single['requestId'], b.requestId);
          expect(a.requestId == b.requestId, isFalse);
          expect(cart.removed, ['l1', 'pp1']);
          expect(landedOn, AppRoutes.farmerMarketplaceOrderSuccess);
          // The success screen is told which is which: a Cooperative order carries its prefix.
          expect(successExtra, ['order-l1', 'pso:coop-pp1']);
        });
      },
    );

    testWidgets(
      'a Cooperative Product on its own (Buy Now) is placed the same way',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final coop = _Coop();
          final line = _coopLine(qty: 3);
          await open(
            tester,
            items: [line],
            cart: false,
            farmer: true,
            market: _Market(),
            coop: coop,
            delivery: _Delivery(),
            cartService: _Cart(),
          );
          await placeOrder(tester);
          expect(coop.calls.single['qty'], 3);
          expect(coop.calls.single['requestId'], line.requestId);
          expect(successExtra, ['pso:coop-pp1']);
        });
      },
    );

    testWidgets(
      'while the delivery rules are off, Delivery is not offered for Cooperative Products and a note says so',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final coop = _Coop();
          await open(
            tester,
            items: [_coopLine()],
            cart: false,
            farmer: true,
            market: _Market(),
            coop: coop,
            delivery: _Delivery(),
            cartService: _Cart(),
          );
          final l10n = l10nOf(tester);
          expect(find.byKey(const Key('deliveryOffNote')), findsOneWidget);
          expect(find.text(l10n.uoCheckoutDeliveryOff), findsOneWidget);
          await tester.tap(find.text(l10n.checkoutFulfillmentDelivery));
          await tester.pump();
          // Still Pickup: the chip does nothing.
          expect(find.text(l10n.checkoutPickupAt), findsOneWidget);
          await placeOrder(tester);
          expect(coop.calls.single['method'], 'pickup');
        });
      },
    );

    for (final (who, farmer, line)
        in <(String, bool, CartItemModel Function())>[
          ('a Buyer, Marketplace product', false, _market),
          ('a Farmer, Marketplace product', true, _market),
          ('a Farmer, Cooperative product', true, _coopLine),
        ]) {
      testWidgets(
        'Pickup shows the address saved in Cooperative Details, not a typed-in one: $who',
        (tester) async {
          await runIgnoringFontErrors(() async {
            // A postal code the app has never heard of proves nothing is hardcoded.
            const saved = CooperativeDetails(
              cooperativeName: 'SP3 Agriculture Cooperative',
              postalCode: '4999',
            );
            await open(
              tester,
              items: [line()],
              cart: false,
              farmer: farmer,
              market: _Market(),
              coop: _Coop(),
              delivery: _Delivery(details: saved),
              cartService: _Cart(),
            );
            final l10n = l10nOf(tester);
            expect(find.text(l10n.checkoutPickupAt), findsOneWidget);
            expect(
              tester.widget<Text>(find.byKey(const Key('pickupAddress'))).data,
              'Barangay Payanas, Torrijos, Marinduque, MIMAROPA Region, 4999',
            );
            expect(find.text(saved.addressLine), findsOneWidget);
          });
        },
      );
    }

    testWidgets(
      'the pickup card shows the cooperative and never a placeholder number',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(
            tester,
            items: [_coopLine()],
            cart: false,
            farmer: true,
            market: _Market(),
            coop: _Coop(),
            delivery: _Delivery(),
            cartService: _Cart(),
          );
          expect(find.text('SP3 Agriculture Cooperative'), findsOneWidget);
          expect(find.byKey(const Key('pickupContact')), findsNothing);
        });
      },
    );
  });

  group('delivery with the rules on: one group, one fee', () {
    final on = DeliveryStatus.fromMap({
      'enabled': true,
      'ready': true,
      'allowed_barangay_codes': ['1704006019'],
      'missing': [],
    });
    const quote = DeliveryQuote(
      distanceKm: 1.25,
      fee: 35,
      bandMinKm: 0,
      bandMaxKm: 2,
    );

    testWidgets(
      'the fee is shown once and added to the total, apart from the items',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(
            tester,
            items: [
              _market(id: 'l1'),
              _coopLine(),
            ],
            cart: true,
            farmer: true,
            market: _Market(),
            coop: _Coop(),
            delivery: _Delivery(status: on, quote: quote),
            cartService: _Cart(),
          );
          final l10n = l10nOf(tester);
          await tester.tap(find.text(l10n.checkoutFulfillmentDelivery));
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.byKey(const Key('quoteCard')), findsOneWidget);
          expect(find.byKey(const Key('deliveryFeeRow')), findsOneWidget);
          // 2 kg x 30 + 2 pack x 45 = 150 for the items, + 35 once.
          expect(
            tester.widget<Text>(find.byKey(const Key('grandTotal'))).data,
            '₱185.00',
          );
        });
      },
    );

    testWidgets(
      'both lines carry the SAME group, created once from the saved address',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final market = _Market();
          final coop = _Coop();
          final delivery = _Delivery(status: on, quote: quote);
          await open(
            tester,
            items: [
              _market(id: 'l1'),
              _coopLine(),
            ],
            cart: true,
            farmer: true,
            market: market,
            coop: coop,
            delivery: delivery,
            cartService: _Cart(),
          );
          await tester.tap(
            find.text(l10nOf(tester).checkoutFulfillmentDelivery),
          );
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
          await placeOrder(tester);
          expect(delivery.groupCalls.length, 1);
          expect(delivery.groupCalls.single['addressId'], 'addr-1');
          expect(market.calls.single['groupId'], 'group-1');
          expect(coop.calls.single['groupId'], 'group-1');
          expect(market.calls.single['method'], 'delivery');
          expect(coop.calls.single['method'], 'delivery');
        });
      },
    );

    testWidgets(
      'Buy Now (one item) makes a group too: the same as Add to Cart',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final coop = _Coop();
          final delivery = _Delivery(status: on, quote: quote);
          await open(
            tester,
            items: [_coopLine()],
            cart: false,
            farmer: true,
            market: _Market(),
            coop: coop,
            delivery: delivery,
            cartService: _Cart(),
          );
          await tester.tap(
            find.text(l10nOf(tester).checkoutFulfillmentDelivery),
          );
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
          await placeOrder(tester);
          expect(delivery.groupCalls.length, 1);
          expect(coop.calls.single['groupId'], 'group-1');
        });
      },
    );

    testWidgets('pickup with the rules on makes no group and pays no fee', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final market = _Market();
        final delivery = _Delivery(status: on, quote: quote);
        await open(
          tester,
          items: [_market()],
          cart: false,
          market: market,
          coop: _Coop(),
          delivery: delivery,
          cartService: _Cart(),
        );
        await placeOrder(tester);
        expect(delivery.groupCalls, isEmpty);
        expect(market.calls.single['groupId'], isNull);
        expect(find.byKey(const Key('deliveryFeeRow')), findsNothing);
      });
    });

    testWidgets(
      'an address outside Payanas is refused with the reason, and the order cannot be placed',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(
            tester,
            items: [_market()],
            cart: false,
            market: _Market(),
            coop: _Coop(),
            delivery: _Delivery(
              status: on,
              quoteError: Exception(
                'OUTSIDE_AREA: We deliver only within Barangay Payanas.',
              ),
            ),
            cartService: _Cart(),
          );
          final l10n = l10nOf(tester);
          await tester.tap(find.text(l10n.checkoutFulfillmentDelivery));
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.byKey(const Key('quoteProblem')), findsOneWidget);
          expect(find.text(l10n.errOutsideArea), findsOneWidget);
          expect(placeButton(tester).onPressed, isNull);
        });
      },
    );

    testWidgets(
      'an address with no map pin is told to add one, and nothing is charged',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final delivery = _Delivery(
            status: on,
            quoteError: Exception(
              'NO_PIN: Add the delivery location on the map',
            ),
          );
          await open(
            tester,
            items: [_market()],
            cart: false,
            market: _Market(),
            coop: _Coop(),
            delivery: delivery,
            cartService: _Cart(),
            address: _address(pin: false),
          );
          final l10n = l10nOf(tester);
          await tester.tap(find.text(l10n.checkoutFulfillmentDelivery));
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.text(l10n.errNoPin), findsOneWidget);
          expect(find.byKey(const Key('editAddressForPin')), findsOneWidget);
          expect(placeButton(tester).onPressed, isNull);
          expect(
            find.byKey(const Key('deliveryFeeRow')),
            findsNothing,
          ); // never silently zero
        });
      },
    );
  });

  group('duplicate protection', () {
    testWidgets(
      'a retry after a failure sends the SAME request id for the line and for the delivery group',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final on = DeliveryStatus.fromMap({
            'enabled': true,
            'ready': true,
            'missing': [],
          });
          const quote = DeliveryQuote(
            distanceKm: 1,
            fee: 20,
            bandMinKm: 0,
            bandMaxKm: 2,
          );
          final market = _Market()
            ..failFirst = Exception(
              'Not enough stock available. Only 1 kg remaining.',
            );
          final delivery = _Delivery(status: on, quote: quote);
          final line = _market();
          await open(
            tester,
            items: [line],
            cart: false,
            market: market,
            coop: _Coop(),
            delivery: delivery,
            cartService: _Cart(),
          );
          await tester.tap(
            find.text(l10nOf(tester).checkoutFulfillmentDelivery),
          );
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
          await placeOrder(tester); // fails
          expect(landedOn, isNull);
          expect(
            find.text(l10nOf(tester).errNoStock),
            findsOneWidget,
          ); // the database refusal, in the person's own language
          await placeOrder(tester); // retried
          expect(market.calls.length, 2);
          expect(market.calls[0]['requestId'], market.calls[1]['requestId']);
          expect(market.calls[1]['requestId'], line.requestId);
          expect(delivery.groupCalls.length, 2);
          expect(
            delivery.groupCalls[0]['requestId'],
            delivery.groupCalls[1]['requestId'],
          );
          expect(landedOn, AppRoutes.orderSuccess);
        });
      },
    );

    testWidgets(
      'a second tap while the order is being placed does not place it twice',
      (tester) async {
        await runIgnoringFontErrors(() async {
          final market = _Market();
          await open(
            tester,
            items: [_market()],
            cart: false,
            market: market,
            coop: _Coop(),
            delivery: _Delivery(),
            cartService: _Cart(),
          );
          final l10n = l10nOf(tester);
          await tester.tap(find.text(l10n.checkoutPlaceOrder));
          await tester.tap(
            find.text(l10n.checkoutPlaceOrder),
            warnIfMissed: false,
          );
          for (var i = 0; i < 6; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 150));
          }
          expect(market.calls.length, 1);
        });
      },
    );
  });
}
