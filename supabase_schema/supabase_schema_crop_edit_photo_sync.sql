-- ============================================================
-- SAGANA — Sync crop_requests.photo_url into farmer_crops on approval
-- (Farmer-Harvest Tab redesign, Revision D — Crop Roster / Edit Crop)
--
-- Gap identified while building Crop Roster's new Edit Crop action: a
-- farmer's reference photo for a pending crop is captured on the
-- crop_requests row (via CropRepository.uploadCropRequestPhoto(),
-- requestNewCrop()) but approve_crop_request() never copied it onto the
-- linked farmer_crops row. FarmerCropModel.displayImageUrl reads
-- farmer_crops.photo_url first (falling back to crop_master.image_url),
-- so an approved crop's own request photo was silently dropped and the
-- crop fell back to the generic category icon or catalog photo forever.
--
-- Full function body re-supplied (CREATE OR REPLACE requires the whole
-- thing) — identical to supabase_schema_da_amad_ginger_exclusive.sql's
-- version (the latest of the several approve_crop_request migrations;
-- confirmed by content — it's the only one with both the da_amad_market
-- validation and the p_crop_type fallback chain the others lack) except
-- for the one added line copying the photo across. COALESCE keeps
-- whatever photo the farmer may have already set via Edit Crop before
-- approval landed, rather than overwriting it with the (possibly older)
-- request photo.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION approve_crop_request(
  p_request_id UUID,
  p_admin_notes TEXT DEFAULT NULL,
  p_crop_type TEXT DEFAULT NULL
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

  IF p_crop_type IS NOT NULL AND p_crop_type NOT IN ('sp3_cooperative', 'da_amad_market', 'open_market') THEN
    RAISE EXCEPTION 'Invalid crop_type: %', p_crop_type;
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
      COALESCE(p_crop_type, v_request.crop_type, 'open_market'),
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

GRANT EXECUTE ON FUNCTION approve_crop_request(UUID, TEXT, TEXT) TO authenticated;

-- ─── Backfill already-approved crops ────────────────────────────────────────
-- Crops approved before this migration existed never got their request
-- photo copied across. Only fills farmer_crops rows that are still blank
-- and whose originating (approved) request actually had a photo — never
-- overwrites a photo the farmer already has set.
UPDATE public.farmer_crops fc
SET photo_url = cr.photo_url
FROM public.crop_requests cr
WHERE cr.farmer_crop_id = fc.id
  AND cr.status = 'approved'
  AND fc.photo_url IS NULL
  AND cr.photo_url IS NOT NULL;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) Backfill worked for existing approved crops that had a request photo:
--    SELECT fc.id, fc.crop_name, fc.photo_url, cr.photo_url AS request_photo
--    FROM farmer_crops fc
--    JOIN crop_requests cr ON cr.farmer_crop_id = fc.id
--    WHERE cr.status = 'approved' AND cr.photo_url IS NOT NULL;
--    -- expect fc.photo_url = cr.photo_url for every row
--
-- 2) New approvals copy the photo going forward: approve a pending
--    request submitted with a photo (Request New Crop, with a photo
--    attached), then:
--    SELECT fc.photo_url FROM farmer_crops fc WHERE fc.id = '<farmer_crop_id>';
--    -- expect the same URL the request was submitted with
--
-- 3) A farmer-set Edit Crop photo is never clobbered by a later approval:
--    (only relevant if a crop can somehow still be pending after Edit
--    Crop touched it) — SELECT photo_url stays the Edit Crop value, not
--    the original request's.
