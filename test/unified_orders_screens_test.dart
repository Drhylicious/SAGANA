import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/data/services/staff_permission_service.dart';
import 'package:sagana/presentation/screens/admin/admin_program_order_detail_screen.dart';
import 'package:sagana/presentation/screens/admin/cooperative_details_screen.dart';
import 'package:sagana/presentation/screens/admin/delivery_settings_screen.dart';
import 'package:sagana/presentation/screens/admin/order_management_screen.dart';
import 'package:sagana/presentation/widgets/listing_filter_modal.dart'
    show ListingStatusFilterChip;
import 'package:sagana/presentation/widgets/order_payment_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

/// The staff screens of the unified orders, with the REAL repositories over a fake network:
/// the one order list, the Cooperative order steps (and what a View Only Officer cannot do),
/// the cash and assisted-completion dialogs, Cooperative Details and Delivery Settings.

Map<String, Object?> _coop({
  String id = 'c1',
  String status = 'pending',
  String method = 'pickup',
  String payment = 'unpaid',
  String number = 'PSO-20261106-A001',
  String requested = '2026-11-06T10:00:00Z',
  String? group,
  num total = 90,
}) => {
  'id': id,
  'program_id': 'p1',
  'program_name': 'Peanut Cookies Sale',
  'product_id': 'pp1',
  'item_name': 'Peanut Cookies',
  'unit': 'pack',
  'farmer_id': 'f1',
  'quantity': 2,
  'unit_price': 45,
  'total_amount': total,
  'regular_unit_price': 50,
  'discount_percent': 10,
  'discount_amount': 10,
  'is_member_price': true,
  'status': status,
  'requested_at': requested,
  'order_number': number,
  'fulfillment_method': method,
  'payment_status': payment,
  'checkout_group_id': group,
  if (method == 'delivery') ...{
    'delivery_address': 'Purok 2, Payanas, Torrijos, Marinduque',
    'delivery_contact': '09171234567',
    'delivery_recipient': 'Maria Santos',
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_unified_orders');
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
  });

  Future<void> signIn(
    WidgetTester tester,
    String role, {
    Map<StaffModule, StaffAccess> access = const {},
  }) async {
    await tester.runAsync(
      () => HiveService.saveUserSession(
        userId: 'u-$role',
        email: 'x@y.z',
        role: role,
      ),
    );
    StaffPermissions.instance.debugSet(access);
  }

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(420, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Keeps pumping (with real time for the fake network) until [finder] shows up.
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  // ── the one order list ────────────────────────────────────────────────────
  // The Marketplace half of this list is read through the offline snapshot (real file storage), which
  // is not the subject here and is covered with the merge logic in unified_orders_logic_test.dart. The
  // Marketplace read is therefore answered with an error and the Cooperative orders are what is shown.
  group('Order Management: the Cooperative orders in the staff list', () {
    Future<void> openList(WidgetTester tester) async {
      fake.reset();
      fake.on(
        'GET /rest/v1/orders',
        (_) => const FakeError(500, 'not part of this test'),
      );
      fake.on(
        'GET /rest/v1/user_information',
        (_) => [
          {'user_id': 'f1', 'full_name': 'Maria Santos'},
        ],
      );
      fake.on(
        'GET /rest/v1/program_product_purchases',
        (_) => [
          _coop(
            id: 'c1',
            status: 'ready_for_pickup',
            requested: '2026-11-06T10:00:00Z',
          ),
          _coop(
            id: 'c2',
            status: 'approved',
            requested: '2026-11-04T10:00:00Z',
            number: 'PSO-20261104-A002',
          ),
          _coop(
            id: 'c3',
            status: 'delivered',
            method: 'delivery',
            payment: 'paid',
            requested: '2026-11-03T10:00:00Z',
            number: 'PSO-20261103-A003',
          ),
          _coop(
            id: 'c4',
            status: 'completed',
            payment: 'paid',
            requested: '2026-11-02T10:00:00Z',
            number: 'PSO-20261102-A004',
          ),
        ],
      );
      await signIn(tester, 'admin');
      // Wide, so every chip of the horizontal rows is built.
      await pump(
        tester,
        const OrderManagementScreen(),
        size: const Size(2600, 1600),
      );
      await waitFor(tester, find.byKey(const Key('orderRow_c4')));
    }

    testWidgets(
      'each order shows its PSO number, its source badge, the item and the member',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openList(tester);
          expect(find.byKey(const Key('orderRow_c1')), findsOneWidget);
          expect(
            find.byKey(const Key('sourceBadge_cooperative')),
            findsNWidgets(4),
          );
          expect(find.text('PSO-20261106-A001'), findsOneWidget);
          expect(find.text('Peanut Cookies · 2 pack'), findsNWidgets(4));
          expect(find.text('Maria Santos'), findsNWidgets(4));
        });
      },
    );

    testWidgets(
      'there is ONE filter button beside the search bar (no separate source chips); it opens a modal with the three sources',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openList(tester);
          final l10n = l10nOf(tester);
          expect(
            find.byKey(const Key('sourceFilter')),
            findsNothing,
          ); // the old chip row is gone
          expect(find.byKey(const Key('orderFilterButton')), findsOneWidget);
          expect(
            find.byKey(const Key('orderFilterDot')),
            findsNothing,
          ); // nothing filtered yet
          await tester.tap(find.byKey(const Key('orderFilterButton')));
          await tester.pumpAndSettle();
          expect(find.text(l10n.omFilterTitle), findsOneWidget);
          expect(find.text('${l10n.uoSourceAll} (4)'), findsOneWidget);
          expect(find.text('${l10n.uoSourceMarketplace} (0)'), findsOneWidget);
          expect(find.text('${l10n.uoSourceCooperative} (4)'), findsOneWidget);
        });
      },
    );

    testWidgets(
      'choosing a source and applying narrows the list, and the button shows it is active',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openList(tester);
          final l10n = l10nOf(tester);
          await tester.tap(find.byKey(const Key('orderFilterButton')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('filterChoice_marketplace')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('filterApply')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('orderRow_c1')),
            findsNothing,
          ); // no Marketplace order here
          expect(find.byKey(const Key('orderFilterDot')), findsOneWidget);
          // Back to everything with Reset.
          await tester.tap(find.byKey(const Key('orderFilterButton')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('filterReset')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('filterApply')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('orderRow_c1')), findsOneWidget);
          expect(find.byKey(const Key('orderFilterDot')), findsNothing);
          expect(find.text(l10n.omFilterTitle), findsNothing);
        });
      },
    );

    testWidgets('dismissing the modal changes nothing', (tester) async {
      await runIgnoringFontErrors(() async {
        await openList(tester);
        await tester.tap(find.byKey(const Key('orderFilterButton')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('filterChoice_marketplace')));
        await tester.pump();
        await tester.tapAt(const Offset(5, 5)); // outside the modal
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('orderRow_c1')), findsOneWidget);
        expect(find.byKey(const Key('orderFilterDot')), findsNothing);
      });
    });

    testWidgets(
      'a settings icon at the top right opens Delivery Settings (a Manager and an Officer both see it)',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openList(tester);
          expect(find.byKey(const Key('orderSettings')), findsOneWidget);
          expect(
            tester
                .widget<IconButton>(find.byKey(const Key('orderSettings')))
                .tooltip,
            l10nOf(tester).dsTitle,
          );
        });
      },
    );

    testWidgets('six status chips and Needs Action: there is no Delivered chip', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await openList(tester);
        final l10n = l10nOf(tester);
        expect(
          find.textContaining(l10n.orderMgmtChipNeedsAction),
          findsOneWidget,
        );
        expect(find.textContaining(l10n.orderMgmtChipPending), findsWidgets);
        expect(
          find.text('${l10n.adminOrderStatusPendingReview} ('),
          findsNothing,
        );
        // All, Needs Action and exactly six statuses: eight chips, none of them Delivered.
        final chips = find.descendant(
          of: find.byKey(const Key('statusFilter')),
          matching: find.byType(ListingStatusFilterChip),
        );
        expect(chips, findsNWidgets(8));
        for (final label in [
          l10n.buyerOrderDetailStepApproved,
          l10n.orderStatusReadyForPickup,
          l10n.orderStatusOutForDelivery,
          l10n.statCompleted,
        ]) {
          expect(find.textContaining('$label ('), findsWidgets, reason: label);
        }
        expect(
          find.textContaining('${l10n.orderStatusDelivered} ('),
          findsNothing,
        );
      });
    });

    testWidgets(
      'a handed-over, paid delivery is filed under Out for Delivery and says it awaits confirmation',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openList(tester);
          final l10n = l10nOf(tester);
          expect(find.byKey(const Key('handedOver_c3')), findsOneWidget);
          expect(find.text(l10n.uoHandedOver), findsOneWidget);
          await tester.tap(find.text('${l10n.orderStatusOutForDelivery} (1)'));
          await tester.pump();
          expect(find.byKey(const Key('orderRow_c3')), findsOneWidget);
          expect(find.byKey(const Key('orderRow_c1')), findsNothing);
        });
      },
    );

    testWidgets(
      'Needs Action holds what staff still have to do: an approved order, and a ready one with no cash recorded',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openList(tester);
          final l10n = l10nOf(tester);
          await tester.tap(find.text('${l10n.orderMgmtChipNeedsAction} (2)'));
          await tester.pump();
          expect(find.byKey(const Key('orderRow_c1')), findsOneWidget);
          expect(find.byKey(const Key('orderRow_c2')), findsOneWidget);
          expect(
            find.byKey(const Key('orderRow_c3')),
            findsNothing,
          ); // paid: waits only for the member
          expect(find.byKey(const Key('orderRow_c4')), findsNothing);
        });
      },
    );
  });

  // ── a Cooperative order, staff side ───────────────────────────────────────
  group('Cooperative order detail (staff)', () {
    Future<void> openOrder(
      WidgetTester tester,
      Map<String, Object?> order, {
      String role = 'admin',
      Map<StaffModule, StaffAccess> access = const {},
    }) async {
      fake.reset();
      fake.on('GET /rest/v1/program_product_purchases', (_) => [order]);
      fake.on(
        'GET /rest/v1/user_information',
        (_) => [
          {'user_id': 'f1', 'full_name': 'Maria Santos'},
        ],
      );
      fake.on(
        'GET /rest/v1/checkout_groups',
        (_) => [
          {'delivery_fee': 25, 'fee_collected_at': null},
        ],
      );
      await signIn(tester, role, access: access);
      // A new key each time: the same screen for the same order would keep its state and not reload.
      await pump(
        tester,
        AdminProgramOrderDetailScreen(
          key: UniqueKey(),
          orderId: order['id']! as String,
        ),
      );
    }

    testWidgets(
      'a Pending order offers Approve, and the order, member and prices are shown',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openOrder(tester, _coop(status: 'pending'));
          final l10n = l10nOf(tester);
          expect(find.byKey(const Key('primaryStep')), findsOneWidget);
          expect(find.text(l10n.adminOrderDetailApproveTitle), findsWidgets);
          expect(find.text('Maria Santos'), findsOneWidget);
          expect(find.text('Peanut Cookies Sale'), findsOneWidget);
          expect(
            find.byKey(const Key('sourceBadge_cooperative')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('cancelOrder')), findsNothing); // staff have no Cancel
        });
      },
    );

    testWidgets('the next step follows the method and the cash', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await openOrder(tester, _coop(status: 'approved', method: 'pickup'));
        expect(
          find.text(l10nOf(tester).orderActionReadyForPickup),
          findsOneWidget,
        );
        await openOrder(tester, _coop(status: 'approved', method: 'delivery'));
        expect(
          find.text(l10nOf(tester).orderActionOutForDelivery),
          findsOneWidget,
        );
        await openOrder(tester, _coop(status: 'ready_for_pickup'));
        expect(find.text(l10nOf(tester).uoActionRecordPayment), findsOneWidget);
        await openOrder(
          tester,
          _coop(status: 'out_for_delivery', method: 'delivery'),
        );
        expect(
          find.text(l10nOf(tester).uoActionRecordHandover),
          findsOneWidget,
        );
        await openOrder(
          tester,
          _coop(status: 'ready_for_pickup', payment: 'paid'),
        );
        expect(
          find.text(l10nOf(tester).uoActionCompleteForCustomer),
          findsOneWidget,
        );
      });
    });

    testWidgets(
      'a paid, handed-over delivery is shown as awaiting the member, with the payment on record',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openOrder(tester, {
            ..._coop(status: 'delivered', method: 'delivery', payment: 'paid'),
            'amount_collected': 115,
            'delivery_fee_collected': 25,
            'paid_at': '2026-11-06T12:00:00Z',
          });
          final l10n = l10nOf(tester);
          expect(find.byKey(const Key('handedOverNote')), findsOneWidget);
          expect(find.text(l10n.uoHandedOver), findsOneWidget);
          expect(find.byKey(const Key('orderPaymentCard')), findsOneWidget);
          expect(
            find.text('₱115.00'),
            findsWidgets,
          ); // the cash collected: items plus the one delivery fee
          expect(find.text('₱25.00'), findsWidgets);
        });
      },
    );

    testWidgets('a completed or cancelled order has no step and no Cancel', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await openOrder(tester, _coop(status: 'completed', payment: 'paid'));
        expect(find.byKey(const Key('primaryStep')), findsNothing);
        expect(find.byKey(const Key('cancelOrder')), findsNothing);
        await openOrder(tester, _coop(status: 'cancelled'));
        expect(find.byKey(const Key('primaryStep')), findsNothing);
        expect(find.byKey(const Key('cancelOrder')), findsNothing);
      });
    });

    testWidgets('a paid order cannot be cancelled from the screen either', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await openOrder(
          tester,
          _coop(status: 'ready_for_pickup', payment: 'paid'),
        );
        expect(find.byKey(const Key('cancelOrder')), findsNothing);
      });
    });

    testWidgets(
      'the Manager approves: one confirmation, then the approve function is called for that order',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openOrder(tester, _coop(status: 'pending'));
          final l10n = l10nOf(tester);
          await tester.tap(find.byKey(const Key('primaryStep')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.adminOrderDetailApproveTitle).last);
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 300));
          final calls = fake.calls('POST /rest/v1/rpc/approve_program_order');
          expect(calls.length, 1);
          expect(calls.single.jsonMap['p_order_id'], 'c1');
          await tester.pump(const Duration(seconds: 4)); // toast timer
        });
      },
    );

    testWidgets(
      'a View Only Officer sees the order and a notice, and tapping the step sends nothing',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openOrder(
            tester,
            _coop(status: 'pending'),
            role: 'officer',
            access: {StaffModule.marketplace: StaffAccess.view},
          );
          final l10n = l10nOf(tester);
          expect(find.text(l10n.staffViewOnlyBanner), findsOneWidget);
          await tester.tap(find.byKey(const Key('primaryStep')));
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text(l10n.staffViewOnlyAction), findsOneWidget);
          expect(
            fake.calls('POST /rest/v1/rpc/approve_program_order'),
            isEmpty,
          );
          await tester.pump(const Duration(seconds: 4));
        });
      },
    );

    testWidgets(
      'an Officer with Marketplace = Manage can approve like the Manager',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openOrder(
            tester,
            _coop(status: 'pending'),
            role: 'officer',
            access: {StaffModule.marketplace: StaffAccess.manage},
          );
          final l10n = l10nOf(tester);
          expect(find.text(l10n.staffViewOnlyBanner), findsNothing);
          await tester.tap(find.byKey(const Key('primaryStep')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.adminOrderDetailApproveTitle).last);
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            fake.calls('POST /rest/v1/rpc/approve_program_order').length,
            1,
          );
          await tester.pump(const Duration(seconds: 4));
        });
      },
    );

    testWidgets(
      'the cash dialog shows the items and the group\'s one delivery fee, and refuses a wrong amount',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openOrder(tester, _coop(status: 'ready_for_pickup'));
          await tester.tap(find.byKey(const Key('primaryStep')));
          await tester.pumpAndSettle();
          final l10n = l10nOf(tester);
          expect(find.byKey(const Key('cashDue')), findsOneWidget);
          expect(find.text('₱90.00'), findsWidgets);
          await tester.enterText(find.byKey(const Key('cashReceived')), '80');
          await tester.tap(find.text(l10n.uoCashRecord));
          await tester.pump();
          expect(find.text(l10n.uoCashMismatch('₱90.00')), findsOneWidget);
          expect(
            fake.calls('POST /rest/v1/rpc/record_program_order_handover'),
            isEmpty,
          );
        });
      },
    );

    testWidgets(
      'a pickup payment is recorded with the exact amount and no photo',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openOrder(tester, _coop(status: 'ready_for_pickup'));
          await tester.tap(find.byKey(const Key('primaryStep')));
          await tester.pumpAndSettle();
          final l10n = l10nOf(tester);
          await tester.tap(find.text(l10n.uoCashRecord));
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 300));
          final calls = fake.calls(
            'POST /rest/v1/rpc/record_program_order_handover',
          );
          expect(calls.length, 1);
          expect(calls.single.jsonMap['p_amount'], 90);
          expect(calls.single.jsonMap['p_photo_url'], isNull);
          await tester.pump(const Duration(seconds: 4));
        });
      },
    );

    testWidgets(
      'a delivery handover asks for the photo and adds the group\'s delivery fee to the cash due',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openOrder(
            tester,
            _coop(status: 'out_for_delivery', method: 'delivery', group: 'g1'),
          );
          await tester.tap(find.byKey(const Key('primaryStep')));
          await tester.pumpAndSettle();
          final l10n = l10nOf(tester);
          expect(find.byKey(const Key('handoverPhoto')), findsOneWidget);
          expect(find.text('₱115.00'), findsWidgets); // 90 items + 25 fee, once
          await tester.tap(find.text(l10n.uoCashRecord));
          await tester.pump();
          expect(find.text(l10n.coopDeliverPhotoRequired), findsOneWidget);
          expect(
            fake.calls('POST /rest/v1/rpc/record_program_order_handover'),
            isEmpty,
          );
        });
      },
    );

    testWidgets(
      'completing for the member needs a reason and a photo before anything is sent',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await openOrder(
            tester,
            _coop(status: 'ready_for_pickup', payment: 'paid'),
          );
          await tester.tap(find.byKey(const Key('primaryStep')));
          await tester.pumpAndSettle();
          final l10n = l10nOf(tester);
          await tester.tap(find.text(l10n.uoAssistConfirm));
          await tester.pump();
          expect(find.text(l10n.uoAssistReasonRequired), findsOneWidget);
          expect(find.text(l10n.coopDeliverPhotoRequired), findsOneWidget);
          await tester.enterText(
            find.byKey(const Key('assistReason')),
            'Member has no phone signal',
          );
          await tester.tap(find.text(l10n.uoAssistConfirm));
          await tester.pump();
          expect(find.text(l10n.uoAssistReasonRequired), findsNothing);
          expect(
            find.text(l10n.coopDeliverPhotoRequired),
            findsOneWidget,
          ); // still no photo
          expect(
            fake.calls('POST /rest/v1/rpc/staff_complete_program_order'),
            isEmpty,
          );
        });
      },
    );
  });

  // ── payment widgets ───────────────────────────────────────────────────────
  group('payment and completion cards', () {
    Future<void> show(WidgetTester tester, Widget w) =>
        pump(tester, Scaffold(body: ListView(children: [w])));

    testWidgets(
      'a consumer sees what was paid but never who recorded it; staff see the person',
      (tester) async {
        await runIgnoringFontErrors(() async {
          const card = OrderPaymentCard(
            paymentStatus: 'paid',
            itemsTotal: 90,
            amountCollected: 115,
            deliveryFee: 25,
            paidAt: null,
            recordedByName: 'Ana Reyes',
            recordedByRole: 'officer',
          );
          await show(tester, card);
          expect(find.text('₱115.00'), findsOneWidget);
          expect(find.textContaining('Ana Reyes'), findsNothing);
          await show(
            tester,
            const OrderPaymentCard(
              paymentStatus: 'paid',
              itemsTotal: 90,
              amountCollected: 115,
              deliveryFee: 25,
              recordedByName: 'Ana Reyes',
              recordedByRole: 'officer',
              staffView: true,
            ),
          );
          expect(find.textContaining('Ana Reyes'), findsOneWidget);
          expect(find.textContaining('Officer'), findsOneWidget);
        });
      },
    );

    testWidgets('unpaid and not-recorded orders say so plainly', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await show(
          tester,
          const OrderPaymentCard(paymentStatus: 'unpaid', itemsTotal: 90),
        );
        final l10n = l10nOf(tester);
        expect(find.text(l10n.uoPaymentUnpaid), findsOneWidget);
        await show(
          tester,
          const OrderPaymentCard(paymentStatus: 'not_recorded', itemsTotal: 90),
        );
        expect(find.text(l10n.uoPaymentNotRecorded), findsOneWidget);
      });
    });

    testWidgets(
      'a staff-completed order keeps the staff name away from the consumer',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await show(
            tester,
            StaffCompletionCard(
              reason: 'Member had no signal',
              byName: 'Ana Reyes',
              byRole: 'admin',
              at: DateTime(2026, 11, 6, 14),
              showStaffIdentity: false,
            ),
          );
          expect(find.textContaining('Member had no signal'), findsOneWidget);
          expect(find.textContaining('Ana Reyes'), findsNothing);
          await show(
            tester,
            StaffCompletionCard(
              reason: 'Member had no signal',
              byName: 'Ana Reyes',
              byRole: 'admin',
              at: DateTime(2026, 11, 6, 14),
            ),
          );
          expect(find.textContaining('Ana Reyes'), findsOneWidget);
          expect(find.textContaining('Manager'), findsOneWidget);
        });
      },
    );

    testWidgets('the waiting-for-payment card explains the order of things', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await show(tester, const WaitingForPaymentCard());
        final l10n = l10nOf(tester);
        expect(find.text(l10n.uoWaitingPaymentTitle), findsOneWidget);
        expect(find.text(l10n.uoWaitingPaymentBody), findsOneWidget);
      });
    });
  });

  // ── Cooperative Details ───────────────────────────────────────────────────
  group('Cooperative Details', () {
    Future<void> open(
      WidgetTester tester, {
      String role = 'admin',
      Map<String, Object?> details = const {},
      Map<StaffModule, StaffAccess> access = const {},
    }) async {
      fake.reset();
      fake.on(
        'POST /rest/v1/rpc/get_cooperative_details',
        (_) => {
          'cooperative_name': 'SP3 Agriculture Cooperative',
          'barangay_code': '1704006019',
          'barangay_name': 'Payanas',
          'city_municipality_name': 'Torrijos',
          'province_name': 'Marinduque',
          'region_name': 'MIMAROPA Region',
          'postal_code': '4903',
          'sitio_purok': null,
          'address_notes': null,
          'contact_number': null,
          'contact_is_placeholder': true,
          'contact_verified': false,
          'latitude': null,
          'longitude': null,
          ...details,
        },
      );
      await signIn(tester, role, access: access);
      await pump(tester, const CooperativeDetailsScreen());
    }

    testWidgets(
      'the name is fixed, the full address is five LOCKED fields like My Addresses, and the number starts as a yellow "not set" warning',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(tester);
          final l10n = l10nOf(tester);
          expect(find.text('SP3 Agriculture Cooperative'), findsOneWidget);
          // No full address line under the name.
          expect(find.byKey(const Key('cdArea')), findsNothing);
          // ONE section for the address: "Complete Address", with a note that it is also the
          // official pickup location. No separate Pickup Address section, no "Full Address".
          expect(find.text(l10n.cdCompleteAddressTitle), findsOneWidget);
          expect(l10n.cdCompleteAddressTitle, 'Complete Address');
          expect(find.text('Pickup Address'), findsNothing);
          expect(find.text('Full Address'), findsNothing);
          expect(find.byKey(const Key('cdAddressNote')), findsOneWidget);
          expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
          expect(
            l10n.cdCompleteAddressNote,
            "This address is also the cooperative's official pickup location.",
          );
          expect(find.text(l10n.cdCompleteAddressNote), findsOneWidget);
          // The note sits under the heading and above the fields.
          expect(
            tester.getTopLeft(find.text(l10n.cdCompleteAddressTitle)).dy,
            lessThan(
              tester.getTopLeft(find.text(l10n.cdCompleteAddressNote)).dy,
            ),
          );
          expect(
            tester.getTopLeft(find.text(l10n.cdCompleteAddressNote)).dy,
            lessThan(
              tester
                  .getTopLeft(
                    find.byKey(const ValueKey('fixed-address-region')),
                  )
                  .dy,
            ),
          );
          for (final entry in {
            'region': 'MIMAROPA Region',
            'province': 'Marinduque',
            'city': 'Torrijos',
            'barangay': 'Payanas',
            'postal': '4903',
          }.entries) {
            final field = find.byKey(ValueKey('fixed-address-${entry.key}'));
            await tester.ensureVisible(field);
            expect(field, findsOneWidget, reason: entry.key);
            expect(
              tester.widget<TextFormField>(field).enabled,
              isTrue,
            ); // readOnly, not disabled: it looks like My Addresses
            final input = find.descendant(
              of: field,
              matching: find.byType(EditableText),
            );
            expect(
              tester.widget<EditableText>(input).readOnly,
              isTrue,
              reason: entry.key,
            );
            expect(
              tester.widget<EditableText>(input).controller.text,
              entry.value,
            );
          }
          expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(5));
          // Nothing else to type: no Sitio / Purok, no landmark, no street / house number.
          expect(find.byKey(const Key('cdSitio')), findsNothing);
          expect(find.byKey(const Key('cdNotes')), findsNothing);
          expect(find.textContaining('Sitio'), findsNothing);
          expect(find.textContaining('Landmark'), findsNothing);
          expect(find.textContaining('Street'), findsNothing);
          expect(find.textContaining('House'), findsNothing);
          // The number: just the field, no counter, no explanation, and a yellow warning.
          await tester.ensureVisible(find.byKey(const Key('cdContact')));
          expect(find.text('0/20'), findsNothing);
          expect(find.text(l10n.cdContactLabel), findsOneWidget);
          expect(
            l10n.cdContactPlaceholder,
            "Not set yet. The cooperative's official contact number has not been entered.",
          );
          expect(find.text(l10n.cdContactPlaceholder), findsOneWidget);
          final box = tester.widget<Container>(
            find.byKey(const Key('cdContactStatus')),
          );
          expect(((box.decoration as BoxDecoration).color!).a, greaterThan(0));
          expect(find.text(l10n.cdPinNotSet), findsOneWidget);
        });
      },
    );

    testWidgets(
      'the Manager can edit; saving sends only the pin and the number to the Manager-only function',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(tester);
          final l10n = l10nOf(tester);
          await tester.enterText(
            find.byKey(const Key('cdContact')),
            '09171234567',
          );
          await tester.pump();
          await tester.ensureVisible(find.byKey(const Key('cdSave')));
          await tester.tap(find.byKey(const Key('cdSave')));
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 300));
          final calls = fake.calls(
            'POST /rest/v1/rpc/save_cooperative_details',
          );
          expect(calls.length, 1);
          expect(calls.single.jsonMap['p_sitio_purok'], isNull);
          expect(calls.single.jsonMap['p_address_notes'], isNull);
          expect(calls.single.jsonMap['p_contact_number'], '09171234567');
          expect(calls.single.jsonMap['p_latitude'], isNull);
          expect(find.text(l10n.cdSaved), findsOneWidget);
          await tester.pump(const Duration(seconds: 4));
        });
      },
    );

    testWidgets(
      'a number that is too short is refused before anything is sent',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(tester);
          final l10n = l10nOf(tester);
          await tester.enterText(find.byKey(const Key('cdContact')), '123');
          await tester.pump();
          await tester.ensureVisible(find.byKey(const Key('cdSave')));
          await tester.tap(find.byKey(const Key('cdSave')));
          await tester.pump();
          expect(find.text(l10n.cdContactInvalid), findsOneWidget);
          expect(
            fake.calls('POST /rest/v1/rpc/save_cooperative_details'),
            isEmpty,
          );
        });
      },
    );

    testWidgets(
      'an entered number must be verified by the Manager before it counts',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(
            tester,
            details: {
              'contact_number': '09171234567',
              'contact_is_placeholder': false,
            },
          );
          final l10n = l10nOf(tester);
          expect(find.text(l10n.cdContactNotVerified), findsOneWidget);
          await tester.ensureVisible(find.byKey(const Key('cdVerify')));
          await tester.tap(find.byKey(const Key('cdVerify')));
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            fake.calls('POST /rest/v1/rpc/verify_cooperative_contact').length,
            1,
          );
          await tester.pump(const Duration(seconds: 4));
        });
      },
    );

    testWidgets(
      'an Officer only views: no fields to edit, no Save, no Verify, no pin button',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(
            tester,
            role: 'officer',
            details: {
              'contact_number': '09171234567',
              'contact_is_placeholder': false,
            },
            access: {StaffModule.marketplace: StaffAccess.manage},
          ); // even with Manage: only the Manager edits
          expect(find.byKey(const Key('cdViewOnly')), findsOneWidget);
          expect(find.byKey(const Key('cdSave')), findsNothing);
          expect(find.byKey(const Key('cdVerify')), findsNothing);
          expect(find.byKey(const Key('cdSetPin')), findsNothing);
          await tester.ensureVisible(find.byKey(const Key('cdContact')));
          final contact = tester.widget<TextField>(
            find.byKey(const Key('cdContact')),
          );
          expect(contact.enabled, isFalse);
        });
      },
    );
  });

  // ── Delivery Settings ─────────────────────────────────────────────────────
  group('Delivery Settings', () {
    Future<void> open(
      WidgetTester tester, {
      String role = 'admin',
      bool enabled = false,
      bool ready = false,
      bool pickup = true,
      List<String> missing = const [
        'cooperative_pin',
        'contact_number',
        'fee_bands',
      ],
      List<Map<String, Object?>> bands = const [],
    }) async {
      fake.reset();
      fake.on(
        'POST /rest/v1/rpc/get_delivery_status',
        (_) => {
          'enabled': enabled,
          'ready': ready,
          'allowed_barangay_codes': ['1704006019'],
          'pickup_enabled': pickup,
          'missing': missing,
        },
      );
      fake.on('GET /rest/v1/delivery_fee_bands', (_) => bands);
      await signIn(tester, role);
      await pump(tester, const DeliverySettingsScreen());
    }

    testWidgets(
      'three things only: Pickup, Delivery and the fees; nothing is pre-filled and no area description',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(tester);
          final l10n = l10nOf(tester);
          expect(find.byKey(const Key('dsPickupSwitch')), findsOneWidget);
          expect(find.byKey(const Key('dsSwitch')), findsOneWidget);
          expect(find.byKey(const Key('bandsEmpty')), findsOneWidget);
          expect(find.byKey(const Key('bandRow_0')), findsNothing);
          expect(find.text(l10n.dsSwitchOff), findsOneWidget);
          expect(find.text(l10n.dsPickupOn), findsOneWidget);
          expect(
            find.textContaining('Sitio and Purok are parts of Payanas'),
            findsNothing,
          ); // the description is gone
          expect(
            tester.widget<Switch>(find.byKey(const Key('dsSwitch'))).value,
            isFalse,
          );
        });
      },
    );

    testWidgets(
      'Delivery OFF with things missing: the checklist is right under the switch, and the switch cannot be turned on',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(tester);
          expect(find.byKey(const Key('dsChecklist')), findsOneWidget);
          expect(
            tester.widget<Switch>(find.byKey(const Key('dsSwitch'))).onChanged,
            isNull,
          );
          for (final k in ['pin', 'contact', 'bands']) {
            expect(find.byKey(Key('check_$k')), findsOneWidget);
          }
        });
      },
    );

    testWidgets('the checklist shows exactly what is missing', (tester) async {
      await runIgnoringFontErrors(() async {
        await open(tester, missing: ['cooperative_pin']);
        Icon iconOf(String key) => tester.widget<Icon>(
          find.descendant(
            of: find.byKey(Key('check_$key')),
            matching: find.byType(Icon),
          ),
        );
        expect(iconOf('pin').icon, Icons.radio_button_unchecked_rounded);
        expect(iconOf('contact').icon, Icons.check_circle_rounded);
        expect(iconOf('bands').icon, Icons.check_circle_rounded);
      });
    });

    testWidgets(
      'a contact number that is not entered is NEVER shown as verified (it is one item: entered and verified)',
      (tester) async {
        await runIgnoringFontErrors(() async {
          // The database lists only "contact_number" when nothing is entered (it cannot be verified yet).
          await open(tester, missing: ['contact_number']);
          Icon iconOf(String key) => tester.widget<Icon>(
            find.descendant(
              of: find.byKey(Key('check_$key')),
              matching: find.byType(Icon),
            ),
          );
          expect(iconOf('contact').icon, Icons.radio_button_unchecked_rounded);
          // Entered but not verified: still not done.
          await open(tester, missing: ['contact_verified']);
          expect(iconOf('contact').icon, Icons.radio_button_unchecked_rounded);
          expect(find.text(l10nOf(tester).dsCheckContact), findsOneWidget);
        });
      },
    );

    testWidgets(
      'once everything is in place the checklist disappears and the Manager can switch Delivery on',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(
            tester,
            ready: true,
            missing: const [],
            bands: [
              {
                'min_km': 0,
                'max_km': 2,
                'fee': 30,
                'is_demo': false,
                'set_version': 1,
              },
            ],
          );
          expect(find.byKey(const Key('dsChecklist')), findsNothing);
          final sw = tester.widget<Switch>(find.byKey(const Key('dsSwitch')));
          expect(sw.onChanged, isNotNull);
          await tester.tap(find.byKey(const Key('dsSwitch')));
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 300));
          final calls = fake.calls('POST /rest/v1/rpc/set_delivery_enabled');
          expect(calls.length, 1);
          expect(calls.single.jsonMap['p_enabled'], true);
          await tester.pump(const Duration(seconds: 4));
        });
      },
    );

    testWidgets(
      'Pickup and Delivery are separate switches: Pickup cannot be switched off while Delivery is off',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(tester); // Delivery off, Pickup on
          expect(
            tester
                .widget<Switch>(find.byKey(const Key('dsPickupSwitch')))
                .onChanged,
            isNull,
          );
          expect(find.text(l10nOf(tester).dsOneMethod), findsOneWidget);
        });
      },
    );

    testWidgets(
      'with Delivery on, Pickup can be switched off on its own, and the call is for Pickup only',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(
            tester,
            enabled: true,
            ready: true,
            missing: const [],
            bands: [
              {
                'min_km': 0,
                'max_km': 2,
                'fee': 30,
                'is_demo': false,
                'set_version': 1,
              },
            ],
          );
          expect(
            tester
                .widget<Switch>(find.byKey(const Key('dsPickupSwitch')))
                .onChanged,
            isNotNull,
          );
          await tester.tap(find.byKey(const Key('dsPickupSwitch')));
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            fake
                .calls('POST /rest/v1/rpc/set_pickup_enabled')
                .single
                .jsonMap['p_enabled'],
            false,
          );
          expect(fake.calls('POST /rest/v1/rpc/set_delivery_enabled'), isEmpty);
          await tester.pump(const Duration(seconds: 4));
        });
      },
    );

    testWidgets('with Pickup off, Delivery cannot be switched off', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await open(
          tester,
          enabled: true,
          ready: true,
          pickup: false,
          missing: const [],
          bands: [
            {
              'min_km': 0,
              'max_km': 2,
              'fee': 30,
              'is_demo': false,
              'set_version': 1,
            },
          ],
        );
        expect(find.text(l10nOf(tester).dsPickupOff), findsOneWidget);
        expect(
          tester.widget<Switch>(find.byKey(const Key('dsSwitch'))).onChanged,
          isNull,
        );
        expect(
          tester
              .widget<Switch>(find.byKey(const Key('dsPickupSwitch')))
              .onChanged,
          isNotNull,
        );
      });
    });

    testWidgets(
      'bands: the start of each is where the last one ends, a gap cannot be typed',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(tester);
          final l10n = l10nOf(tester);
          await tester.ensureVisible(find.byKey(const Key('addBand')));
          await tester.tap(find.byKey(const Key('addBand')));
          await tester.pump();
          await tester.enterText(find.byKey(const Key('bandUpTo_0')), '1.5');
          await tester.enterText(find.byKey(const Key('bandFee_0')), '30');
          await tester.ensureVisible(find.byKey(const Key('addBand')));
          await tester.tap(find.byKey(const Key('addBand')));
          await tester.pump();
          await tester.enterText(find.byKey(const Key('bandUpTo_1')), '3');
          await tester.enterText(find.byKey(const Key('bandFee_1')), '50');
          await tester.pump();
          expect(find.text(l10n.dsBandFrom('0')), findsOneWidget);
          expect(find.text(l10n.dsBandFrom('1.5')), findsOneWidget);
        });
      },
    );

    testWidgets(
      'a band that ends before it starts is refused with a reason, and nothing is saved',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(tester);
          final l10n = l10nOf(tester);
          await tester.ensureVisible(find.byKey(const Key('addBand')));
          await tester.tap(find.byKey(const Key('addBand')));
          await tester.pump();
          await tester.enterText(find.byKey(const Key('bandUpTo_0')), '2');
          await tester.enterText(find.byKey(const Key('bandFee_0')), '30');
          await tester.ensureVisible(find.byKey(const Key('addBand')));
          await tester.tap(find.byKey(const Key('addBand')));
          await tester.pump();
          await tester.enterText(
            find.byKey(const Key('bandUpTo_1')),
            '1',
          ); // ends before it starts (2)
          await tester.enterText(find.byKey(const Key('bandFee_1')), '40');
          await tester.pump();
          await tester.ensureVisible(find.byKey(const Key('saveBands')));
          await tester.tap(find.byKey(const Key('saveBands')));
          await tester.pump();
          expect(find.text(l10n.dsBandsProblemRow), findsOneWidget);
          expect(
            fake.calls('POST /rest/v1/rpc/save_delivery_fee_bands'),
            isEmpty,
          );
        });
      },
    );

    testWidgets(
      'valid bands are saved as typed, never as demonstration rates',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(tester);
          await tester.ensureVisible(find.byKey(const Key('addBand')));
          await tester.tap(find.byKey(const Key('addBand')));
          await tester.pump();
          await tester.enterText(find.byKey(const Key('bandUpTo_0')), '2');
          await tester.enterText(find.byKey(const Key('bandFee_0')), '30');
          await tester.ensureVisible(find.byKey(const Key('addBand')));
          await tester.tap(find.byKey(const Key('addBand')));
          await tester.pump();
          await tester.enterText(find.byKey(const Key('bandUpTo_1')), '5');
          await tester.enterText(find.byKey(const Key('bandFee_1')), '55');
          await tester.pump();
          await tester.ensureVisible(find.byKey(const Key('saveBands')));
          await tester.tap(find.byKey(const Key('saveBands')));
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 300));
          final calls = fake.calls('POST /rest/v1/rpc/save_delivery_fee_bands');
          expect(calls.length, 1);
          expect(calls.single.jsonMap['p_is_demo'], false);
          final sent = (calls.single.jsonMap['p_bands'] as List).cast<Map>();
          expect(
            sent.map((b) => [b['min_km'], b['max_km'], b['fee']]).toList(),
            [
              [0, 2, 30],
              [2, 5, 55],
            ],
          );
          await tester.pump(const Duration(seconds: 4));
        });
      },
    );

    testWidgets(
      'an Officer only looks: the table has no controls and the switch is dead',
      (tester) async {
        await runIgnoringFontErrors(() async {
          await open(
            tester,
            role: 'officer',
            ready: true,
            missing: const [],
            bands: [
              {
                'min_km': 0,
                'max_km': 2,
                'fee': 30,
                'is_demo': false,
                'set_version': 1,
              },
            ],
          );
          expect(find.byKey(const Key('dsViewOnly')), findsOneWidget);
          expect(find.byKey(const Key('addBand')), findsNothing);
          expect(find.byKey(const Key('saveBands')), findsNothing);
          final sw = tester.widget<Switch>(find.byKey(const Key('dsSwitch')));
          expect(sw.onChanged, isNull);
          expect(
            tester
                .widget<Switch>(find.byKey(const Key('dsPickupSwitch')))
                .onChanged,
            isNull,
          );
          expect(
            tester
                .widget<TextField>(find.byKey(const Key('bandFee_0')))
                .enabled,
            isFalse,
          );
        });
      },
    );

    testWidgets('demonstration rates are called out and block the checklist', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        await open(
          tester,
          missing: ['fee_bands_demo_only'],
          bands: [
            {
              'min_km': 0,
              'max_km': 2,
              'fee': 30,
              'is_demo': true,
              'set_version': 1,
            },
          ],
        );
        final l10n = l10nOf(tester);
        expect(find.text(l10n.dsDemoWarning), findsOneWidget);
        // Demonstration rates do not count as set: the fees item stays unchecked.
        expect(find.byKey(const Key('dsChecklist')), findsOneWidget);
        expect(
          tester
              .widget<Icon>(
                find.descendant(
                  of: find.byKey(const Key('check_bands')),
                  matching: find.byType(Icon),
                ),
              )
              .icon,
          Icons.radio_button_unchecked_rounded,
        );
      });
    });
  });
}
