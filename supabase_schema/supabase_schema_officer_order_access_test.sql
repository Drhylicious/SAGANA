-- ============================================================
-- SAGANA — Officer access to order approval + fulfillment, and the final
-- Marketplace rules: end-to-end test
--
-- As a real OFFICER (and a Farmer and a Buyer) on a fresh 30-unit batch:
--   * the Officer can read the orders and who ordered, approve, record Ready for
--     Pickup / Out for Delivery / Delivered (photo), exactly like a Manager;
--   * the Officer cannot complete, cancel or confirm receipt, and there is no
--     reject / cancel-order function for any staff role;
--   * "Needs Action" = Pending + Approved + Out for Delivery, and leaves out the
--     orders that wait only for the consumer (Ready for Pickup, Delivered);
--   * orders waiting for the consumer stay as they are, with their stock Reserved,
--     until the consumer confirms; completion sells it exactly once;
--   * a cancelled (pending) order returns its stock.
--
-- Needs an active Officer in user_roles; otherwise the Officer steps print SKIP.
-- It changes nothing: it ends by raising an error on purpose (rolled back).
-- Run supabase_schema_officer_order_access.sql first.
-- ============================================================

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.chk(p_ok boolean, p_label text, p_detail text DEFAULT NULL)
RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN COALESCE(p_ok, false) THEN 'PASS ' ELSE 'FAIL ' END || p_label ||
         CASE WHEN p_detail IS NULL THEN '' ELSE ' — ' || p_detail END || E'\n';
$$;

DO $test$
DECLARE
  v_rep   TEXT := E'\n';
  F UUID; O UUID; B UUID; M UUID;
  v_mtype TEXT; v_unit TEXT;
  v_name  CONSTANT TEXT := 'Zz Officer Test Crop';
  v_cm UUID; v_fc UUID; v_h UUID; v_batch UUID; v_listing UUID;
  o_pick UUID; o_del UUID; o_pend UUID; o_appr UUID; o_out UUID; o_rdy UUID; o_dlv UUID; o_cancel UUID;
  v_msg TEXT; v_n INT; v_ok BOOLEAN;
  ord  orders%ROWTYPE;
  bt   inventory_batches%ROWTYPE;
  l    marketplace_listings%ROWTYPE;
BEGIN
  SELECT user_id INTO F FROM user_roles WHERE role = 'farmer' AND status = 'active'
    AND NOT COALESCE(pending_acknowledgement, false) ORDER BY user_id LIMIT 1;
  SELECT user_id INTO O FROM user_roles WHERE role = 'officer' AND status = 'active' ORDER BY user_id LIMIT 1;
  SELECT user_id INTO M FROM user_roles WHERE role = 'admin' AND status = 'active' LIMIT 1;
  SELECT user_id INTO B FROM user_roles WHERE role = 'buyer' AND status = 'active' LIMIT 1;
  SELECT code INTO v_mtype FROM market_types WHERE buyer_visible AND is_active ORDER BY sort_order LIMIT 1;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM units WHERE is_active AND lower(name) = 'kg') THEN 'kg' ELSE
           (SELECT name FROM units WHERE is_active ORDER BY name LIMIT 1) END INTO v_unit;
  IF F IS NULL OR B IS NULL OR M IS NULL OR v_mtype IS NULL THEN
    RAISE EXCEPTION E'OFFICER TEST REPORT\nSKIP everything: needs an active farmer and buyer and a buyer-visible market type (farmer=%, buyer=%, market=%)', F, B, v_mtype;
  END IF;
  IF O IS NULL THEN
    RAISE EXCEPTION E'OFFICER TEST REPORT\nSKIP everything: there is no active Officer in user_roles. Create an Officer account, then run this again.';
  END IF;
  v_rep := v_rep || 'INFO farmer ' || F || ', officer ' || O || ', buyer ' || B || E'\n';

  -- Test stock and a listing (a Manager approves it)
  INSERT INTO crop_master (crop_name, category, crop_type) VALUES (v_name, 'Other', v_mtype) RETURNING id INTO v_cm;
  INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id, photo_url)
    VALUES (F, v_name, 'Other', v_cm, 'https://example.invalid/zz-test-crop.jpg') RETURNING id INTO v_fc;
  INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
    VALUES (F, v_fc, v_name, 30, DATE '2096-03-04', v_unit) RETURNING id INTO v_h;
  INSERT INTO inventory_batches (farmer_id, harvest_record_id, crop_id, crop_name, quantity_kg, available_kg,
                                 status, is_coop_eligible, crop_type)
    VALUES (F, v_h, v_fc, v_name, 30, 30, 'available', TRUE, v_mtype) RETURNING id INTO v_batch;
  PERFORM pg_temp.as_user(F);
  v_listing := create_listing_with_reservation(v_batch, v_name, NULL, 20, 10.00, NULL, 'Officer test');
  RESET ROLE;
  -- Approving a LISTING is a Manager-only rule (approve_listing refuses Officers);
  -- the Officer's part is the ORDERS below.
  PERFORM pg_temp.as_user(M);
  PERFORM approve_listing(v_listing);
  RESET ROLE;

  -- Eight orders from the Buyer: 1 each, the delivery ones with an address.
  PERFORM pg_temp.as_user(B);
  o_pick   := place_order(v_listing, 1);
  o_del    := place_order(v_listing, 1, 'delivery', 'Purok 1, Payanas', 13.3, 122.1, '0917 000 0000', NULL, 'Test Buyer', 'Home');
  o_pend   := place_order(v_listing, 1);
  o_appr   := place_order(v_listing, 1);
  o_out    := place_order(v_listing, 1, 'delivery', 'Purok 2, Payanas', 13.3, 122.1, '0917 000 0001', NULL, 'Test Buyer', 'Home');
  o_rdy    := place_order(v_listing, 1);
  o_dlv    := place_order(v_listing, 1, 'delivery', 'Purok 3, Payanas', 13.3, 122.1, '0917 000 0002', NULL, 'Test Buyer', 'Home');
  o_cancel := place_order(v_listing, 1);
  RESET ROLE;

  -- ═════════════ The Officer reads what the order screens read ═════════════
  PERFORM pg_temp.as_user(O);
  SELECT count(*) INTO v_n FROM orders WHERE listing_id = v_listing;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_n = 8, 'O1 the Officer sees all 8 orders (Row Level Security lets staff read orders)', v_n::text);

  PERFORM pg_temp.as_user(O);
  SELECT count(*) INTO v_n FROM user_information WHERE user_id = B;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_n = 1, 'O2 the Officer can read the name and phone of the person who ordered', v_n::text);

  PERFORM pg_temp.as_user(O);
  SELECT count(*) INTO v_n FROM marketplace_listings WHERE id = v_listing;
  SELECT count(*) INTO bt.reserved_kg FROM inventory_batches WHERE id = v_batch;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_n = 1 AND bt.reserved_kg = 1, 'O3 the Officer can read the listing and its batch', v_n || ' / ' || bt.reserved_kg);

  -- ═════════════ The Officer approves and records fulfillment ═════════════
  PERFORM pg_temp.as_user(O);
  v_ok := approve_order(o_pick);
  PERFORM approve_order(o_del);
  PERFORM approve_order(o_appr);
  PERFORM approve_order(o_out);
  PERFORM approve_order(o_rdy);
  PERFORM approve_order(o_dlv);
  RESET ROLE;
  SELECT * INTO ord FROM orders WHERE id = o_pick;
  v_rep := v_rep || pg_temp.chk(v_ok AND ord.status = 'approved', 'O4 the Officer approves an order', ord.status);
  SELECT count(*) INTO v_n FROM notifications WHERE user_id = B AND title = 'Order Approved' AND created_at > now() - interval '1 minute';
  v_rep := v_rep || pg_temp.chk(v_n >= 6, 'O5 the consumer is notified of each approval', v_n::text);

  PERFORM pg_temp.as_user(O);
  v_ok := approve_order(o_pick);
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(NOT v_ok, 'O6 approving an already approved order is refused quietly (no second approval)', v_ok::text);

  PERFORM pg_temp.as_user(O);
  PERFORM mark_order_ready_for_pickup(o_pick);
  PERFORM mark_order_ready_for_pickup(o_rdy);
  PERFORM mark_order_out_for_delivery(o_del);
  PERFORM mark_order_out_for_delivery(o_out);
  PERFORM mark_order_out_for_delivery(o_dlv);
  PERFORM mark_order_delivered(o_del, 'https://example.invalid/zz-officer-1.jpg', NULL);
  PERFORM mark_order_delivered(o_dlv, 'https://example.invalid/zz-officer-2.jpg', 'left at the gate');
  RESET ROLE;
  SELECT * INTO ord FROM orders WHERE id = o_dlv;
  v_rep := v_rep || pg_temp.chk(ord.status = 'delivered' AND ord.fulfilled_by = O AND ord.delivery_photo_url IS NOT NULL,
    'O7 the Officer records Ready for Pickup, Out for Delivery and Delivered (with photo); the Officer is recorded', ord.status);

  -- ═════════════ What the Officer must NOT be able to do ═════════════
  v_msg := NULL;
  PERFORM pg_temp.as_user(O);
  BEGIN PERFORM complete_order(o_pick); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  BEGIN UPDATE orders SET status = 'completed' WHERE id = o_pick; EXCEPTION WHEN OTHERS THEN v_msg := COALESCE(v_msg, '') || ' | ' || SQLERRM; END;
  RESET ROLE;
  SELECT * INTO ord FROM orders WHERE id = o_pick;
  v_rep := v_rep || pg_temp.chk(ord.status = 'ready_for_pickup', 'O8 the Officer cannot complete an order (no override)', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(O);
  BEGIN PERFORM confirm_order_received(o_pick); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'O9 the Officer cannot confirm receipt for the consumer', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(O);
  BEGIN PERFORM cancel_my_order(o_appr, 'officer'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT * INTO ord FROM orders WHERE id = o_appr;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL AND ord.status = 'approved', 'O10 the Officer cannot cancel an order', v_msg);

  SELECT count(*) INTO v_n FROM pg_proc
   WHERE pronamespace = 'public'::regnamespace AND proname IN ('reject_order', 'cancel_order', 'disapprove_order');
  v_rep := v_rep || pg_temp.chk(v_n = 0, 'O11 there is no reject / cancel-order function for any staff role', v_n::text);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM approve_order(o_pend); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'O12 a Farmer cannot approve orders', v_msg);

  -- ═════════════ Cancelling: consumer only, pending only, stock released ═════════════
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  PERFORM pg_temp.as_user(B);
  PERFORM cancel_my_order(o_cancel, 'changed my mind');
  RESET ROLE;
  SELECT remaining_kg - l.remaining_kg INTO v_n FROM marketplace_listings WHERE id = v_listing;
  SELECT * INTO ord FROM orders WHERE id = o_cancel;
  v_rep := v_rep || pg_temp.chk(ord.status = 'cancelled' AND v_n = 1, 'C1 the consumer cancels a PENDING order: its stock returns to Available', ord.status || ', +' || v_n);

  v_msg := NULL;
  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM cancel_my_order(o_appr, 'late'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT * INTO ord FROM orders WHERE id = o_appr;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL AND ord.status = 'approved', 'C2 no cancellation after Approved', v_msg);

  -- ═════════════ Needs Action (the dashboard's count) ═════════════
  -- pending o_pend, approved o_appr, out_for_delivery o_out  => 3
  -- ready_for_pickup o_pick/o_rdy and delivered o_del/o_dlv wait only for the consumer => not counted
  PERFORM pg_temp.as_user(O);
  SELECT count(*) INTO v_n FROM orders
   WHERE listing_id = v_listing AND status IN ('pending', 'approved', 'out_for_delivery');
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_n = 3, 'N1 Needs Action = Pending 1 + Approved 1 + Out for Delivery 1 = 3', v_n::text);
  SELECT count(*) INTO v_n FROM orders
   WHERE listing_id = v_listing AND status IN ('ready_for_pickup', 'delivered');
  v_rep := v_rep || pg_temp.chk(v_n = 4, 'N2 the 4 orders waiting only for the consumer (2 Ready for Pickup + 2 Delivered) are left out', v_n::text);

  -- ═════════════ Stuck orders stay put, stock stays Reserved ═════════════
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(bt.sold_kg = 0 AND bt.reserved_kg = 20,
    'S1 nothing is sold while orders wait: sold 0, still reserved 20 (the whole listing)', 'sold ' || bt.sold_kg || ', reserved ' || bt.reserved_kg);

  -- the consumer confirms two of them: Reserved -> Sold, once, Completed
  PERFORM pg_temp.as_user(B);
  PERFORM confirm_order_received(o_pick);
  PERFORM confirm_order_received(o_del);
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  SELECT * INTO ord FROM orders WHERE id = o_del;
  v_rep := v_rep || pg_temp.chk(ord.status = 'completed' AND bt.sold_kg = 2 AND bt.reserved_kg = 18,
    'S2 on the consumer''s confirmation: Completed, Reserved -> Sold (2 sold, 18 reserved)', 'sold ' || bt.sold_kg || ', reserved ' || bt.reserved_kg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM confirm_order_received(o_pick); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL AND bt.sold_kg = 2, 'S3 confirming twice is refused: still 2 sold (exactly once)', v_msg);

  SELECT count(*) INTO v_n FROM orders WHERE listing_id = v_listing AND status IN ('ready_for_pickup', 'delivered', 'approved', 'out_for_delivery', 'pending');
  v_rep := v_rep || pg_temp.chk(v_n = 5, 'S4 the 5 unconfirmed orders are exactly where they were (no auto-complete)', v_n::text);

  RAISE EXCEPTION E'OFFICER TEST REPORT (rolled back; nothing was saved)\n%FAILED CHECKS: %',
    v_rep, (length(v_rep) - length(replace(v_rep, E'\nFAIL ', ''))) / 6;
END
$test$;
