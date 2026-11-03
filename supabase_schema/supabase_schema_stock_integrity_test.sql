-- ============================================================
-- SAGANA — Marketplace stock: scenario test
--
-- Plays the real story with the real functions: a Buyer orders 5 kg from a
-- 20 kg listing; the Manager approves and completes it; orders are cancelled;
-- someone tries to order more than is left. After each step it checks the
-- quantity left (20 -> 15 and never wrong, never deducted twice).
--
-- It changes nothing: it ends by raising an error on purpose, which rolls
-- everything back, and the error text IS the report.
--
-- It borrows one approved Public listing and sets it to 20 kg inside the
-- test only. To choose your own, fill in v_listing / v_buyer / v_manager.
-- ============================================================

DO $test$
DECLARE
  v_listing  UUID := NULL;
  v_buyer    UUID := NULL;
  v_manager  UUID := NULL;

  v_report   TEXT := E'\n';
  v_fail     INT;
  v_farmer   UUID;
  v_o1       UUID;
  v_o2       UUID;
  v_o3       UUID;
  v_o4       UUID;
  v_rem      NUMERIC;
  v_status   TEXT;
  v_ostatus  TEXT;
  v_active   NUMERIC;
  v_ok       BOOLEAN;
BEGIN
  IF v_listing IS NULL THEN
    SELECT l.id INTO v_listing
    FROM marketplace_listings l
    WHERE l.status = 'approved'
      AND l.crop_type = (SELECT code FROM market_types WHERE buyer_visible ORDER BY sort_order LIMIT 1)
    LIMIT 1;
  END IF;
  SELECT farmer_id INTO v_farmer FROM marketplace_listings WHERE id = v_listing;
  IF v_buyer IS NULL THEN
    SELECT user_id INTO v_buyer FROM user_roles
    WHERE role = 'buyer' AND status = 'active' AND user_id <> COALESCE(v_farmer, '00000000-0000-0000-0000-000000000000') LIMIT 1;
  END IF;
  IF v_manager IS NULL THEN
    SELECT ap.user_id INTO v_manager FROM admin_profiles ap JOIN user_roles r ON r.user_id = ap.user_id AND r.status = 'active' LIMIT 1;
  END IF;
  IF v_listing IS NULL OR v_buyer IS NULL OR v_manager IS NULL THEN
    RAISE EXCEPTION 'Nothing suitable found. Need an approved Public listing (found: %), an active Buyer (found: %) and a Manager (found: %). Fill them in at the top of the test.',
      COALESCE(v_listing::text, 'none'), COALESCE(v_buyer::text, 'none'), COALESCE(v_manager::text, 'none');
  END IF;

  -- Start from a clean 20 kg listing (rolled back at the end).
  UPDATE marketplace_listings SET volume_kg = 20, remaining_kg = 20 WHERE id = v_listing;
  SELECT COALESCE(SUM(quantity_kg), 0) INTO v_active FROM orders
  WHERE listing_id = v_listing AND status NOT IN ('cancelled', 'rejected');
  -- Existing orders on this listing are real data; count them as already taken.
  IF v_active > 0 THEN
    UPDATE marketplace_listings SET volume_kg = 20 + v_active, remaining_kg = 20 WHERE id = v_listing;
  END IF;

  -- 1. Buyer orders 5 kg ----------------------------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_buyer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_o1 := public.place_order(v_listing, 5);
  EXECUTE 'RESET ROLE';
  SELECT remaining_kg, status INTO v_rem, v_status FROM marketplace_listings WHERE id = v_listing;
  v_report := v_report || CASE WHEN v_rem = 15 AND v_status = 'approved' THEN 'PASS ' ELSE 'FAIL ' END
    || E'1  ordering 5 kg from 20 kg leaves 15 kg at once (pending order): ' || v_rem || E' kg\n';

  -- 2. Manager approves: nothing more is taken ---------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM public.approve_order(v_o1);
  PERFORM public.mark_order_ready_for_pickup(v_o1);
  EXECUTE 'RESET ROLE';
  SELECT remaining_kg INTO v_rem FROM marketplace_listings WHERE id = v_listing;
  SELECT status INTO v_ostatus FROM orders WHERE id = v_o1;
  v_report := v_report || CASE WHEN v_rem = 15 AND v_ostatus IN ('approved', 'ready_for_pickup') THEN 'PASS ' ELSE 'FAIL ' END
    || E'2  approving the order keeps 15 kg (no second deduction): ' || v_rem || E' kg\n';

  -- 3. The Buyer confirms receipt (this completes it): still nothing more is taken ----
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_buyer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM public.confirm_order_received(v_o1);
  EXECUTE 'RESET ROLE';
  SELECT remaining_kg, status INTO v_rem, v_status FROM marketplace_listings WHERE id = v_listing;
  SELECT status INTO v_ostatus FROM orders WHERE id = v_o1;
  v_report := v_report || CASE WHEN v_rem = 15 AND v_ostatus = 'completed' THEN 'PASS ' ELSE 'FAIL ' END
    || E'3  completing the order keeps 15 kg: ' || v_rem || E' kg\n';
  v_report := v_report || CASE WHEN v_status = 'approved' THEN 'PASS ' ELSE 'FAIL ' END
    || E'4  the listing is still Available (not Sold Out) with 15 kg left: status ' || v_status || E'\n';

  -- 5. Buyer orders 5 kg and cancels: the kg come back once ---------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_buyer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_o2 := public.place_order(v_listing, 5);
  EXECUTE 'RESET ROLE';
  SELECT remaining_kg INTO v_rem FROM marketplace_listings WHERE id = v_listing;
  v_report := v_report || CASE WHEN v_rem = 10 THEN 'PASS ' ELSE 'FAIL ' END || E'5a a second 5 kg order leaves 10 kg: ' || v_rem || E' kg\n';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_buyer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM public.cancel_my_order(v_o2, 'changed my mind');
  EXECUTE 'RESET ROLE';
  SELECT remaining_kg INTO v_rem FROM marketplace_listings WHERE id = v_listing;
  v_report := v_report || CASE WHEN v_rem = 15 THEN 'PASS ' ELSE 'FAIL ' END || E'5b cancelling it gives the 5 kg back, once: ' || v_rem || E' kg\n';

  -- 6. Cancelling the same order again must not give more back ------------------
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_buyer, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.cancel_my_order(v_o2, 'again');
    EXECUTE 'RESET ROLE';
    v_report := v_report || E'FAIL 6  a cancelled order was cancelled a second time\n';
  EXCEPTION WHEN OTHERS THEN
    EXECUTE 'RESET ROLE';
    v_report := v_report || 'PASS 6  a cancelled order cannot be cancelled again (' || SQLERRM || E')\n';
  END;
  SELECT remaining_kg INTO v_rem FROM marketplace_listings WHERE id = v_listing;
  v_report := v_report || CASE WHEN v_rem = 15 THEN 'PASS ' ELSE 'FAIL ' END || E'7  still 15 kg after the refused second cancel: ' || v_rem || E' kg\n';

  -- 8. Take everything that is left: Sold Out, then an order is refused ----------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_buyer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_o3 := public.place_order(v_listing, 15);
  EXECUTE 'RESET ROLE';
  SELECT remaining_kg INTO v_rem FROM marketplace_listings WHERE id = v_listing;
  v_report := v_report || CASE WHEN v_rem = 0 THEN 'PASS ' ELSE 'FAIL ' END || E'8  ordering the last 15 kg leaves 0 (Sold Out): ' || v_rem || E' kg\n';

  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_buyer, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_o4 := public.place_order(v_listing, 1);
    EXECUTE 'RESET ROLE';
    v_report := v_report || E'FAIL 9  an order was accepted on a sold-out listing (overselling)\n';
  EXCEPTION WHEN OTHERS THEN
    EXECUTE 'RESET ROLE';
    v_report := v_report || 'PASS 9  no overselling: the next order is refused (' || SQLERRM || E')\n';
  END;

  -- 10. Cancelling the 15 kg order puts the listing back on sale -----------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_buyer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM public.cancel_my_order(v_o3, NULL);
  EXECUTE 'RESET ROLE';
  SELECT remaining_kg, status INTO v_rem, v_status FROM marketplace_listings WHERE id = v_listing;
  v_report := v_report || CASE WHEN v_rem = 15 AND v_status = 'approved' THEN 'PASS ' ELSE 'FAIL ' END
    || E'10 cancelling it brings 15 kg back and the listing is Available again: ' || v_rem || ' kg, ' || v_status || E'\n';

  -- 11. The books balance --------------------------------------------------------
  SELECT l.remaining_kg = l.volume_kg - COALESCE((SELECT SUM(quantity_kg) FROM orders
      WHERE listing_id = l.id AND status NOT IN ('cancelled', 'rejected')), 0)
  INTO STRICT v_ok FROM marketplace_listings l WHERE l.id = v_listing;
  v_report := v_report || CASE WHEN v_ok THEN 'PASS ' ELSE 'FAIL ' END
    || E'11 remaining_kg = listed kg - live orders, to the gram\n';

  -- 12. The rules are in place ---------------------------------------------------
  v_report := v_report || CASE WHEN (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
      WHERE p.proname = 'place_order') = 1 THEN 'PASS ' ELSE 'FAIL ' END || E'12 exactly one place_order exists (no old overload)\n';
  v_report := v_report || CASE WHEN EXISTS (SELECT 1 FROM pg_constraint
      WHERE conrelid = 'public.marketplace_listings'::regclass AND conname = 'marketplace_listings_remaining_le_volume')
    THEN 'PASS ' ELSE 'SKIP ' END || E'13 remaining_kg <= volume_kg rule installed (run supabase_schema_stock_integrity.sql STEP 3)\n';
  v_report := v_report || CASE WHEN (SELECT count(*) FROM pg_publication_tables WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public' AND tablename IN ('marketplace_listings', 'orders')) = 2
    THEN 'PASS ' ELSE 'SKIP ' END || E'14 listings and orders are in the realtime publication (live updates)\n';

  v_fail := (length(v_report) - length(replace(v_report, E'\nFAIL ', ''))) / 6;
  RAISE EXCEPTION E'STOCK TEST REPORT (nothing was saved)\n% \nFAILED CHECKS: %', v_report, v_fail;
END
$test$;
