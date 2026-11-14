-- ============================================================
-- SAGANA — Price Management: Reference Price (Fixed Price or Price Range)
--          and the Marketplace listing price rules  (script r01)
--
-- FOR YOUR REVIEW — NOT APPLIED. Run AFTER the shelf-life scripts s01 and s02
-- (it uses listing_shelf_life from s01). One transaction, safe to re-run.
-- Then run r02 (existing listings).
--
-- WHAT IT ADDS
--   1. price_records.price_mode  'fixed' | 'range'
--      price_records.price_max   the Maximum Reference Price of a range
--      (price stays the Fixed Price, or the Minimum Reference Price of a range).
--      EVERY EXISTING PRICE RECORD BECOMES A FIXED PRICE, which is what it was.
--   2. Price Management is the source of the Marketplace price rule. The rule
--      for a listing is the LATEST price record of the listing's crop in the
--      crop's own market type, when that record is priced in the same unit as
--      the harvest batch (a per-kg price cannot limit a per-sack listing).
--      No price record, or a different unit: no restriction, as before.
--        Fixed Price   a new listing is created AT that price; any other price
--                      is refused.
--        Price Range   the price must be within Minimum..Maximum (2 decimals).
--      Enforced by triggers, so it covers Create Listing, the direct edit of a
--      Pending Approval listing, an edit request for a published listing, and
--      the approval that applies it. No existing function is replaced.
--   3. The one exception (your decision): the automatic shelf-life discount may
--      take a listing below the Fixed Price / Minimum. While a listing is
--      discounted, the Farmer may set any price from the discounted price up to
--      the Fixed Price / Maximum (still subject to approval).
--   4. get_listing_price_rule(batch)  what the Farmer's listing screens read.
--      notify_reference_price_range() the notice for a price range (the existing
--      notify_price_update() is kept as it is for a Fixed Price).
--   5. Guest browsing: public_latest_prices / public_price_trend are patched IN
--      PLACE to also return price_mode and price_max.
--
-- A price that is NOT changed is never checked: a Farmer can still edit the
-- quantity or description of a listing whose old price is outside a rule set
-- later. Script r02 brings those existing listings in line.
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.listing_shelf_life') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_shelf_life_s01_foundation.sql first (listing_shelf_life is missing).';
  END IF;
  IF to_regclass('public.listing_edit_requests') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_listing_edit_approval.sql first.';
  END IF;
END;
$$;

-- ═══ 1. Fixed Price or Reference Price Range ════════════════════════════
ALTER TABLE public.price_records
  ADD COLUMN IF NOT EXISTS price_mode TEXT NOT NULL DEFAULT 'fixed',
  ADD COLUMN IF NOT EXISTS price_max  NUMERIC(10,2);

ALTER TABLE public.price_records DROP CONSTRAINT IF EXISTS price_records_price_mode_check;
ALTER TABLE public.price_records
  ADD CONSTRAINT price_records_price_mode_check
  CHECK (
    (price_mode = 'fixed' AND price_max IS NULL)
    OR (price_mode = 'range' AND price_max IS NOT NULL AND price_max > price)
  );

COMMENT ON COLUMN public.price_records.price_mode IS
  '''fixed'': price is the Fixed Price. ''range'': price is the Minimum Reference Price and price_max the Maximum.';

-- ═══ 2. The rule that applies to one harvest batch ══════════════════════
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
    ORDER BY pr.recorded_at DESC
    LIMIT 1
  ) latest ON TRUE
  WHERE b.id = p_batch_id
    AND lower(btrim(latest.unit)) = lower(btrim(COALESCE(b.unit, 'kg')));
$$;
REVOKE ALL ON FUNCTION public._listing_price_rule(UUID) FROM PUBLIC, anon, authenticated;

-- What the Farmer's Create Listing / Edit Listing screens read. NULL = no rule.
-- discounted_floor is set while the listing carries the shelf-life discount: the
-- lowest price the Farmer may then keep.
CREATE OR REPLACE FUNCTION public.get_listing_price_rule(
  p_batch_id   UUID,
  p_listing_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r       RECORD;
  v_floor NUMERIC;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NULL;
  END IF;
  IF NOT public.is_staff()
     AND NOT EXISTS (SELECT 1 FROM inventory_batches b WHERE b.id = p_batch_id AND b.farmer_id = auth.uid()) THEN
    RETURN NULL;
  END IF;

  SELECT * INTO r FROM public._listing_price_rule(p_batch_id);
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF p_listing_id IS NOT NULL THEN
    SELECT ml.price_per_kg INTO v_floor
    FROM marketplace_listings ml
    JOIN listing_shelf_life x ON x.listing_id = ml.id
    WHERE ml.id = p_listing_id AND x.discount_applied_on IS NOT NULL
      AND ml.price_per_kg < r.price_min;
  END IF;

  RETURN jsonb_build_object(
    'mode', r.mode, 'price_min', r.price_min, 'price_max', r.price_max,
    'unit', r.unit, 'discounted_floor', v_floor);
END;
$$;
REVOKE ALL ON FUNCTION public.get_listing_price_rule(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_listing_price_rule(UUID, UUID) TO authenticated;

-- One place that says whether a price is allowed. p_floor lowers the minimum
-- (the discounted price of a listing that carries the shelf-life discount).
CREATE OR REPLACE FUNCTION public._assert_listing_price(
  p_batch_id UUID, p_price NUMERIC, p_floor NUMERIC DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r     RECORD;
  v_min NUMERIC;
BEGIN
  IF p_batch_id IS NULL OR p_price IS NULL THEN
    RETURN;
  END IF;
  SELECT * INTO r FROM public._listing_price_rule(p_batch_id);
  IF NOT FOUND THEN
    RETURN;                                     -- no rule for this crop / unit
  END IF;

  v_min := LEAST(r.price_min, COALESCE(p_floor, r.price_min));
  IF p_price >= v_min AND p_price <= r.price_max THEN
    RETURN;
  END IF;

  IF r.mode = 'fixed' AND v_min = r.price_max THEN
    RAISE EXCEPTION 'PRICE_RULE: The price of % is fixed at ₱% per % by the cooperative and cannot be changed.',
      r.crop_name, to_char(r.price_max, 'FM999999990.00'), r.unit;
  END IF;
  RAISE EXCEPTION 'PRICE_RULE: The price of % must be from ₱% to ₱% per %.',
    r.crop_name, to_char(v_min, 'FM999999990.00'), to_char(r.price_max, 'FM999999990.00'), r.unit;
END;
$$;
REVOKE ALL ON FUNCTION public._assert_listing_price(UUID, NUMERIC, NUMERIC) FROM PUBLIC, anon, authenticated;

-- ═══ 3. Enforcement on the listing itself ═══════════════════════════════
CREATE OR REPLACE FUNCTION public._listing_price_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r       RECORD;
  v_floor NUMERIC;
BEGIN
  IF NEW.inventory_batch_id IS NULL THEN
    RETURN NEW;
  END IF;
  -- The automatic shelf-life discount is exempt (process_shelf_life sets this).
  IF COALESCE(current_setting('sagana.shelf_discount', true), '') = '1' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- A Fixed Price crop is listed AT the fixed price, whatever was sent.
    SELECT * INTO r FROM public._listing_price_rule(NEW.inventory_batch_id);
    IF FOUND AND r.mode = 'fixed' THEN
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

DROP TRIGGER IF EXISTS trg_listings_price_guard ON public.marketplace_listings;
CREATE TRIGGER trg_listings_price_guard
  BEFORE INSERT OR UPDATE OF price_per_kg ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION public._listing_price_guard();

-- The same check when the Farmer SUBMITS an edit for approval, so they are told
-- at once and not only when the Manager / Officer tries to approve it.
CREATE OR REPLACE FUNCTION public._listing_edit_price_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch UUID;
  v_floor NUMERIC;
BEGIN
  IF NEW.proposed_price IS NOT DISTINCT FROM NEW.original_price THEN
    RETURN NEW;
  END IF;
  SELECT ml.inventory_batch_id INTO v_batch FROM marketplace_listings ml WHERE ml.id = NEW.listing_id;
  IF EXISTS (SELECT 1 FROM listing_shelf_life x
             WHERE x.listing_id = NEW.listing_id AND x.discount_applied_on IS NOT NULL) THEN
    v_floor := NEW.original_price;
  END IF;
  PERFORM public._assert_listing_price(v_batch, NEW.proposed_price, v_floor);
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._listing_edit_price_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_listing_edit_price_guard ON public.listing_edit_requests;
CREATE TRIGGER trg_listing_edit_price_guard
  BEFORE INSERT ON public.listing_edit_requests
  FOR EACH ROW EXECUTE FUNCTION public._listing_edit_price_guard();

-- ═══ 4. The notice for a Reference Price Range ══════════════════════════
-- Same recipients as notify_price_update(): Farmers always; Buyers only when the
-- market's prices are visible to Buyers.
CREATE OR REPLACE FUNCTION public.notify_reference_price_range(
  p_crop_name  TEXT,
  p_price_min  NUMERIC,
  p_price_max  NUMERIC,
  p_unit       TEXT,
  p_price_type TEXT DEFAULT NULL
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count      INTEGER;
  v_buyers_see BOOLEAN;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can announce price updates';
  END IF;

  v_buyers_see := COALESCE(
    (SELECT mt.buyer_visible FROM market_types mt WHERE mt.code = p_price_type), FALSE);

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ur.user_id, 'price', 'Price Update: ' || p_crop_name,
         'The cooperative set the reference price of ' || p_crop_name || ' to ₱' ||
           to_char(p_price_min, 'FM999999990.00') || '–₱' || to_char(p_price_max, 'FM999999990.00') ||
           '/' || p_unit || '. ' ||
           CASE WHEN ur.role = 'buyer' THEN 'Check the Prices tab for the latest market rates.'
                ELSE 'Check the Analytics tab for the latest market rates.' END,
         FALSE, NOW(),
         CASE WHEN ur.role = 'buyer' THEN '/buyer/prices' ELSE '/farmer/analytics' END
  FROM user_roles ur
  WHERE ur.status = 'active'
    AND (ur.role = 'farmer' OR (ur.role = 'buyer' AND v_buyers_see));

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.notify_reference_price_range(TEXT, NUMERIC, NUMERIC, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notify_reference_price_range(TEXT, NUMERIC, NUMERIC, TEXT, TEXT) TO authenticated;

DO $$
BEGIN
  IF to_regclass('public.staff_permission_targets') IS NOT NULL THEN
    INSERT INTO public.staff_permission_targets (kind, name, module)
    VALUES ('rpc', 'notify_reference_price_range', 'dashboard')
    ON CONFLICT (kind, name) DO NOTHING;
  END IF;
END;
$$;

-- ═══ 5. Guest price screens also get the mode and the maximum ═══════════
-- Patched in place from the LIVE definitions: two keys are added after 'price'.
DO $patch$
DECLARE
  v_oid oid;
  v_def text;
  v_new text;
BEGIN
  FOR v_oid IN
    SELECT p.oid FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN ('public_latest_prices', 'public_price_trend')
  LOOP
    v_def := pg_get_functiondef(v_oid);
    IF v_def ILIKE '%pr.price_mode%' THEN
      CONTINUE;                                   -- already patched
    END IF;
    v_new := regexp_replace(
      v_def,
      $p$('price',\s*pr\.price,)$p$,
      $r$\1 'price_mode', pr.price_mode, 'price_max', pr.price_max,$r$,
      'gi');
    IF v_new = v_def THEN
      RAISE NOTICE '%: no "''price'', pr.price," key found, left unchanged. Send me its live definition.', v_oid::regprocedure;
      CONTINUE;
    END IF;
    EXECUTE v_new;
  END LOOP;
END
$patch$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── CHECKS (read-only) ──────────────────────────────────────────────────
-- C1  Every existing price record is a Fixed Price (expect one row: fixed):
--     SELECT price_mode, count(*) FROM price_records GROUP BY 1;
-- C2  The two triggers exist (expect 2 rows):
--     SELECT tgname FROM pg_trigger WHERE NOT tgisinternal
--        AND tgname IN ('trg_listings_price_guard','trg_listing_edit_price_guard');
-- C3  The rule each open listing falls under (NULL mode = no rule / other unit):
--     SELECT ml.crop_name, ml.price_per_kg, ml.unit, ml.status, r.mode, r.price_min, r.price_max
--       FROM marketplace_listings ml
--       LEFT JOIN LATERAL public._listing_price_rule(ml.inventory_batch_id) r ON TRUE
--      WHERE ml.status IN ('pending_review','approved') ORDER BY 1;
-- C4  Guest price functions return the new keys (expect true, true):
--     SELECT proname, pg_get_functiondef(oid) ILIKE '%pr.price_mode%' AS patched
--       FROM pg_proc WHERE pronamespace='public'::regnamespace
--        AND proname IN ('public_latest_prices','public_price_trend');
