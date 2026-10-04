-- ============================================================
-- SAGANA — Phase 3: Close 4 half-loop notification gaps
-- ============================================================
-- Four workflows notify only one side of a two-party action. This adds
-- the missing side in each, without touching the existing (working)
-- notification on the other side:
--   1. offer_batch_to_cooperative — farmer submits, nobody told. Admins
--      now get notified, same fan-out pattern as
--      notify_admins_of_crop_request().
--   2. submit_application — only self-notifies the applicant. Admins
--      now also get notified of the new pending application.
--   3. place_order — already notifies every admin. The farmer whose
--      listing was ordered now also gets notified.
--   4. approveOrder (Dart, admin_order_repository.dart) — already
--      notifies the buyer. The farmer now also gets notified, mirroring
--      complete_order's existing both-party pattern.
-- ============================================================

-- ─── 1. offer_batch_to_cooperative → notify all admins ─────────────────────

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

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT
    ap.user_id,
    'cooperative_offer',
    'New Cooperative Offer',
    p_crop_name || ' (' || p_quantity_kg || ' kg) was offered to the cooperative and needs review.',
    FALSE,
    NOW()
  FROM admin_profiles ap;

  RETURN v_offer_id;
END;
$$;

-- ─── 2. submit_application → also notify all admins ────────────────────────

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

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT
    ap.user_id,
    'member_pending',
    'New Membership Application',
    COALESCE(v_full_name, 'A farmer') || ' submitted a membership application and needs review.',
    FALSE,
    NOW()
  FROM admin_profiles ap;

  RETURN (v_attempts + 1)::SMALLINT;
END;
$$;

-- ─── 3. place_order → also notify the farmer ────────────────────────────────

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
  INSERT INTO notifications (user_id, type, title, body)
  SELECT ap.user_id,
         'order',
         'New order placed',
         format('A new order (%s kg) has been placed and is awaiting approval.', p_quantity_kg)
  FROM admin_profiles ap;

  -- Notify the farmer whose listing was ordered.
  INSERT INTO notifications (user_id, type, title, body)
  VALUES (
    v_farmer_id,
    'order',
    'New Order Received',
    format('A buyer placed an order for %s kg of your %s listing.', p_quantity_kg, COALESCE(v_crop_name, 'produce'))
  );

  RETURN v_order_id;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) All three now contain the new insert:
--    SELECT proname, prosrc ILIKE '%admin_profiles%' AS notifies_admins
--    FROM pg_proc WHERE proname IN ('offer_batch_to_cooperative','submit_application');
--    -- expect both TRUE
--    SELECT prosrc ILIKE '%New Order Received%' FROM pg_proc WHERE proname = 'place_order';
--    -- expect TRUE
--
-- 2) In-app: submit a cooperative offer / a membership application / place
--    an order, and confirm the new notification appears for the intended
--    recipient(s) without breaking the existing one.
-- ============================================================
