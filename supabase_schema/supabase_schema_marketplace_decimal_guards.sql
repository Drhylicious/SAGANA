-- ============================================================
-- SAGANA — Marketplace decimals: the database refuses more than 2 decimal places
--          when a Marketplace order or listing is created
--
-- FOR YOUR REVIEW — NOT APPLIED. Run it once in the Supabase SQL editor, then the
-- CHECKS at the bottom. One transaction, safe to re-run.
--
-- WHAT ALREADY WORKS (nothing here changes it)
--   Harvest, listing quantity and price edits, stock adjustments, Product Sales
--   orders and payments are all DECIMAL(10,2) and the functions that take them
--   already refuse more than 2 decimals ("Use at most 2 decimal places ...").
--   The app only ever sends 2 decimals (0.45, 1.25, 10.75 ...).
--
-- THE GAP THIS CLOSES
--   Two Marketplace functions did not check the number of decimals:
--     1. place_order()                      the QUANTITY a Buyer or Farmer orders
--     2. create_listing_with_reservation()  the asking PRICE of a new listing
--        (its quantity is already checked, by _apply_batch_reservation)
--   Called from outside the app with, say, 0.456, the column rounds the stored
--   quantity to 0.46 while the total was worked out from 0.456, so an order could
--   carry a total a few centavos different from quantity x price. The app can't
--   cause that; a direct API call could.
--
-- HOW (so nothing newer is overwritten)
--   Each function is patched IN PLACE from its LIVE definition: one check is
--   inserted next to the check that is already there, and nothing else is
--   touched (so the order changes in the m05 script, the photo and selling-channel
--   rules, stock rules and the Officer permission gate all stay as they are). If
--   the expected line is not found, the script stops and changes nothing.
--
-- NOT CHANGED: tables, columns, RLS policies, grants, any other function; the
-- Cooperative Product functions (place_program_order already has this check).
-- ============================================================

BEGIN;

DO $patch$
DECLARE
  v_oid     oid;
  v_def     text;
  v_new     text;
  v_done    integer;

  -- 1. place_order: after the existing "quantity above zero" check.
  c_order_find  CONSTANT text := $p$(IF\s+p_quantity_kg\s+IS\s+NULL\s+OR\s+p_quantity_kg\s*<=\s*0\s+THEN\s+RAISE\s+EXCEPTION\s+'Quantity must be greater than zero';\s+END\s+IF;)$p$;
  c_order_add   CONSTANT text := $r$
  IF p_quantity_kg <> round(p_quantity_kg, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the quantity.';
  END IF;$r$;

  -- 2. create_listing_with_reservation: before the stock is reserved.
  c_list_find   CONSTANT text := $p$(PERFORM\s+(?:public\.)?_apply_batch_reservation\(\s*p_batch_id\s*,\s*p_quantity_kg\s*\)\s*;)$p$;
  c_list_add    CONSTANT text := $r$IF p_price_per_kg IS NULL OR p_price_per_kg <= 0 THEN
    RAISE EXCEPTION 'Enter a price greater than zero.';
  END IF;
  IF p_price_per_kg <> round(p_price_per_kg, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the price.';
  END IF;
  $r$;
BEGIN
  -- ── place_order ───────────────────────────────────────────────────────────
  v_done := 0;
  FOR v_oid IN
    SELECT p.oid FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'place_order'
  LOOP
    v_def := pg_get_functiondef(v_oid);
    IF v_def ~* 'p_quantity_kg\s*<>\s*round\(\s*p_quantity_kg' THEN
      v_done := v_done + 1;                       -- already has it
      CONTINUE;
    END IF;
    v_new := regexp_replace(v_def, c_order_find, '\1' || c_order_add, 'i');
    IF v_new = v_def THEN
      RAISE EXCEPTION 'place_order(): could not find the "Quantity must be greater than zero" check, so nothing was changed. Send me the live definition (CHECKS C1).';
    END IF;
    EXECUTE v_new;
    v_done := v_done + 1;
  END LOOP;
  IF v_done = 0 THEN
    RAISE EXCEPTION 'place_order() does not exist.';
  END IF;

  -- ── create_listing_with_reservation ───────────────────────────────────────
  v_done := 0;
  FOR v_oid IN
    SELECT p.oid FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'create_listing_with_reservation'
  LOOP
    v_def := pg_get_functiondef(v_oid);
    IF v_def ~* 'p_price_per_kg\s*<>\s*round\(\s*p_price_per_kg' THEN
      v_done := v_done + 1;
      CONTINUE;
    END IF;
    v_new := regexp_replace(v_def, c_list_find, c_list_add || '\1', 'i');
    IF v_new = v_def THEN
      RAISE NOTICE 'create_listing_with_reservation(%): no stock-reservation call found, left unchanged.', v_oid::regprocedure;
      CONTINUE;
    END IF;
    EXECUTE v_new;
    v_done := v_done + 1;
  END LOOP;
  IF v_done = 0 THEN
    RAISE EXCEPTION 'create_listing_with_reservation(): nothing was patched. Send me the live definition (CHECKS C2).';
  END IF;
END
$patch$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECKS (read-only; run after the script)
-- ============================================================
-- C1  place_order now checks the decimals (expect true on every row):
--     SELECT p.oid::regprocedure AS fn,
--            pg_get_functiondef(p.oid) ~* 'p_quantity_kg\s*<>\s*round\(\s*p_quantity_kg' AS checks_quantity_decimals,
--            pg_get_functiondef(p.oid) ILIKE '%own listing%'                            AS still_blocks_own_listing,
--            pg_get_functiondef(p.oid) ILIKE '%request_id%'                             AS still_idempotent
--       FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'place_order';
--
-- C2  The listing function now checks the price decimals, and still reserves stock:
--     SELECT p.oid::regprocedure AS fn,
--            pg_get_functiondef(p.oid) ~* 'p_price_per_kg\s*<>\s*round\(\s*p_price_per_kg' AS checks_price_decimals,
--            pg_get_functiondef(p.oid) ILIKE '%_apply_batch_reservation%'                   AS still_reserves_stock
--       FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'create_listing_with_reservation';
--
-- C3  Grants were kept (authenticated only, never anon):
--     SELECT routine_name, grantee FROM information_schema.routine_privileges
--      WHERE routine_schema = 'public' AND routine_name IN ('place_order','create_listing_with_reservation')
--      ORDER BY 1, 2;
--
-- C4  In the app: order 0.45 of a unit (works), and the order's total is
--     quantity x price to the centavo:
--     SELECT order_number, quantity_kg, price_per_kg, total_price,
--            total_price = round(quantity_kg * price_per_kg, 2) AS total_ok
--       FROM orders ORDER BY created_at DESC LIMIT 10;
