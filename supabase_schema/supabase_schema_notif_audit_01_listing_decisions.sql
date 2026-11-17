-- ============================================================================
-- Notification audit 01: the Farmer is told when a listing is approved or
-- disapproved.
--
-- Found in the audit: approve_listing and reject_listing (live definitions) send
-- no notification at all. The last "Listing Approved" notification in the
-- database is from 2026-09-28; a later rewrite of both functions dropped it. A
-- Farmer whose listing is reviewed was never told.
--
-- This script re-creates both functions EXACTLY as they are live today and adds
-- only the Farmer notification. Run once, in the Supabase SQL editor.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.approve_listing(p_listing_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status    TEXT;
  v_farmer_id UUID;
  v_crop_name TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only Managers can approve listings';
  END IF;

  SELECT status, farmer_id, crop_name
    INTO v_status, v_farmer_id, v_crop_name
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
    'Your ' || COALESCE(v_crop_name, 'produce') || ' listing is now live on the Marketplace.',
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_listing(p_listing_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_listing RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only Managers can reject listings';
  END IF;

  SELECT * INTO v_listing FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_listing.inventory_batch_id IS NOT NULL THEN
    PERFORM _release_batch_reservation(v_listing.inventory_batch_id, v_listing.volume_kg);
  END IF;

  UPDATE marketplace_listings
  SET status = 'rejected', admin_notes = p_reason, reviewed_by = auth.uid(), reviewed_at = NOW(), updated_at = NOW()
  WHERE id = p_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_listing.farmer_id, 'listing', 'Listing Disapproved',
    'Your ' || COALESCE(v_listing.crop_name, 'produce') || ' listing was not approved.' ||
      CASE WHEN NULLIF(btrim(p_reason), '') IS NOT NULL THEN ' Reason: ' || btrim(p_reason) ELSE '' END,
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$$;

-- Same permissions as before (CREATE OR REPLACE keeps them).
