import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contract tests for the unified Marketplace / Cooperative purchasing scripts
/// (m01 - m06). The scripts are run by hand, so these read their text and pin the
/// rules the approved plan depends on.
String sql(String name) =>
    File('supabase_schema/supabase_schema_unify_$name.sql').readAsStringSync();

String strip(String s) => s.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

void main() {
  late String m01, m02, m03, m04, m05, m06;
  setUpAll(() {
    m01 = strip(sql('m01_foundation'));
    m02 = strip(sql('m02_cooperative_details_delivery_settings'));
    m03 = strip(sql('m03_checkout_groups_delivery_fees'));
    m04 = strip(sql('m04_cooperative_order_engine'));
    m05 = strip(sql('m05_marketplace_payment_place_order'));
    m06 = strip(sql('m06_program_completion_blockers'));
  });

  group('m01 foundation', () {
    test('drops the unrestricted orders INSERT policy, but only if place_order is SECURITY DEFINER', () {
      expect(m01, contains('DROP POLICY IF EXISTS "Buyers create orders" ON public.orders'));
      expect(m01, contains('prosecdef'));
    });
    test('adds request id uniqueness and payment / staff completion columns', () {
      expect(m01, contains('uq_orders_buyer_request'));
      for (final c in ['payment_status', 'paid_at', 'amount_collected', 'staff_completion_reason', 'staff_completion_photo_url', 'staff_completed_by', 'staff_completed_at', 'checkout_group_id']) {
        expect(m01, contains(c));
      }
    });
    test('completed orders of the past are marked not_recorded, never invented as paid', () {
      expect(m01, contains("payment_status = 'not_recorded'"));
      expect(m01, isNot(contains("payment_status = 'paid'")));
    });
  });

  group('m02 cooperative details and delivery settings', () {
    test('Delivery is OFF, Payanas only, and no fee band is ever inserted by the script', () {
      expect(m02, contains('delivery_enabled       BOOLEAN NOT NULL DEFAULT FALSE'));
      expect(m02, contains("ARRAY['1704006019']"));
      expect(RegExp(r'INSERT INTO public\.delivery_fee_bands').hasMatch(m02), isFalse,
          reason: 'only the Manager function may create bands; the script must not invent rates');
      expect(m02, contains('allow_demo_rates       BOOLEAN NOT NULL DEFAULT FALSE'));
    });
    test('the service area is forced by a trigger, not sent by the app', () {
      expect(m02, contains("NEW.barangay_code := '1704006019'"));
      expect(m02, contains("NEW.province_name := 'Marinduque'"));
    });
    test('a flexible rural address: sitio/purok optional, no street, building or house number', () {
      expect(m02, contains('sitio_purok'));
      expect(m02, isNot(contains('street')));
      expect(m02, isNot(contains('house_no')));
      expect(m02, isNot(contains('building')));
    });
    test('Delivery needs a pin, a real VERIFIED contact number, a non-demo band set and an allowed barangay', () {
      for (final k in ['cooperative_pin', 'contact_number', 'contact_verified', 'fee_bands', 'fee_bands_demo_only', 'allowed_barangay']) {
        expect(m02, contains("'$k'"));
      }
      expect(m02, contains("RAISE EXCEPTION 'DELIVERY_NOT_READY"));
    });
    test('only the Manager writes; an Officer can only read', () {
      for (final fn in ['save_cooperative_details', 'verify_cooperative_contact', 'save_delivery_fee_bands', 'set_delivery_enabled']) {
        final body = m02.substring(m02.indexOf('FUNCTION public.$fn'));
        expect(body.substring(0, 700), contains('public.is_manager()'), reason: fn);
      }
      expect(m02, contains('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.cooperative_details'));
    });
    test('bands start at 0, follow with no gap, are never edited or deleted', () {
      expect(m02, contains('The first band must start at 0 km'));
      expect(m02, contains('no gap and no overlap'));
      expect(m02, contains('cannot be edited'));
      expect(m02, contains('cannot be deleted'));
    });
    test('changing the pin, the number or the rates switches Delivery off until re-checked', () {
      expect(RegExp(r'delivery_enabled = FALSE').allMatches(m02).length, greaterThanOrEqualTo(2));
    });
  });

  group('m03 delivery groups and fee', () {
    test('one fee per group, collected once, snapshot not editable', () {
      expect(m03, contains('CREATE TABLE IF NOT EXISTS public.checkout_groups'));
      expect(m03, contains('uq_checkout_groups_buyer_request'));
      expect(m03, contains('_collect_group_fee'));
      expect(m03, contains('fee_collected_at IS NOT NULL THEN RETURN 0'));
      expect(m03, contains('A delivery group snapshot cannot be edited'));
    });
    test('refuses outside Payanas, with no pin, off, not ready, too far, or with no band: never charges zero silently', () {
      for (final k in ['DELIVERY_OFF', 'DELIVERY_NOT_READY', 'OUTSIDE_AREA', 'NO_PIN', 'TOO_FAR', 'NO_BAND']) {
        expect(m03, contains(k));
      }
      expect(m03, isNot(contains('COALESCE(b.fee, 0)')));
    });
    test('the address comes from the consumer\'s own saved row, validated on the server', () {
      expect(m03, contains('user_id = auth.uid()'));
      expect(m03, contains('a.barangay_code'));
    });
  });

  group('m04 Cooperative order engine', () {
    test('seven statuses, no paid status, PSO reference with the A001 pattern', () {
      expect(m04, contains("'pending', 'approved', 'ready_for_pickup', 'out_for_delivery', 'delivered', 'completed', 'cancelled'"));
      expect(m04, contains("'PSO-'"));
      expect(m04, contains('format_order_sequence'));
      expect(m04, contains('^PSO-[0-9]{8}-[A-Z]+[0-9]{3}\$'));
    });
    test('clients can no longer write purchases; every change is a function', () {
      expect(m04, contains('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.program_product_purchases FROM authenticated, anon'));
      expect(m04, contains('trg_program_orders_guard'));
    });
    test('state machine: completion only with a recorded payment and only through a function', () {
      expect(m04, contains('An order is completed only after the payment is recorded'));
      expect(m04, contains("current_setting('sagana.program_order_rpc', true)"));
      expect(m04, contains('An order that was paid cannot be cancelled'));
    });
    test('payment is separate from status and must equal what is due (total + one group fee)', () {
      expect(m04, contains("payment_status = 'paid'"));
      expect(m04, contains('_collect_group_fee(o.checkout_group_id, o.id, \'cooperative\')'));
      expect(m04, contains('AMOUNT_MISMATCH'));
      expect(m04, contains('Upload a photo of the delivery first'));
    });
    test('a Farmer confirms receipt only after payment; staff completion needs reason and photo', () {
      final confirm = m04.substring(m04.indexOf('FUNCTION public.confirm_program_order_received'));
      expect(confirm.substring(0, 900), contains('PAYMENT_NOT_RECORDED'));
      final staff = m04.substring(m04.indexOf('FUNCTION public.staff_complete_program_order'));
      expect(staff.substring(0, 1200), allOf(contains('p_reason'), contains('p_photo_url'), contains('PAYMENT_NOT_RECORDED')));
      expect(m04, contains("completion_method = 'staff'"));
      expect(m04, contains('staff_completed_by = auth.uid()'));
    });
    test('Buyers can never order Cooperative Products', () {
      final place = m04.substring(m04.indexOf('FUNCTION public.place_program_order'));
      expect(place.substring(0, 900), contains("role = 'farmer'"));
      expect(place, contains('COOPERATIVE_FARMERS_ONLY'));
    });
    test('duplicate protection: request id unique per Farmer, a retry returns the same order', () {
      expect(m04, contains('uq_program_purchases_farmer_request'));
      expect(m04, contains("'existing', TRUE"));
    });
    test('stock is reserved at placement, released on cancel, deducted once at completion', () {
      expect(m04, contains('stock_reserved = stock_reserved + p_quantity'));
      expect(m04, contains('stock_reserved = GREATEST(stock_reserved - o.quantity, 0)'));
      expect(m04, contains('IF o.stock_deducted_at IS NOT NULL THEN RETURN'));
      expect(m04, contains("'sold', -o.quantity"));
    });
    test('allocated stock is protected from every other use and cannot be over-allocated', () {
      expect(m04, contains('trg_inventory_allocation_protect'));
      expect(m04, contains('STOCK_ALLOCATED'));
      expect(m04, contains('OVER_ALLOCATED'));
      expect(m04, contains('stock_reserved <= stock_allocated'));
    });
    test('the old single-step functions are retired', () {
      expect(m04, contains('UPDATE_REQUIRED'));
    });
    test('old purchases are migrated and documented, not duplicated or deleted', () {
      expect(m04, contains('purchase_migration_log'));
      expect(m04, contains("'paid_to_completed'"));
      expect(m04, contains('stock_deducted_at = COALESCE(confirmed_at, requested_at)'));
      expect(RegExp(r'DELETE FROM public\.program_product_purchases').hasMatch(m04), isFalse);
    });
    test('staff actions need Marketplace Manage; the Officer registry is updated', () {
      expect(m04, contains("staff_can_manage('marketplace')"));
      expect(m04, contains("('rpc',   'record_program_order_handover',      'marketplace')"));
      expect(m04, contains("('table', 'program_product_purchases',          'marketplace')"));
    });
  });

  group('m05 Marketplace payment and place_order', () {
    test('Buyer ordering stays: the same guards, a retry returns the same order, new args optional', () {
      expect(m05, contains('DROP FUNCTION IF EXISTS public.place_order(uuid, numeric, text, text, double precision, double precision, text, text, text, text)'));
      expect(m05, contains('p_request_id              UUID DEFAULT NULL'));
      expect(m05, contains('p_group_id                UUID DEFAULT NULL'));
      expect(m05, contains('You cannot place an order on your own listing'));
      expect(m05, contains('Not enough stock available'));
      expect(m05, contains('Only buyer or farmer accounts can place marketplace orders'));
    });
    test('with delivery rules OFF the legacy delivery path is unchanged', () {
      expect(m05, contains('A delivery address is required when choosing delivery'));
      expect(m05, contains('GROUP_REQUIRED'));
    });
    test('completion needs a recorded payment; payment fields only change through the functions', () {
      expect(m05, contains('PAYMENT_NOT_RECORDED'));
      expect(m05, contains('trg_orders_payment_guard'));
      expect(m05, contains("sagana.order_payment"));
    });
    test('consumer Confirm Receipt is gated on payment; staff completion records reason, photo, who, when', () {
      final confirm = m05.substring(m05.indexOf('FUNCTION public.confirm_order_received'));
      expect(confirm.substring(0, 1500), contains('PAYMENT_NOT_RECORDED'));
      final staff = m05.substring(m05.indexOf('FUNCTION public.staff_complete_order'));
      expect(staff.substring(0, 1500), allOf(contains('p_reason'), contains('p_photo_url')));
      expect(m05, contains("completion_method = 'staff'"));
      expect(m05, contains('staff_completed_at = NOW()'));
    });
    test('delivery is handed over with a photo and the cash; the fee is collected once per group', () {
      expect(m05, contains("_collect_group_fee(o.checkout_group_id, o.id, 'marketplace')"));
      expect(m05, contains('Upload a photo of the delivery first'));
      expect(m05, contains('UPDATE_REQUIRED'));
    });
    test('the order completion effects (sold figure, listing, notices) are shared by both paths', () {
      expect(m05, contains('_order_after_completion(o.id, false)'));
      expect(m05, contains('_order_after_completion(o.id, true)'));
      expect(m05, contains('reconcile_batch_sold'));
    });
  });

  group('m06 program completion', () {
    test('open orders and allocated stock block; shared stock and everything else does not', () {
      expect(m06, contains("p.status IN ('pending', 'approved', 'ready_for_pickup', 'out_for_delivery', 'delivered')"));
      expect(m06, contains('pp.stock_allocated > 0'));
      expect(m06, contains("'open_orders'"));
      expect(m06, contains("'allocated_stock'"));
      expect(m06, isNot(contains('quantity_on_hand')));
    });
    test('distribution programs are untouched; nothing is cancelled or deleted', () {
      expect(m06, contains("v_p.program_purpose = 'distribution'"));
      expect(m06, isNot(contains('DELETE')));
      expect(m06, isNot(contains("status = 'cancelled'")));
    });
  });

  test('the staff order notices open the real orders route', () {
    expect(m04, contains("'/admin/marketplace/orders'"));
    expect(m05, contains("'/admin/marketplace/orders'"));
    expect(m04, isNot(contains("'/admin/orders'")));
  });
}
