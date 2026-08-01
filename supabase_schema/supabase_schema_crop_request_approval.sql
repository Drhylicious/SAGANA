-- ============================================================
-- SAGANA — Crop Request Approval Workflow
-- ============================================================

-- Link crop_requests back to the farmer_crops row it originated from.
-- ON DELETE CASCADE: if the farmer deletes their pending crop, the
-- orphaned request should disappear too, not sit in the queue forever
-- pointing at nothing.
ALTER TABLE public.crop_requests
  ADD COLUMN IF NOT EXISTS farmer_crop_id UUID REFERENCES public.farmer_crops(id) ON DELETE CASCADE;

-- ─── Approve ─────────────────────────────────────────────────────────────────
-- Atomic: matches an existing crop_master row case-insensitively (so two
-- farmers requesting "Tomato" don't create two catalog entries), or
-- creates one if none exists; backfills farmer_crops.crop_master_id;
-- marks the request approved; notifies the farmer. All-or-nothing.
CREATE OR REPLACE FUNCTION approve_crop_request(
  p_request_id UUID,
  p_admin_notes TEXT DEFAULT NULL
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
    INSERT INTO crop_master (crop_name, category, is_active, sort_order)
    VALUES (
      v_request.requested_name,
      COALESCE(v_request.category, 'Other'),
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

-- ─── Reject ──────────────────────────────────────────────────────────────────
-- farmer_crops row is left untouched (never deleted) — the farmer keeps
-- any harvests already recorded against it. Only its displayed status
-- changes, via the join added to fetchCrops() below.
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
    'system',
    'Crop Request Declined',
    v_request.requested_name || ' was not added to the official list. Reason: ' || p_admin_notes,
    FALSE,
    NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION reject_crop_request TO authenticated;

-- If you hit a schema-cache-related 400 error after running this (same
-- issue as the loan/inventory link earlier), force a reload:
NOTIFY pgrst, 'reload schema';
