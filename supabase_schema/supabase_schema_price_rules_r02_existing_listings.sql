-- ============================================================
-- SAGANA — Price rules: bring EXISTING open listings in line  (script r02)
--
-- FOR YOUR REVIEW — NOT APPLIED. Run AFTER r01 AND r03 (it uses the per-unit
-- rule from r03). One transaction, safe to re-run.
--
-- WHY
--   The price rules only act when a price is created or changed, or when a
--   Reference Price is saved. Listings that were already open when the rules
--   arrived were never evaluated. This script evaluates them once, the same way
--   saving a Reference Price now does:
--     Fixed Price   -> the listing price becomes the Fixed Price, and the Farmer
--                      is told. (A Fixed Price is the cooperative's price.)
--     Price Range   -> NOTHING is changed. A listing outside the range stays
--                      available with its own price; its Farmer is told that a
--                      price update is required and submits it for approval.
--   Orders already placed keep the price they were placed at.
--
-- NOT TOUCHED: listings whose crop has no Reference Price in their unit; sold,
-- withdrawn or disapproved listings; a listing carrying the shelf-life discount.
--
-- RUN THE PREVIEW FIRST.
-- ============================================================

-- ─── PREVIEW (read-only; run it by itself BEFORE the script) ─────────────
--   SELECT ml.id, ml.crop_name, ml.status, ml.remaining_kg, ml.unit,
--          ml.price_per_kg AS current_price, r.mode, r.price_min, r.price_max,
--          CASE WHEN r.mode = 'fixed' THEN 'price becomes ' || r.price_min
--               ELSE 'Farmer is asked to update the price' END AS what_happens
--     FROM marketplace_listings ml
--     JOIN LATERAL public._listing_price_rule(ml.inventory_batch_id) r ON TRUE
--     LEFT JOIN listing_shelf_life x ON x.listing_id = ml.id
--    WHERE ml.status IN ('pending_review', 'approved')
--      AND ml.remaining_kg > 0
--      AND x.discount_applied_on IS NULL
--      AND (ml.price_per_kg < r.price_min OR ml.price_per_kg > r.price_max)
--    ORDER BY ml.crop_name;
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$
DECLARE
  l       RECORD;
  v_fixed INTEGER := 0;
  v_asked INTEGER := 0;
BEGIN
  IF to_regprocedure('public.get_price_update_required_listings()') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_price_rules_r03_required_reference_and_changes.sql first.';
  END IF;

  FOR l IN
    SELECT ml.id, ml.farmer_id, ml.crop_name, ml.price_per_kg, ml.unit,
           r.mode, r.price_min, r.price_max
    FROM marketplace_listings ml
    JOIN LATERAL public._listing_price_rule(ml.inventory_batch_id) r ON TRUE
    LEFT JOIN listing_shelf_life x ON x.listing_id = ml.id
    WHERE ml.status IN ('pending_review', 'approved')
      AND ml.remaining_kg > 0
      AND x.discount_applied_on IS NULL
      AND (ml.price_per_kg < r.price_min OR ml.price_per_kg > r.price_max)
    FOR UPDATE OF ml
  LOOP
    IF l.mode = 'fixed' THEN
      UPDATE marketplace_listings SET price_per_kg = l.price_min WHERE id = l.id;
      INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
      VALUES (
        l.farmer_id, 'listing', 'Listing Price Updated',
        'The price of your ' || l.crop_name || ' listing was changed from ₱' ||
          to_char(l.price_per_kg, 'FM999999990.00') || ' to ₱' || to_char(l.price_min, 'FM999999990.00') ||
          ' per ' || l.unit || ' to follow the cooperative''s fixed price.',
        FALSE, NOW(), '/farmer/marketplace');
      v_fixed := v_fixed + 1;
    ELSE
      INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
      VALUES (
        l.farmer_id, 'listing', 'Price Update Required',
        'The Reference Price of ' || l.crop_name || ' is ₱' ||
          to_char(l.price_min, 'FM999999990.00') || '–₱' || to_char(l.price_max, 'FM999999990.00') ||
          ' per ' || l.unit || '. Your listing price of ₱' || to_char(l.price_per_kg, 'FM999999990.00') ||
          ' is outside this range. Your listing stays available; please edit its price and submit it for approval.',
        FALSE, NOW(), '/farmer/marketplace');
      v_asked := v_asked + 1;
    END IF;
  END LOOP;

  RAISE NOTICE 'Moved to the fixed price: %. Farmers asked to update a price: %.', v_fixed, v_asked;
END;
$$;

COMMIT;

-- ─── CHECK (read-only) ───────────────────────────────────────────────────
-- Run the PREVIEW again: only Price Range rows remain (they wait for the Farmer).
