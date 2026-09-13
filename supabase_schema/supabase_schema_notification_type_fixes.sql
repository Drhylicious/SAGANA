-- ============================================================
-- SAGANA — Notification Filter Chip Fix (Item 1)
-- Six farmer-facing notification sources were inserting with
-- type = 'system', which has no matching NotificationFilter chip
-- — these notifications were only ever visible under "All".
-- This migration:
--   1. Extends notifications_type_check with two new values
--      ('cooperative_offer', 'program') — 'crop_request' already
--      exists and was simply unused by farmer-facing code.
--   2. Updates 5 functions (reject_listing, approve_crop_request,
--      reject_crop_request, confirm_cooperative_offer,
--      decline_cooperative_offer, confirm_program_return — 6 total)
--      to use their correct, specific type instead of 'system'.
-- Every other line of business logic in each function is
-- byte-for-byte unchanged; only the notification 'type' value
-- itself is touched.
-- ============================================================

-- ─── 1. Extend the CHECK constraint ────────────────────────────────────────

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (type IN (
    'order', 'listing', 'loan', 'price', 'sync', 'system',
    'listing_submitted', 'loan_overdue', 'member_pending',
    'member_registered', 'member_updated',
    'low_stock', 'stock_depleted',
    'crop_request', 'cooperative_offer', 'program'
  ));

-- ─── 2. reject_listing → 'listing' ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION reject_listing(
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
  SET status = 'rejected', admin_notes = p_reason, remaining_kg = 0, updated_at = NOW()
  WHERE id = p_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_listing.farmer_id, 'listing', 'Listing Rejected',
    'Your ' || v_listing.crop_name || ' listing was rejected. Reason: ' || p_reason,
    FALSE, NOW()
  );
END;
$$;

-- ─── 3. approve_crop_request → 'crop_request' ──────────────────────────────

CREATE OR REPLACE FUNCTION approve_crop_request(
  p_request_id UUID,
  p_admin_notes TEXT DEFAULT NULL,
  p_crop_type TEXT DEFAULT 'open_market'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  SELECT id INTO v_crop_master_id
  FROM crop_master
  WHERE lower(crop_name) = lower(v_request.requested_name)
  LIMIT 1;

  IF v_crop_master_id IS NULL THEN
    INSERT INTO crop_master (crop_name, category, crop_type, is_active, sort_order)
    VALUES (
      v_request.requested_name,
      COALESCE(v_request.category, 'Other'),
      p_crop_type,
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

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_request.farmer_id,
    'crop_request',
    'Crop Request Approved',
    v_request.requested_name || ' has been added to the official crop list and is now fully approved.',
    FALSE,
    NOW()
  );

  RETURN v_crop_master_id;
END;
$$;

GRANT EXECUTE ON FUNCTION approve_crop_request TO authenticated;

-- ─── 4. reject_crop_request → 'crop_request' ───────────────────────────────

CREATE OR REPLACE FUNCTION reject_crop_request(
  p_request_id UUID,
  p_admin_notes TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_request.farmer_id,
    'crop_request',
    'Crop Request Declined',
    v_request.requested_name || ' was not added to the official list. Reason: ' || p_admin_notes,
    FALSE,
    NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION reject_crop_request TO authenticated;

-- ─── 5. confirm_cooperative_offer / decline_cooperative_offer → 'cooperative_offer' ─

CREATE OR REPLACE FUNCTION confirm_cooperative_offer(
  p_offer_id UUID,
  p_confirmed_quantity_kg DECIMAL,
  p_confirmed_amount DECIMAL,
  p_admin_notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
  IF v_crop_type NOT IN ('palay', 'peanut') THEN
    RAISE EXCEPTION 'Crop % is not eligible for a Balik-Tangkilik sales record.', v_offer.crop_name;
  END IF;

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

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_offer.farmer_id,
    'cooperative_offer',
    'Cooperative Purchase Confirmed',
    'Your offer of ' || p_confirmed_quantity_kg || 'kg ' || v_offer.crop_name ||
      ' was confirmed by SP3 for ₱' || p_confirmed_amount || '.',
    FALSE,
    NOW()
  );

  RETURN v_transaction_id;
END;
$$;

GRANT EXECUTE ON FUNCTION confirm_cooperative_offer TO authenticated;

CREATE OR REPLACE FUNCTION decline_cooperative_offer(
  p_offer_id UUID,
  p_admin_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_offer.farmer_id,
    'cooperative_offer',
    'Cooperative Purchase Offer Declined',
    'Your offer of ' || v_offer.offered_quantity_kg || 'kg ' || v_offer.crop_name ||
      ' was not accepted by SP3.' ||
      CASE WHEN p_admin_notes IS NOT NULL THEN ' Reason: ' || p_admin_notes ELSE '' END,
    FALSE,
    NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION decline_cooperative_offer TO authenticated;

-- ─── 6. confirm_program_return → 'program' ─────────────────────────────────

CREATE OR REPLACE FUNCTION confirm_program_return(
  p_program_member_id UUID,
  p_amount_returned DECIMAL,
  p_admin_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_member.farmer_id,
    'program',
    'Program Return Settled',
    'Your return of ₱' || p_amount_returned || ' for ' || v_program.program_name || ' has been recorded. Thank you!',
    FALSE,
    NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION confirm_program_return(UUID, DECIMAL, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';