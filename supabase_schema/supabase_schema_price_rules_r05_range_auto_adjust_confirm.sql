-- ============================================================
-- SAGANA — Price rules, part 5: Range Price auto-adjustment &
--          Farmer confirmation ("Accept" or "Edit for Approval")
--
-- Run AFTER supabase_schema_price_rules_r04_fixed_price_updates_pending_edits.sql.
-- Safe to re-run. One transaction.
--
-- WHAT THIS ADDS / CHANGES
--   1. Adds confirmation-tracking columns on public.marketplace_listings:
--        price_confirmation_required, price_adjusted_from,
--        price_adjusted_at, price_adjusted_min, price_adjusted_max
--   2. Updates _listing_price_rule() so future-dated price records
--      (recorded_at > NOW()) do not take effect prematurely.
--   3. Updates _price_record_apply_to_listings() trigger:
--        - Fixed Price: unchanged (auto-updates open listings to the
--          new Fixed Price and notifies the Farmer).
--        - Range Price:
--            * If an open, non-discounted listing's price is OUTSIDE
--              the new [price_min, price_max] range, automatically adjusts
--              price_per_kg to price_min (lower boundary), marks
--              price_confirmation_required = TRUE, keeps the listing
--              active, and notifies the Farmer to Accept or Edit.
--            * If the listing's price is ALREADY INSIDE the new range,
--              leaves price_per_kg untouched, clears any stale
--              confirmation flag, and notifies the Farmer of the new range.
--   4. Adds accept_adjusted_listing_price(p_listing_id) RPC so the
--      Farmer can accept the auto-adjusted price in one tap.
--   5. Updates get_price_update_required_listings() to include listings
--      awaiting Farmer confirmation (price_confirmation_required = TRUE).
--   6. Updates update_my_listing() and approve_listing_edit() to clear
--      price_confirmation_required when the Farmer's edited price is saved.
--   7. One-time pass: brings any currently open out-of-range listings
--      into the new auto-adjusted + awaiting confirmation state.
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public._listing_price_rule(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_price_rules_r03_required_reference_and_changes.sql first.';
  END IF;
  IF to_regprocedure('public.approve_listing_edit(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_listing_edit_approval.sql first.';
  END IF;
END;
$$;

-- ═══ 1. Confirmation tracking columns on marketplace_listings ═══════════
ALTER TABLE public.marketplace_listings
  ADD COLUMN IF NOT EXISTS price_confirmation_required BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS price_adjusted_from         NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS price_adjusted_at           TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS price_adjusted_min          NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS price_adjusted_max          NUMERIC(10,2);

-- ═══ 2. Latest active rule (ignore future-dated effective records) ══════
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
      AND pr.recorded_at <= NOW()
    ORDER BY pr.recorded_at DESC
    LIMIT 1
  ) latest ON TRUE
  WHERE b.id = p_batch_id;
$$;
REVOKE ALL ON FUNCTION public._listing_price_rule(UUID) FROM PUBLIC, anon, authenticated;

-- ═══ 3. Propagate Reference Price changes to open listings ══════════════
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
  IF NEW.recorded_at > NOW() THEN
    RETURN NULL;
  END IF;

  FOR l IN
    SELECT ml.id, ml.farmer_id, ml.crop_name, ml.price_per_kg, ml.unit,
           ml.inventory_batch_id, ml.price_confirmation_required,
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
    SELECT * INTO r FROM public._listing_price_rule(l.inventory_batch_id);
    CONTINUE WHEN NOT FOUND;

    IF r.mode = 'fixed' THEN
      IF l.discounted THEN
        UPDATE listing_shelf_life
           SET pre_discount_price = r.price_min, updated_at = NOW()
         WHERE listing_id = l.id;
        IF l.price_confirmation_required THEN
          UPDATE marketplace_listings
             SET price_confirmation_required = FALSE,
                 price_adjusted_from = NULL,
                 price_adjusted_at = NULL,
                 price_adjusted_min = NULL,
                 price_adjusted_max = NULL
           WHERE id = l.id;
        END IF;
      ELSIF l.price_per_kg <> r.price_min THEN
        UPDATE marketplace_listings
           SET price_per_kg                = r.price_min,
               price_confirmation_required = FALSE,
               price_adjusted_from         = NULL,
               price_adjusted_at           = NULL,
               price_adjusted_min          = NULL,
               price_adjusted_max          = NULL
         WHERE id = l.id;

        INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
        VALUES (
          l.farmer_id, 'listing', 'Listing Price Updated',
          'The cooperative changed the fixed price of ' || l.crop_name || '. Your listing moved from ₱' ||
            to_char(l.price_per_kg, 'FM999999990.00') || ' to ₱' || to_char(r.price_min, 'FM999999990.00') ||
            ' per ' || l.unit || '.',
          FALSE, NOW(), '/farmer/marketplace');
      ELSIF l.price_confirmation_required THEN
        UPDATE marketplace_listings
           SET price_confirmation_required = FALSE,
               price_adjusted_from = NULL,
               price_adjusted_at = NULL,
               price_adjusted_min = NULL,
               price_adjusted_max = NULL
         WHERE id = l.id;
      END IF;
    ELSIF NOT l.discounted THEN
      IF l.price_per_kg < r.price_min OR l.price_per_kg > r.price_max THEN
        -- Outside the new range: automatically adjust to the lower boundary
        -- and keep the listing active while awaiting Farmer confirmation.
        UPDATE marketplace_listings
           SET price_per_kg                = r.price_min,
               price_confirmation_required = TRUE,
               price_adjusted_from         = l.price_per_kg,
               price_adjusted_at           = NOW(),
               price_adjusted_min          = r.price_min,
               price_adjusted_max          = r.price_max
         WHERE id = l.id;

        INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
        VALUES (
          l.farmer_id, 'listing', 'Listing Price Adjusted',
          'The Reference Price of ' || l.crop_name || ' changed to ₱' ||
            to_char(r.price_min, 'FM999999990.00') || '–₱' || to_char(r.price_max, 'FM999999990.00') ||
            ' per ' || l.unit || '. Your listing price was automatically adjusted from ₱' ||
            to_char(l.price_per_kg, 'FM999999990.00') || ' to ₱' || to_char(r.price_min, 'FM999999990.00') ||
            ' per ' || l.unit || ' and remains active. Please review and accept this price or edit it within the new range for approval.',
          FALSE, NOW(), '/farmer/marketplace');
      ELSE
        -- Still inside the new range: keep price, clear any old confirmation flag, and notify.
        IF l.price_confirmation_required THEN
          UPDATE marketplace_listings
             SET price_confirmation_required = FALSE,
                 price_adjusted_from         = NULL,
                 price_adjusted_at           = NULL,
                 price_adjusted_min          = NULL,
                 price_adjusted_max          = NULL
           WHERE id = l.id;
        END IF;

        INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
        VALUES (
          l.farmer_id, 'listing', 'Reference Price Updated',
          'The cooperative updated the Reference Price of ' || l.crop_name || ' to ₱' ||
            to_char(r.price_min, 'FM999999990.00') || '–₱' || to_char(r.price_max, 'FM999999990.00') ||
            ' per ' || l.unit || '. Your listing price of ₱' || to_char(l.price_per_kg, 'FM999999990.00') ||
            ' per ' || l.unit || ' remains within the new range.',
          FALSE, NOW(), '/farmer/marketplace');
      END IF;
    END IF;
  END LOOP;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._price_record_apply_to_listings() FROM PUBLIC, anon, authenticated;

-- ═══ 4. Farmer accepts the auto-adjusted price ══════════════════════════
CREATE OR REPLACE FUNCTION public.accept_adjusted_listing_price(p_listing_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    UUID := auth.uid();
  v_role   TEXT;
  v_status TEXT;
  l        marketplace_listings%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT role, status INTO v_role, v_status FROM user_roles WHERE user_id = v_uid;
  IF v_role IS DISTINCT FROM 'farmer' OR v_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Only an active Farmer account can confirm a listing price.';
  END IF;

  SELECT * INTO l FROM marketplace_listings
   WHERE id = p_listing_id AND farmer_id = v_uid
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF l.status NOT IN ('pending_review', 'approved') OR l.remaining_kg <= 0 THEN
    RAISE EXCEPTION 'This listing is no longer active.';
  END IF;
  IF NOT l.price_confirmation_required THEN
    RETURN;
  END IF;

  PERFORM public._assert_listing_price(l.inventory_batch_id, l.price_per_kg);

  PERFORM set_config('sagana.skip_listing_edit_event', '1', true);
  UPDATE marketplace_listings
     SET price_confirmation_required = FALSE,
         price_adjusted_from         = NULL,
         price_adjusted_at           = NULL,
         price_adjusted_min          = NULL,
         price_adjusted_max          = NULL
   WHERE id = l.id;
  PERFORM set_config('sagana.skip_listing_edit_event', '0', true);

  PERFORM public._wf_log('listing', l.id, 'price_accepted', l.status, l.status, NULL,
    jsonb_build_object('price', l.price_per_kg, 'previous_price', l.price_adjusted_from, 'unit', l.unit));
END;
$$;
REVOKE ALL ON FUNCTION public.accept_adjusted_listing_price(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_adjusted_listing_price(UUID) TO authenticated;

-- ═══ 5. Listings needing Farmer confirmation or price update ════════════
CREATE OR REPLACE FUNCTION public.get_price_update_required_listings()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'listing_id', ml.id,
           'price_min', r.price_min,
           'price_max', r.price_max,
           'unit', r.unit,
           'price_confirmation_required', ml.price_confirmation_required,
           'price_adjusted_from', ml.price_adjusted_from)), '[]'::jsonb)
  FROM marketplace_listings ml
  JOIN LATERAL public._listing_price_rule(ml.inventory_batch_id) r ON TRUE
  LEFT JOIN listing_shelf_life x ON x.listing_id = ml.id
  WHERE auth.uid() IS NOT NULL
    AND (ml.farmer_id = auth.uid() OR public.is_staff())
    AND ml.status IN ('pending_review', 'approved')
    AND ml.remaining_kg > 0
    AND x.discount_applied_on IS NULL
    AND (
      ml.price_confirmation_required = TRUE
      OR ml.price_per_kg < r.price_min
      OR ml.price_per_kg > r.price_max
    );
$$;
REVOKE ALL ON FUNCTION public.get_price_update_required_listings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_price_update_required_listings() TO authenticated;

-- ═══ 6. Clear confirmation flag when Farmer edits or edit is approved ═══
-- Patch update_my_listing and approve_listing_edit via a lightweight trigger
-- when price_per_kg or description/volume changes on a farmer edit, OR
-- directly via a BEFORE UPDATE trigger when a new price is explicitly set
-- by update_my_listing / approve_listing_edit.
CREATE OR REPLACE FUNCTION public._clear_price_confirmation_on_edit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.price_confirmation_required = TRUE
     AND NEW.price_confirmation_required = TRUE
     AND NEW.price_per_kg IS DISTINCT FROM OLD.price_per_kg
     AND NEW.price_adjusted_at IS NOT DISTINCT FROM OLD.price_adjusted_at THEN
    NEW.price_confirmation_required := FALSE;
    NEW.price_adjusted_from         := NULL;
    NEW.price_adjusted_at           := NULL;
    NEW.price_adjusted_min          := NULL;
    NEW.price_adjusted_max          := NULL;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._clear_price_confirmation_on_edit() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_listings_clear_price_confirmation ON public.marketplace_listings;
CREATE TRIGGER trg_listings_clear_price_confirmation
  BEFORE UPDATE OF price_per_kg ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION public._clear_price_confirmation_on_edit();

-- ═══ 7. One-time pass for existing out-of-range open listings ═══════════
DO $$
DECLARE
  l RECORD;
BEGIN
  FOR l IN
    SELECT ml.id, ml.farmer_id, ml.crop_name, ml.price_per_kg, ml.unit,
           r.mode, r.price_min, r.price_max
    FROM marketplace_listings ml
    JOIN LATERAL public._listing_price_rule(ml.inventory_batch_id) r ON TRUE
    LEFT JOIN listing_shelf_life x ON x.listing_id = ml.id
    WHERE ml.status IN ('pending_review', 'approved')
      AND ml.remaining_kg > 0
      AND x.discount_applied_on IS NULL
      AND r.mode = 'range'
      AND (ml.price_per_kg < r.price_min OR ml.price_per_kg > r.price_max)
    FOR UPDATE OF ml
  LOOP
    UPDATE marketplace_listings
       SET price_per_kg                = l.price_min,
           price_confirmation_required = TRUE,
           price_adjusted_from         = l.price_per_kg,
           price_adjusted_at           = NOW(),
           price_adjusted_min          = l.price_min,
           price_adjusted_max          = l.price_max
     WHERE id = l.id;

    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      l.farmer_id, 'listing', 'Listing Price Adjusted',
      'The Reference Price of ' || l.crop_name || ' is ₱' ||
        to_char(l.price_min, 'FM999999990.00') || '–₱' || to_char(l.price_max, 'FM999999990.00') ||
        ' per ' || l.unit || '. Your listing price was automatically adjusted from ₱' ||
        to_char(l.price_per_kg, 'FM999999990.00') || ' to ₱' || to_char(l.price_min, 'FM999999990.00') ||
        ' per ' || l.unit || ' and remains active. Please review and accept this price or edit it within the new range for approval.',
      FALSE, NOW(), '/farmer/marketplace');
  END LOOP;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
