-- ============================================================
-- SAGANA — DA-AMAD Ginger Market Linking: Enrollment
-- (Market Linking revision round — real enrollment, distinct from
-- individual harvest submissions)
--
-- Until now, market_linking_programs conflated two different things into
-- one row: "is this farmer participating in the DA-AMAD program" and
-- "this specific harvest's sale record." There was no way to ask "is
-- this farmer enrolled" independent of whether they currently have a
-- harvest in the pipeline. This adds a dedicated enrollment record,
-- mirroring crop_requests' own pending/approved/rejected shape (the
-- closest existing precedent in this schema) rather than inventing a new
-- pattern.
--
-- Once approved here, a farmer's Ginger harvest submissions go straight
-- to market_linking_programs at status='submitted' — the previous
-- per-harvest 'requested' -> Approve/Decline gate on individual
-- submissions is now redundant (a farmer already vetted through
-- Enrollment shouldn't be re-vetted on every single harvest) and is
-- retired by this migration's companion Dart changes. The 'requested'
-- status value and respond_to_market_linking_request() RPC are left in
-- the database, unreferenced — same precedent as every other retired
-- code path in this project (e.g. delete_inventory_batch RPC).
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.da_amad_enrollments (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  farmer_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status        TEXT        NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_notes   TEXT,
  reviewed_by   UUID        REFERENCES auth.users(id),
  submitted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_da_amad_enrollments_farmer
  ON public.da_amad_enrollments (farmer_id, submitted_at DESC);

CREATE INDEX IF NOT EXISTS idx_da_amad_enrollments_status
  ON public.da_amad_enrollments (status, submitted_at DESC);

ALTER TABLE public.da_amad_enrollments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "da_amad_enrollments: farmer reads own"
  ON public.da_amad_enrollments FOR SELECT
  USING (auth.uid() = farmer_id);

CREATE POLICY "da_amad_enrollments: admin manages all"
  ON public.da_amad_enrollments FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.admin_profiles ap WHERE ap.user_id = auth.uid())
  );

-- No plain farmer INSERT policy — submission goes through
-- submit_da_amad_enrollment() below (SECURITY DEFINER), which enforces
-- the Ginger-crop and no-duplicate-active-enrollment checks server-side,
-- not just in the Flutter UI.

-- ─── Farmer submits (or resubmits after rejection) ─────────────────────────

CREATE OR REPLACE FUNCTION submit_da_amad_enrollment()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer_id UUID := auth.uid();
  v_has_ginger BOOLEAN;
  v_new_id UUID;
BEGIN
  IF EXISTS (
    SELECT 1 FROM da_amad_enrollments
    WHERE farmer_id = v_farmer_id AND status IN ('pending', 'approved')
  ) THEN
    RAISE EXCEPTION 'You already have a pending or approved enrollment';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM farmer_crops fc
    JOIN crop_master cm ON cm.id = fc.crop_master_id
    WHERE fc.farmer_id = v_farmer_id AND cm.crop_type = 'da_amad_market'
  ) INTO v_has_ginger;

  IF NOT v_has_ginger THEN
    RAISE EXCEPTION 'A Ginger crop in your Crop Roster is required to enroll';
  END IF;

  INSERT INTO da_amad_enrollments (farmer_id, status, submitted_at)
  VALUES (v_farmer_id, 'pending', NOW())
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION submit_da_amad_enrollment() TO authenticated;

-- ─── Admin approves or rejects ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION respond_to_da_amad_enrollment(
  p_enrollment_id UUID,
  p_approve BOOLEAN,
  p_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer_id UUID;
  v_status TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can review enrollments';
  END IF;

  SELECT farmer_id, status INTO v_farmer_id, v_status
  FROM da_amad_enrollments WHERE id = p_enrollment_id FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Enrollment not found';
  END IF;
  IF v_status != 'pending' THEN
    RAISE EXCEPTION 'Enrollment already reviewed (status: %)', v_status;
  END IF;

  UPDATE da_amad_enrollments
  SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
      reviewed_by = auth.uid(),
      reviewed_at = NOW(),
      admin_notes = p_notes
  WHERE id = p_enrollment_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id,
    'system',
    CASE WHEN p_approve THEN 'Market Linking Enrollment Approved' ELSE 'Market Linking Enrollment Declined' END,
    CASE WHEN p_approve
      THEN 'You can now submit your Ginger harvest for sale through Market Linking.'
      ELSE COALESCE('Your enrollment was declined: ' || p_notes, 'Your enrollment was declined. You may submit a new request.')
    END,
    FALSE,
    NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION respond_to_da_amad_enrollment(UUID, BOOLEAN, TEXT) TO authenticated;

-- ─── Farmer submits a Ginger harvest for sale (approved enrollees only) ────
-- The existing "Farmers request own market linking enrollment" RLS INSERT
-- policy (supabase_schema_market_linking_farmer_requests.sql) only ever
-- allows a farmer to insert at status='requested' — by design, a farmer
-- could never insert directly into 'submitted'. That's exactly right for
-- an un-enrolled farmer, but now that Enrollment is its own approval gate,
-- an already-approved farmer submitting a harvest shouldn't need a SECOND
-- per-harvest approval. This RPC is the one narrow exception: it inserts
-- directly at 'submitted', but only after verifying the caller currently
-- holds an approved enrollment and the batch is really theirs — the exact
-- checks the RLS policy would have done, just for a different outcome
-- status. The RLS policy itself is untouched, so the old 'requested' path
-- (now unused by the app) still can't be bypassed any other way.
CREATE OR REPLACE FUNCTION submit_ginger_for_sale(
  p_inventory_batch_id UUID,
  p_volume_kg NUMERIC
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer_id UUID := auth.uid();
  v_new_id UUID;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM da_amad_enrollments
    WHERE farmer_id = v_farmer_id AND status = 'approved'
  ) THEN
    RAISE EXCEPTION 'An approved Market Linking enrollment is required to submit a Ginger harvest';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM inventory_batches
    WHERE id = p_inventory_batch_id AND farmer_id = v_farmer_id
  ) THEN
    RAISE EXCEPTION 'That batch does not belong to you';
  END IF;

  INSERT INTO market_linking_programs (
    farmer_id, crop_name, season_year, status, created_by,
    inventory_batch_id, volume_kg, submitted_at
  )
  VALUES (
    v_farmer_id, 'Ginger', EXTRACT(YEAR FROM NOW())::INT, 'submitted', v_farmer_id,
    p_inventory_batch_id, p_volume_kg, NOW()
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION submit_ginger_for_sale(UUID, NUMERIC) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) As a farmer session with NO Ginger crop: SELECT submit_da_amad_enrollment();
--    -- expect an error: "A Ginger crop in your Crop Roster is required to enroll"
--
-- 2) As a farmer session WITH a Ginger crop: SELECT submit_da_amad_enrollment();
--    -- expect success, one new row with status='pending'
--    SELECT * FROM da_amad_enrollments WHERE farmer_id = auth.uid();
--
-- 3) Same farmer session again: SELECT submit_da_amad_enrollment();
--    -- expect an error: "You already have a pending or approved enrollment"
--
-- 4) As an admin session: SELECT respond_to_da_amad_enrollment('<id from step 2>', true, NULL);
--    -- expect success; row's status becomes 'approved'; a notification
--    -- row appears for that farmer_id
--
-- 5) As that now-approved farmer, with a real Ginger inventory batch id:
--    SELECT submit_ginger_for_sale('<inventory_batch_id>', 20);
--    -- expect success; a new market_linking_programs row appears with
--    -- status='submitted' (not 'requested')
--
-- 6) As a DIFFERENT farmer with no approved enrollment:
--    SELECT submit_ginger_for_sale('<any batch id>', 20);
--    -- expect an error: "An approved Market Linking enrollment is
--    -- required to submit a Ginger harvest"
