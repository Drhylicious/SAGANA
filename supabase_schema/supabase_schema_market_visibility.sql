-- ============================================================
-- SAGANA — Public Market / Cooperative Market visibility
-- (Manager Dashboard > Crop Management, Marketplace Management)
--
-- THE RULE
--   Public Market      (crop_type = 'open_market')      Buyers, Farmers, Staff
--   Cooperative Market (crop_type = 'sp3_cooperative')  Farmers and Staff only
--   (Ginger, 'da_amad_market', can never be listed; unchanged.)
--   "Farmers" means a farmer account that is Approved (status 'active'); Staff
--   means Manager (admin) or Officer. Buyers never see a Cooperative Market
--   listing and cannot order one.
--
-- THREE PIECES (all additive; no existing policy, function or row is edited)
--   1. can_access_cooperative_market(uid): the one place the rule is written.
--   2. A RESTRICTIVE read policy on marketplace_listings. Restrictive policies
--      are ANDed with the existing permissive ones, so it can only remove
--      access: today's "buyers read approved" policy is untouched. A buyer
--      still sees a listing they already ordered, so their own order history
--      keeps showing the crop name and photo.
--   3. A BEFORE INSERT trigger on orders. place_order() is SECURITY DEFINER and
--      bypasses RLS, so the read policy alone would not stop an order placed by
--      calling the function directly. The trigger looks at the order's buyer,
--      not at the function body, so it does not depend on which version of
--      place_order is live (only one is: the 10-argument fulfillment version).
--   4. Keeping the stored market type in step with Crop Management. A batch and
--      its listings carry a copy of the crop's market type. When the Manager
--      switches a crop between Public and Cooperative, the copy on its batches
--      and on its Pending / Live listings is updated at once; Sold, Rejected and
--      Withdrawn listings, and every informal-sale / cooperative-offer record,
--      keep the value they were created with. Switches involving Ginger are
--      not propagated.
--
-- IMPACT TODAY (from the pre-flight): 2 approved Cooperative Market listings
-- stop being visible to Buyers. One buyer has 15 existing orders on such
-- listings (3 pending): those orders, and the Manager's view of them, are
-- unchanged.
--
-- Not applied automatically. Run in the Supabase SQL editor, then run the
-- verification block at the end.
-- ============================================================

BEGIN;

-- ─── 1. The rule ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.can_access_cooperative_market(p_uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles ur
    WHERE ur.user_id = p_uid
      AND (
        ur.role IN ('admin', 'officer')
        OR (ur.role = 'farmer' AND ur.status = 'active')
      )
  );
$$;

REVOKE ALL ON FUNCTION public.can_access_cooperative_market(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_access_cooperative_market(uuid) TO authenticated;

-- ─── 2. Read gate on listings ────────────────────────────────────────────
DROP POLICY IF EXISTS "marketplace_listings: cooperative market hidden from buyers"
  ON public.marketplace_listings;
CREATE POLICY "marketplace_listings: cooperative market hidden from buyers"
  ON public.marketplace_listings
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (
    crop_type IS DISTINCT FROM 'sp3_cooperative'
    OR public.can_access_cooperative_market()
    OR EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.listing_id = marketplace_listings.id
        AND o.buyer_id = auth.uid()
    )
  );

-- ─── 3. Order gate ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_cooperative_market_order()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type text;
BEGIN
  SELECT crop_type INTO v_type
  FROM public.marketplace_listings
  WHERE id = NEW.listing_id;

  IF v_type = 'sp3_cooperative'
     AND NOT public.can_access_cooperative_market(NEW.buyer_id) THEN
    RAISE EXCEPTION 'This item is in the Cooperative Market, which is open to SP3 farmer members only.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_cooperative_market_order ON public.orders;
CREATE TRIGGER trg_enforce_cooperative_market_order
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.enforce_cooperative_market_order();

-- ─── 4. Crop Management -> batches and open listings ─────────────────────
CREATE OR REPLACE FUNCTION public.sync_market_type_from_crop_master()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.crop_type IS DISTINCT FROM OLD.crop_type
     AND OLD.crop_type IN ('sp3_cooperative', 'open_market')
     AND NEW.crop_type IN ('sp3_cooperative', 'open_market') THEN

    UPDATE public.inventory_batches ib
    SET crop_type = NEW.crop_type
    FROM public.farmer_crops fc
    WHERE ib.crop_id = fc.id
      AND fc.crop_master_id = NEW.id
      AND ib.crop_type IS DISTINCT FROM NEW.crop_type;

    UPDATE public.marketplace_listings ml
    SET crop_type = NEW.crop_type
    FROM public.inventory_batches ib
    JOIN public.farmer_crops fc ON fc.id = ib.crop_id
    WHERE ml.inventory_batch_id = ib.id
      AND fc.crop_master_id = NEW.id
      AND ml.status IN ('pending_review', 'approved')
      AND ml.crop_type IS DISTINCT FROM NEW.crop_type;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_market_type_from_crop_master ON public.crop_master;
CREATE TRIGGER trg_sync_market_type_from_crop_master
  AFTER UPDATE OF crop_type ON public.crop_master
  FOR EACH ROW EXECUTE FUNCTION public.sync_market_type_from_crop_master();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION ────────────────────────────────────────────
-- 1. Objects exist (expect 1 row each):
--    SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--      AND proname IN ('can_access_cooperative_market','enforce_cooperative_market_order','sync_market_type_from_crop_master');
--    SELECT policyname, permissive FROM pg_policies WHERE tablename='marketplace_listings'
--      AND policyname = 'marketplace_listings: cooperative market hidden from buyers';  -- RESTRICTIVE
--
-- 2. The rule by role (replace the ids with a buyer / a farmer / the Manager from
--    user_roles). Each returns the answer for that person:
--    SELECT role, status, public.can_access_cooperative_market(user_id) FROM public.user_roles
--    ORDER BY role, status;          -- buyer = false; admin, officer, active farmer = true;
--                                    -- pending / rejected farmer = false
--
-- 3. What a Buyer can read (simulates the buyer's session; run as one block):
--    BEGIN;
--      SELECT set_config('request.jwt.claims',
--        json_build_object('sub', '<BUYER_USER_ID>', 'role', 'authenticated')::text, true);
--      SET LOCAL ROLE authenticated;
--      SELECT crop_type, count(*) FROM public.marketplace_listings
--      WHERE status = 'approved' GROUP BY 1;   -- expect open_market only
--    ROLLBACK;
--    Repeat with a farmer id: expect open_market AND sp3_cooperative.
--
-- 4. A Buyer cannot order a Cooperative Market listing (expect the exception
--    "This item is in the Cooperative Market..."), nothing is kept:
--    BEGIN;
--      SELECT set_config('request.jwt.claims',
--        json_build_object('sub', '<BUYER_USER_ID>', 'role', 'authenticated')::text, true);
--      SET LOCAL ROLE authenticated;
--      SELECT public.place_order('<COOPERATIVE_LISTING_ID>'::uuid, 1);
--    ROLLBACK;
--
-- 5. Market type follows Crop Management (inside a transaction, then rolled back):
--    BEGIN;
--      UPDATE public.crop_master SET crop_type = 'sp3_cooperative' WHERE crop_name = 'Banana';
--      SELECT ml.status, ml.crop_type FROM public.marketplace_listings ml WHERE ml.crop_name = 'Banana';
--    ROLLBACK;
-- ============================================================
