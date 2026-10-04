-- ============================================================
-- Fix: approve_crop_request notification regression
-- ============================================================
-- supabase_schema_crop_master_image_on_approval.sql (2026-09-21, a
-- later, separate session's work) rebuilt approve_crop_request to add
-- crop-image-seeding logic (copying the request's photo into
-- crop_master.image_url and, via COALESCE, into the linked
-- farmer_crops.photo_url — that logic is correct and preserved below
-- unchanged), but based its rewrite on an outdated function body.
-- That silently reverted two earlier, unrelated fixes to this same
-- function:
--   1. Phase 0 of the Notification project (2026-09-19) standardized
--      this notification's type from 'system' to 'crop_request' so it
--      shows under the farmer's "Crop Requests" filter instead of only
--      "All" — reverted back to 'system'.
--   2. Phase 7 of the Notification project (2026-09-19) added
--      route_on_tap so tapping the notification opens
--      /farmer/harvest/crops — the route_on_tap column was dropped
--      from the INSERT entirely.
-- reject_crop_request (this function's sibling, same workflow) was
-- untouched by the Sept 21 migration and still correctly has both
-- type='crop_request' and route_on_tap='/farmer/harvest/crops' — this
-- restores approve_crop_request to match it exactly.
--
-- Every other line of business logic (admin check, status guard,
-- crop_type validation, crop_master lookup/insert with image seeding,
-- crop_requests update, farmer_crops crop_master_id/photo_url update)
-- is byte-for-byte unchanged from the current live version.
-- ============================================================

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
    INSERT INTO crop_master (crop_name, category, crop_type, image_url, is_active, sort_order)
    VALUES (
      v_request.requested_name,
      COALESCE(v_request.category, 'Other'),
      COALESCE(p_crop_type, v_request.crop_type, 'open_market'),
      v_request.photo_url,
      TRUE,
      (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM crop_master)
    )
    RETURNING id INTO v_crop_master_id;
  END IF;

  UPDATE crop_requests
  SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = NOW(), admin_notes = p_admin_notes
  WHERE id = p_request_id;

  IF v_request.farmer_crop_id IS NOT NULL THEN
    UPDATE farmer_crops
    SET crop_master_id = v_crop_master_id,
        photo_url = COALESCE(farmer_crops.photo_url, v_request.photo_url)
    WHERE id = v_request.farmer_crop_id;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_request.farmer_id,
    'crop_request',
    'Crop Request Approved',
    v_request.requested_name || ' has been added to the official crop list and is now fully approved.',
    FALSE,
    NOW(),
    '/farmer/harvest/crops'
  );

  RETURN v_crop_master_id;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- SELECT prosrc ILIKE '%''crop_request''%' AND prosrc ILIKE '%route_on_tap%'
--   AND prosrc ILIKE '%v_request.photo_url%'
-- FROM pg_proc WHERE proname = 'approve_crop_request';
-- -- expect TRUE (type fixed, route restored, image-seeding logic preserved)
--
-- In-app: approve a pending crop request as admin, confirm the farmer's
-- notification shows under the "Crop Requests" filter (not just "All")
-- and tapping it opens My Crops.
-- ============================================================
