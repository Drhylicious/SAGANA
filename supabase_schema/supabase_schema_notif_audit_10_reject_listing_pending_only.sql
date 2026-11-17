-- ============================================================================
-- Audit 10: reject_listing refuses a listing that is no longer pending review.
--
-- reject_listing (live) released the listing's reserved quantity and set the
-- status to Rejected without checking the listing's current status. If two staff
-- reviewed the same listing at once (one approves, the other still sees it as
-- pending and rejects), the live listing was rejected and its quantity released
-- again, which could leave a batch showing more available stock than it holds.
--
-- This re-creates reject_listing EXACTLY as it is live today and adds only the
-- check approve_listing already has: only a pending_review listing can be
-- decided, and the second person gets a clear message.
-- Run once, in the Supabase SQL editor.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.reject_listing(p_listing_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_listing RECORD;
BEGIN
  IF NOT (public.is_staff() AND public.staff_can_manage('marketplace', auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized: only the Manager or an Officer with Manage access to Marketplace can reject listings';
  END IF;

  SELECT * INTO v_listing FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_listing.status != 'pending_review' THEN
    RAISE EXCEPTION 'Only pending_review listings can be rejected (current: %)', v_listing.status;
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
$function$;
