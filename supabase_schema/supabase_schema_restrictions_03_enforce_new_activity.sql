-- ============================================================
-- supabase_schema_restrictions_03_enforce_new_activity.sql
--
-- FEATURE RESTRICTIONS (3 of 4). Run after script 02.
--
-- The restriction is checked ON THE SERVER, at the start of each function that
-- starts something new. A farmer who bypasses the app still gets refused. Only
-- the starting points are checked, so existing listings, offers, orders, loans
-- and program participation are never touched.
--
--   marketplace_listing  create_listing_with_reservation
--   coop_offer           offer_batch_to_cooperative
--   informal_sale        record_informal_sale
--   ginger_da_amad       submit_ginger_for_sale   (+ the table guard below)
--   checkout             place_order (Buy Now and cart), create_checkout_group,
--                        place_program_order (Cooperative Products)
--   loan_request         submit_loan_request
--   program_join         submit_program_enrollment_request
--
-- THE FUNCTIONS BELOW ARE THE LIVE DEFINITIONS with one line added. If a function was
-- changed in the database after this script was written, regenerate it rather
-- than running an old copy.
--
-- TABLE GUARD: farmers may INSERT into market_linking_programs directly (policy
-- "Farmers request own market linking enrollment"), so a new Ginger sale request could
-- skip submit_ginger_for_sale. A trigger closes that side door.
--
-- Safe to re-run.
-- ============================================================

BEGIN;

-- create_listing_with_reservation  ->  marketplace_listing
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
  -- Feature restriction (member_restrictions): refuses with the readable reason.
  PERFORM public.assert_feature_available('marketplace_listing');
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

  IF p_price_per_kg IS NULL OR p_price_per_kg <= 0 THEN
    RAISE EXCEPTION 'Enter a price greater than zero.';
  END IF;
  IF p_price_per_kg <> round(p_price_per_kg, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the price.';
  END IF;
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
    p_crop_name || ' (' || p_quantity_kg || ' ' || COALESCE((SELECT unit FROM public.inventory_batches WHERE id = p_batch_id), 'kg') || ') was submitted for review.',
    FALSE,
    NOW()
  FROM public.user_roles ap WHERE ap.role IN ('admin', 'officer');

  RETURN v_listing_id;
END;
$function$
;

-- offer_batch_to_cooperative  ->  coop_offer
CREATE OR REPLACE FUNCTION public.offer_batch_to_cooperative(p_batch_id uuid, p_quantity_kg numeric, p_asking_price_per_kg numeric, p_note text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_batch    RECORD;
  v_offer_id UUID;
  v_name     TEXT;
BEGIN
  -- Feature restriction (member_restrictions): refuses with the readable reason.
  PERFORM public.assert_feature_available('coop_offer');
  IF NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role = 'farmer') THEN
    RAISE EXCEPTION 'Only farmer members can offer a harvest to the cooperative.';
  END IF;
  IF p_quantity_kg IS NULL OR p_quantity_kg <= 0 THEN
    RAISE EXCEPTION 'Enter a quantity greater than zero.';
  END IF;
  IF p_asking_price_per_kg IS NULL OR p_asking_price_per_kg <= 0 THEN
    RAISE EXCEPTION 'Enter your asking price per kg.';
  END IF;
  IF p_asking_price_per_kg > 100000 THEN
    RAISE EXCEPTION 'That asking price is too high. Please check it.';
  END IF;

  -- The batch must be the caller's own. (The previous version did not check.)
  SELECT farmer_id, crop_name, is_coop_eligible INTO v_batch
  FROM inventory_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND OR v_batch.farmer_id <> auth.uid() THEN
    RAISE EXCEPTION 'This batch was not found in your inventory.';
  END IF;
  IF NOT COALESCE(v_batch.is_coop_eligible, FALSE) THEN
    RAISE EXCEPTION 'This crop is not eligible for cooperative purchase.';
  END IF;

  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  -- trg_channel_offer (Ginger is DA-AMAD only) and trg_coop_offers_crop_type
  -- still run on this INSERT.
  INSERT INTO cooperative_purchase_offers (
    farmer_id, inventory_batch_id, crop_name, offered_quantity_kg,
    asking_price_per_kg, current_price_per_kg, last_proposed_by, negotiation_round
  ) VALUES (
    auth.uid(), p_batch_id, v_batch.crop_name, p_quantity_kg,
    p_asking_price_per_kg, p_asking_price_per_kg, 'farmer', 1
  ) RETURNING id INTO v_offer_id;

  INSERT INTO cooperative_offer_events
    (offer_id, round, action, actor_role, actor_id, price_per_kg, quantity_kg, note)
  VALUES
    (v_offer_id, 1, 'offered', 'farmer', auth.uid(), p_asking_price_per_kg, p_quantity_kg, NULLIF(btrim(p_note), ''));

  SELECT full_name INTO v_name FROM user_information WHERE user_id = auth.uid();
  PERFORM public._coop_offer_notify_staff(
    'New Cooperative Offer',
    COALESCE(v_name, 'A farmer') || ' offered ' || p_quantity_kg || ' ' || COALESCE((SELECT unit FROM public.inventory_batches WHERE id = p_batch_id), 'kg') || ' ' || v_batch.crop_name ||
      ' at ' || public._coop_offer_peso(p_asking_price_per_kg) || '/' || COALESCE((SELECT unit FROM public.inventory_batches WHERE id = p_batch_id), 'kg') || ' and needs a response.'
  );

  RETURN v_offer_id;
END;
$function$
;

-- record_informal_sale  ->  informal_sale
CREATE OR REPLACE FUNCTION public.record_informal_sale(p_batch_id uuid, p_crop_name text, p_quantity_kg numeric, p_buyer_name text, p_amount numeric, p_notes text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sale_id UUID;
BEGIN
  -- Feature restriction (member_restrictions): refuses with the readable reason.
  PERFORM public.assert_feature_available('informal_sale');
  IF p_amount IS NOT NULL AND p_amount < 0 THEN
    RAISE EXCEPTION 'The amount received cannot be negative.';
  END IF;
  IF p_amount IS NOT NULL AND p_amount <> round(p_amount, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the amount.';
  END IF;

  -- Checks the owner, the quantity (above zero, 2 decimals) and the stock.
  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  INSERT INTO public.informal_sales (
    farmer_id, inventory_batch_id, crop_name, quantity_kg,
    buyer_name, amount, notes
  ) VALUES (
    auth.uid(), p_batch_id, p_crop_name, p_quantity_kg,
    p_buyer_name, p_amount, p_notes
  ) RETURNING id INTO v_sale_id;

  RETURN v_sale_id;
END;
$function$
;

-- submit_ginger_for_sale  ->  ginger_da_amad
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
  v_available NUMERIC;
BEGIN
  -- Feature restriction (member_restrictions): refuses with the readable reason.
  PERFORM public.assert_feature_available('ginger_da_amad');
  IF p_volume_kg IS NULL OR p_volume_kg <= 0 THEN
    RAISE EXCEPTION 'Enter a quantity greater than zero.';
  END IF;
  IF p_volume_kg <> round(p_volume_kg, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the quantity.';
  END IF;

  SELECT id INTO v_enrollment_id
  FROM da_amad_enrollments
  WHERE farmer_id = v_farmer_id AND status = 'approved'
  ORDER BY reviewed_at DESC NULLS LAST
  LIMIT 1;

  IF v_enrollment_id IS NULL THEN
    RAISE EXCEPTION 'An approved Market Linking enrollment is required to submit a Ginger harvest';
  END IF;

  SELECT available_kg INTO v_available
  FROM inventory_batches
  WHERE id = p_inventory_batch_id AND farmer_id = v_farmer_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'That batch does not belong to you';
  END IF;
  IF p_volume_kg > v_available THEN
    RAISE EXCEPTION 'That is more than this batch has available (% left).', v_available;
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

  -- Checks owner, stock and decimals again under a row lock, then holds the
  -- quantity so no other channel can sell it.
  PERFORM public._apply_batch_reservation(p_inventory_batch_id, p_volume_kg);

  INSERT INTO market_linking_programs (
    farmer_id, crop_name, season_year, status, created_by,
    inventory_batch_id, volume_kg, reserved_kg, submitted_at, enrollment_id
  )
  VALUES (
    v_farmer_id, v_crop_name, EXTRACT(YEAR FROM NOW())::INT, 'submitted', v_farmer_id,
    p_inventory_batch_id, p_volume_kg, p_volume_kg, NOW(), v_enrollment_id
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$function$
;

-- place_order  ->  checkout
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

-- create_checkout_group  ->  checkout
CREATE OR REPLACE FUNCTION public.create_checkout_group(p_address_id uuid, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  a buyer_addresses%ROWTYPE;
  g checkout_groups%ROWTYPE;
  q jsonb;
BEGIN
  -- Feature restriction (member_restrictions): refuses with the readable reason.
  PERFORM public.assert_feature_available('checkout');
  IF p_request_id IS NULL THEN RAISE EXCEPTION 'A request id is required.'; END IF;
  a := public._saved_address_for_delivery(p_address_id);

  PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text || p_request_id::text, 31));
  SELECT * INTO g FROM checkout_groups WHERE buyer_id = auth.uid() AND request_id = p_request_id;
  IF NOT FOUND THEN
    q := public._delivery_quote(a.barangay_code, a.latitude, a.longitude);
    INSERT INTO checkout_groups (
      buyer_id, request_id, address_id, recipient_name, contact_number, address_line, barangay_code,
      address_label, delivery_notes, latitude, longitude, origin_latitude, origin_longitude,
      distance_km, delivery_fee, fee_band_version, fee_band_min_km, fee_band_max_km)
    VALUES (
      auth.uid(), p_request_id, a.id, a.recipient_name, a.contact_number, a.address_line, a.barangay_code,
      a.label, a.notes, a.latitude, a.longitude, (q ->> 'origin_latitude')::double precision, (q ->> 'origin_longitude')::double precision,
      (q ->> 'distance_km')::numeric, (q ->> 'fee')::numeric, (q ->> 'band_version')::integer,
      (q ->> 'band_min_km')::numeric, (q ->> 'band_max_km')::numeric)
    RETURNING * INTO g;
  END IF;
  RETURN jsonb_build_object('group_id', g.id, 'delivery_fee', g.delivery_fee, 'distance_km', g.distance_km);
END $function$
;

-- place_program_order  ->  checkout
CREATE OR REPLACE FUNCTION public.place_program_order(p_program_id uuid, p_product_id uuid, p_quantity numeric, p_fulfillment_method text, p_group_id uuid, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_farmer   uuid := auth.uid();
  v_program  cooperative_programs%ROWTYPE;
  v_product  program_products%ROWTYPE;
  v_item     cooperative_inventory%ROWTYPE;
  g          checkout_groups%ROWTYPE;
  o          program_product_purchases%ROWTYPE;
  v_member   boolean; v_pct numeric; v_regular numeric; v_unit numeric; v_total numeric; v_discount numeric;
  v_name     text;
BEGIN
  -- Feature restriction (member_restrictions): refuses with the readable reason.
  PERFORM public.assert_feature_available('checkout');
  IF v_farmer IS NULL THEN RAISE EXCEPTION 'You must be signed in.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = v_farmer AND role = 'farmer' AND status = 'active') THEN
    RAISE EXCEPTION 'COOPERATIVE_FARMERS_ONLY: Cooperative Products can be bought by active cooperative members only.';
  END IF;
  IF p_request_id IS NULL THEN RAISE EXCEPTION 'A request id is required.'; END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 OR p_quantity <> round(p_quantity, 2) THEN
    RAISE EXCEPTION 'Quantity must be greater than zero (two decimals at most).';
  END IF;
  IF p_fulfillment_method IS NULL OR p_fulfillment_method NOT IN ('pickup', 'delivery') THEN
    RAISE EXCEPTION 'Choose Pickup or Delivery.';
  END IF;

  -- A retry of the same request returns the same order and changes nothing.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_farmer::text || p_request_id::text, 41));
  SELECT * INTO o FROM program_product_purchases WHERE farmer_id = v_farmer AND request_id = p_request_id;
  IF FOUND THEN
    RETURN jsonb_build_object('order_id', o.id, 'order_number', o.order_number, 'total_amount', o.total_amount, 'existing', TRUE);
  END IF;

  SELECT * INTO v_program FROM cooperative_programs WHERE id = p_program_id;
  IF NOT FOUND OR v_program.program_purpose <> 'sales' THEN RAISE EXCEPTION 'Product Sales program not found.'; END IF;
  IF v_program.status <> 'active' THEN RAISE EXCEPTION 'This program is Completed and no longer accepts orders.'; END IF;

  SELECT * INTO v_product FROM program_products WHERE id = p_product_id AND program_id = p_program_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product not found for this program.'; END IF;
  IF NOT v_product.is_available THEN RAISE EXCEPTION 'This product is not currently available.'; END IF;
  SELECT * INTO v_item FROM cooperative_inventory WHERE id = v_product.inventory_item_id;
  IF NOT FOUND OR NOT v_item.is_active THEN RAISE EXCEPTION 'This product is no longer in stock.'; END IF;

  -- Overselling is impossible: the product row is locked and the free stock is checked.
  IF v_product.stock_allocated - v_product.stock_reserved < p_quantity THEN
    RAISE EXCEPTION 'OUT_OF_STOCK: Only % % left for this product.',
      GREATEST(v_product.stock_allocated - v_product.stock_reserved, 0), COALESCE(v_item.unit, '');
  END IF;

  IF p_fulfillment_method = 'delivery' THEN
    IF p_group_id IS NULL THEN RAISE EXCEPTION 'GROUP_REQUIRED: Choose a delivery address first.'; END IF;
    SELECT * INTO g FROM checkout_groups WHERE id = p_group_id AND buyer_id = v_farmer;
    IF NOT FOUND THEN RAISE EXCEPTION 'GROUP_REQUIRED: The delivery address was not found. Choose it again.'; END IF;
  ELSIF p_group_id IS NOT NULL THEN
    RAISE EXCEPTION 'A Pickup order has no delivery group.';
  END IF;

  v_member := EXISTS (SELECT 1 FROM program_members WHERE program_id = p_program_id AND farmer_id = v_farmer AND status = 'active');
  v_regular  := v_product.unit_price;
  v_pct      := CASE WHEN v_member THEN COALESCE(v_program.member_discount_percent, 0) ELSE 0 END;
  v_unit     := round(v_regular * (1 - v_pct / 100.0), 2);
  v_total    := round(v_unit * p_quantity, 2);
  v_discount := round(v_regular * p_quantity, 2) - v_total;

  INSERT INTO program_product_purchases (
    program_id, product_id, farmer_id, quantity, unit_price, total_amount, status,
    regular_unit_price, discount_percent, discount_amount, is_member_price,
    order_number, request_id, fulfillment_method, checkout_group_id,
    delivery_address, delivery_latitude, delivery_longitude, delivery_contact, delivery_recipient, delivery_label, delivery_notes,
    item_name, unit, program_name)
  VALUES (
    p_program_id, p_product_id, v_farmer, p_quantity, v_unit, v_total, 'pending',
    v_regular, v_pct, v_discount, v_member,
    public.next_program_order_number(), p_request_id, p_fulfillment_method, g.id,
    g.address_line, g.latitude, g.longitude, g.contact_number, g.recipient_name, g.address_label, g.delivery_notes,
    v_item.item_name, v_item.unit, v_program.program_name)
  RETURNING * INTO o;

  UPDATE program_products SET stock_reserved = stock_reserved + p_quantity WHERE id = v_product.id;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_farmer;
  PERFORM public._pp_notify_staff('New Cooperative Order',
    COALESCE(v_name, 'A Farmer') || ' ordered ' || p_quantity || ' ' || COALESCE(v_item.unit, '') || ' ' || v_item.item_name ||
    ' (' || o.order_number || ', ' || CASE p_fulfillment_method WHEN 'delivery' THEN 'Delivery' ELSE 'Pickup' END || ').');

  RETURN jsonb_build_object('order_id', o.id, 'order_number', o.order_number, 'total_amount', o.total_amount, 'existing', FALSE);
END $function$
;

-- submit_loan_request  ->  loan_request
CREATE OR REPLACE FUNCTION public.submit_loan_request(p_items jsonb, p_notes text DEFAULT NULL::text, p_idempotency_key text DEFAULT NULL::text, p_program_member_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(new_request_id uuid, new_request_no text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid        UUID := auth.uid();
  v_status     TEXT;
  v_item       JSONB;
  v_inv_id     UUID;
  v_qty        NUMERIC;
  v_price      NUMERIC;
  v_available  NUMERIC;
  v_name       TEXT;
  v_unit       TEXT;
  v_total      NUMERIC := 0;
  v_seen       UUID[] := ARRAY[]::UUID[];
  v_request    UUID;
  v_no         TEXT;
  v_existing   RECORD;
  v_farmer     TEXT;
  v_member     program_members%ROWTYPE;
  v_latest     TEXT;
BEGIN
  -- Feature restriction (member_restrictions): refuses with the readable reason.
  PERFORM public.assert_feature_available('loan_request');
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'You must be signed in.';
  END IF;

  SELECT ur.status INTO v_status FROM user_roles ur WHERE ur.user_id = v_uid AND ur.role = 'farmer';
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Only a farmer can request a loan.';
  END IF;
  IF v_status <> 'active' THEN
    RAISE EXCEPTION 'Only an active cooperative member can request a loan (status: %).', v_status;
  END IF;

  -- A replayed submission returns the request it already created.
  IF p_idempotency_key IS NOT NULL THEN
    SELECT lr.id AS id, lr.request_no AS request_no INTO v_existing
      FROM loan_requests lr
     WHERE lr.idempotency_key = p_idempotency_key AND lr.farmer_id = v_uid;
    IF FOUND THEN
      RETURN QUERY SELECT v_existing.id, v_existing.request_no;
      RETURN;
    END IF;
  END IF;

  -- The referral this request comes from (optional).
  IF p_program_member_id IS NOT NULL THEN
    SELECT * INTO v_member FROM program_members WHERE id = p_program_member_id;
    IF NOT FOUND OR v_member.farmer_id IS DISTINCT FROM v_uid
       OR v_member.status <> 'active' OR COALESCE(v_member.distribution_outcome, '') <> 'failed' THEN
      RAISE EXCEPTION 'LOAN_REFERRAL_INVALID';
    END IF;
    SELECT f.resolution INTO v_latest FROM program_failure_resolutions f
     WHERE f.program_member_id = p_program_member_id ORDER BY f.created_at DESC LIMIT 1;
    IF v_latest IS DISTINCT FROM 'referred_for_loan_assessment' THEN
      RAISE EXCEPTION 'LOAN_REFERRAL_INVALID';
    END IF;
    IF EXISTS (SELECT 1 FROM loan_requests lr
                WHERE lr.program_member_id = p_program_member_id
                  AND lr.status IN ('pending', 'approved')) THEN
      RAISE EXCEPTION 'LOAN_REFERRAL_ALREADY_REQUESTED';
    END IF;
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Choose at least one item.';
  END IF;
  IF jsonb_array_length(p_items) > 20 THEN
    RAISE EXCEPTION 'A request can have at most 20 items.';
  END IF;

  -- Pass 1: validate every line against the catalog and the stock on hand.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_inv_id := NULLIF(v_item->>'inventoryItemId', '')::UUID;
    v_qty    := (v_item->>'quantity')::NUMERIC;

    IF v_inv_id IS NULL THEN
      RAISE EXCEPTION 'Every item must be chosen from the loan catalog.';
    END IF;
    IF v_inv_id = ANY (v_seen) THEN
      RAISE EXCEPTION 'An item can appear only once in a request.';
    END IF;
    v_seen := v_seen || v_inv_id;

    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Enter a quantity greater than zero.';
    END IF;
    IF v_qty <> round(v_qty, 2) THEN
      RAISE EXCEPTION 'Use at most 2 decimal places for a quantity.';
    END IF;

    SELECT ci.item_name, ci.unit, ci.quantity_on_hand, lim.unit_price
      INTO v_name, v_unit, v_available, v_price
      FROM loan_items_master lim
      JOIN cooperative_inventory ci ON ci.id = lim.inventory_item_id
     WHERE lim.inventory_item_id = v_inv_id AND lim.is_loan_eligible AND ci.is_active
     LIMIT 1;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'This item is not available for loans.';
    END IF;
    IF v_available <= 0 THEN
      RAISE EXCEPTION '% is out of stock.', v_name;
    END IF;
    IF v_qty > v_available THEN
      RAISE EXCEPTION 'Not enough stock for %: % % available, % requested.',
        v_name, to_char(v_available, 'FM999,999,990.##'), v_unit, to_char(v_qty, 'FM999,999,990.##');
    END IF;

    v_total := v_total + round(v_qty * v_price, 2);
  END LOOP;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'The request total must be more than zero.';
  END IF;

  INSERT INTO loan_requests AS lr (farmer_id, status, total_value, notes, idempotency_key, program_member_id)
  VALUES (v_uid, 'pending', v_total, NULLIF(btrim(COALESCE(p_notes, '')), ''), p_idempotency_key, p_program_member_id)
  RETURNING lr.id, lr.request_no INTO v_request, v_no;

  -- Pass 2: save the lines with the catalog's name, unit and price at this moment.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_inv_id := (v_item->>'inventoryItemId')::UUID;
    v_qty    := (v_item->>'quantity')::NUMERIC;
    SELECT ci.item_name, ci.unit, lim.unit_price INTO v_name, v_unit, v_price
      FROM loan_items_master lim
      JOIN cooperative_inventory ci ON ci.id = lim.inventory_item_id
     WHERE lim.inventory_item_id = v_inv_id
     LIMIT 1;
    INSERT INTO loan_request_items
      (request_id, inventory_item_id, item_name, unit, quantity, unit_price, line_total)
    VALUES
      (v_request, v_inv_id, v_name, v_unit, v_qty, v_price, round(v_qty * v_price, 2));
  END LOOP;

  PERFORM public._wf_log('loan_request', v_request, 'submitted', NULL, 'pending', NULL,
    jsonb_build_object('total', v_total, 'items', jsonb_array_length(p_items),
                       'program_member_id', p_program_member_id));

  SELECT ui.full_name INTO v_farmer FROM user_information ui WHERE ui.user_id = v_uid;
  PERFORM public.notify_staff(
    'loan',
    'New Loan Request',
    COALESCE(v_farmer, 'A farmer') || ' requested a loan (' || v_no || ') worth ₱' ||
      to_char(v_total, 'FM999,999,990.00') || '. It is waiting for your review.',
    '/admin/loans/requests'
  );

  RETURN QUERY SELECT v_request, v_no;
END;
$function$
;

-- submit_program_enrollment_request  ->  program_join
CREATE OR REPLACE FUNCTION public.submit_program_enrollment_request(p_program_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_farmer_id UUID := auth.uid();
  v_program_status TEXT;
  v_new_id UUID;
BEGIN
  -- Feature restriction (member_restrictions): refuses with the readable reason.
  PERFORM public.assert_feature_available('program_join');
  SELECT status INTO v_program_status
  FROM cooperative_programs WHERE id = p_program_id;

  IF v_program_status IS NULL THEN
    RAISE EXCEPTION 'Program not found';
  END IF;
  IF v_program_status <> 'active' THEN
    RAISE EXCEPTION 'This program is not currently accepting enrollments';
  END IF;

  IF EXISTS (
    SELECT 1 FROM program_enrollment_requests
    WHERE farmer_id = v_farmer_id AND program_id = p_program_id
      AND status IN ('pending', 'approved')
  ) THEN
    RAISE EXCEPTION 'You already have a pending or approved request for this program';
  END IF;

  IF EXISTS (
    SELECT 1 FROM program_members
    WHERE farmer_id = v_farmer_id AND program_id = p_program_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'You are already enrolled in this program';
  END IF;

  INSERT INTO program_enrollment_requests (farmer_id, program_id, status, submitted_at)
  VALUES (v_farmer_id, p_program_id, 'pending', NOW())
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$function$
;


CREATE OR REPLACE FUNCTION public.guard_ginger_sale_restriction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.assert_feature_available('ginger_da_amad');
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.guard_ginger_sale_restriction() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_ginger_sale_restriction ON public.market_linking_programs;
CREATE TRIGGER trg_ginger_sale_restriction
  BEFORE INSERT ON public.market_linking_programs
  FOR EACH ROW EXECUTE FUNCTION public.guard_ginger_sale_restriction();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECK (read-only). Run on its own. Every row PASS.
-- ============================================================
SELECT p.proname AS check_name,
       CASE WHEN p.prosrc LIKE '%assert_feature_available(''' || t.feature || ''')%' THEN 'PASS' ELSE 'FAIL' END AS result
FROM (VALUES
  ('create_listing_with_reservation', 'marketplace_listing'),
  ('offer_batch_to_cooperative',      'coop_offer'),
  ('record_informal_sale',            'informal_sale'),
  ('submit_ginger_for_sale',          'ginger_da_amad'),
  ('place_order',                     'checkout'),
  ('create_checkout_group',           'checkout'),
  ('place_program_order',             'checkout'),
  ('submit_loan_request',             'loan_request'),
  ('submit_program_enrollment_request', 'program_join')
) AS t(fn, feature)
JOIN pg_proc p ON p.proname = t.fn AND p.pronamespace = 'public'::regnamespace
UNION ALL
SELECT 'market_linking_programs guard',
       CASE WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_ginger_sale_restriction'
                         AND tgrelid = 'public.market_linking_programs'::regclass)
            THEN 'PASS' ELSE 'FAIL' END;
