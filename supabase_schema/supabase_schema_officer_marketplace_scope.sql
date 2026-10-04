-- Officers: marketplace, orders, cooperative offers, market linking and buyer records.
--
-- Why: Officers already use these screens (Marketplace, Pending Review, All Listings,
-- Orders, Offer to Cooperative, Market Linking, Buyer Management and Buyer Details).
-- The database did not allow them, so the actions failed or showed nothing.
--
-- Admin access is unchanged: each Admin check gains an Officer alternative. Farmers,
-- Buyers and other roles are still refused by these functions.
--
-- Not applied automatically. Run in the Supabase SQL editor, then the checks at the bottom.

BEGIN;

-- 1. Admin-only actions: Admin OR Officer may run them.
CREATE OR REPLACE FUNCTION public.approve_listing(p_listing_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status     TEXT;
  v_farmer_id  UUID;
  v_crop_name  TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can approve listings';
  END IF;

  SELECT status, farmer_id, crop_name INTO v_status, v_farmer_id, v_crop_name
  FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_status != 'pending_review' THEN
    RAISE EXCEPTION 'Only pending_review listings can be approved (current: %)', v_status;
  END IF;

  UPDATE marketplace_listings
  SET status = 'approved', admin_notes = NULL, reviewed_by = auth.uid(), reviewed_at = NOW(), updated_at = NOW()
  WHERE id = p_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'listing', 'Listing Approved',
    'Your ' || v_crop_name || ' listing is now live on the Marketplace.',
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.reject_listing(p_listing_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_listing RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can reject listings';
  END IF;

  SELECT * INTO v_listing FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_listing.status != 'pending_review' THEN
    RAISE EXCEPTION 'Only pending_review listings can be rejected (current: %)', v_listing.status;
  END IF;

  IF v_listing.inventory_batch_id IS NOT NULL AND v_listing.remaining_kg > 0 THEN
    PERFORM _release_batch_reservation(v_listing.inventory_batch_id, v_listing.remaining_kg);
  END IF;

  UPDATE marketplace_listings
  SET status = 'rejected', admin_notes = p_reason, remaining_kg = 0,
      reviewed_by = auth.uid(), reviewed_at = NOW(), updated_at = NOW()
  WHERE id = p_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_listing.farmer_id, 'listing', 'Listing Rejected',
    'Your ' || v_listing.crop_name || ' listing was rejected. Reason: ' || p_reason,
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.approve_order(p_order_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status     TEXT;
  v_listing_id UUID;
  v_buyer_id   UUID;
  v_farmer_id  UUID;
  v_crop_name  TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can approve orders';
  END IF;

  SELECT status, listing_id, buyer_id, farmer_id
  INTO v_status, v_listing_id, v_buyer_id, v_farmer_id
  FROM orders WHERE id = p_order_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_status <> 'pending' THEN
    RETURN FALSE;
  END IF;

  UPDATE orders SET status = 'approved' WHERE id = p_order_id;

  SELECT crop_name INTO v_crop_name FROM marketplace_listings WHERE id = v_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_buyer_id, 'order', 'Order Approved',
    'Your order for ' || COALESCE(v_crop_name, 'produce') || ' has been approved and is being prepared.',
    FALSE, NOW(), '/buyer/orders'
  );

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'order', 'Order Approved',
    'Your ' || COALESCE(v_crop_name, 'produce') || ' order has been approved and is being prepared for the buyer.',
    FALSE, NOW(), '/farmer/marketplace'
  );

  RETURN TRUE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_order(p_order_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status      TEXT;
  v_listing_id  UUID;
  v_quantity_kg NUMERIC;
  v_buyer_id    UUID;
  v_farmer_id   UUID;
  v_crop_name   TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can cancel orders';
  END IF;

  SELECT status, listing_id, quantity_kg
  INTO v_status, v_listing_id, v_quantity_kg
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Order cannot be cancelled once approved — current status: %', v_status;
  END IF;

  SELECT buyer_id INTO v_buyer_id FROM orders WHERE id = p_order_id;
  SELECT crop_name, farmer_id INTO v_crop_name, v_farmer_id
  FROM marketplace_listings WHERE id = v_listing_id;

  UPDATE marketplace_listings
  SET remaining_kg = remaining_kg + v_quantity_kg,
      status = CASE WHEN status = 'sold' THEN 'approved' ELSE status END
  WHERE id = v_listing_id;

  UPDATE orders
  SET status = 'cancelled', notes = COALESCE(p_reason, notes)
  WHERE id = p_order_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_buyer_id, 'order', 'Order Cancelled',
    'Your order for ' || COALESCE(v_crop_name, 'produce') || ' was cancelled.' ||
      CASE WHEN p_reason IS NOT NULL THEN ' Reason: ' || p_reason ELSE '' END,
    FALSE, NOW(), '/buyer/orders'
  );

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'order', 'Order Cancelled',
    'An order for your ' || COALESCE(v_crop_name, 'produce') || ' listing was cancelled.' ||
      CASE WHEN p_reason IS NOT NULL THEN ' Reason: ' || p_reason ELSE '' END,
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_order(p_order_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status      TEXT;
  v_listing_id  UUID;
  v_quantity_kg NUMERIC;
  v_batch_id    UUID;
  v_remaining   NUMERIC;
  v_buyer_id    UUID;
  v_farmer_id   UUID;
  v_crop_name   TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can complete orders';
  END IF;

  SELECT status, listing_id, quantity_kg
  INTO v_status, v_listing_id, v_quantity_kg
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_status != 'approved' THEN
    RAISE EXCEPTION 'Only approved orders can be marked completed (current status: %)', v_status;
  END IF;

  SELECT inventory_batch_id INTO v_batch_id
  FROM marketplace_listings WHERE id = v_listing_id;

  IF v_batch_id IS NOT NULL THEN
    UPDATE inventory_batches SET sold_kg = sold_kg + v_quantity_kg WHERE id = v_batch_id;
  END IF;

  SELECT remaining_kg INTO v_remaining
  FROM marketplace_listings WHERE id = v_listing_id;

  IF v_remaining <= 0 THEN
    UPDATE marketplace_listings SET status = 'sold' WHERE id = v_listing_id;
  END IF;

  UPDATE orders SET status = 'completed' WHERE id = p_order_id;

  SELECT buyer_id INTO v_buyer_id FROM orders WHERE id = p_order_id;
  SELECT crop_name, farmer_id INTO v_crop_name, v_farmer_id
  FROM marketplace_listings WHERE id = v_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_buyer_id, 'order', 'Order Completed',
    'Your order for ' || COALESCE(v_crop_name, 'produce') ||
      ' has been completed. Thank you for supporting SP3 farmers!',
    FALSE, NOW(), '/buyer/orders'
  );

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'order', 'Order Completed',
    'Your ' || COALESCE(v_crop_name, 'produce') || ' order has been completed and sold.',
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_cooperative_offer(p_offer_id uuid, p_confirmed_quantity_kg numeric, p_confirmed_amount numeric, p_admin_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_offer RECORD;
  v_transaction_id UUID;
  v_crop_type TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can confirm cooperative offers';
  END IF;

  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF v_offer IS NULL THEN
    RAISE EXCEPTION 'Cooperative offer not found';
  END IF;
  IF v_offer.status != 'pending' THEN
    RAISE EXCEPTION 'Offer already reviewed (status: %)', v_offer.status;
  END IF;

  IF p_confirmed_quantity_kg <= 0 OR p_confirmed_quantity_kg > v_offer.offered_quantity_kg THEN
    RAISE EXCEPTION 'Confirmed quantity must be between 0 and the offered quantity (%).', v_offer.offered_quantity_kg;
  END IF;

  v_crop_type := lower(v_offer.crop_name);

  -- Every confirmed offer, any crop, settles through
  -- member_sales_transactions as of this migration (Phase 9 / "Full
  -- financial parity") — this is the single change from the prior
  -- version, which only did this for palay/peanut.
  INSERT INTO member_sales_transactions (
    farmer_id, crop_name, crop_type, quantity_kg, amount, sale_date, recorded_by
  ) VALUES (
    v_offer.farmer_id, v_offer.crop_name, v_crop_type,
    p_confirmed_quantity_kg, p_confirmed_amount, CURRENT_DATE, auth.uid()
  ) RETURNING id INTO v_transaction_id;

  UPDATE cooperative_purchase_offers
  SET status = 'confirmed',
      confirmed_quantity_kg = p_confirmed_quantity_kg,
      confirmed_amount = p_confirmed_amount,
      member_sales_transaction_id = v_transaction_id,
      admin_notes = p_admin_notes,
      confirmed_by = auth.uid(),
      confirmed_at = NOW()
  WHERE id = p_offer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_offer.farmer_id,
    'cooperative_offer',
    'Cooperative Purchase Confirmed',
    'Your offer of ' || p_confirmed_quantity_kg || 'kg ' || v_offer.crop_name ||
      ' was confirmed by SP3 for ₱' || p_confirmed_amount || '.',
    FALSE,
    NOW(),
    '/farmer/harvest/inventory'
  );

  RETURN v_transaction_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.decline_cooperative_offer(p_offer_id uuid, p_admin_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_offer RECORD;
  v_batch RECORD;
  v_new_available DECIMAL;
  v_new_status TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can decline cooperative offers';
  END IF;

  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF v_offer IS NULL THEN
    RAISE EXCEPTION 'Cooperative offer not found';
  END IF;
  IF v_offer.status != 'pending' THEN
    RAISE EXCEPTION 'Offer already reviewed (status: %)', v_offer.status;
  END IF;

  SELECT quantity_kg, available_kg, sold_kg INTO v_batch
    FROM inventory_batches WHERE id = v_offer.inventory_batch_id FOR UPDATE;

  v_new_available := v_batch.available_kg + v_offer.offered_quantity_kg;
  v_new_status := CASE
    WHEN v_new_available <= 0 THEN 'sold_out'
    WHEN v_new_available < v_batch.quantity_kg * 0.15 THEN 'low_stock'
    ELSE 'available'
  END;

  UPDATE inventory_batches
  SET available_kg = v_new_available, status = v_new_status
  WHERE id = v_offer.inventory_batch_id;

  UPDATE cooperative_purchase_offers
  SET status = 'declined', admin_notes = p_admin_notes,
      confirmed_by = auth.uid(), confirmed_at = NOW()
  WHERE id = p_offer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_offer.farmer_id,
    'cooperative_offer',
    'Cooperative Purchase Offer Declined',
    'Your offer of ' || v_offer.offered_quantity_kg || 'kg ' || v_offer.crop_name ||
      ' was not accepted by SP3.' ||
      CASE WHEN p_admin_notes IS NOT NULL THEN ' Reason: ' || p_admin_notes ELSE '' END,
    FALSE,
    NOW(),
    '/farmer/harvest/inventory'
  );
END;
$function$;

-- 2. Offer batch to cooperative: notify Officers as well as Admins.
CREATE OR REPLACE FUNCTION public.offer_batch_to_cooperative(p_batch_id uuid, p_crop_name text, p_quantity_kg numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_offer_id UUID;
  v_eligible BOOLEAN;
BEGIN
  SELECT is_coop_eligible INTO v_eligible
    FROM public.inventory_batches WHERE id = p_batch_id;

  IF NOT v_eligible THEN
    RAISE EXCEPTION 'This crop is not eligible for cooperative purchase.';
  END IF;

  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  INSERT INTO public.cooperative_purchase_offers (
    farmer_id, inventory_batch_id, crop_name, offered_quantity_kg
  ) VALUES (
    auth.uid(), p_batch_id, p_crop_name, p_quantity_kg
  ) RETURNING id INTO v_offer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT
    ap.user_id,
    'cooperative_offer',
    'New Cooperative Offer',
    p_crop_name || ' (' || p_quantity_kg || ' kg) was offered to the cooperative and needs review.',
    FALSE,
    NOW(),
    '/admin/marketplace/offer-to-cooperative'
  FROM (SELECT user_id FROM admin_profiles UNION SELECT user_id FROM officer_profiles) ap;

  RETURN v_offer_id;
END;
$function$;

-- 3. Officer policies (only on the tables these screens use).
DROP POLICY IF EXISTS "officer reads buyer_profiles" ON public.buyer_profiles;
CREATE POLICY "officer reads buyer_profiles" ON public.buyer_profiles FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
DROP POLICY IF EXISTS "officer reads buyer_addresses" ON public.buyer_addresses;
CREATE POLICY "officer reads buyer_addresses" ON public.buyer_addresses FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
DROP POLICY IF EXISTS "officer reads buyer_profile_activity" ON public.buyer_profile_activity;
CREATE POLICY "officer reads buyer_profile_activity" ON public.buyer_profile_activity FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
DROP POLICY IF EXISTS "officer reads inventory_batches" ON public.inventory_batches;
CREATE POLICY "officer reads inventory_batches" ON public.inventory_batches FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
DROP POLICY IF EXISTS "officer reads member_sales_transactions" ON public.member_sales_transactions;
CREATE POLICY "officer reads member_sales_transactions" ON public.member_sales_transactions FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
DROP POLICY IF EXISTS "officer reads farmer_crops" ON public.farmer_crops;
CREATE POLICY "officer reads farmer_crops" ON public.farmer_crops FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
DROP POLICY IF EXISTS "officer reads cooperative_purchase_offers" ON public.cooperative_purchase_offers;
CREATE POLICY "officer reads cooperative_purchase_offers" ON public.cooperative_purchase_offers FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
DROP POLICY IF EXISTS "officer reads da_amad_enrollments" ON public.da_amad_enrollments;
CREATE POLICY "officer reads da_amad_enrollments" ON public.da_amad_enrollments FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
DROP POLICY IF EXISTS "officer manages marketplace_listings" ON public.marketplace_listings;
CREATE POLICY "officer manages marketplace_listings" ON public.marketplace_listings FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));
DROP POLICY IF EXISTS "officer manages market_linking_programs" ON public.market_linking_programs;
CREATE POLICY "officer manages market_linking_programs" ON public.market_linking_programs FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()));

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── CHECKS (run after applying) ─────────────────────────────────────────
-- 1. Officer policies exist:
--    select tablename, policyname from pg_policies where policyname like 'officer %' order by 1;
-- 2. Admin and Officer checks: calling approve_listing on a listing that is not pending
--    should fail with a status message for an Officer, not 'Unauthorized'.
-- 3. Farmer and Buyer accounts still get 'Unauthorized' from these actions.
