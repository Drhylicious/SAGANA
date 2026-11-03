-- ============================================================
-- SAGANA — Farmer can edit their own Marketplace listing (pending OR approved)
--
-- WHAT THIS ADDS
--   public.update_my_listing(listing, quantity, price, description, refresh_photo)
--
-- WHO / WHEN
--   * Only the Farmer who owns the listing, and only while the Farmer account is
--     active.
--   * Only a listing that is Pending Approval, or Approved with quantity still
--     left (Available). A Sold Out, Disapproved or Withdrawn listing is final.
--   * Withdrawing is NOT changed: withdraw_listing() still accepts Pending
--     Approval only. An edit cannot be used to close a listing either: the new
--     quantity must stay ABOVE what is already ordered.
--
-- WHAT CAN CHANGE            WHAT CANNOT
--   quantity (decimals)        the crop / product name and crop identity
--   asking price (decimals)    the unit (it stays the harvest batch's unit)
--   description                the batch, the status, the approval
--   product photo (see below)
--
-- STOCK (the existing reservation model, unchanged)
--   The whole listed quantity is reserved against the batch when the listing is
--   created, and every order only draws down the listing's remaining_kg. So:
--     * raising the quantity reserves the EXTRA from the batch through
--       _apply_batch_reservation() (refused when the batch does not have it);
--     * lowering it gives the difference back through _release_batch_reservation();
--     * remaining_kg moves by the same difference, so what is already ordered
--       (volume_kg - remaining_kg) never changes.
--   Orders keep their own quantity and price (orders.quantity_kg / price_per_kg /
--   total_price are copied at order time), so an edit never touches them.
--   The row is locked FOR UPDATE, the same lock place_order() takes, so an edit
--   and an order cannot overlap.
--
-- PHOTO
--   A listing always shows the Farmer's own camera photo of the crop (Crop
--   Roster is its one source). The app retakes that photo first, then asks for
--   p_refresh_photo = true; the database copies the crop's CURRENT photo onto the
--   listing. A client can never send an arbitrary photo address.
--
-- APPROVAL
--   NO new re-approval step is introduced: an approved listing stays approved
--   after an edit. Manager and Officer are told through a notification instead.
--   (If the cooperative wants edits re-approved, that is a policy decision to be
--   made first: it is listed as pending in the report.)
--
-- SUPERSEDED for APPROVED listings by supabase_schema_listing_edit_approval.sql:
-- after that script runs, a change to an approved listing is an edit REQUEST that a
-- Manager / Officer must approve, and update_my_listing() only edits a listing that
-- is still Pending Approval. If this file is ever re-run, run the approval script
-- again afterwards.
--
-- Run after: supabase_schema_farmer_stock_management.sql (and the files it
-- names). Safe to re-run. Not applied automatically.
-- Then run supabase_schema_farmer_listing_edit_test.sql.
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public._apply_batch_reservation(uuid,numeric)') IS NULL
     OR to_regprocedure('public._release_batch_reservation(uuid,numeric)') IS NULL THEN
    RAISE EXCEPTION 'The batch reservation helpers are missing. Run the earlier marketplace scripts first.';
  END IF;
  IF to_regprocedure('public.notify_staff(text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'notify_staff() is missing. Run supabase_schema_phase2_notification_completeness.sql first.';
  END IF;
  IF to_regprocedure('public.farmer_crop_photo_for_batch(uuid)') IS NULL THEN
    RAISE EXCEPTION 'farmer_crop_photo_for_batch() is missing. Run supabase_schema_crop_photos_selling_rules.sql first.';
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

  -- The same row lock place_order() takes: an edit and an order never overlap.
  SELECT * INTO l FROM marketplace_listings
   WHERE id = p_listing_id AND farmer_id = v_uid
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF l.status NOT IN ('pending_review', 'approved') THEN
    RAISE EXCEPTION 'This listing can no longer be edited.';
  END IF;
  IF l.status = 'approved' AND l.remaining_kg <= 0 THEN
    RAISE EXCEPTION 'This listing is sold out and can no longer be edited.';
  END IF;

  -- Validation (the database is the authority; the app checks the same things).
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

  -- What buyers have already ordered stays untouched, and the listing must keep
  -- something to sell: an edit is not a way to close a listing.
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
      -- Reserves the extra from the batch; refuses with "Not enough available
      -- quantity in this batch." when it is not there, and checks the owner.
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
      ' listing (' || CASE WHEN l.status = 'approved' THEN 'approved' ELSE 'pending approval' END ||
      '): ' || p_quantity || ' ' || l.unit || ' at ' || p_price_per_kg || ' per ' || l.unit || '.',
    '/admin/marketplace'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.update_my_listing(UUID, NUMERIC, NUMERIC, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_my_listing(UUID, NUMERIC, NUMERIC, TEXT, BOOLEAN) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY CHECK (read-only) ───────────────────────────────────────
-- Expect exactly 1 row, authenticated can execute, anon cannot:
--   SELECT p.oid::regprocedure,
--          has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can,
--          has_function_privilege('anon', p.oid, 'EXECUTE')          AS anon_can
--   FROM pg_proc p WHERE p.proname = 'update_my_listing';
