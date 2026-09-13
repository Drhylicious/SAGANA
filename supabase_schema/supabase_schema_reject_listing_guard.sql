-- Adds the same pending_review-only guard that approve_listing and
-- request_listing_changes already have (Phase 1, Decision 3). reject_listing
-- was never in that decision's original scope and was left ungated —
-- found during final verification. No other logic touched: reservation
-- release, admin_notes, remaining_kg zeroing, and the farmer notification
-- are byte-for-byte unchanged from the current live function.

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
    v_listing.farmer_id, 'system', 'Listing Rejected',
    'Your ' || v_listing.crop_name || ' listing was rejected. Reason: ' || p_reason,
    FALSE, NOW()
  );
END;
$$;
