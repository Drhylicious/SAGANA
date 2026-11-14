-- ============================================================
-- SAGANA — Price rules, part 3: a Reference Price is REQUIRED to list, it is
--          matched by UNIT, and a price change is applied to existing listings
--
-- FOR YOUR REVIEW — NOT APPLIED. Run AFTER r01 and BEFORE r02 (the order is
-- r01, r03, r02). One transaction, safe to re-run.
--
-- WHAT CHANGES
--   1. THE RULE IS PER UNIT. The Marketplace rule of a harvest batch is now the
--      latest Reference Price of its crop, in its market type, IN THE BATCH'S OWN
--      UNIT. A crop can therefore carry one Reference Price per unit (kg, sack,
--      bottle ...). Nothing is converted and no harvest record is changed.
--   2. NO REFERENCE PRICE, NO MARKETPLACE LISTING. Creating a listing is refused
--      when the crop has no Reference Price in the harvest's unit. Only the
--      Marketplace is affected: Offer to Cooperative, Informal Sale and DA-AMAD
--      Market Linking do not use this rule at all. Editing an existing listing is
--      unchanged (a price that is not being changed is never re-checked).
--   3. A SAVED REFERENCE PRICE IS APPLIED TO OPEN LISTINGS (trigger on
--      price_records):
--        Fixed Price   every open listing of that crop/market/unit moves to the
--                      new price at once; the Farmer is told. A listing carrying
--                      the shelf-life discount keeps its discounted price (only
--                      the price it returns to is updated).
--        Price Range   no listing price is changed. A listing now outside the
--                      range stays available; its Farmer is told to update it.
--   4. get_price_update_required_listings(): the open listings whose price is
--      outside their crop's current range. Worked out from live data, so the
--      "Price Update Required" mark disappears by itself once an in-range price
--      is approved. A Farmer gets their own; staff get all.
--   5. Guest price list (public_latest_prices) is patched IN PLACE to keep one
--      latest price per crop, market AND unit.
--
-- NOT CHANGED: tables and columns, the approval workflow, order prices (an
-- order keeps the price it was placed at), any selling function.
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public._assert_listing_price(uuid, numeric, numeric)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_price_rules_r01_reference_price.sql first.';
  END IF;
END;
$$;

-- ═══ 1. The rule of a batch: latest Reference Price IN THE BATCH'S UNIT ══
CREATE OR REPLACE FUNCTION public._listing_price_rule(p_batch_id UUID)
RETURNS TABLE (mode TEXT, price_min NUMERIC, price_max NUMERIC, unit TEXT, crop_name TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT latest.price_mode, latest.price, COALESCE(latest.price_max, latest.price),
         latest.unit, latest.crop_name
  FROM inventory_batches b
  JOIN farmer_crops fc ON fc.id = b.crop_id
  JOIN crop_master cm  ON cm.id = fc.crop_master_id
  JOIN LATERAL (
    SELECT pr.price_mode, pr.price, pr.price_max, pr.unit, pr.crop_name
    FROM price_records pr
    WHERE pr.crop_id = cm.id
      AND pr.price_type = COALESCE(b.crop_type, cm.crop_type)
      AND lower(btrim(pr.unit)) = lower(btrim(COALESCE(b.unit, 'kg')))
    ORDER BY pr.recorded_at DESC
    LIMIT 1
  ) latest ON TRUE
  WHERE b.id = p_batch_id;
$$;
REVOKE ALL ON FUNCTION public._listing_price_rule(UUID) FROM PUBLIC, anon, authenticated;

-- ═══ 2. A new listing needs a Reference Price in its unit ═══════════════
-- Same function as r01 with one addition: on INSERT, no rule = refused.
CREATE OR REPLACE FUNCTION public._listing_price_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r       RECORD;
  v_floor NUMERIC;
  v_crop  TEXT;
  v_unit  TEXT;
BEGIN
  IF NEW.inventory_batch_id IS NULL THEN
    RETURN NEW;
  END IF;
  -- The automatic shelf-life discount is exempt (process_shelf_life sets this).
  IF COALESCE(current_setting('sagana.shelf_discount', true), '') = '1' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    SELECT * INTO r FROM public._listing_price_rule(NEW.inventory_batch_id);
    IF NOT FOUND THEN
      SELECT b.crop_name, COALESCE(b.unit, 'kg') INTO v_crop, v_unit
      FROM inventory_batches b WHERE b.id = NEW.inventory_batch_id;
      RAISE EXCEPTION 'PRICE_REFERENCE_REQUIRED: The cooperative has not set a Reference Price for % per % yet, so it cannot be listed on the Marketplace. You can still sell this harvest through your other selling channels.',
        COALESCE(v_crop, NEW.crop_name, 'this crop'), v_unit;
    END IF;
    -- A Fixed Price crop is listed AT the fixed price, whatever was sent.
    IF r.mode = 'fixed' THEN
      NEW.price_per_kg := r.price_min;
      RETURN NEW;
    END IF;
    PERFORM public._assert_listing_price(NEW.inventory_batch_id, NEW.price_per_kg);
    RETURN NEW;
  END IF;

  IF NEW.price_per_kg IS NOT DISTINCT FROM OLD.price_per_kg THEN
    RETURN NEW;                                 -- the price is not being changed
  END IF;

  IF EXISTS (SELECT 1 FROM listing_shelf_life x
             WHERE x.listing_id = NEW.id AND x.discount_applied_on IS NOT NULL) THEN
    v_floor := OLD.price_per_kg;
  END IF;
  PERFORM public._assert_listing_price(NEW.inventory_batch_id, NEW.price_per_kg, v_floor);
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._listing_price_guard() FROM PUBLIC, anon, authenticated;

-- ═══ 3. A saved Reference Price is applied to the open listings ═════════
CREATE OR REPLACE FUNCTION public._price_record_apply_to_listings()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  l RECORD;
  r RECORD;
BEGIN
  IF NEW.crop_id IS NULL THEN
    RETURN NULL;
  END IF;

  FOR l IN
    SELECT ml.id, ml.farmer_id, ml.crop_name, ml.price_per_kg, ml.unit, ml.inventory_batch_id,
           (x.discount_applied_on IS NOT NULL) AS discounted
    FROM marketplace_listings ml
    JOIN inventory_batches b ON b.id = ml.inventory_batch_id
    JOIN farmer_crops fc     ON fc.id = b.crop_id
    JOIN crop_master cm      ON cm.id = fc.crop_master_id
    LEFT JOIN listing_shelf_life x ON x.listing_id = ml.id
    WHERE cm.id = NEW.crop_id
      AND COALESCE(b.crop_type, cm.crop_type) = NEW.price_type
      AND lower(btrim(COALESCE(b.unit, 'kg'))) = lower(btrim(NEW.unit))
      AND ml.status IN ('pending_review', 'approved')
      AND ml.remaining_kg > 0
    FOR UPDATE OF ml
  LOOP
    -- The rule now in force (a backdated record may not be the latest one).
    SELECT * INTO r FROM public._listing_price_rule(l.inventory_batch_id);
    CONTINUE WHEN NOT FOUND;

    IF r.mode = 'fixed' THEN
      IF l.discounted THEN
        -- Keeps its shelf-life discount; only the price it returns to moves.
        UPDATE listing_shelf_life
           SET pre_discount_price = r.price_min, updated_at = NOW()
         WHERE listing_id = l.id;
      ELSIF l.price_per_kg <> r.price_min THEN
        UPDATE marketplace_listings SET price_per_kg = r.price_min WHERE id = l.id;
        INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
        VALUES (
          l.farmer_id, 'listing', 'Listing Price Updated',
          'The cooperative changed the fixed price of ' || l.crop_name || '. Your listing moved from ₱' ||
            to_char(l.price_per_kg, 'FM999999990.00') || ' to ₱' || to_char(r.price_min, 'FM999999990.00') ||
            ' per ' || l.unit || '.',
          FALSE, NOW(), '/farmer/marketplace');
      END IF;
    ELSIF NOT l.discounted
          AND (l.price_per_kg < r.price_min OR l.price_per_kg > r.price_max) THEN
      INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
      VALUES (
        l.farmer_id, 'listing', 'Price Update Required',
        'The Reference Price of ' || l.crop_name || ' changed to ₱' ||
          to_char(r.price_min, 'FM999999990.00') || '–₱' || to_char(r.price_max, 'FM999999990.00') ||
          ' per ' || l.unit || '. Your listing price of ₱' || to_char(l.price_per_kg, 'FM999999990.00') ||
          ' is outside this range. Your listing stays available; please edit its price and submit it for approval.',
        FALSE, NOW(), '/farmer/marketplace');
    END IF;
  END LOOP;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._price_record_apply_to_listings() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_price_records_apply_to_listings ON public.price_records;
CREATE TRIGGER trg_price_records_apply_to_listings
  AFTER INSERT ON public.price_records
  FOR EACH ROW EXECUTE FUNCTION public._price_record_apply_to_listings();

-- ═══ 4. Which listings need a price update ══════════════════════════════
-- Open listings whose price is outside their crop's CURRENT rule (and that do
-- not carry the shelf-life discount, which is allowed below the minimum).
-- Returns [{listing_id, price_min, price_max, unit}]. Nothing is stored.
CREATE OR REPLACE FUNCTION public.get_price_update_required_listings()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'listing_id', ml.id, 'price_min', r.price_min,
           'price_max', r.price_max, 'unit', r.unit)), '[]'::jsonb)
  FROM marketplace_listings ml
  JOIN LATERAL public._listing_price_rule(ml.inventory_batch_id) r ON TRUE
  LEFT JOIN listing_shelf_life x ON x.listing_id = ml.id
  WHERE auth.uid() IS NOT NULL
    AND (ml.farmer_id = auth.uid() OR public.is_staff())
    AND ml.status IN ('pending_review', 'approved')
    AND ml.remaining_kg > 0
    AND x.discount_applied_on IS NULL
    AND (ml.price_per_kg < r.price_min OR ml.price_per_kg > r.price_max);
$$;
REVOKE ALL ON FUNCTION public.get_price_update_required_listings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_price_update_required_listings() TO authenticated;

-- ═══ 5. Guest price list: one latest price per crop, market AND unit ════
DO $patch$
DECLARE
  v_oid oid;
  v_def text;
  v_new text;
BEGIN
  FOR v_oid IN
    SELECT p.oid FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'public_latest_prices'
  LOOP
    v_def := pg_get_functiondef(v_oid);
    IF v_def ILIKE '%lower(pr.unit)%' THEN
      CONTINUE;                                   -- already patched
    END IF;
    v_new := regexp_replace(v_def,
      $p$DISTINCT\s+ON\s*\(\s*pr\.crop_id\s*,\s*pr\.price_type\s*\)$p$,
      'DISTINCT ON (pr.crop_id, pr.price_type, lower(pr.unit))', 'i');
    v_new := regexp_replace(v_new,
      $p$ORDER\s+BY\s+pr\.crop_id\s*,\s*pr\.price_type\s*,\s*pr\.recorded_at\s+DESC$p$,
      'ORDER BY pr.crop_id, pr.price_type, lower(pr.unit), pr.recorded_at DESC', 'i');
    IF v_new = v_def OR v_new NOT ILIKE '%price_type, lower(pr.unit), pr.recorded_at%' THEN
      RAISE NOTICE 'public_latest_prices: expected DISTINCT ON / ORDER BY not found, left unchanged. Send me its live definition.';
      CONTINUE;
    END IF;
    EXECUTE v_new;
  END LOOP;
END
$patch$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── CHECKS (read-only) ──────────────────────────────────────────────────
-- C1  Crops (active) that still have NO Reference Price in their market type.
--     Farmers cannot list these on the Marketplace until one is set:
--     SELECT cm.crop_name, cm.crop_type FROM crop_master cm
--      WHERE cm.is_active AND NOT EXISTS (
--        SELECT 1 FROM price_records pr WHERE pr.crop_id = cm.id AND pr.price_type = cm.crop_type)
--      ORDER BY 1;
-- C2  Harvest batches with stock whose UNIT has no Reference Price (they can be
--     sold through the other channels, not the Marketplace):
--     SELECT b.crop_name, b.unit, count(*) AS batches FROM inventory_batches b
--      WHERE b.available_kg > 0 AND b.exclusive_channel IS NULL
--        AND NOT EXISTS (SELECT 1 FROM public._listing_price_rule(b.id))
--      GROUP BY 1, 2 ORDER BY 1, 2;
-- C3  Open listings currently marked Price Update Required (run as postgres, so
--     this version does not filter by user):
--     SELECT ml.crop_name, ml.price_per_kg, ml.unit, r.price_min, r.price_max
--       FROM marketplace_listings ml
--       JOIN LATERAL public._listing_price_rule(ml.inventory_batch_id) r ON TRUE
--       LEFT JOIN listing_shelf_life x ON x.listing_id = ml.id
--      WHERE ml.status IN ('pending_review','approved') AND ml.remaining_kg > 0
--        AND x.discount_applied_on IS NULL
--        AND (ml.price_per_kg < r.price_min OR ml.price_per_kg > r.price_max);
-- C4  The trigger exists (expect 1 row):
--     SELECT tgname FROM pg_trigger WHERE tgname = 'trg_price_records_apply_to_listings';
