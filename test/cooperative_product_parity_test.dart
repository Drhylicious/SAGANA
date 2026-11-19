import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/utils/listing_order.dart';
import 'package:sagana/core/utils/member_activity_label.dart';
import 'package:sagana/core/utils/quantity_utils.dart';
import 'package:sagana/data/models/staff_action_model.dart';
import 'package:sagana/presentation/widgets/product_buy_now_sheet.dart';

import 'support/ignore_font_errors.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// The Cooperative Product screens follow the Marketplace ones; decimals; queues oldest first;
/// readable log lines for the cooperative settings; staff notices to active accounts only.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final en = lookupAppLocalizations(const Locale('en'));
  final tl = lookupAppLocalizations(const Locale('tl'));

  StaffActionEntry entry({
    required String table,
    required String operation,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) => StaffActionEntry.fromMap({
    'id': 'x',
    'admin_id': 'm1',
    'actor_name': 'Manager',
    'actor_role': 'admin',
    'module': 'marketplace',
    'operation': operation,
    'table_name': table,
    'record_id': 'r',
    'reference_label': null,
    'description': 'database text',
    'old_values': before,
    'new_values': after,
    'created_at': '2026-11-08T08:30:00Z',
  });

  group('one Buy Now sheet for both kinds of product', () {
    final listing = _read(
      'lib/presentation/screens/buyer/listing_details_screen.dart',
    );
    final coop = _read(
      'lib/presentation/screens/farmer/cooperative_product_details_screen.dart',
    );

    test(
      'the Marketplace and the Cooperative Product screens both open the shared sheet',
      () {
        expect(listing, contains('ProductBuyNowSheet.show('));
        expect(coop, contains('ProductBuyNowSheet.show('));
        expect(listing.contains('class _BuyNowSheet'), isFalse);
      },
    );

    test(
      'the Cooperative Product page has no title bar and the same 400 px photo as a listing',
      () {
        expect(coop.contains('SubPageTopBar('), isFalse);
        expect(coop, contains('SubPageBackButton('));
        expect(listing, contains('height: 400'));
        expect(coop, contains('height: 400'));
        expect(coop, contains('buyerListingMoreFromSp3'));
        expect(coop, contains('CooperativeAddressText'));
      },
    );

    test(
      'the Cooperative Product page no longer carries its own quantity field',
      () {
        expect(coop.contains('TextEditingController'), isFalse);
        expect(coop.contains("Key('cpQty')"), isFalse);
        expect(coop.contains('FilteringTextInputFormatter'), isFalse);
      },
    );

    testWidgets(
      'the sheet passes the typed quantity (two decimals) on and closes',
      (tester) async {
        await runIgnoringFontErrors(() async {
          double? got;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    key: const Key('open'),
                    onPressed: () => ProductBuyNowSheet.show(
                      context,
                      photoUrl: null,
                      price: 45,
                      unit: 'sack',
                      available: 12.5,
                      pillLabel: 'Cooperative Product',
                      initialQuantity: 1,
                      onConfirm: (q) => got = q,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byKey(const Key('open')));
          await tester.pumpAndSettle();
          expect(find.text('Max: 12.50 sack available'), findsOneWidget);
          await tester.enterText(find.byType(TextField), '2.75');
          await tester.pump();
          await tester.tap(find.byKey(const Key('buyNowConfirm')));
          await tester.pumpAndSettle();
          expect(got, 2.75);
          expect(find.byType(ProductBuyNowSheet), findsNothing);
        });
      },
    );
  });

  group('decimals for Cooperative Products', () {
    test(
      'a discount percent keeps its two decimals (12.25% is not shown as 12.3%)',
      () {
        expect(formatQuantity(12.25), '12.25');
        expect(formatQuantity(10), '10');
        final coop = _read(
          'lib/presentation/screens/farmer/cooperative_product_details_screen.dart',
        );
        expect(coop.contains('toStringAsFixed(1)'), isFalse);
        expect(
          _read('lib/presentation/screens/admin/program_products_screen.dart'),
          allOf(contains('_percentText(double v)'), contains('formatQuantity(v)')),
        );
      },
    );

    test(
      'nothing in the Cooperative order functions is integer-only (read from the script)',
      () {
        final sql = _read(
          'supabase_schema/supabase_schema_unify_m04_cooperative_order_engine.sql',
        );
        final code = sql
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('--'))
            .join('\n');
        final place = code.substring(
          code.indexOf('FUNCTION public.place_program_order'),
          code.indexOf('FUNCTION public.approve_program_order'),
        );
        expect(place, contains('p_quantity           numeric'));
        expect(place, contains('p_quantity <> round(p_quantity, 2)'));
        expect(
          RegExp(r'::int\b|::integer\b', caseSensitive: false).hasMatch(place),
          isFalse,
        );
        expect(code, contains('stock_allocated NUMERIC(12,2)'));
        expect(code, contains('stock_reserved  NUMERIC(12,2)'));
      },
    );
  });

  group(
    'first in, first out for the work queues; newest first everywhere else',
    () {
      _Row row(String name, DateTime at) => _Row(name, at);

      test('oldestFirst keeps equal times in their original order', () {
        final t = DateTime(2026, 11, 1);
        final out = oldestFirst([
          row('b', t.add(const Duration(days: 2))),
          row('a', t),
          row('c', t),
        ], (r) => r.at);
        expect(out.map((r) => r.name), ['a', 'c', 'b']);
      });

      test(
        'Listing Approvals: what is pending comes first and the OLDEST pending first',
        () {
          final src = _read(
            'lib/presentation/screens/admin/pending_approvals_screen.dart',
          );
          expect(src, contains('oldestFirst('));
          expect(
            src,
            contains('a.pending ? a.at.compareTo(b.at) : b.at.compareTo(a.at)'),
          );
          expect(
            _read('lib/core/utils/listing_order.dart'),
            contains(
              '...oldestFirst(grouped.sublist(0, end), (l) => l.createdAt)',
            ),
          );
        },
      );

      test(
        'Order Management: only Pending and Needs Action are oldest first',
        () {
          final src = _read('lib/data/models/staff_order_row.dart');
          expect(
            src,
            contains(
              "status == kOrderNeedsActionFilter || status == 'pending'",
            ),
          );
          expect(src, contains('oldestFirst(result, (r) => r.createdAt)'));
        },
      );

      test('Cooperative Products in the Farmer Marketplace: newest first', () {
        final repo = _read(
          'lib/data/repositories/farmer_program_repository.dart',
        );
        expect(
          repo,
          contains(
            ".eq('is_available', true).order('created_at', ascending: false)",
          ),
        );
      });
    },
  );

  group(
    'the Accountability Log says what the Manager did to the cooperative settings',
    () {
      test('location and contact number', () {
        final e = entry(
          table: 'cooperative_details',
          operation: 'updated',
          before: {
            'latitude': 13.1,
            'longitude': 122.0,
            'contact_number': null,
          },
          after: {
            'latitude': 13.3213,
            'longitude': 122.0392,
            'contact_number': '09171234567',
            'contact_is_placeholder': false,
          },
        );
        expect(
          staffActionHeadline(e, en),
          'Changed Cooperative Details: location, contact number',
        );
        expect(
          staffActionHeadline(e, tl),
          'Binago ang Detalye ng Kooperatiba: lokasyon, numero ng contact',
        );
      });

      test('verifying the number', () {
        final e = entry(
          table: 'cooperative_details',
          operation: 'updated',
          before: {'contact_verified_at': null},
          after: {'contact_verified_at': '2026-11-08T01:00:00Z'},
        );
        expect(
          staffActionHeadline(e, en),
          'Changed Cooperative Details: number verification',
        );
      });

      test('switching Delivery and Pickup on and off', () {
        expect(
          staffActionHeadline(
            entry(
              table: 'delivery_settings',
              operation: 'updated',
              before: {'delivery_enabled': false},
              after: {'delivery_enabled': true},
            ),
            en,
          ),
          'Switched Delivery ON',
        );
        expect(
          staffActionHeadline(
            entry(
              table: 'delivery_settings',
              operation: 'updated',
              before: {'pickup_enabled': true},
              after: {'pickup_enabled': false},
            ),
            en,
          ),
          'Switched Pickup OFF',
        );
        expect(
          staffActionHeadline(
            entry(
              table: 'delivery_settings',
              operation: 'updated',
              before: {'delivery_enabled': false},
              after: {'delivery_enabled': true},
            ),
            tl,
          ),
          'Binuksan ang Delivery',
        );
      });

      test('setting a delivery fee', () {
        final e = entry(
          table: 'delivery_fee_bands',
          operation: 'created',
          after: {'min_km': 0, 'max_km': 2.5, 'fee': 30},
        );
        expect(
          staffActionHeadline(e, en),
          'Set a delivery fee: 0–2.5 km, ₱30.00',
        );
      });

      test('they have their own chip in the Marketplace tab of the log', () {
        final filters = _read('lib/core/utils/staff_log_filters.dart');
        expect(
          filters,
          contains(
            "StaffLogFeature('delivery', ['cooperative_details', 'delivery_settings', 'delivery_fee_bands'])",
          ),
        );
        expect(
          _read(
            'lib/presentation/screens/admin/staff_accountability_screen.dart',
          ),
          contains('staffLogFeatureDelivery'),
        );
      });
    },
  );

  group('m08: staff notices go to active accounts only (read from the script)', () {
    final sql = _read(
      'supabase_schema/supabase_schema_unify_m08_staff_notifications_active_only.sql',
    );
    final code = sql
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('--'))
        .join('\n');

    test(
      'the Cooperative order notice uses the helper that filters on active accounts',
      () {
        expect(
          code,
          contains(
            "public.notify_staff('order', p_title, p_body, '/admin/marketplace/orders')",
          ),
        );
        final helper = _read(
          'supabase_schema/supabase_schema_phase2_notification_completeness.sql',
        );
        expect(helper, contains("AND ur.status = 'active'"));
      },
    );

    test(
      'the Marketplace completion notice is patched in place, and it stops rather than guess',
      () {
        expect(code, contains("ur.status = 'active'"));
        expect(code, contains('pg_get_functiondef'));
        expect(code, contains('nothing was changed'));
      },
    );

    test(
      'nothing else is touched: no table, policy or grant is created or dropped',
      () {
        expect(
          RegExp(
            r'CREATE TABLE|ALTER TABLE|DROP |CREATE POLICY|GRANT ',
            caseSensitive: false,
          ).hasMatch(code),
          isFalse,
        );
      },
    );
  });

  group(
    'cancel: the same rule as a Marketplace order (only the Farmer, only while Pending)',
    () {
      test('staff have no Cancel on a Cooperative order, at any status', () {
        final screen = _read(
          'lib/presentation/screens/admin/admin_program_order_detail_screen.dart',
        );
        expect(screen.contains('cancelOrder'), isFalse);
        expect(screen.contains('_cancel'), isFalse);
        expect(screen.contains('.cancel('), isFalse);
      });

      test('the Farmer still cancels a Pending order from their own screen', () {
        expect(
          _read(
            'lib/presentation/screens/farmer/farmer_program_order_detail_screen.dart',
          ),
          contains('_repo.cancel('),
        );
      });

      test(
        'm09: only Pending can become Cancelled, and cancel_program_purchase has no staff branch',
        () {
          final sql = _read(
            'supabase_schema/supabase_schema_unify_m09_cooperative_cancel_pending_only.sql',
          );
          final code = sql
              .split('\n')
              .where((l) => !l.trimLeft().startsWith('--'))
              .join('\n');
          final guard = code.substring(
            code.indexOf('FUNCTION public._program_orders_guard'),
            code.indexOf('FUNCTION public.cancel_program_purchase'),
          );
          expect(
            guard,
            contains(
              "OLD.status = 'pending'          AND NEW.status IN ('approved', 'cancelled')",
            ),
          );
          expect(guard.contains("'completed', 'cancelled'"), isFalse);
          expect(guard.contains("'delivered', 'cancelled'"), isFalse);
          expect(
            RegExp(
              r"OLD\.status = '(approved|ready_for_pickup|out_for_delivery)'[^\n]*cancelled",
            ).hasMatch(guard),
            isFalse,
          );
          final fn = code.substring(
            code.indexOf('FUNCTION public.cancel_program_purchase'),
          );
          expect(fn.contains('is_staff'), isFalse);
          expect(fn, contains("o.status <> 'pending'"));
          expect(fn, contains('o.farmer_id <> auth.uid()'));
          expect(
            RegExp(
              r'CREATE TABLE|ALTER TABLE|DROP |CREATE POLICY',
              caseSensitive: false,
            ).hasMatch(code),
            isFalse,
          );
        },
      );
    },
  );
}

class _Row {
  final String name;
  final DateTime at;
  _Row(this.name, this.at);
}
