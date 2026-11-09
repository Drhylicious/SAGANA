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
import 'package:sagana/data/models/cooperative_product_model.dart';
import 'package:sagana/data/repositories/buyer_address_repository.dart';
import 'package:sagana/data/repositories/buyer_marketplace_repository.dart';
import 'package:sagana/data/repositories/cooperative_delivery_repository.dart';
import 'package:sagana/data/repositories/cooperative_order_repository.dart';
import 'package:sagana/data/services/cart_service.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/data/services/staff_permission_service.dart';
import 'package:sagana/presentation/screens/admin/admin_program_order_detail_screen.dart';
import 'package:sagana/presentation/screens/admin/cooperative_details_screen.dart';
import 'package:sagana/presentation/screens/admin/delivery_settings_screen.dart';
import 'package:sagana/presentation/screens/admin/order_management_screen.dart';
import 'package:sagana/presentation/screens/buyer/checkout_screen.dart';
import 'package:sagana/presentation/screens/farmer/cooperative_product_details_screen.dart';
import 'package:sagana/presentation/screens/farmer/farmer_program_order_detail_screen.dart';
import 'package:sagana/presentation/widgets/order_payment_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/ignore_font_errors.dart';
import 'support/stand_in_fonts.dart';
import 'support/test_storage_mocks.dart';

/// Every new screen on a small phone, a normal phone and a tablet, at normal and enlarged text,
/// in English and Tagalog: nothing overflows or is cut off. (Letters take real room here, as on a
/// phone: the solid blocks tests draw by default would overflow anywhere.)

class _Device {
  const _Device(this.name, this.size, this.scale);
  final String name;
  final Size size;
  final double scale;
}

const _devices = [
  _Device('small phone 320x568, text x1.0', Size(320, 568), 1.0),
  _Device('phone 360x640, text x1.3', Size(360, 640), 1.3),
  _Device('phone 412x915, text x1.0', Size(412, 915), 1.0),
  _Device('tablet 600x960, text x2.0', Size(600, 960), 2.0),
];

Map<String, Object?> _coop({
  String status = 'out_for_delivery',
  String method = 'delivery',
  String payment = 'unpaid',
}) => {
  'id': 'c1',
  'program_id': 'p1',
  'program_name': 'Peanut Cookies Sale',
  'product_id': 'pp1',
  'item_name': 'Peanut Cookies with Extra Long Name',
  'unit': 'pack',
  'farmer_id': 'f1',
  'farmer_name': 'Maria Clara Santos Dela Cruz',
  'quantity': 12.5,
  'unit_price': 45,
  'total_amount': 562.5,
  'regular_unit_price': 50,
  'discount_percent': 10,
  'discount_amount': 62.5,
  'is_member_price': true,
  'status': status,
  'requested_at': '2026-11-06T10:00:00Z',
  'order_number': 'PSO-20261106-A001',
  'fulfillment_method': method,
  'payment_status': payment,
  'checkout_group_id': 'g1',
  'delivery_address':
      'Purok 2, Sitio Malinao, Barangay Payanas, Torrijos, Marinduque',
  'delivery_contact': '09171234567',
  'delivery_recipient': 'Maria Clara Santos Dela Cruz',
  'amount_collected': payment == 'paid' ? 587.5 : null,
  'delivery_fee_collected': payment == 'paid' ? 25 : 0,
  'completion_method': 'staff',
  'staff_completion_reason':
      'The member has no phone signal at home, so the order was completed at the counter.',
  'payment_recorded_by_name': 'Ana Reyes',
  'payment_recorded_by_role': 'officer',
};

class _Market extends BuyerMarketplaceRepository {
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
  }) async => 'x';
}

class _Delivery extends CooperativeDeliveryRepository {
  @override
  Future<DeliveryStatus> fetchDeliveryStatus() async => DeliveryStatus.fromMap({
    'enabled': true,
    'ready': true,
    'allowed_barangay_codes': ['1704006019'],
    'missing': [],
  });
  @override
  Future<CooperativeDetails> fetchDetails() async =>
      const CooperativeDetails(cooperativeName: 'SP3 Agriculture Cooperative');
  @override
  Future<DeliveryQuote> fetchQuote(String addressId) async =>
      const DeliveryQuote(
        distanceKm: 12.34,
        fee: 1250.5,
        bandMinKm: 10,
        bandMaxKm: 15,
      );
}

class _Addresses extends BuyerAddressRepository {
  @override
  Future<List<BuyerAddressModel>> fetchAddresses() async => [
    BuyerAddressModel(
      id: 'a1',
      userId: 'u',
      label: 'Home',
      recipientName: 'Maria Clara Santos Dela Cruz',
      contactNumber: '09171234567',
      addressLine:
          'Purok 2, Sitio Malinao, Barangay Payanas, Torrijos, Marinduque, MIMAROPA Region',
      latitude: 13.3,
      longitude: 122.0,
      isDefault: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];
}

class _Cart extends CartService {
  @override
  Future<void> removeItem(String listingId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_unified_layout');
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

  Future<void> show(
    WidgetTester tester,
    _Device d,
    Locale locale,
    Widget home,
  ) async {
    tester.view.physicalSize = d.size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(d.scale)),
          child: child!,
        ),
        home: home,
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  void routes() {
    fake.reset();
    fake.on(
      'GET /rest/v1/orders',
      (_) => const FakeError(500, 'not part of this test'),
    );
    fake.on(
      'GET /rest/v1/user_information',
      (_) => [
        {'user_id': 'f1', 'full_name': 'Maria Clara Santos Dela Cruz'},
      ],
    );
    fake.on(
      'GET /rest/v1/program_product_purchases',
      (_) => [_coop(), _coop(status: 'delivered', payment: 'paid')],
    );
    fake.on(
      'GET /rest/v1/checkout_groups',
      (_) => [
        {'delivery_fee': 25, 'fee_collected_at': null},
      ],
    );
    fake.on(
      'POST /rest/v1/rpc/get_cooperative_details',
      (_) => {
        'cooperative_name': 'SP3 Agriculture Cooperative',
        'barangay_name': 'Payanas',
        'city_municipality_name': 'Torrijos',
        'province_name': 'Marinduque',
        'region_name': 'MIMAROPA Region',
        'postal_code': '4903',
        'sitio_purok': 'Purok 3, Sitio Malinao',
        'address_notes': 'Beside the barangay hall, across the covered court',
        'contact_number': '09171234567',
        'contact_is_placeholder': false,
        'contact_verified': false,
        'latitude': 13.32,
        'longitude': 122.04,
      },
    );
    fake.on(
      'POST /rest/v1/rpc/get_delivery_status',
      (_) => {
        'enabled': false,
        'ready': false,
        'allowed_barangay_codes': ['1704006019'],
        'missing': ['cooperative_pin', 'contact_verified', 'fee_bands'],
      },
    );
    fake.on(
      'GET /rest/v1/delivery_fee_bands',
      (_) => [
        {
          'min_km': 0,
          'max_km': 1.5,
          'fee': 20,
          'is_demo': false,
          'set_version': 1,
        },
        {
          'min_km': 1.5,
          'max_km': 3,
          'fee': 35,
          'is_demo': false,
          'set_version': 1,
        },
        {
          'min_km': 3,
          'max_km': 5,
          'fee': 60,
          'is_demo': false,
          'set_version': 1,
        },
      ],
    );
  }

  final product = CooperativeProduct.fromRow({
    'id': 'pp1',
    'program_id': 'p1',
    'unit_price': 50,
    'is_available': true,
    'stock_allocated': 20,
    'stock_reserved': 5,
    'cooperative_inventory': {
      'item_name': 'Peanut Cookies with Extra Long Name',
      'category': 'Harvest Stock',
      'unit': 'pack',
      'image_url': null,
    },
    'cooperative_programs': {
      'program_name': 'Peanut Cookies Sale with a Long Program Name',
      'member_discount_percent': 10,
      'status': 'active',
      'program_purpose': 'sales',
    },
  }, isMember: false)!;

  final screens = <String, Widget Function()>{
    'staff order list': () => const OrderManagementScreen(),
    'staff Cooperative order (delivery, out)': () =>
        AdminProgramOrderDetailScreen(key: UniqueKey(), orderId: 'c1'),
    'Farmer Cooperative order': () =>
        FarmerProgramOrderDetailScreen(key: UniqueKey(), orderId: 'c1'),
    'Cooperative Details': () => const CooperativeDetailsScreen(),
    'Delivery Settings': () => const DeliverySettingsScreen(),
    'Cooperative Product page': () =>
        CooperativeProductDetailsScreen(product: product),
    'payment cards': () => Scaffold(
      body: ListView(
        children: [
          const OrderPaymentCard(
            paymentStatus: 'paid',
            itemsTotal: 562.5,
            amountCollected: 587.5,
            deliveryFee: 25,
            recordedByName: 'Ana Reyes',
            recordedByRole: 'officer',
            staffView: true,
          ),
          StaffCompletionCard(
            reason:
                'The member has no phone signal at home, so the order was completed at the counter.',
            byName: 'Ana Reyes',
            byRole: 'admin',
            at: DateTime(2026, 11, 6, 14),
          ),
          const WaitingForPaymentCard(),
        ],
      ),
    ),
  };

  for (final d in _devices) {
    for (final locale in const [Locale('en'), Locale('tl')]) {
      for (final entry in screens.entries) {
        testWidgets('${entry.key}: ${d.name}, ${locale.languageCode}', (
          tester,
        ) async {
          await runIgnoringFontErrors(() async {
            routes();
            await tester.runAsync(
              () => HiveService.saveUserSession(
                userId: 'u-admin',
                email: 'x@y.z',
                role: 'admin',
              ),
            );
            StaffPermissions.instance.debugSet(const {});
            await show(tester, d, locale, entry.value());
            expect(tester.takeException(), isNull);
          });
        });
      }

      testWidgets(
        'checkout with the delivery fee: ${d.name}, ${locale.languageCode}',
        (tester) async {
          await runIgnoringFontErrors(() async {
            routes();
            final items = [
              CartItemModel(
                listingId: 'l1',
                cropName: 'Tomato (a variety with a long name)',
                pricePerKg: 30,
                unit: 'kg',
                availableKgSnapshot: 50,
                quantityKg: 12.5,
                marketType: 'public',
              ),
              CartItemModel(
                listingId: 'pp1',
                cropName: 'Peanut Cookies with Extra Long Name',
                pricePerKg: 45,
                unit: 'pack',
                availableKgSnapshot: 20,
                quantityKg: 12.5,
                source: kCartSourceCooperative,
                programId: 'p1',
                programName: 'Peanut Cookies Sale',
              ),
            ];
            final router = GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (c, s) => CheckoutScreen(
                    items: items,
                    isCartCheckout: true,
                    isFarmerContext: true,
                    marketRepo: _Market(),
                    addressRepo: _Addresses(),
                    deliveryRepo: _Delivery(),
                    coopRepo: CooperativeOrderRepository(),
                    cartService: _Cart(),
                  ),
                ),
              ],
            );
            tester.view.physicalSize = d.size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              MaterialApp.router(
                theme: AppTheme.lightTheme,
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(d.scale)),
                  child: child!,
                ),
                routerConfig: router,
              ),
            );
            for (var i = 0; i < 6; i++) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 25)),
              );
              await tester.pump(const Duration(milliseconds: 150));
            }
            final l10n = AppLocalizations.of(
              tester.element(find.byType(Scaffold).first),
            );
            await tester.ensureVisible(
              find.text(l10n.checkoutFulfillmentDelivery),
            );
            await tester.tap(find.text(l10n.checkoutFulfillmentDelivery));
            for (var i = 0; i < 4; i++) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 25)),
              );
              await tester.pump(const Duration(milliseconds: 150));
            }
            await tester.scrollUntilVisible(
              find.byKey(const Key('deliveryFeeRow')),
              300,
              scrollable: find.byType(Scrollable).first,
            );
            expect(find.byKey(const Key('deliveryFeeRow')), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        },
      );
    }
  }
}
