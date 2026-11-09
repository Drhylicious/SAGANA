-- ============================================================
-- SAGANA — Edit Listing changes THREE fields only: quantity, asking price, description
--
-- WHY
--   A listing's photo is always the Farmer's own Crop Roster photo (a database
--   trigger copies it onto the listing when it is created, and the Create Listing
--   screen locks it). It is therefore not an independent field a Farmer can edit.
--   The previous edit functions still accepted a photo; this script closes that, so
--   the rule is enforced in Supabase and not only in the app.
--
-- WHAT IT DOES (same names, same signatures; only these two functions are replaced)
--   * update_my_listing()   a Pending Approval listing is still edited directly, but a
--                           request to refresh the photo (p_refresh_photo = true) is
--                           now refused.
--   * request_listing_edit() the edit of a PUBLISHED listing, submitted for approval,
--                           now refuses any photo (p_photo_url must be NULL), and the
--                           notice to staff names an "edited listing".
--   Everything else in the approval workflow is unchanged: the live listing is never
--   touched until a Manager / Officer approves; a disapproval needs a reason and
--   leaves the published listing as it is; stock, orders and history are as before.
--   Edit requests already stored (with no photo) are unaffected.
--
-- Run after: supabase_schema_listing_edit_approval.sql. If that file is ever re-run,
-- run this one again afterwards (it contains the final versions of these two
-- functions). Safe to re-run. Not applied automatically.
-- Then run supabase_schema_listing_edit_fields_test.sql.
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.request_listing_edit(uuid,numeric,numeric,text,text)') IS NULL
     OR to_regclass('public.listing_edit_requests') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_listing_edit_approval.sql first.';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_my_listing(
  p_listing_id    UUID,
  p_quantity      NUMERIC,
  p_price_per_kg  NUMERIC,
  p_description   TEXT,
  p_refresh_photo BOOLEAN DEFAULT FALSE
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_role    TEXT;
  v_status  TEXT;
  l         marketplace_listings%ROWTYPE;
  v_ordered NUMERIC;
  v_delta   NUMERIC;
  v_photo   TEXT;
  v_name    TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT role, status INTO v_role, v_status FROM user_roles WHERE user_id = v_uid;
  IF v_role IS DISTINCT FROM 'farmer' OR v_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Only an active Farmer account can edit a listing.';
  END IF;

  -- The listing photo is the Farmer's Crop Roster photo: it is not part of an edit.
  IF p_refresh_photo THEN
    RAISE EXCEPTION 'The listing photo is your Crop Roster photo and cannot be changed in an edit.';
  END IF;

  SELECT * INTO l FROM marketplace_listings
   WHERE id = p_listing_id AND farmer_id = v_uid
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF l.status = 'approved' THEN
    RAISE EXCEPTION 'An approved listing is changed by sending an edit request for approval.';
  END IF;
  IF l.status <> 'pending_review' THEN
    RAISE EXCEPTION 'This listing can no longer be edited.';
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Enter a quantity greater than zero.';
  END IF;
  IF p_quantity <> round(p_quantity, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the quantity.';
  END IF;
  IF p_quantity > 99999999.99 THEN
    RAISE EXCEPTION 'The quantity is too large.';
  END IF;
  IF p_price_per_kg IS NULL OR p_price_per_kg <= 0 THEN
    RAISE EXCEPTION 'Enter an asking price greater than zero.';
  END IF;
  IF p_price_per_kg <> round(p_price_per_kg, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the price.';
  END IF;
  IF p_price_per_kg > 99999999.99 THEN
    RAISE EXCEPTION 'The price is too large.';
  END IF;
  IF p_description IS NULL OR btrim(p_description) = '' THEN
    RAISE EXCEPTION 'A description is required for a listing.';
  END IF;

  v_ordered := l.volume_kg - l.remaining_kg;
  IF p_quantity <= v_ordered THEN
    RAISE EXCEPTION 'The quantity must be more than the % % already ordered.', v_ordered, l.unit;
  END IF;

  v_delta := p_quantity - l.volume_kg;
  IF v_delta <> 0 THEN
    IF l.inventory_batch_id IS NULL THEN
      RAISE EXCEPTION 'This listing is no longer linked to a harvest batch, so its quantity cannot be changed.';
    END IF;
    IF v_delta > 0 THEN
      PERFORM public._apply_batch_reservation(l.inventory_batch_id, v_delta);
    ELSE
      PERFORM public._release_batch_reservation(l.inventory_batch_id, -v_delta);
    END IF;
  END IF;

  IF p_refresh_photo THEN
    v_photo := public.farmer_crop_photo_for_batch(l.inventory_batch_id);
    IF v_photo IS NULL THEN
      RAISE EXCEPTION 'PHOTO_REQUIRED: Take a photo of your actual crop in Crop Roster before selling this batch.';
    END IF;
  END IF;

  UPDATE marketplace_listings
     SET volume_kg    = p_quantity,
         remaining_kg = l.remaining_kg + v_delta,
         price_per_kg = p_price_per_kg,
         description  = btrim(p_description),
         photo_url    = COALESCE(v_photo, l.photo_url)
   WHERE id = l.id;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_uid;
  PERFORM public.notify_staff(
    'listing',
    'Listing Updated',
    COALESCE(v_name, 'A farmer') || ' updated their ' || COALESCE(l.crop_name, 'produce') ||
      ' listing (pending approval): ' || p_quantity || ' ' || l.unit || ' at ' || p_price_per_kg || ' per ' || l.unit || '.',
    '/admin/marketplace/pending'
  );
END;
$$;
REVOKE ALL ON FUNCTION public.update_my_listing(UUID, NUMERIC, NUMERIC, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_my_listing(UUID, NUMERIC, NUMERIC, TEXT, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.request_listing_edit(
  p_listing_id   UUID,
  p_quantity     NUMERIC,
  p_price_per_kg NUMERIC,
  p_description  TEXT,
  p_photo_url    TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       UUID := auth.uid();
  v_role      TEXT;
  v_status    TEXT;
  l           marketplace_listings%ROWTYPE;
  v_ordered   NUMERIC;
  v_delta     NUMERIC;
  v_available NUMERIC;
  v_desc      TEXT := btrim(COALESCE(p_description, ''));
  v_photo     TEXT := NULLIF(btrim(COALESCE(p_photo_url, '')), '');
  v_id        UUID;
  v_name      TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT role, status INTO v_role, v_status FROM user_roles WHERE user_id = v_uid;
  IF v_role IS DISTINCT FROM 'farmer' OR v_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Only an active Farmer account can edit a listing.';
  END IF;

  SELECT * INTO l FROM marketplace_listings
   WHERE id = p_listing_id AND farmer_id = v_uid
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF l.status <> 'approved' THEN
    RAISE EXCEPTION 'Only an approved listing needs an edit request. A listing that is pending approval is edited directly.';
  END IF;
  IF l.remaining_kg <= 0 THEN
    RAISE EXCEPTION 'This listing is sold out and can no longer be edited.';
  END IF;
  IF EXISTS (SELECT 1 FROM listing_edit_requests WHERE listing_id = l.id AND status = 'pending') THEN
    RAISE EXCEPTION 'You already have an edit request waiting for approval on this listing.';
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Enter a quantity greater than zero.';
  END IF;
  IF p_quantity <> round(p_quantity, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the quantity.';
  END IF;
  IF p_quantity > 99999999.99 THEN
    RAISE EXCEPTION 'The quantity is too large.';
  END IF;
  IF p_price_per_kg IS NULL OR p_price_per_kg <= 0 THEN
    RAISE EXCEPTION 'Enter an asking price greater than zero.';
  END IF;
  IF p_price_per_kg <> round(p_price_per_kg, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the price.';
  END IF;
  IF p_price_per_kg > 99999999.99 THEN
    RAISE EXCEPTION 'The price is too large.';
  END IF;
  IF v_desc = '' THEN
    RAISE EXCEPTION 'A description is required for a listing.';
  END IF;

  -- The listing photo is the Farmer's Crop Roster photo: it is not part of an edit.
  IF v_photo IS NOT NULL THEN
    RAISE EXCEPTION 'The listing photo is your Crop Roster photo and cannot be changed in an edit.';
  END IF;

  v_ordered := l.volume_kg - l.remaining_kg;
  IF p_quantity <= v_ordered THEN
    RAISE EXCEPTION 'The quantity must be more than the % % already ordered.', v_ordered, l.unit;
  END IF;

  v_delta := p_quantity - l.volume_kg;
  IF v_delta <> 0 THEN
    IF l.inventory_batch_id IS NULL THEN
      RAISE EXCEPTION 'This listing is no longer linked to a harvest batch, so its quantity cannot be changed.';
    END IF;
    IF v_delta > 0 THEN
      -- An early answer only: nothing is reserved until the change is approved,
      -- and the approval checks the batch again.
      SELECT available_kg INTO v_available FROM inventory_batches WHERE id = l.inventory_batch_id;
      IF COALESCE(v_available, 0) < v_delta THEN
        RAISE EXCEPTION 'Not enough available quantity in this batch.';
      END IF;
    END IF;
  END IF;

  IF p_quantity = l.volume_kg AND p_price_per_kg = l.price_per_kg
     AND v_desc = btrim(COALESCE(l.description, '')) AND v_photo IS NULL THEN
    RAISE EXCEPTION 'You have not changed anything.';
  END IF;

  INSERT INTO listing_edit_requests (
    listing_id, farmer_id, unit,
    original_quantity, original_price, original_description, original_photo_url,
    proposed_quantity, proposed_price, proposed_description, proposed_photo_url
  ) VALUES (
    l.id, v_uid, l.unit,
    l.volume_kg, l.price_per_kg, l.description, l.photo_url,
    p_quantity, p_price_per_kg, v_desc, v_photo
  ) RETURNING id INTO v_id;

  PERFORM public._wf_log('listing', l.id, 'edit_requested', l.status, l.status, NULL,
    jsonb_build_object('request_id', v_id, 'unit', l.unit,
      'changes', jsonb_strip_nulls(jsonb_build_object(
        'quantity',    CASE WHEN p_quantity <> l.volume_kg THEN jsonb_build_object('from', l.volume_kg, 'to', p_quantity) END,
        'price',       CASE WHEN p_price_per_kg <> l.price_per_kg THEN jsonb_build_object('from', l.price_per_kg, 'to', p_price_per_kg) END,
        'description', CASE WHEN v_desc <> btrim(COALESCE(l.description, '')) THEN jsonb_build_object('from', l.description, 'to', v_desc) END,
        'photo',       CASE WHEN v_photo IS NOT NULL THEN TRUE END))));

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_uid;
  PERFORM public.notify_staff(
    'listing',
    'Edited Listing for Approval',
    COALESCE(v_name, 'A farmer') || ' edited their published ' || COALESCE(l.crop_name, 'produce') ||
      ' listing and submitted it for approval. The live listing stays as it is until you decide.',
    '/admin/marketplace/pending'
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.request_listing_edit(UUID, NUMERIC, NUMERIC, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_listing_edit(UUID, NUMERIC, NUMERIC, TEXT, TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY CHECK (read-only) ───────────────────────────────────────
-- Both functions now refuse a photo (expect 2 rows):
--   SELECT p.oid::regprocedure FROM pg_proc p
--   WHERE p.proname IN ('update_my_listing', 'request_listing_edit')
--     AND pg_get_functiondef(p.oid) LIKE '%cannot be changed in an edit%';
