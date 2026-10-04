-- ============================================================
-- SAGANA — Carry a Request New Crop photo onto crop_master.image_url
-- (Crop Management as the source of truth for a crop's catalog image)
--
-- supabase_schema_crop_edit_photo_sync.sql copied a request's photo onto
-- farmer_crops.photo_url (the requesting farmer's own copy) but never
-- touched crop_master.image_url — the catalog-level image Admin's Crop
-- Management reads directly, and that Price Management already joins on
-- (price_management_repository.dart: "Price Management only ever
-- references this image, never uploads or stores its own copy"). A
-- brand-new crop created via a farmer's request therefore always got the
-- default icon on the Admin side, and nothing for Price Management to
-- reuse, regardless of whether a photo was attached to the request.
--
-- Full function body re-supplied (CREATE OR REPLACE requires the whole
-- thing) — identical to supabase_schema_crop_edit_photo_sync.sql's
-- version, plus image_url added to the crop_master INSERT when a new
-- catalog entry is created. Does NOT touch crop_master.image_url for an
-- already-existing catalog crop (v_crop_master_id found, not created) —
-- that image is Admin's own to manage from Crop Management directly, and
-- a farmer's request photo for an already-cataloged crop shouldn't
-- silently override it.
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

-- ─── Backfill already-approved crops whose catalog entry never got an
-- image, using the photo from the request that created them ────────────
UPDATE public.crop_master cm
SET image_url = cr.photo_url
FROM public.crop_requests cr
WHERE cr.status = 'approved'
  AND lower(cm.crop_name) = lower(cr.requested_name)
  AND cm.image_url IS NULL
  AND cr.photo_url IS NOT NULL;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) Backfill worked for the Eggplant example (or any prior approval that
--    had a photo but no crop_master image):
--    SELECT cm.crop_name, cm.image_url, cr.photo_url AS request_photo
--    FROM crop_master cm
--    JOIN crop_requests cr ON lower(cr.requested_name) = lower(cm.crop_name)
--    WHERE cr.status = 'approved' AND cr.photo_url IS NOT NULL;
--    -- expect cm.image_url = cr.photo_url for every row
--
-- 2) New approvals set the catalog image going forward: submit a new
--    Request New Crop with a photo, approve it, then:
--    SELECT image_url FROM crop_master WHERE crop_name = '<the new crop>';
--    -- expect the same URL the request was submitted with
--
-- 3) Price Management should now show the same photo automatically for
--    any crop that has a price record — no separate change needed there,
--    it already joins crop_master(image_url).
