-- ============================================================
-- SAGANA — Phase 1: Restore listing-approval farmer notifications
-- ============================================================
-- Root cause: supabase_schema_admin_profile_settings_phase1.sql
-- (2026-09-15) recreated approve_listing / reject_listing /
-- request_listing_changes to add reviewed_by/reviewed_at tracking,
-- but built each one from an outdated base body that predates the
-- 2026-08-24 notification work (supabase_schema_farmer_notification_
-- gaps.sql for approve_listing/request_listing_changes, and the
-- later same-day supabase_schema_notification_type_fixes.sql for
-- reject_listing). That silently dropped:
--   * approve_listing:          the farmer notification insert
--   * request_listing_changes:  the farmer notification insert
--   * reject_listing:           the farmer notification insert, the
--                                'Only pending_review listings can be
--                                rejected' guard, resetting
--                                remaining_kg to 0, and released the
--                                wrong quantity from the reserved
--                                batch (volume_kg instead of the
--                                listing's actual remaining_kg).
--
-- This migration restores all of the above while preserving the
-- reviewed_by/reviewed_at columns/assignments added on 2026-09-15.
-- No notifications_type_check change needed — 'listing' is already
-- an allowed type.
-- ============================================================

-- ─── 1. approve_listing → restore farmer notification ─────────────────────

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

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id, 'listing', 'Listing Approved',
    'Your ' || v_crop_name || ' listing is now live on the Marketplace.',
    FALSE, NOW()
  );
END;
$$;

-- ─── 2. reject_listing → restore guard, remaining_kg reset, correct ────────
-- ─── release quantity, and farmer notification ─────────────────────────────

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

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_listing.farmer_id, 'listing', 'Listing Rejected',
    'Your ' || v_listing.crop_name || ' listing was rejected. Reason: ' || p_reason,
    FALSE, NOW()
  );
END;
$$;

-- ─── 3. request_listing_changes → restore farmer notification ─────────────

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

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id, 'listing', 'Changes Requested',
    'Your ' || v_crop_name || ' listing needs changes before it can go live. Note: ' || p_notes,
    FALSE, NOW()
  );
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) All three functions still contain reviewed_by/reviewed_at:
--    SELECT proname, prosrc ILIKE '%reviewed_by%' AS has_reviewed_by
--    FROM pg_proc WHERE proname IN ('approve_listing','reject_listing','request_listing_changes');
--    -- expect 3 rows, all TRUE
--
-- 2) All three now contain a notification insert:
--    SELECT proname, prosrc ILIKE '%INSERT INTO notifications%' AS has_notify
--    FROM pg_proc WHERE proname IN ('approve_listing','reject_listing','request_listing_changes');
--    -- expect 3 rows, all TRUE
--
-- 3) reject_listing has its pending_review guard back:
--    SELECT prosrc ILIKE '%Only pending_review listings can be rejected%'
--    FROM pg_proc WHERE proname = 'reject_listing';
--    -- expect TRUE
--
-- 4) Approve/reject/request-changes a real pending_review listing in-app
--    and confirm the farmer receives a 'listing' notification with the
--    expected title/body.
-- ============================================================
