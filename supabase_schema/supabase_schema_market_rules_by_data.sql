-- ============================================================
-- SAGANA — Market Types vs Selling Channels, step 2 of 2: RULES FROM DATA
-- Requires supabase_schema_market_types_channels.sql (step 1).
--
-- Every rule below now reads market_types / selling_channels /
-- crop_master.exclusive_channel instead of a crop name or a market-type literal.
--
--   A. MARKET TYPE VISIBILITY (Buyers vs Farmers)
--      * can_view_market_type(): one place the rule lives (buyer_visible flag).
--      * Listings read policy: no more "has ordered it" clause. That clause made
--        a Cooperative Market listing show up in Browse for any Buyer who had
--        ever ordered it (the leak seen with buyer "amane": 7 orders on Palay,
--        8 on Peanut). Order history gets the crop name/photo from a view that
--        only contains the signed-in buyer's own ordered listings, and the
--        order-batch / order-harvest read policies stop going through the
--        (now buyer-hidden) listing rows.
--      * Order trigger: a Buyer cannot order a listing whose market type is not
--        buyer-visible, even by calling place_order() directly.
--      * Market-type changes on a crop follow through to its batches and its
--        Pending / Live listings (any change between the two market types).
--      * Cooperative Market price editing keys off market_types.manager_sets_price.
--
--   B. SELLING CHANNEL RULES (Ginger only through DA-AMAD)
--      * enforce_selling_channel(): a generic row trigger on the four channel
--        tables. A crop with an exclusive channel can only use that channel;
--        DA-AMAD Market Linking accepts only a crop reserved for it. This
--        closes the gaps found in the pre-flight: Informal Sale had no database
--        guard, and Market Linking never checked that the batch was Ginger.
--      * create_listing_with_reservation: the crop-NAME test ('%ginger%') is
--        replaced by the exclusive-channel test.
--      * submit_ginger_for_sale: checks the batch's crop and takes the crop
--        name from it (was the literal 'Ginger').
--      * submit_da_amad_enrollment: checks exclusive_channel, not crop_type.
--      * approve_crop_request: validates the market type against market_types,
--        not a three-value list.
--
-- Function bodies are the LIVE ones from the pre-flight (C3), changed only where
-- described. Everything else in them is unchanged.
-- Not applied automatically. Run in the Supabase SQL editor after step 1.
-- ============================================================

BEGIN;

-- ═══ A. MARKET TYPE VISIBILITY ═══════════════════════════════════════════

-- Who may enter restricted markets: Managers, Officers, and APPROVED farmers.
-- (Unchanged from the first version; kept so existing policies still resolve.)
CREATE OR REPLACE FUNCTION public.can_access_cooperative_market(p_uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles ur
    WHERE ur.user_id = p_uid
      AND (ur.role IN ('admin', 'officer')
           OR (ur.role = 'farmer' AND ur.status = 'active'))
  );
$$;

-- May this person see / purchase something of market type p_code?
--   NULL code        -> yes (an old row with no market type)
--   buyer_visible    -> yes (Public Market)
--   otherwise        -> only people who can enter restricted markets
CREATE OR REPLACE FUNCTION public.can_view_market_type(p_code text, p_uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_code IS NULL
      OR COALESCE((SELECT mt.buyer_visible FROM public.market_types mt WHERE mt.code = p_code), FALSE)
      OR public.can_access_cooperative_market(p_uid);
$$;

REVOKE ALL ON FUNCTION public.can_view_market_type(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_market_type(text, uuid) TO authenticated;

-- Listings read gate (restrictive: only ever removes access).
DROP POLICY IF EXISTS "marketplace_listings: cooperative market hidden from buyers"
  ON public.marketplace_listings;
CREATE POLICY "marketplace_listings: cooperative market hidden from buyers"
  ON public.marketplace_listings
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (public.can_view_market_type(crop_type));

-- Order history: the listing details a buyer needs for THEIR OWN orders, and
-- nothing else. Runs with the view owner's rights (so it is not hidden by the
-- gate above) but only returns listings this signed-in user has ordered. It is
-- not browsable: you can only find a listing here after ordering it.
CREATE OR REPLACE VIEW public.my_order_listings AS
SELECT ml.id, ml.crop_name, ml.variety, ml.photo_url, ml.description,
       ml.inventory_batch_id, ml.crop_type
FROM public.marketplace_listings ml
WHERE EXISTS (
  SELECT 1 FROM public.orders o
  WHERE o.listing_id = ml.id AND o.buyer_id = auth.uid()
);
GRANT SELECT ON public.my_order_listings TO authenticated;

-- The two policies that let a buyer read the batch / harvest behind their own
-- orders joined through marketplace_listings, which the gate now hides for a
-- Cooperative Market order. Same rule, evaluated by a definer function.
CREATE OR REPLACE FUNCTION public.buyer_has_ordered_batch(p_batch_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.marketplace_listings ml
    JOIN public.orders o ON o.listing_id = ml.id
    WHERE ml.inventory_batch_id = p_batch_id
      AND o.buyer_id = auth.uid()
  );
$$;

DROP POLICY IF EXISTS "inventory_batches: buyers read own order batches" ON public.inventory_batches;
CREATE POLICY "inventory_batches: buyers read own order batches"
  ON public.inventory_batches FOR SELECT
  USING (public.buyer_has_ordered_batch(inventory_batches.id));

DROP POLICY IF EXISTS "harvest_records: buyers read own order harvests" ON public.harvest_records;
CREATE POLICY "harvest_records: buyers read own order harvests"
  ON public.harvest_records FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.inventory_batches ib
      WHERE ib.harvest_record_id = harvest_records.id
        AND public.buyer_has_ordered_batch(ib.id)
    )
  );

-- Order gate (function name kept so the existing trigger keeps working).
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

  IF NOT public.can_view_market_type(v_type, NEW.buyer_id) THEN
    RAISE EXCEPTION 'This item is in the Cooperative Market, which is open to SP3 farmer members only.';
  END IF;

  RETURN NEW;
END;
$$;

-- A crop's market type changed in Crop Management: keep its batches and its
-- Pending / Live listings in step. Sold, Rejected and Withdrawn listings and
-- all sale records keep the value they were created with.
CREATE OR REPLACE FUNCTION public.sync_market_type_from_crop_master()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.crop_type IS DISTINCT FROM OLD.crop_type THEN
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

-- Manager edits a Cooperative Market listing's price (live body from C3; the
-- only change is how "this market's prices are set by the Manager" is decided).
CREATE OR REPLACE FUNCTION public.admin_update_listing_price(p_listing_id uuid, p_new_price numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status    TEXT;
  v_crop_type TEXT;
  v_farmer_id UUID;
  v_crop_name TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only Managers can edit listing prices';
  END IF;

  IF p_new_price IS NULL OR p_new_price <= 0 THEN
    RAISE EXCEPTION 'Price must be greater than zero';
  END IF;

  SELECT ml.status, ml.crop_type, ml.farmer_id, ml.crop_name
    INTO v_status, v_crop_type, v_farmer_id, v_crop_name
  FROM marketplace_listings ml
  WHERE ml.id = p_listing_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_status != 'approved' THEN
    RAISE EXCEPTION 'Only live (approved) listings can have their price edited';
  END IF;

  IF NOT COALESCE((SELECT mt.manager_sets_price FROM market_types mt WHERE mt.code = v_crop_type), FALSE) THEN
    RAISE EXCEPTION 'Only Cooperative Market listings can have their price edited by a Manager';
  END IF;

  UPDATE marketplace_listings SET price_per_kg = p_new_price WHERE id = p_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'price', 'Cooperative Price Updated',
    'The cooperative changed the price of your ' || COALESCE(v_crop_name, 'listing') ||
      ' listing to ₱' || to_char(p_new_price, 'FM999999990.00') || '/kg.',
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$function$;

-- ═══ B. SELLING CHANNEL RULES ════════════════════════════════════════════

-- One generic guard, attached once per channel table with the channel's code.
CREATE OR REPLACE FUNCTION public.enforce_selling_channel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_channel        text := TG_ARGV[0];
  v_channel_name   text;
  v_requires       boolean;
  v_excl           text;
  v_excl_name      text;
  v_crop           text;
BEGIN
  IF NEW.inventory_batch_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT cm.exclusive_channel, cm.crop_name
    INTO v_excl, v_crop
  FROM public.inventory_batches ib
  JOIN public.farmer_crops fc ON fc.id = ib.crop_id
  JOIN public.crop_master cm  ON cm.id = fc.crop_master_id
  WHERE ib.id = NEW.inventory_batch_id;

  -- A batch whose crop cannot be resolved is left to the other rules.
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  SELECT sc.name, sc.requires_exclusive_crop
    INTO v_channel_name, v_requires
  FROM public.selling_channels sc WHERE sc.code = v_channel;

  -- A crop reserved for one channel cannot be sold through another.
  IF v_excl IS NOT NULL AND v_excl <> v_channel THEN
    SELECT sc.name INTO v_excl_name FROM public.selling_channels sc WHERE sc.code = v_excl;
    RAISE EXCEPTION '% can only be sold through % — it cannot be sold through %.',
      v_crop, v_excl_name, v_channel_name;
  END IF;

  -- A channel that is only for reserved crops refuses any other crop.
  IF v_excl IS NULL AND COALESCE(v_requires, FALSE) THEN
    RAISE EXCEPTION '% cannot be sold through % — that channel is only for crops reserved for it.',
      v_crop, v_channel_name;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_channel_marketplace ON public.marketplace_listings;
CREATE TRIGGER trg_channel_marketplace
  BEFORE INSERT ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION public.enforce_selling_channel('marketplace');

DROP TRIGGER IF EXISTS trg_channel_offer ON public.cooperative_purchase_offers;
CREATE TRIGGER trg_channel_offer
  BEFORE INSERT ON public.cooperative_purchase_offers
  FOR EACH ROW EXECUTE FUNCTION public.enforce_selling_channel('offer_to_cooperative');

DROP TRIGGER IF EXISTS trg_channel_informal ON public.informal_sales;
CREATE TRIGGER trg_channel_informal
  BEFORE INSERT ON public.informal_sales
  FOR EACH ROW EXECUTE FUNCTION public.enforce_selling_channel('informal_sale');

DROP TRIGGER IF EXISTS trg_channel_market_linking ON public.market_linking_programs;
CREATE TRIGGER trg_channel_market_linking
  BEFORE INSERT ON public.market_linking_programs
  FOR EACH ROW EXECUTE FUNCTION public.enforce_selling_channel('da_amad_market_linking');

-- create_listing_with_reservation: live body (C3). Only the first check changed:
-- the crop-NAME test is now the exclusive-channel test on the batch's crop. The
-- error text keeps "can only be sold through" (the app matches it).
CREATE OR REPLACE FUNCTION public.create_listing_with_reservation(p_batch_id uuid, p_crop_name text, p_variety text, p_quantity_kg numeric, p_price_per_kg numeric, p_photo_url text, p_description text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_listing_id UUID;
  v_crop_id UUID;
  v_excl TEXT;
  v_excl_name TEXT;
BEGIN
  SELECT cm.exclusive_channel, sc.name
    INTO v_excl, v_excl_name
  FROM public.inventory_batches ib
  JOIN public.farmer_crops fc ON fc.id = ib.crop_id
  JOIN public.crop_master cm  ON cm.id = fc.crop_master_id
  LEFT JOIN public.selling_channels sc ON sc.code = cm.exclusive_channel
  WHERE ib.id = p_batch_id;

  IF v_excl IS NOT NULL THEN
    RAISE EXCEPTION '% can only be sold through % — it cannot be listed on the Marketplace.',
      p_crop_name, v_excl_name;
  END IF;

  IF p_description IS NULL OR btrim(p_description) = '' THEN
    RAISE EXCEPTION 'A description is required to create a listing.';
  END IF;

  SELECT fc.crop_master_id INTO v_crop_id
  FROM public.inventory_batches ib
  JOIN public.farmer_crops fc ON fc.id = ib.crop_id
  WHERE ib.id = p_batch_id;

  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  INSERT INTO public.marketplace_listings (
    farmer_id, inventory_batch_id, crop_id, crop_name, variety, volume_kg,
    price_per_kg, photo_url, description, status, remaining_kg
  ) VALUES (
    auth.uid(), p_batch_id, v_crop_id, p_crop_name, p_variety, p_quantity_kg,
    p_price_per_kg, p_photo_url, btrim(p_description), 'pending_review', p_quantity_kg
  ) RETURNING id INTO v_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT
    ap.user_id,
    'listing_submitted',
    'New Listing Submitted',
    p_crop_name || ' (' || p_quantity_kg || 'kg) was submitted for review.',
    FALSE,
    NOW()
  FROM public.user_roles ap WHERE ap.role IN ('admin', 'officer');

  RETURN v_listing_id;
END;
$function$;

-- Market Linking enrollment: the farmer needs a crop reserved for DA-AMAD.
CREATE OR REPLACE FUNCTION public.submit_da_amad_enrollment()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_farmer_id UUID := auth.uid();
  v_has_ginger BOOLEAN;
  v_new_id UUID;
  v_name TEXT;
BEGIN
  IF EXISTS (
    SELECT 1 FROM da_amad_enrollments
    WHERE farmer_id = v_farmer_id AND status IN ('pending', 'approved')
  ) THEN
    RAISE EXCEPTION 'You already have a pending or approved enrollment';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM farmer_crops fc
    JOIN crop_master cm ON cm.id = fc.crop_master_id
    WHERE fc.farmer_id = v_farmer_id AND cm.exclusive_channel = 'da_amad_market_linking'
  ) INTO v_has_ginger;

  IF NOT v_has_ginger THEN
    RAISE EXCEPTION 'A Ginger crop in your Crop Roster is required to enroll';
  END IF;

  INSERT INTO da_amad_enrollments (farmer_id, status, submitted_at)
  VALUES (v_farmer_id, 'pending', NOW())
  RETURNING id INTO v_new_id;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_farmer_id;

  PERFORM public.notify_staff(
    'system',
    'New Market Linking Enrollment',
    COALESCE(v_name, 'A farmer') || ' submitted a Market Linking enrollment for Ginger and needs review.'
  );

  RETURN v_new_id;
END;
$function$;

-- Market Linking submission: the batch must be the farmer's own AND belong to a
-- crop reserved for DA-AMAD; the crop name comes from that crop (was 'Ginger').
CREATE OR REPLACE FUNCTION public.submit_ginger_for_sale(p_inventory_batch_id uuid, p_volume_kg numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_farmer_id UUID := auth.uid();
  v_enrollment_id UUID;
  v_new_id UUID;
  v_crop_name TEXT;
  v_excl TEXT;
BEGIN
  SELECT id INTO v_enrollment_id
  FROM da_amad_enrollments
  WHERE farmer_id = v_farmer_id AND status = 'approved'
  ORDER BY reviewed_at DESC NULLS LAST
  LIMIT 1;

  IF v_enrollment_id IS NULL THEN
    RAISE EXCEPTION 'An approved Market Linking enrollment is required to submit a Ginger harvest';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM inventory_batches
    WHERE id = p_inventory_batch_id AND farmer_id = v_farmer_id
  ) THEN
    RAISE EXCEPTION 'That batch does not belong to you';
  END IF;

  SELECT cm.crop_name, cm.exclusive_channel
    INTO v_crop_name, v_excl
  FROM inventory_batches ib
  JOIN farmer_crops fc ON fc.id = ib.crop_id
  JOIN crop_master cm ON cm.id = fc.crop_master_id
  WHERE ib.id = p_inventory_batch_id;

  IF v_excl IS DISTINCT FROM 'da_amad_market_linking' THEN
    RAISE EXCEPTION 'Only a Ginger harvest can be submitted through Market Linking';
  END IF;

  INSERT INTO market_linking_programs (
    farmer_id, crop_name, season_year, status, created_by,
    inventory_batch_id, volume_kg, submitted_at, enrollment_id
  )
  VALUES (
    v_farmer_id, v_crop_name, EXTRACT(YEAR FROM NOW())::INT, 'submitted', v_farmer_id,
    p_inventory_batch_id, p_volume_kg, NOW(), v_enrollment_id
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$function$;

-- approve_crop_request: live body (C3). Changes: the market type is validated
-- against market_types, and the fallback is the first buyer-visible active type.
CREATE OR REPLACE FUNCTION public.approve_crop_request(p_request_id uuid, p_admin_notes text DEFAULT NULL::text, p_crop_type text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_request RECORD;
  v_crop_master_id UUID;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only Managers can approve crop requests';
  END IF;

  SELECT * INTO v_request FROM crop_requests WHERE id = p_request_id FOR UPDATE;
  IF v_request IS NULL THEN
    RAISE EXCEPTION 'Crop request not found';
  END IF;
  IF v_request.status != 'pending' THEN
    RAISE EXCEPTION 'Request already reviewed (status: %)', v_request.status;
  END IF;

  IF p_crop_type IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM market_types WHERE code = p_crop_type AND is_active) THEN
    RAISE EXCEPTION 'Invalid crop_type: %', p_crop_type;
  END IF;

  SELECT id INTO v_crop_master_id
  FROM crop_master
  WHERE lower(crop_name) = lower(v_request.requested_name)
  LIMIT 1;

  IF v_crop_master_id IS NULL THEN
    INSERT INTO crop_master (crop_name, category, crop_type, image_url, is_active, sort_order)
    VALUES (
      v_request.requested_name,
      COALESCE(v_request.category, 'Other'),
      COALESCE(
        p_crop_type,
        v_request.crop_type,
        (SELECT code FROM market_types WHERE buyer_visible AND is_active ORDER BY sort_order LIMIT 1)
      ),
      v_request.photo_url,
      TRUE,
      (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM crop_master)
    )
    RETURNING id INTO v_crop_master_id;
  END IF;

  UPDATE crop_requests
  SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = NOW(), admin_notes = p_admin_notes
  WHERE id = p_request_id;

  IF v_request.farmer_crop_id IS NOT NULL THEN
    UPDATE farmer_crops
    SET crop_master_id = v_crop_master_id,
        photo_url = COALESCE(farmer_crops.photo_url, v_request.photo_url)
    WHERE id = v_request.farmer_crop_id;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_request.farmer_id,
    'crop_request',
    'Crop Request Approved',
    v_request.requested_name || ' has been added to the official crop list and is now fully approved.',
    FALSE,
    NOW(),
    '/farmer/harvest/crops'
  );

  RETURN v_crop_master_id;
END;
$function$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION ────────────────────────────────────────────
-- 1. Objects exist (expect: 4 channel triggers + order trigger + sync trigger + policy):
--    SELECT tgname, tgrelid::regclass FROM pg_trigger WHERE NOT tgisinternal AND tgname IN
--      ('trg_channel_marketplace','trg_channel_offer','trg_channel_informal','trg_channel_market_linking',
--       'trg_enforce_cooperative_market_order','trg_sync_market_type_from_crop_master');
--    SELECT policyname FROM pg_policies WHERE tablename='marketplace_listings'
--      AND policyname LIKE '%hidden from buyers';
--
-- 2. THE LEAK IS CLOSED. As buyer "amane" (replace the id) Browse must show only
--    open_market rows, even though amane has ordered Palay and Peanut:
--    BEGIN;
--      SELECT set_config('request.jwt.claims',
--        json_build_object('sub','<AMANE_USER_ID>','role','authenticated')::text, true);
--      SET LOCAL ROLE authenticated;
--      SELECT crop_type, count(*) FROM public.marketplace_listings WHERE status='approved' GROUP BY 1;
--      -- expect open_market only
--      SELECT crop_name, crop_type FROM public.my_order_listings;
--      -- expect Palay and Peanut (order history still has its crop details)
--      SELECT count(*) FROM public.inventory_batches;   -- amane can still read the batches behind his own orders
--    ROLLBACK;
--
-- 3. Ginger cannot use Marketplace / Offer / Informal Sale (each must raise
--    "Ginger can only be sold through DA-AMAD Market Linking ..."; nothing is kept):
--    BEGIN;
--      INSERT INTO public.informal_sales (farmer_id, inventory_batch_id, crop_name, quantity_kg, buyer_name, amount)
--      SELECT farmer_id, id, crop_name, 1, 'test', 1 FROM public.inventory_batches WHERE exclusive_channel IS NOT NULL LIMIT 1;
--    ROLLBACK;
--    (repeat with cooperative_purchase_offers (farmer_id, inventory_batch_id, crop_name, offered_quantity_kg)
--     and marketplace_listings if you want each path shown.)
--
-- 4. Market Linking refuses a non-Ginger batch (expect "...only for crops reserved for it"):
--    BEGIN;
--      INSERT INTO public.market_linking_programs (farmer_id, crop_name, season_year, status, inventory_batch_id, volume_kg)
--      SELECT farmer_id, crop_name, 2026, 'submitted', id, 1 FROM public.inventory_batches WHERE exclusive_channel IS NULL LIMIT 1;
--    ROLLBACK;
--
-- 5. Ginger's existing records are intact (expect 1 approved enrollment; Ginger batch 10.00 kg available):
--    SELECT status, count(*) FROM public.da_amad_enrollments GROUP BY status;
--    SELECT status, available_kg, exclusive_channel FROM public.inventory_batches WHERE exclusive_channel IS NOT NULL;
-- ============================================================
