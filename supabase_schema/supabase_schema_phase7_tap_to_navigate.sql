-- ============================================================
-- SAGANA — Phase 7: Tap-to-navigate (full coverage)
-- ============================================================
-- Adds route_on_tap/route_extra to notifications, and populates
-- route_on_tap on every notification-creating function's INSERT.
-- route_extra is left NULL everywhere — every route chosen below is a
-- list/dashboard screen the recipient already has access to (not a
-- specific-record deep link), so no extra payload is needed, and it
-- sidesteps guessing at each detail screen's expected extra shape.
--
-- Routes point at plain path strings matching lib/routes/app_routes.dart
-- constants' literal values (Dart can't be referenced from SQL, so the
-- string values are hand-copied — kept in sync manually; if a route
-- constant's path ever changes, these values need updating too).
--
-- Broadcast-originated notifications (sendBroadcast /
-- process_scheduled_broadcasts) and sendReminders intentionally get no
-- route — their content is arbitrary admin-authored text not tied to
-- one specific record or screen.
-- ============================================================

ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS route_on_tap TEXT;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS route_extra TEXT;

-- ─── notify_user() helper → accepts optional route params ─────────────────
-- Adding parameters changes the signature, so CREATE OR REPLACE alone
-- would leave the old 4-arg version behind as a second overload rather
-- than replacing it (same gotcha documented for create_officer_account
-- elsewhere in this schema history) — the old one must be dropped first.

DROP FUNCTION IF EXISTS public.notify_user(uuid, text, text, text);

CREATE OR REPLACE FUNCTION public.notify_user(
  p_user_id UUID,
  p_type    TEXT,
  p_title   TEXT,
  p_body    TEXT,
  p_route_on_tap TEXT DEFAULT NULL,
  p_route_extra  TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap, route_extra)
  VALUES (p_user_id, p_type, p_title, p_body, FALSE, NOW(), p_route_on_tap, p_route_extra);
END;
$$;

-- ─── notify_admins_of_crop_request (trigger) → /admin/crops/requests ──────

CREATE OR REPLACE FUNCTION public.notify_admins_of_crop_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT
    ap.user_id,
    'crop_request',
    'New Crop Request',
    NEW.requested_name || ' was requested by a farmer and needs review.',
    FALSE,
    NOW(),
    '/admin/crops/requests'
  FROM admin_profiles ap;
  RETURN NEW;
END;
$$;

-- ─── approve_crop_request → farmer, /farmer/harvest/crops ─────────────────

CREATE OR REPLACE FUNCTION public.approve_crop_request(p_request_id uuid, p_admin_notes text DEFAULT NULL::text, p_crop_type text DEFAULT NULL::text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_request RECORD;
  v_crop_master_id UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can approve crop requests';
  END IF;

  SELECT * INTO v_request FROM crop_requests WHERE id = p_request_id FOR UPDATE;
  IF v_request IS NULL THEN
    RAISE EXCEPTION 'Crop request not found';
  END IF;
  IF v_request.status != 'pending' THEN
    RAISE EXCEPTION 'Request already reviewed (status: %)', v_request.status;
  END IF;

  IF p_crop_type IS NOT NULL AND p_crop_type NOT IN ('sp3_cooperative', 'da_amad_market', 'open_market') THEN
    RAISE EXCEPTION 'Invalid crop_type: %', p_crop_type;
  END IF;

  SELECT id INTO v_crop_master_id
  FROM crop_master
  WHERE lower(crop_name) = lower(v_request.requested_name)
  LIMIT 1;

  IF v_crop_master_id IS NULL THEN
    INSERT INTO crop_master (crop_name, category, crop_type, is_active, sort_order)
    VALUES (
      v_request.requested_name,
      COALESCE(v_request.category, 'Other'),
      COALESCE(p_crop_type, v_request.crop_type, 'open_market'),
      TRUE,
      (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM crop_master)
    )
    RETURNING id INTO v_crop_master_id;
  END IF;

  UPDATE crop_requests
  SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = NOW(), admin_notes = p_admin_notes
  WHERE id = p_request_id;

  IF v_request.farmer_crop_id IS NOT NULL THEN
    UPDATE farmer_crops SET crop_master_id = v_crop_master_id WHERE id = v_request.farmer_crop_id;
  END IF;

  PERFORM notify_user(
    v_request.farmer_id,
    'crop_request',
    'Crop Request Approved',
    v_request.requested_name || ' has been added to the official crop list and is now fully approved.',
    '/farmer/harvest/crops'
  );

  RETURN v_crop_master_id;
END;
$$;

-- ─── reject_crop_request → farmer, /farmer/harvest/crops ──────────────────

CREATE OR REPLACE FUNCTION public.reject_crop_request(p_request_id uuid, p_admin_notes text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_request RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can reject crop requests';
  END IF;

  SELECT * INTO v_request FROM crop_requests WHERE id = p_request_id FOR UPDATE;
  IF v_request IS NULL THEN
    RAISE EXCEPTION 'Crop request not found';
  END IF;
  IF v_request.status != 'pending' THEN
    RAISE EXCEPTION 'Request already reviewed (status: %)', v_request.status;
  END IF;

  UPDATE crop_requests
  SET status = 'rejected', reviewed_by = auth.uid(), reviewed_at = NOW(), admin_notes = p_admin_notes
  WHERE id = p_request_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_request.farmer_id,
    'crop_request',
    'Crop Request Declined',
    v_request.requested_name || ' was not added to the official list. Reason: ' || p_admin_notes,
    FALSE,
    NOW(),
    '/farmer/harvest/crops'
  );
END;
$$;

-- ─── approve_listing → farmer, /farmer/marketplace ─────────────────────────

CREATE OR REPLACE FUNCTION public.approve_listing(p_listing_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status     TEXT;
  v_farmer_id  UUID;
  v_crop_name  TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can approve listings';
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
$$;

-- ─── reject_listing → farmer, /farmer/marketplace ──────────────────────────

CREATE OR REPLACE FUNCTION public.reject_listing(
  p_listing_id UUID,
  p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_listing RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can reject listings';
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
$$;

-- ─── request_listing_changes → farmer, /farmer/marketplace ─────────────────

CREATE OR REPLACE FUNCTION public.request_listing_changes(p_listing_id UUID, p_notes TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status     TEXT;
  v_farmer_id  UUID;
  v_crop_name  TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can request changes on listings';
  END IF;

  SELECT status, farmer_id, crop_name INTO v_status, v_farmer_id, v_crop_name
  FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_status != 'pending_review' THEN
    RAISE EXCEPTION 'Only pending_review listings can have changes requested (current: %)', v_status;
  END IF;

  UPDATE marketplace_listings
  SET status = 'changes_required', admin_notes = p_notes, reviewed_by = auth.uid(), reviewed_at = NOW(), updated_at = NOW()
  WHERE id = p_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'listing', 'Changes Requested',
    'Your ' || v_crop_name || ' listing needs changes before it can go live. Note: ' || p_notes,
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$$;

-- ─── create_listing_with_reservation → admin, /admin/listings/pending ─────

CREATE OR REPLACE FUNCTION public.create_listing_with_reservation(p_batch_id uuid, p_crop_name text, p_variety text, p_quantity_kg numeric, p_price_per_kg numeric, p_photo_url text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_listing_id UUID;
BEGIN
  IF p_crop_name ILIKE '%ginger%' THEN
    RAISE EXCEPTION 'Ginger cannot be listed on the open Marketplace — it can only be sold through Market Linking.';
  END IF;

  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  INSERT INTO public.marketplace_listings (
    farmer_id, inventory_batch_id, crop_name, variety, volume_kg,
    price_per_kg, photo_url, status, remaining_kg
  ) VALUES (
    auth.uid(), p_batch_id, p_crop_name, p_variety, p_quantity_kg,
    p_price_per_kg, p_photo_url, 'pending_review', p_quantity_kg
  ) RETURNING id INTO v_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT
    ap.user_id,
    'listing_submitted',
    'New Listing Submitted',
    p_crop_name || ' (' || p_quantity_kg || 'kg) was submitted for review.',
    FALSE,
    NOW(),
    '/admin/listings/pending'
  FROM admin_profiles ap;

  RETURN v_listing_id;
END;
$$;

-- ─── place_order → admin /admin/marketplace/orders, farmer /farmer/marketplace ─

CREATE OR REPLACE FUNCTION public.place_order(p_listing_id uuid, p_quantity_kg numeric)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_buyer_id      UUID := auth.uid();
  v_buyer_status  TEXT;
  v_farmer_id     UUID;
  v_crop_name     TEXT;
  v_price_per_kg  NUMERIC;
  v_remaining     NUMERIC;
  v_order_id      UUID;
BEGIN
  IF v_buyer_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT status INTO v_buyer_status
  FROM user_roles
  WHERE user_id = v_buyer_id AND role = 'buyer';

  IF v_buyer_status IS NULL THEN
    RAISE EXCEPTION 'Buyer account not found';
  END IF;
  IF v_buyer_status != 'active' THEN
    RAISE EXCEPTION 'Your account has been suspended by the SP3 Administrator. Please contact the cooperative for assistance.';
  END IF;

  IF p_quantity_kg IS NULL OR p_quantity_kg <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero';
  END IF;

  SELECT farmer_id, crop_name, price_per_kg, remaining_kg
  INTO v_farmer_id, v_crop_name, v_price_per_kg, v_remaining
  FROM marketplace_listings
  WHERE id = p_listing_id AND status = 'approved'
  FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Listing is no longer available';
  END IF;
  IF v_remaining < p_quantity_kg THEN
    RAISE EXCEPTION 'Not enough stock available. Only % kg remaining.', v_remaining;
  END IF;

  UPDATE marketplace_listings
  SET remaining_kg = remaining_kg - p_quantity_kg
  WHERE id = p_listing_id;

  INSERT INTO orders (listing_id, farmer_id, buyer_id, quantity_kg, price_per_kg, total_price, status)
  VALUES (p_listing_id, v_farmer_id, v_buyer_id, p_quantity_kg, v_price_per_kg,
          p_quantity_kg * v_price_per_kg, 'pending')
  RETURNING id INTO v_order_id;

  -- Notify every admin of the new pending order.
  INSERT INTO notifications (user_id, type, title, body, route_on_tap)
  SELECT ap.user_id,
         'order',
         'New order placed',
         format('A new order (%s kg) has been placed and is awaiting approval.', p_quantity_kg),
         '/admin/marketplace/orders'
  FROM admin_profiles ap;

  -- Notify the farmer whose listing was ordered.
  INSERT INTO notifications (user_id, type, title, body, route_on_tap)
  VALUES (
    v_farmer_id,
    'order',
    'New Order Received',
    format('A buyer placed an order for %s kg of your %s listing.', p_quantity_kg, COALESCE(v_crop_name, 'produce')),
    '/farmer/marketplace'
  );

  RETURN v_order_id;
END;
$$;

-- ─── complete_order → buyer /buyer/orders, farmer /farmer/marketplace ─────

CREATE OR REPLACE FUNCTION public.complete_order(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
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
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can complete orders';
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
$$;

-- ─── cancel_order → buyer /buyer/orders, farmer /farmer/marketplace ───────

CREATE OR REPLACE FUNCTION public.cancel_order(p_order_id uuid, p_reason text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_status      TEXT;
  v_listing_id  UUID;
  v_quantity_kg NUMERIC;
  v_buyer_id    UUID;
  v_farmer_id   UUID;
  v_crop_name   TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can cancel orders';
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
$$;

-- ─── offer_batch_to_cooperative → admin, /admin/marketplace/offer-to-cooperative ─

CREATE OR REPLACE FUNCTION public.offer_batch_to_cooperative(p_batch_id uuid, p_crop_name text, p_quantity_kg numeric)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
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
  FROM admin_profiles ap;

  RETURN v_offer_id;
END;
$$;

-- ─── confirm_cooperative_offer → farmer, /farmer/harvest/inventory ────────

CREATE OR REPLACE FUNCTION public.confirm_cooperative_offer(p_offer_id uuid, p_confirmed_quantity_kg numeric, p_confirmed_amount numeric, p_admin_notes text DEFAULT NULL::text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_offer RECORD;
  v_transaction_id UUID;
  v_crop_type TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can confirm cooperative offers';
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
$$;

-- ─── decline_cooperative_offer → farmer, /farmer/harvest/inventory ────────

CREATE OR REPLACE FUNCTION public.decline_cooperative_offer(p_offer_id uuid, p_admin_notes text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_offer RECORD;
  v_batch RECORD;
  v_new_available DECIMAL;
  v_new_status TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can decline cooperative offers';
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
$$;

-- ─── submit_application → admin, /admin/farmers ────────────────────────────

CREATE OR REPLACE FUNCTION public.submit_application()
RETURNS smallint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid       UUID := auth.uid();
  v_status    TEXT;
  v_attempts  SMALLINT;
  v_full_name TEXT;
BEGIN
  SELECT status, application_attempts INTO v_status, v_attempts
  FROM user_roles WHERE user_id = v_uid
  FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'No membership record found';
  END IF;

  IF v_status NOT IN ('draft', 'rejected') THEN
    RAISE EXCEPTION 'Application cannot be submitted from status %', v_status;
  END IF;

  IF v_attempts >= 3 THEN
    RAISE EXCEPTION 'You have used all 3 application attempts. Please visit the SP3 office.';
  END IF;

  UPDATE user_roles
  SET status = 'pending',
      application_attempts = v_attempts + 1,
      rejection_reason = NULL,
      pending_acknowledgement = false
  WHERE user_id = v_uid;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (v_uid, v_status, 'pending',
          'Application submitted (attempt ' || (v_attempts + 1) || ' of 3)', v_uid);

  INSERT INTO notifications (user_id, type, title, body, is_read)
  VALUES (v_uid, 'member_pending', 'Application Submitted',
          'Your membership application has been sent to the SP3 Cooperative for review.',
          false);

  SELECT full_name INTO v_full_name FROM user_information WHERE user_id = v_uid;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT
    ap.user_id,
    'member_pending',
    'New Membership Application',
    COALESCE(v_full_name, 'A farmer') || ' submitted a membership application and needs review.',
    FALSE,
    NOW(),
    '/admin/farmers'
  FROM admin_profiles ap;

  RETURN (v_attempts + 1)::SMALLINT;
END;
$$;

-- ─── approve_member / reject_member / suspend_member / reactivate_member ──
-- ─── → farmer, /farmer/profile ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.approve_member(p_user_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_status    TEXT;
  v_full_name TEXT;
  v_member_id TEXT;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending application can be approved (current: %)', v_status;
  END IF;

  SELECT full_name INTO v_full_name FROM user_information WHERE user_id = p_user_id;

  UPDATE user_roles
  SET status = 'active',
      pending_acknowledgement = true,
      rejection_reason = NULL,
      suspension_reason = NULL
  WHERE user_id = p_user_id;

  SELECT member_id INTO v_member_id FROM farmer_profiles WHERE user_id = p_user_id;
  IF v_member_id IS NULL OR trim(v_member_id) = '' THEN
    v_member_id := generate_member_id(EXTRACT(YEAR FROM now())::INT);
  END IF;

  UPDATE farmer_profiles
  SET member_id = v_member_id, is_verified = true
  WHERE user_id = p_user_id;

  -- Every approved member gets a capital-shares row immediately (parity
  -- with create_farmer_account) — starts at 0, loan-ineligible until a
  -- payment is recorded, but the row always exists.
  INSERT INTO member_capital_shares (farmer_id, share_value_per_unit, total_contribution)
  VALUES (p_user_id, 2000.00, 0)
  ON CONFLICT (farmer_id) DO NOTHING;

  IF EXISTS (SELECT 1 FROM sp3_member_registry WHERE registered_user_id = p_user_id) THEN
    UPDATE sp3_member_registry SET is_registered = true WHERE registered_user_id = p_user_id;
  ELSE
    INSERT INTO sp3_member_registry (full_name, is_registered, registered_user_id)
    VALUES (COALESCE(v_full_name, 'SP3 Member'), true, p_user_id)
    ON CONFLICT (registered_user_id) DO UPDATE SET is_registered = true;
  END IF;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, 'pending', 'active', 'Application approved', auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read, route_on_tap)
  VALUES (p_user_id, 'member_approved', 'Membership Approved',
          'Your SP3 cooperative membership has been approved. Open SAGANA and tap '
          || 'Continue to activate your farmer access. Your Member ID is ' || v_member_id || '.',
          false, '/farmer/profile');

  RETURN v_member_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_member(p_user_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A rejection reason is required';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending application can be rejected (current: %)', v_status;
  END IF;

  UPDATE user_roles
  SET status = 'rejected',
      rejection_reason = trim(p_reason),
      pending_acknowledgement = false
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, 'pending', 'rejected', trim(p_reason), auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read, route_on_tap)
  VALUES (p_user_id, 'member_rejected', 'Application Not Approved',
          'Your SP3 membership application was not approved. Reason: ' || trim(p_reason)
          || ' You may review your details and resubmit.',
          false, '/farmer/profile');
END;
$$;

CREATE OR REPLACE FUNCTION public.suspend_member(p_user_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A suspension reason is required';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  UPDATE user_roles
  SET status = 'suspended', suspension_reason = trim(p_reason)
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, v_status, 'suspended', trim(p_reason), auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read, route_on_tap)
  VALUES (p_user_id, 'member_updated', 'Account Suspended',
          'Your SP3 account has been suspended. Reason: ' || trim(p_reason)
          || ' Please contact the SP3 Cooperative.',
          false, '/farmer/profile');
END;
$$;

CREATE OR REPLACE FUNCTION public.reactivate_member(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  UPDATE user_roles
  SET status = 'active', suspension_reason = NULL
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, v_status, 'active', 'Reactivated by admin', auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read, route_on_tap)
  VALUES (p_user_id, 'member_updated', 'Account Reactivated',
          'Your SP3 account has been reactivated. Welcome back!',
          false, '/farmer/profile');
END;
$$;

-- ─── confirm_program_return → farmer, /farmer/profile/programs ────────────

CREATE OR REPLACE FUNCTION public.confirm_program_return(p_program_member_id uuid, p_amount_returned numeric, p_admin_notes text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_member RECORD;
  v_program RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can confirm a program return';
  END IF;

  SELECT * INTO v_member FROM program_members WHERE id = p_program_member_id FOR UPDATE;
  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Program enrollment not found';
  END IF;
  IF v_member.settled_at IS NOT NULL THEN
    RAISE EXCEPTION 'This enrollment has already been settled';
  END IF;

  SELECT * INTO v_program FROM cooperative_programs WHERE id = v_member.program_id;
  IF v_program.benefit_type != 'revenue_share' THEN
    RAISE EXCEPTION 'This program does not require a return settlement';
  END IF;

  UPDATE program_members
  SET amount_returned = p_amount_returned,
      settled_at = NOW(),
      status = 'completed',
      notes = COALESCE(p_admin_notes, notes)
  WHERE id = p_program_member_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_member.farmer_id,
    'program',
    'Program Return Settled',
    'Your return of ₱' || p_amount_returned || ' for ' || v_program.program_name || ' has been recorded. Thank you!',
    FALSE,
    NOW(),
    '/farmer/profile/programs'
  );
END;
$$;

-- ─── distribute_program_benefit → farmer, /farmer/profile/programs ────────

CREATE OR REPLACE FUNCTION public.distribute_program_benefit(p_program_member_id uuid, p_inventory_item_id uuid, p_quantity numeric, p_recorded_by uuid DEFAULT NULL::uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_available NUMERIC;
  v_item_name TEXT;
  v_farmer_id UUID;
BEGIN
  SELECT quantity_on_hand, item_name INTO v_available, v_item_name
    FROM cooperative_inventory
    WHERE id = p_inventory_item_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory item % no longer exists', p_inventory_item_id;
  END IF;

  IF v_available < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock for %: % on hand, % requested',
      v_item_name, v_available, p_quantity;
  END IF;

  UPDATE cooperative_inventory
  SET quantity_on_hand = quantity_on_hand - p_quantity
  WHERE id = p_inventory_item_id;

  INSERT INTO inventory_transactions (
    inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by
  ) VALUES (
    p_inventory_item_id, 'program_distribution', -p_quantity, p_program_member_id, 'program', p_recorded_by
  );

  UPDATE program_members
  SET inventory_item_id = p_inventory_item_id,
      quantity_given = p_quantity,
      distributed_at = NOW(),
      distributed_item_name = v_item_name
  WHERE id = p_program_member_id
  RETURNING farmer_id INTO v_farmer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'program', 'Benefit Distributed',
    'You received ' || p_quantity || ' ' || COALESCE(v_item_name, 'item(s)') || ' from your program.',
    FALSE, NOW(), '/farmer/profile/programs'
  );
END;
$$;

-- ─── request_program_purchase → admin, /admin/programs/purchases ──────────

CREATE OR REPLACE FUNCTION public.request_program_purchase(p_program_id uuid, p_product_id uuid, p_quantity numeric)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_farmer_id   UUID := auth.uid();
  v_product     RECORD;
  v_on_hand     DECIMAL;
  v_reserved    DECIMAL;
  v_item_name   TEXT;
  v_farmer_name TEXT;
  v_purchase_id UUID;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.program_members
    WHERE program_id = p_program_id
      AND farmer_id = v_farmer_id
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'You are not an active member of this program.';
  END IF;

  SELECT pp.id, pp.unit_price, pp.is_available, pp.inventory_item_id
    INTO v_product
    FROM public.program_products pp
    WHERE pp.id = p_product_id
      AND pp.program_id = p_program_id
    FOR SHARE;

  IF v_product IS NULL THEN
    RAISE EXCEPTION 'Product not found for this program.';
  END IF;
  IF NOT v_product.is_available THEN
    RAISE EXCEPTION 'This product is not currently available for purchase.';
  END IF;

  SELECT quantity_on_hand, quantity_reserved, item_name
    INTO v_on_hand, v_reserved, v_item_name
    FROM public.cooperative_inventory
    WHERE id = v_product.inventory_item_id
    FOR SHARE;

  IF v_on_hand IS NULL THEN
    RAISE EXCEPTION 'Linked inventory item no longer exists.';
  END IF;
  IF (v_on_hand - v_reserved) < p_quantity THEN
    RAISE EXCEPTION 'Not enough stock available for this quantity.';
  END IF;

  INSERT INTO public.program_product_purchases (
    program_id, product_id, farmer_id, quantity, unit_price, total_amount, status
  ) VALUES (
    p_program_id, p_product_id, v_farmer_id, p_quantity, v_product.unit_price,
    (v_product.unit_price * p_quantity), 'pending'
  )
  RETURNING id INTO v_purchase_id;

  SELECT full_name INTO v_farmer_name FROM public.user_information WHERE user_id = v_farmer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT
    ap.user_id,
    'program',
    'New Program Purchase Request',
    COALESCE(v_farmer_name, 'A farmer') || ' requested to purchase ' || p_quantity || ' ' ||
      COALESCE(v_item_name, 'item(s)') || '.',
    FALSE,
    NOW(),
    '/admin/programs/purchases'
  FROM public.admin_profiles ap;

  RETURN v_purchase_id;
END;
$$;

-- ─── confirm_program_purchase → farmer, /farmer/profile/programs ──────────

CREATE OR REPLACE FUNCTION public.confirm_program_purchase(p_purchase_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_admin_id  UUID := auth.uid();
  v_purchase  RECORD;
  v_on_hand   DECIMAL;
  v_item_name TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = v_admin_id) THEN
    RAISE EXCEPTION 'Only an admin can confirm a purchase.';
  END IF;

  SELECT id, product_id, quantity, status, farmer_id
    INTO v_purchase
    FROM public.program_product_purchases
    WHERE id = p_purchase_id
    FOR UPDATE;

  IF v_purchase IS NULL THEN
    RAISE EXCEPTION 'Purchase not found.';
  END IF;
  IF v_purchase.status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending purchase can be confirmed.';
  END IF;

  -- Row-lock the linked inventory item through program_products, re-check
  -- stock at confirmation time (it may have moved since the request).
  SELECT ci.quantity_on_hand, ci.item_name
    INTO v_on_hand, v_item_name
    FROM public.cooperative_inventory ci
    JOIN public.program_products pp ON pp.inventory_item_id = ci.id
    WHERE pp.id = v_purchase.product_id
    FOR UPDATE OF ci;

  IF v_on_hand IS NULL OR v_on_hand < v_purchase.quantity THEN
    RAISE EXCEPTION 'Not enough stock remaining to confirm this purchase.';
  END IF;

  UPDATE public.cooperative_inventory ci
    SET quantity_on_hand = ci.quantity_on_hand - v_purchase.quantity
    FROM public.program_products pp
    WHERE pp.id = v_purchase.product_id
      AND ci.id = pp.inventory_item_id;

  INSERT INTO public.inventory_transactions (
    inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by, notes
  )
  SELECT pp.inventory_item_id, 'sold', -v_purchase.quantity, v_purchase.id, 'program_purchase', v_admin_id,
         'Program product sale'
  FROM public.program_products pp
  WHERE pp.id = v_purchase.product_id;

  UPDATE public.program_product_purchases
    SET status = 'paid',
        confirmed_at = NOW(),
        confirmed_by = v_admin_id
    WHERE id = p_purchase_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_purchase.farmer_id, 'program', 'Purchase Confirmed',
    'Your purchase of ' || v_purchase.quantity || ' ' || COALESCE(v_item_name, 'item(s)') || ' has been confirmed.',
    FALSE, NOW(), '/farmer/profile/programs'
  );
END;
$$;

-- ─── cancel_program_purchase → admin/farmer, /admin/programs/purchases or /farmer/profile/programs ─

CREATE OR REPLACE FUNCTION public.cancel_program_purchase(p_purchase_id uuid, p_reason text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_purchase  RECORD;
  v_is_admin  BOOLEAN;
BEGIN
  SELECT EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = v_caller_id)
    INTO v_is_admin;

  SELECT id, farmer_id, status
    INTO v_purchase
    FROM public.program_product_purchases
    WHERE id = p_purchase_id
    FOR UPDATE;

  IF v_purchase IS NULL THEN
    RAISE EXCEPTION 'Purchase not found.';
  END IF;
  IF NOT v_is_admin AND v_purchase.farmer_id <> v_caller_id THEN
    RAISE EXCEPTION 'You can only cancel your own purchase.';
  END IF;
  IF v_purchase.status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending purchase can be cancelled.';
  END IF;

  UPDATE public.program_product_purchases
    SET status = 'cancelled',
        cancelled_at = NOW(),
        cancel_reason = p_reason
    WHERE id = p_purchase_id;

  IF v_is_admin THEN
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      v_purchase.farmer_id, 'program', 'Purchase Cancelled',
      'Your program purchase was cancelled by the SP3 Admin.' ||
        CASE WHEN p_reason IS NOT NULL THEN ' Reason: ' || p_reason ELSE '' END,
      FALSE, NOW(), '/farmer/profile/programs'
    );
  ELSE
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    SELECT ap.user_id, 'program', 'Purchase Cancelled',
           'A farmer cancelled their pending program purchase.',
           FALSE, NOW(), '/admin/programs/purchases'
    FROM public.admin_profiles ap;
  END IF;
END;
$$;

-- ─── issue_loan / record_loan_payment / notify_overdue_farmers ────────────
-- ─── → farmer, /farmer/profile/loans ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.issue_loan(p_farmer_id uuid, p_items jsonb, p_issued_date date, p_monthly_payment numeric, p_next_payment_date date, p_notes text DEFAULT NULL::text, p_recorded_by uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text)
RETURNS TABLE(loan_id uuid, reference_no text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_loan_id       UUID;
  v_total_value   NUMERIC := 0;
  v_item          JSONB;
  v_inventory_id  UUID;
  v_quantity      NUMERIC;
  v_unit_price    NUMERIC;
  v_line_total    NUMERIC;
  v_available     NUMERIC;
  v_item_name     TEXT;
  v_year          INT := EXTRACT(YEAR FROM p_issued_date)::INT;
  v_next_seq      INT;
  v_reference_no  TEXT;
  v_existing_id   UUID;
  v_existing_ref  TEXT;
  v_contribution  NUMERIC;
  v_minimum       NUMERIC;
  v_farmer_status TEXT;
BEGIN
  -- Admin check — first statement in the body.
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Only admins may issue loans';
  END IF;

  -- Farmer membership-status gate (Admin-Loan Issue 1.3) — the target
  -- farmer must be an active member. Checked before the capital-share
  -- gate so a non-member gets a membership-specific error rather than a
  -- misleading capital-contribution one.
  SELECT status INTO v_farmer_status
  FROM user_roles
  WHERE user_id = p_farmer_id AND role = 'farmer';

  IF v_farmer_status IS NULL THEN
    RAISE EXCEPTION 'Farmer account not found';
  END IF;

  IF v_farmer_status <> 'active' THEN
    RAISE EXCEPTION 'Farmer is not an active cooperative member (status: %) and is not eligible for a loan', v_farmer_status;
  END IF;

  -- Capital-share loan eligibility — HARD block (Issue 4d). Runs before
  -- the replay check so a replayed call re-verifies too. The Issue-Loan
  -- screen shows its own warning banner; this is the backend authority.
  SELECT COALESCE(mcs.total_contribution, 0) INTO v_contribution
  FROM member_capital_shares mcs
  WHERE mcs.farmer_id = p_farmer_id;
  v_contribution := COALESCE(v_contribution, 0);

  SELECT COALESCE(lps.minimum_capital_contribution, 2000) INTO v_minimum
  FROM loan_policy_settings lps
  WHERE lps.id = 1;
  v_minimum := COALESCE(v_minimum, 2000);

  IF v_contribution < v_minimum THEN
    RAISE EXCEPTION
      'Farmer has not met the minimum capital contribution of % required for a loan (current contribution: %)',
      v_minimum, v_contribution;
  END IF;

  -- Input validation.
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one loan item is required';
  END IF;

  IF p_monthly_payment <= 0 THEN
    RAISE EXCEPTION 'Monthly payment must be greater than zero';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_quantity   := (v_item->>'quantity')::NUMERIC;
    v_unit_price := (v_item->>'unitPrice')::NUMERIC;
    v_line_total := (v_item->>'lineTotal')::NUMERIC;

    IF v_quantity IS NULL OR v_quantity <= 0 THEN
      RAISE EXCEPTION 'Item quantity must be greater than zero: %', v_item->>'itemName';
    END IF;

    IF v_unit_price IS NULL OR v_unit_price < 0 THEN
      RAISE EXCEPTION 'Item unit price must not be negative: %', v_item->>'itemName';
    END IF;

    IF v_line_total IS NULL OR v_line_total < 0 THEN
      RAISE EXCEPTION 'Item line total must not be negative: %', v_item->>'itemName';
    END IF;
  END LOOP;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT fl.id, fl.reference_no INTO v_existing_id, v_existing_ref
      FROM farmer_loans fl
      WHERE fl.idempotency_key = p_idempotency_key;

    IF FOUND THEN
      RETURN QUERY SELECT v_existing_id, v_existing_ref;
      RETURN;
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('loan_reference_' || v_year::TEXT));

  SELECT COALESCE(MAX(
    NULLIF(regexp_replace(fl.reference_no, '^LN-\d{4}-', ''), '')::INT
  ), 0) + 1
  INTO v_next_seq
  FROM farmer_loans fl
  WHERE fl.reference_no LIKE 'LN-' || v_year || '-%';

  v_reference_no := 'LN-' || v_year || '-' || LPAD(v_next_seq::TEXT, 3, '0');

  SELECT COALESCE(SUM((elem->>'lineTotal')::NUMERIC), 0)
    INTO v_total_value
    FROM jsonb_array_elements(p_items) AS elem;

  INSERT INTO farmer_loans (
    farmer_id, reference_no, issued_date, total_value, amount_paid,
    status, notes, monthly_payment, next_payment_date, idempotency_key
  ) VALUES (
    p_farmer_id, v_reference_no, p_issued_date, v_total_value, 0,
    'active', p_notes, p_monthly_payment, p_next_payment_date, p_idempotency_key
  )
  RETURNING id INTO v_loan_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO farmer_loan_items (loan_id, item_name, quantity, unit, unit_price, line_total)
    VALUES (
      v_loan_id,
      v_item->>'itemName',
      (v_item->>'quantity')::NUMERIC,
      v_item->>'unit',
      (v_item->>'unitPrice')::NUMERIC,
      (v_item->>'lineTotal')::NUMERIC
    );

    v_inventory_id := NULLIF(v_item->>'inventoryItemId', '')::UUID;
    IF v_inventory_id IS NOT NULL THEN
      v_quantity := (v_item->>'quantity')::NUMERIC;

      SELECT quantity_on_hand, item_name INTO v_available, v_item_name
        FROM cooperative_inventory
        WHERE id = v_inventory_id
        FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Inventory item % no longer exists', v_inventory_id;
      END IF;

      IF v_available < v_quantity THEN
        RAISE EXCEPTION 'Insufficient stock for %: % on hand, % requested',
          v_item_name, v_available, v_quantity;
      END IF;

      UPDATE cooperative_inventory
      SET quantity_on_hand = quantity_on_hand - v_quantity
      WHERE id = v_inventory_id;

      INSERT INTO inventory_transactions (
        inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by
      ) VALUES (
        v_inventory_id, 'loan_issued', -v_quantity, v_loan_id, 'loan', p_recorded_by
      );
    END IF;
  END LOOP;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    p_farmer_id, 'loan', 'Loan Issued',
    'A new loan (' || v_reference_no || ') worth ₱' ||
      to_char(v_total_value, 'FM999,999,990.00') || ' has been issued to you.',
    FALSE, NOW(), '/farmer/profile/loans'
  );

  RETURN QUERY SELECT v_loan_id, v_reference_no;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_loan_payment(p_loan_id uuid, p_amount numeric, p_payment_date date, p_next_payment_date_if_active date, p_notes text DEFAULT NULL::text, p_recorded_by uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text)
RETURNS TABLE(is_fully_paid boolean, running_balance numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_total_value      NUMERIC;
  v_current_paid     NUMERIC;
  v_new_paid         NUMERIC;
  v_running_balance  NUMERIC;
  v_is_fully_paid    BOOLEAN;
  v_existing_balance NUMERIC;
  v_farmer_id        UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Only admins may record loan payments';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Payment amount must be greater than zero';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT flp.running_balance INTO v_existing_balance
      FROM farmer_loan_payments flp
      WHERE flp.idempotency_key = p_idempotency_key;

    IF FOUND THEN
      RETURN QUERY SELECT (v_existing_balance = 0), v_existing_balance;
      RETURN;
    END IF;
  END IF;

  SELECT total_value, COALESCE(amount_paid, 0), farmer_id
    INTO v_total_value, v_current_paid, v_farmer_id
    FROM farmer_loans
    WHERE id = p_loan_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Loan % not found', p_loan_id;
  END IF;

  v_new_paid        := v_current_paid + p_amount;
  v_running_balance := GREATEST(v_total_value - v_new_paid, 0);
  v_is_fully_paid   := v_new_paid >= v_total_value;

  INSERT INTO farmer_loan_payments (
    loan_id, payment_date, amount_paid, running_balance, notes, recorded_by, idempotency_key
  ) VALUES (
    p_loan_id, p_payment_date, p_amount, v_running_balance, p_notes, p_recorded_by, p_idempotency_key
  );

  UPDATE farmer_loans
  SET amount_paid         = v_new_paid,
      status              = CASE WHEN v_is_fully_paid THEN 'paid' ELSE 'active' END,
      notified_overdue_at = NULL,
      next_payment_date   = CASE WHEN v_is_fully_paid
                               THEN next_payment_date
                               ELSE p_next_payment_date_if_active
                             END
  WHERE id = p_loan_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'loan',
    CASE WHEN v_is_fully_paid THEN 'Loan Fully Paid' ELSE 'Payment Recorded' END,
    'Your payment of ₱' || to_char(p_amount, 'FM999,999,990.00') || ' was recorded.' ||
      CASE WHEN v_is_fully_paid
        THEN ' Your loan is now fully paid off. Thank you!'
        ELSE ' Remaining balance: ₱' || to_char(v_running_balance, 'FM999,999,990.00') || '.'
      END,
    FALSE, NOW(), '/farmer/profile/loans'
  );

  RETURN QUERY SELECT v_is_fully_paid, v_running_balance;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_overdue_farmers()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_mode           TEXT;
  v_delay_days     INT;
  v_notified_count INT := 0;
  v_loan           RECORD;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Only admins or the scheduled maintenance job may call this function';
  END IF;

  SELECT notification_timing_mode, notification_delay_days
  INTO v_mode, v_delay_days
  FROM loan_policy_settings WHERE id = 1;

  FOR v_loan IN
    SELECT id, farmer_id, reference_no, total_value, amount_paid, next_payment_date
    FROM farmer_loans
    WHERE status = 'overdue'
      AND notified_overdue_at IS NULL
      AND (
        v_mode = 'on_transition'
        OR (v_mode = 'delayed' AND next_payment_date <= CURRENT_DATE - v_delay_days)
        OR (v_mode = 'next_bod_meeting' AND CURRENT_DATE >= next_bod_saturday_after(next_payment_date))
      )
  LOOP
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      v_loan.farmer_id,
      'loan',
      'Payment Reminder',
      'Your loan ' || v_loan.reference_no || ' has a missed payment. Outstanding balance: ₱' ||
      to_char(v_loan.total_value - v_loan.amount_paid, 'FM999,999,990.00') ||
      '. Please settle at the next BOD meeting or visit the cooperative office.',
      FALSE,
      NOW(),
      '/farmer/profile/loans'
    );

    UPDATE farmer_loans SET notified_overdue_at = NOW() WHERE id = v_loan.id;
    v_notified_count := v_notified_count + 1;
  END LOOP;

  RETURN v_notified_count;
END;
$$;

-- ─── reinvest_patronage_capital → admin, /admin/balik-tangkilik ───────────

CREATE OR REPLACE FUNCTION public.reinvest_patronage_capital(p_year integer, p_amount numeric, p_note text DEFAULT NULL::text)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_farmer UUID := auth.uid();
  v_row RECORD;
  v_total_payout NUMERIC;
  v_available NUMERIC;
  v_farmer_name TEXT;
BEGIN
  IF v_farmer IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  SELECT * INTO v_row
  FROM member_contributions
  WHERE farmer_id = v_farmer AND year = p_year
  FOR UPDATE;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'No contribution record found for % (%)', v_farmer, p_year;
  END IF;
  IF v_row.status != 'paid' THEN
    RAISE EXCEPTION 'This year''s Balik-Tangkilik has not been finalized yet (status: %)', v_row.status;
  END IF;

  v_total_payout := COALESCE(v_row.actual_balik_tangkilik, 0)
                   + COALESCE(v_row.actual_interest_on_capital, 0)
                   + COALESCE(v_row.actual_purchase_patronage, 0);
  v_available := v_total_payout - v_row.reinvested_amount;

  IF p_amount > v_available THEN
    RAISE EXCEPTION 'Amount (%) exceeds what remains available to reinvest (%)', p_amount, v_available;
  END IF;

  INSERT INTO capital_contribution_events (farmer_id, amount, source, note, recorded_by)
  VALUES (
    v_farmer,
    p_amount,
    'patronage_capital',
    COALESCE(p_note, 'Reinvested from ' || p_year || ' Balik-Tangkilik payout'),
    v_farmer
  );

  UPDATE member_contributions
  SET reinvested_amount = reinvested_amount + p_amount
  WHERE farmer_id = v_farmer AND year = p_year;

  SELECT full_name INTO v_farmer_name FROM user_information WHERE user_id = v_farmer;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT
    ap.user_id,
    'capital',
    'Patronage Capital Reinvested',
    COALESCE(v_farmer_name, 'A farmer') || ' reinvested ₱' || to_char(p_amount, 'FM999,999,990.00') ||
      ' of their ' || p_year || ' Balik-Tangkilik payout into their capital share.',
    FALSE,
    NOW(),
    '/admin/balik-tangkilik'
  FROM admin_profiles ap;

  RETURN v_available - p_amount;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- SELECT column_name FROM information_schema.columns
-- WHERE table_name = 'notifications' AND column_name IN ('route_on_tap','route_extra');
-- -- expect 2 rows
--
-- SELECT proname FROM pg_proc
-- WHERE prosrc ILIKE '%INSERT INTO notifications%' AND prosrc NOT ILIKE '%route_on_tap%';
-- -- expect 0 rows — every notification-creating function now sets it
-- ============================================================
