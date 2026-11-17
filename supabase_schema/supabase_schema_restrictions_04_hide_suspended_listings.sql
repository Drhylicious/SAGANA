-- ============================================================
-- supabase_schema_restrictions_04_hide_suspended_listings.sql
--
-- FEATURE RESTRICTIONS (4 of 4). Run after script 03.
--
-- A SUSPENDED Farmer's data is hidden, never deleted. Suspending changes nothing in their
-- listings, orders, loans or records; this script only makes the Marketplace hide the
-- listings of a farmer whose status is 'suspended', and stops NEW purchases of them.
-- Reactivating the farmer flips the status back, and everything is visible again,
-- exactly as it was: there is no "hidden" flag to undo.
--
--   * Buyers (and guests) no longer see the listings in the Marketplace feed, the crop
--     list, or by direct read. A buyer who ALREADY ordered from a listing can still read it,
--     so existing orders stay intact.
--   * place_order refuses a new order on such a listing ("Listing is no longer available").
--   * Existing orders are untouched: the buyer and the Manager / Officer still see them,
--     and staff can complete them with the usual staff actions.
--   * Manager and Officer screens are unchanged.
--
-- place_order below is the LIVE definition plus the lines for this change and the
-- checkout restriction from script 03, so running this after 03 keeps both.
--
-- Safe to re-run.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.farmer_is_suspended(p_farmer uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = p_farmer AND r.status = 'suspended');
$$;

REVOKE ALL ON FUNCTION public.farmer_is_suspended(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.farmer_is_suspended(uuid) TO authenticated, anon;

-- The Marketplace feed and the crop list.
CREATE OR REPLACE FUNCTION public.public_marketplace_listings(p_limit integer DEFAULT NULL::integer, p_offset integer DEFAULT 0, p_listing_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(jsonb_agg(x.j ORDER BY x.created_at DESC), '[]'::jsonb)
  FROM (
    SELECT
      ml.created_at,
      jsonb_build_object(
        'id',                  ml.id,
        'crop_name',           ml.crop_name,
        'crop_id',             ml.crop_id,
        'variety',             ml.variety,
        'volume_kg',           ml.volume_kg,
        'remaining_kg',        ml.remaining_kg,
        'price_per_kg',        ml.price_per_kg,
        'unit',                ml.unit,
        'photo_url',           ml.photo_url,
        'description',         ml.description,
        'created_at',          ml.created_at,
        'market_type',         ml.crop_type,
        'category',            cm.category,
        'canonical_crop_name', CASE WHEN ml.crop_id IS NOT NULL THEN cm.crop_name END,
        'available_kg',        ib.available_kg,
        'batch_number',        ib.batch_number,
        'harvest_date',        hr.harvest_date,
        'sold_kg',             COALESCE(s.sold_kg, 0),
        'buyers', COALESCE(s.buyers, 0)
      ) AS j
    FROM public.marketplace_listings ml
    LEFT JOIN LATERAL (
      SELECT c.category, c.crop_name
      FROM public.crop_master c
      WHERE c.id = ml.crop_id OR lower(c.crop_name) = lower(ml.crop_name)
      ORDER BY (c.id = ml.crop_id) DESC
      LIMIT 1
    ) cm ON TRUE
    LEFT JOIN public.inventory_batches ib ON ib.id = ml.inventory_batch_id
    LEFT JOIN public.harvest_records   hr ON hr.id = ib.harvest_record_id
    LEFT JOIN public.marketplace_listing_units_sold s ON s.listing_id = ml.id
    WHERE ml.status = 'approved' AND NOT public._listing_shelf_unavailable(ml.id)
      AND NOT public.farmer_is_suspended(ml.farmer_id)
      AND (p_listing_id IS NULL OR ml.id = p_listing_id)
      AND (
        ml.crop_type IS NULL
        OR EXISTS (
          SELECT 1 FROM public.market_types mt
          WHERE mt.code = ml.crop_type AND mt.buyer_visible
        )
      )
    ORDER BY ml.created_at DESC
    LIMIT LEAST(COALESCE(p_limit, 200), 200)
    OFFSET GREATEST(COALESCE(p_offset, 0), 0)
  ) x;
$function$
;

CREATE OR REPLACE FUNCTION public.public_listed_crop_names()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(jsonb_agg(DISTINCT lower(ml.crop_name)), '[]'::jsonb)
  FROM public.marketplace_listings ml
  WHERE ml.status = 'approved' AND NOT public._listing_shelf_unavailable(ml.id)
    AND NOT public.farmer_is_suspended(ml.farmer_id)
    AND (
      ml.crop_type IS NULL
      OR EXISTS (
        SELECT 1 FROM public.market_types mt
        WHERE mt.code = ml.crop_type AND mt.buyer_visible
      )
    );
$function$
;

-- Direct reads by signed-in buyers. A buyer who already ordered from the listing keeps access.
DROP POLICY IF EXISTS "buyers read approved" ON public.marketplace_listings;
CREATE POLICY "buyers read approved" ON public.marketplace_listings
  FOR SELECT
  USING (
    status = 'approved'
    AND auth.role() = 'authenticated'
    AND (NOT public.farmer_is_suspended(farmer_id) OR public._user_ordered_listing(id))
  );

-- New purchases.
CREATE OR REPLACE FUNCTION public.place_order(p_listing_id uuid, p_quantity_kg numeric, p_fulfillment_method text DEFAULT 'pickup'::text, p_delivery_address text DEFAULT NULL::text, p_delivery_latitude double precision DEFAULT NULL::double precision, p_delivery_longitude double precision DEFAULT NULL::double precision, p_delivery_contact_number text DEFAULT NULL::text, p_delivery_notes text DEFAULT NULL::text, p_delivery_recipient_name text DEFAULT NULL::text, p_delivery_label text DEFAULT NULL::text, p_request_id uuid DEFAULT NULL::uuid, p_group_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_buyer_id      UUID := auth.uid();
  v_caller_role   TEXT;
  v_caller_status TEXT;
  v_farmer_id     UUID;
  v_price_per_kg  NUMERIC;
  v_remaining     NUMERIC;
  v_order_id      UUID;
  v_rules_on      BOOLEAN := FALSE;
  g               checkout_groups%ROWTYPE;
BEGIN
  -- Feature restriction (member_restrictions): refuses with the readable reason.
  PERFORM public.assert_feature_available('checkout');
  IF v_buyer_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT role, status INTO v_caller_role, v_caller_status FROM user_roles WHERE user_id = v_buyer_id;
  IF v_caller_role IS NULL OR v_caller_role NOT IN ('buyer', 'farmer') THEN
    RAISE EXCEPTION 'Only buyer or farmer accounts can place marketplace orders';
  END IF;
  IF v_caller_status != 'active' THEN
    RAISE EXCEPTION 'Your account has been suspended by the SP3 Administrator. Please contact the cooperative for assistance.';
  END IF;

  IF p_quantity_kg IS NULL OR p_quantity_kg <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero';
  END IF;
  IF p_quantity_kg <> round(p_quantity_kg, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the quantity.';
  END IF;

  IF p_fulfillment_method NOT IN ('pickup', 'delivery') THEN
    RAISE EXCEPTION 'fulfillment_method must be pickup or delivery';
  END IF;

  -- A retry of the same checkout line returns the same order: no second reservation.
  IF p_request_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(v_buyer_id::text || p_request_id::text, 51));
    SELECT id INTO v_order_id FROM orders WHERE buyer_id = v_buyer_id AND request_id = p_request_id;
    IF FOUND THEN RETURN v_order_id; END IF;
  END IF;

  IF p_fulfillment_method = 'delivery' THEN
    SELECT (delivery_enabled AND COALESCE(array_length(public._delivery_missing(), 1), 0) = 0)
      INTO v_rules_on FROM delivery_settings WHERE id;
    IF v_rules_on THEN
      -- The new rules: the address and fee come from the server-side snapshot, never from typed text.
      IF p_group_id IS NULL THEN
        RAISE EXCEPTION 'GROUP_REQUIRED: Choose a saved delivery address first.';
      END IF;
      SELECT * INTO g FROM checkout_groups WHERE id = p_group_id AND buyer_id = v_buyer_id;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'GROUP_REQUIRED: The delivery address was not found. Choose it again.';
      END IF;
    ELSE
      IF p_delivery_address IS NULL OR trim(p_delivery_address) = '' THEN
        RAISE EXCEPTION 'A delivery address is required when choosing delivery';
      END IF;
      IF p_delivery_contact_number IS NULL OR trim(p_delivery_contact_number) = '' THEN
        RAISE EXCEPTION 'A contact number is required when choosing delivery';
      END IF;
    END IF;
  END IF;

  SELECT farmer_id, price_per_kg, remaining_kg
  INTO v_farmer_id, v_price_per_kg, v_remaining
  FROM marketplace_listings
  WHERE id = p_listing_id AND status = 'approved'
    AND NOT public.farmer_is_suspended(farmer_id)
  FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Listing is no longer available';
  END IF;
  IF v_farmer_id = v_buyer_id THEN
    RAISE EXCEPTION 'You cannot place an order on your own listing';
  END IF;
  IF v_remaining < p_quantity_kg THEN
    RAISE EXCEPTION 'Not enough stock available. Only % kg remaining.', v_remaining;
  END IF;

  UPDATE marketplace_listings
  SET remaining_kg = remaining_kg - p_quantity_kg
  WHERE id = p_listing_id;

  INSERT INTO orders (
    listing_id, farmer_id, buyer_id, quantity_kg, price_per_kg, total_price, status,
    fulfillment_method, delivery_address, delivery_latitude, delivery_longitude,
    delivery_contact_number, delivery_notes, delivery_recipient_name, delivery_label,
    request_id, checkout_group_id
  )
  VALUES (
    p_listing_id, v_farmer_id, v_buyer_id, p_quantity_kg, v_price_per_kg,
    p_quantity_kg * v_price_per_kg, 'pending',
    p_fulfillment_method,
    CASE WHEN p_fulfillment_method <> 'delivery' THEN NULL WHEN v_rules_on THEN g.address_line      ELSE p_delivery_address END,
    CASE WHEN p_fulfillment_method <> 'delivery' THEN NULL WHEN v_rules_on THEN g.latitude          ELSE p_delivery_latitude END,
    CASE WHEN p_fulfillment_method <> 'delivery' THEN NULL WHEN v_rules_on THEN g.longitude         ELSE p_delivery_longitude END,
    CASE WHEN p_fulfillment_method <> 'delivery' THEN NULL WHEN v_rules_on THEN g.contact_number    ELSE p_delivery_contact_number END,
    CASE WHEN p_fulfillment_method <> 'delivery' THEN NULL WHEN v_rules_on THEN g.delivery_notes    ELSE p_delivery_notes END,
    CASE WHEN p_fulfillment_method <> 'delivery' THEN NULL WHEN v_rules_on THEN g.recipient_name    ELSE p_delivery_recipient_name END,
    CASE WHEN p_fulfillment_method <> 'delivery' THEN NULL WHEN v_rules_on THEN g.address_label     ELSE p_delivery_label END,
    p_request_id,
    CASE WHEN p_fulfillment_method = 'delivery' AND v_rules_on THEN g.id ELSE NULL END
  )
  RETURNING id INTO v_order_id;

  RETURN v_order_id;
END;
$function$
;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECK (read-only). Run on its own. Every row PASS.
-- ============================================================
SELECT 'the feed hides a suspended farmer''s listings' AS check_name,
       CASE WHEN (SELECT prosrc FROM pg_proc WHERE proname = 'public_marketplace_listings' AND pronamespace = 'public'::regnamespace)
                 LIKE '%farmer_is_suspended%' THEN 'PASS' ELSE 'FAIL' END AS result
UNION ALL
SELECT 'the crop list hides them too',
       CASE WHEN (SELECT prosrc FROM pg_proc WHERE proname = 'public_listed_crop_names' AND pronamespace = 'public'::regnamespace)
                 LIKE '%farmer_is_suspended%' THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'direct reads hide them (a buyer with an order keeps access)',
       CASE WHEN (SELECT qual FROM pg_policies WHERE tablename = 'marketplace_listings' AND policyname = 'buyers read approved')
                 LIKE '%farmer_is_suspended%' THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'place_order refuses new orders on them, and keeps the checkout restriction',
       CASE WHEN (SELECT prosrc FROM pg_proc WHERE proname = 'place_order' AND pronamespace = 'public'::regnamespace)
                 LIKE '%farmer_is_suspended%'
             AND (SELECT prosrc FROM pg_proc WHERE proname = 'place_order' AND pronamespace = 'public'::regnamespace)
                 LIKE '%assert_feature_available(''checkout'')%'
            THEN 'PASS' ELSE 'FAIL' END;

-- Who is suspended right now (their listings are hidden while this lists them):
-- SELECT ui.full_name, r.suspension_reason, r.suspended_until
-- FROM user_roles r JOIN user_information ui USING (user_id) WHERE r.status = 'suspended';
