-- ============================================================
-- SAGANA — Marketplace order fulfillment workflow: end-to-end test
--
-- As a real Buyer, Farmer(s) and Manager from your data, on a fresh 30-unit batch:
--
--   PICKUP    place -> approve -> Ready for Pickup -> consumer confirms -> Completed
--   DELIVERY  place -> approve -> Out for Delivery -> Mark as Delivered (photo
--             required) -> consumer confirms -> Completed
--   and, for both: every wrong order of steps, the wrong role, the wrong method,
--   confirming too early, confirming twice, the Manager completing, cancelling
--   after approval, and stock (sold only on completion, exactly once).
--
-- It changes nothing: it ends by raising an error on purpose, which rolls
-- everything back; the error text IS the report (PASS / FAIL / SKIP).
-- Run supabase_schema_order_fulfillment_workflow.sql first.
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
  F UUID; F2 UUID; M UUID; B UUID;
  v_mtype TEXT; v_unit TEXT;
  v_name  CONSTANT TEXT := 'Zz Fulfillment Test Crop';
  v_cm UUID; v_fc UUID; v_h UUID; v_batch UUID; v_listing UUID;
  v_p1 UUID; v_p2 UUID; v_d1 UUID; v_d2 UUID; v_f1 UUID;
  v_msg TEXT; v_n INT;
  o   orders%ROWTYPE;
  l   marketplace_listings%ROWTYPE;
  bt  inventory_batches%ROWTYPE;
BEGIN
  SELECT user_id INTO F FROM user_roles WHERE role = 'farmer' AND status = 'active'
    AND NOT COALESCE(pending_acknowledgement, false) ORDER BY user_id LIMIT 1;
  SELECT user_id INTO F2 FROM user_roles WHERE role = 'farmer' AND status = 'active'
    AND user_id <> F ORDER BY user_id LIMIT 1;
  SELECT user_id INTO M FROM user_roles WHERE role = 'admin' AND status = 'active' LIMIT 1;
  SELECT user_id INTO B FROM user_roles WHERE role = 'buyer' AND status = 'active' LIMIT 1;
  SELECT code INTO v_mtype FROM market_types WHERE buyer_visible AND is_active ORDER BY sort_order LIMIT 1;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM units WHERE is_active AND lower(name) = 'kg') THEN 'kg' ELSE
           (SELECT name FROM units WHERE is_active ORDER BY name LIMIT 1) END INTO v_unit;
  IF F IS NULL OR M IS NULL OR B IS NULL OR v_mtype IS NULL THEN
    RAISE EXCEPTION E'FULFILLMENT TEST REPORT\nSKIP everything: needs an active farmer, admin and buyer and a buyer-visible market type (farmer=%, admin=%, buyer=%, market=%)', F, M, B, v_mtype;
  END IF;
  v_rep := v_rep || 'INFO farmer ' || F || ', second farmer ' || COALESCE(F2::text, 'none') || ', manager ' || M || ', buyer ' || B || E'\n';

  INSERT INTO crop_master (crop_name, category, crop_type) VALUES (v_name, 'Other', v_mtype) RETURNING id INTO v_cm;
  INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id, photo_url)
    VALUES (F, v_name, 'Other', v_cm, 'https://example.invalid/zz-test-crop.jpg') RETURNING id INTO v_fc;
  INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
    VALUES (F, v_fc, v_name, 30, DATE '2096-03-04', v_unit) RETURNING id INTO v_h;
  INSERT INTO inventory_batches (farmer_id, harvest_record_id, crop_id, crop_name, quantity_kg, available_kg,
                                 status, is_coop_eligible, crop_type)
    VALUES (F, v_h, v_fc, v_name, 30, 30, 'available', TRUE, v_mtype) RETURNING id INTO v_batch;

  PERFORM pg_temp.as_user(F);
  v_listing := create_listing_with_reservation(v_batch, v_name, NULL, 20, 10.00, NULL, 'Fulfillment test');
  RESET ROLE;
  PERFORM pg_temp.as_user(M);
  PERFORM approve_listing(v_listing);
  RESET ROLE;

  -- ═════════════ PICKUP ═════════════
  PERFORM pg_temp.as_user(B);
  v_p1 := place_order(v_listing, 3);
  v_p2 := place_order(v_listing, 1);
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_p1;
  v_rep := v_rep || pg_temp.chk(o.status = 'pending' AND COALESCE(o.fulfillment_method, 'pickup') = 'pickup',
    'P1 a Buyer places a pickup order: pending', o.status);

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM mark_order_ready_for_pickup(v_p1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'P2 a PENDING order cannot be marked Ready for Pickup (approve first)', v_msg);

  PERFORM pg_temp.as_user(M);
  PERFORM approve_order(v_p1);
  RESET ROLE;

  v_msg := NULL;
  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM confirm_order_received(v_p1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'P3 confirming receipt is refused while only APPROVED', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM mark_order_out_for_delivery(v_p1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'P4 a pickup order cannot go Out for Delivery', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM mark_order_ready_for_pickup(v_p1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'P5 a Buyer cannot mark their own order Ready for Pickup', v_msg);

  PERFORM pg_temp.as_user(M);
  PERFORM mark_order_ready_for_pickup(v_p1);
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_p1;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(o.status = 'ready_for_pickup' AND o.ready_at IS NOT NULL AND o.fulfilled_by = M AND bt.sold_kg = 0,
    'P6 Manager marks Ready for Pickup: status, time and who recorded; nothing sold yet', o.status || ', sold ' || bt.sold_kg);
  SELECT count(*) INTO v_n FROM notifications WHERE user_id = B AND title = 'Order Ready for Pickup' AND created_at > now() - interval '1 minute';
  v_rep := v_rep || pg_temp.chk(v_n >= 1, 'P7 the consumer is notified', v_n::text);

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM mark_order_ready_for_pickup(v_p1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'P8 marking Ready for Pickup twice is refused', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM cancel_my_order(v_p1, 'late'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_p1;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL AND o.status = 'ready_for_pickup',
    'P9 the consumer cannot cancel after approval (cancellation is for pending orders only)', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM complete_order(v_p1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  BEGIN UPDATE orders SET status = 'completed' WHERE id = v_p1; EXCEPTION WHEN OTHERS THEN v_msg := COALESCE(v_msg, '') || ' | ' || SQLERRM; END;
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_p1;
  v_rep := v_rep || pg_temp.chk(o.status = 'ready_for_pickup', 'P10 the Manager cannot complete the order', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM confirm_order_received(v_p1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'P11 only the consumer who ordered can confirm receipt', v_msg);

  PERFORM pg_temp.as_user(B);
  PERFORM confirm_order_received(v_p1);
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_p1;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(o.status = 'completed' AND o.received_by = B AND o.received_at IS NOT NULL AND bt.sold_kg = 3 AND bt.reserved_kg = 17,
    'P12 the Buyer confirms from Ready for Pickup: Completed, sold 3, reserved 17', o.status || ', sold ' || bt.sold_kg || ', reserved ' || bt.reserved_kg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM confirm_order_received(v_p1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL AND bt.sold_kg = 3, 'P13 confirming twice is refused: sold stays 3 (no duplicate deduction)', v_msg);

  v_msg := NULL;
  BEGIN UPDATE orders SET status = 'ready_for_pickup' WHERE id = v_p1; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'P14 a completed order can never move again', v_msg);

  -- a pending order can still be cancelled by its consumer, and gives its kg back
  PERFORM pg_temp.as_user(B);
  PERFORM cancel_my_order(v_p2, 'changed my mind');
  RESET ROLE;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  SELECT * INTO o FROM orders WHERE id = v_p2;
  v_rep := v_rep || pg_temp.chk(o.status = 'cancelled' AND l.remaining_kg = 17,
    'P15 a pending order is still cancelled by its consumer: its kg return to the listing', 'remaining ' || l.remaining_kg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM approve_order(v_p2); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_p2;
  v_rep := v_rep || pg_temp.chk(o.status = 'cancelled', 'P16 a cancelled order cannot be approved', COALESCE(v_msg, 'approve_order returned without changing it'));

  -- ═════════════ DELIVERY ═════════════
  PERFORM pg_temp.as_user(B);
  v_d1 := place_order(v_listing, 2, 'delivery', 'Purok 1, Payanas, Torrijos', 13.3, 122.1, '0917 000 0000', 'gate', 'Test Buyer', 'Home');
  v_d2 := place_order(v_listing, 1, 'delivery', 'Purok 2, Payanas, Torrijos', 13.3, 122.1, '0917 000 0001', NULL, 'Test Buyer', 'Home');
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_d1;
  v_rep := v_rep || pg_temp.chk(o.status = 'pending' AND o.fulfillment_method = 'delivery', 'D1 a Buyer places a delivery order: pending', o.status);

  PERFORM pg_temp.as_user(M);
  PERFORM approve_order(v_d1);
  RESET ROLE;

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM mark_order_ready_for_pickup(v_d1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'D2 a delivery order cannot be marked Ready for Pickup', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM mark_order_delivered(v_d1, 'https://example.invalid/d.jpg', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'D3 cannot be marked Delivered before it is Out for Delivery', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM confirm_order_received(v_d1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'D4 confirming receipt is refused while only APPROVED', v_msg);

  PERFORM pg_temp.as_user(M);
  PERFORM mark_order_out_for_delivery(v_d1);
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_d1;
  v_rep := v_rep || pg_temp.chk(o.status = 'out_for_delivery' AND o.out_for_delivery_at IS NOT NULL AND o.fulfilled_by = M,
    'D5 Manager marks Out for Delivery', o.status);

  v_msg := NULL;
  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM confirm_order_received(v_d1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'D6 confirming receipt is refused while Out for Delivery', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM mark_order_delivered(v_d1, '', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_d1;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL AND o.status = 'out_for_delivery', 'D7 Delivered needs the photo evidence', v_msg);

  v_msg := NULL;
  BEGIN UPDATE orders SET status = 'delivered' WHERE id = v_d1; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'D8 not even a direct update can mark Delivered without a photo', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM mark_order_delivered(v_d1, 'https://example.invalid/d.jpg', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'D9 a Buyer cannot mark their own order Delivered', v_msg);

  PERFORM pg_temp.as_user(M);
  PERFORM mark_order_delivered(v_d1, 'https://example.invalid/zz-order-delivery.jpg', 'left at the gate');
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_d1;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(o.status = 'delivered' AND o.delivery_photo_url IS NOT NULL AND o.delivered_at IS NOT NULL AND bt.sold_kg = 3,
    'D10 Delivered with photo evidence, time and note; still not sold', o.status || ', sold ' || bt.sold_kg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM mark_order_delivered(v_d1, 'https://example.invalid/again.jpg', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'D11 marking Delivered twice is refused', v_msg);

  PERFORM pg_temp.as_user(B);
  PERFORM confirm_order_received(v_d1);
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_d1;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(o.status = 'completed' AND bt.sold_kg = 5 AND bt.reserved_kg = 15,
    'D12 the Buyer confirms from Delivered: Completed, sold 5 (3 + 2), reserved 15', o.status || ', sold ' || bt.sold_kg || ', reserved ' || bt.reserved_kg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM confirm_order_received(v_d1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL AND bt.sold_kg = 5, 'D13 confirming twice is refused: sold stays 5', v_msg);

  -- an approved delivery order is committed: it cannot be cancelled
  PERFORM pg_temp.as_user(M);
  PERFORM approve_order(v_d2);
  RESET ROLE;
  v_msg := NULL;
  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM cancel_my_order(v_d2, 'nope'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_d2;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL AND o.status = 'approved', 'D14 an approved delivery order cannot be cancelled', v_msg);

  -- ═════════════ FARMER AS CONSUMER ═════════════
  IF F2 IS NULL THEN
    v_rep := v_rep || E'SKIP F1-F3 need a second farmer who can buy\n';
  ELSE
    BEGIN
      PERFORM pg_temp.as_user(F2);
      v_f1 := place_order(v_listing, 2);
      RESET ROLE;
      PERFORM pg_temp.as_user(M);
      PERFORM approve_order(v_f1);
      PERFORM mark_order_ready_for_pickup(v_f1);
      RESET ROLE;
      SELECT count(*) INTO v_n FROM notifications WHERE user_id = F2 AND title = 'Order Ready for Pickup'
        AND route_on_tap = '/farmer/profile/orders' AND created_at > now() - interval '1 minute';
      v_rep := v_rep || pg_temp.chk(v_n = 1, 'F1 a Farmer consumer is notified and sent to their own My Orders screen', v_n::text);
      PERFORM pg_temp.as_user(F2);
      PERFORM confirm_order_received(v_f1);
      RESET ROLE;
      SELECT * INTO o FROM orders WHERE id = v_f1;
      SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
      v_rep := v_rep || pg_temp.chk(o.status = 'completed' AND o.received_by = F2 AND bt.sold_kg = 7,
        'F2 a Farmer consumer confirms the same way: Completed, sold 7', o.status || ', sold ' || bt.sold_kg);
      v_msg := NULL;
      PERFORM pg_temp.as_user(F2);
      BEGIN PERFORM mark_order_ready_for_pickup(v_f1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
      RESET ROLE;
      v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'F3 a Farmer cannot record fulfillment steps (Manager / Officer only)', v_msg);
    EXCEPTION WHEN OTHERS THEN
      RESET ROLE;
      v_rep := v_rep || E'SKIP F1-F3 the second farmer could not buy in this data: ' || SQLERRM || E'\n';
    END;
  END IF;

  -- ═════════════ FINAL STOCK ═════════════
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(abs(bt.available_kg + bt.reserved_kg + bt.sold_kg + bt.adjusted_kg - bt.quantity_kg) < 0.005,
    'Z1 available + reserved + sold + adjusted = harvested', bt.available_kg || ' + ' || bt.reserved_kg || ' + ' || bt.sold_kg || ' + ' || bt.adjusted_kg);
  SELECT count(*) INTO v_n FROM stock_movements WHERE batch_id = v_batch AND movement_type = 'sold' AND channel = 'marketplace';
  SELECT sum(quantity) INTO l.remaining_kg FROM stock_movements WHERE batch_id = v_batch AND movement_type = 'sold';
  v_rep := v_rep || pg_temp.chk(l.remaining_kg = bt.sold_kg, 'Z2 the stock history adds up to the sold figure, once per completed order', l.remaining_kg || ' vs ' || bt.sold_kg || ' (' || v_n || ' sold rows)');

  RAISE EXCEPTION E'FULFILLMENT TEST REPORT (rolled back; nothing was saved)\n%FAILED CHECKS: %',
    v_rep, (length(v_rep) - length(replace(v_rep, E'\nFAIL ', ''))) / 6;
END
$test$;
