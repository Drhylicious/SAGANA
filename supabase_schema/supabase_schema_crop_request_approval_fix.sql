-- ============================================================
-- SAGANA — Fix: approve_crop_request() rejects every call
--
-- crop_request_approval_screen.dart always sends p_crop_type to
-- approve_crop_request(), but the function never declared that
-- parameter — every approval call fails at the RPC layer.
-- Separately, crop_requests.crop_type was never added by any
-- migration despite both crop_repository.dart and this screen
-- depending on it. This adds the missing column and replaces
-- the function to accept and actually use crop_type when
-- creating a new crop_master entry. Existing catalog entries
-- matched by name are left untouched — crop_type is treated as
-- a stable catalog-wide property, not something a single
-- approval should silently overwrite for every farmer already
-- using that entry.
-- ============================================================

ALTER TABLE public.crop_requests
  ADD COLUMN IF NOT EXISTS crop_type TEXT;

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
    'system',
    'Crop Request Approved',
    v_request.requested_name || ' has been added to the official crop list and is now fully approved.',
    FALSE,
    NOW()
  );

  RETURN v_crop_master_id;
END;
$$;

GRANT EXECUTE ON FUNCTION approve_crop_request TO authenticated;

NOTIFY pgrst, 'reload schema';
