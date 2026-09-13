-- Item C (Decision 3): server-side state-transition guards for Approve and
-- Request Changes, replacing the previous raw client-side .update() calls
-- that had no precondition at all. Mirrors reject_listing's existing
-- guard pattern. pending_review is the only valid source status for both,
-- per confirmed business rule — the UI already restricts these actions to
-- pending_review listings (listing_review_screen.dart, `if (isPending)`),
-- so this guard is defense-in-depth against a race condition rather than
-- a change to the normal-path behavior.

CREATE OR REPLACE FUNCTION public.approve_listing(p_listing_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can approve listings';
  END IF;

  SELECT status INTO v_status FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_status != 'pending_review' THEN
    RAISE EXCEPTION 'Only pending_review listings can be approved (current: %)', v_status;
  END IF;

  UPDATE marketplace_listings
  SET status = 'approved', admin_notes = NULL, updated_at = NOW()
  WHERE id = p_listing_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.request_listing_changes(p_listing_id UUID, p_notes TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can request changes on listings';
  END IF;

  SELECT status INTO v_status FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_status != 'pending_review' THEN
    RAISE EXCEPTION 'Only pending_review listings can have changes requested (current: %)', v_status;
  END IF;

  UPDATE marketplace_listings
  SET status = 'changes_required', admin_notes = p_notes, updated_at = NOW()
  WHERE id = p_listing_id;
END;
$$;
