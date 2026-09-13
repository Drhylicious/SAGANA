-- ============================================================
-- SAGANA — Remove Da-Amad Reference Market
-- (Admin Dashboard investigation, Issue 6 / Phase 6)
--
-- The 'da_amad_market' crop_type/price_type classification is being
-- removed from general Price/Crop Management. This does NOT touch
-- market_linking_screen.dart's "DA-AMAD Ginger Program" (institutional
-- export pricing that bypasses the open marketplace) — that's a fully
-- separate workflow with its own tables, unaffected by this migration.
-- Confirmed: da_amad_market was only ever assigned to Ginger's crop_master
-- row (see supabase_schema_crop_master_price_records_refactor.sql's
-- backfill), and is_cooperative_eligible (a generated column keyed only
-- off crop_type = 'sp3_cooperative') is unaffected by this reclassification
-- either way.
--
-- Data decision (per explicit approval):
--   - crop_master / crop_requests rows tagged da_amad_market are RECLASSIFIED
--     to open_market — the crop itself (Ginger) keeps existing and stays
--     listable; only its general-market classification changes.
--   - price_records rows tagged da_amad_market are DELETED outright — these
--     were historical DA-AMAD institutional price entries, a different
--     pricing concept than an open_market reference price, so relabeling
--     them would misrepresent what they were.
-- ============================================================

BEGIN;

UPDATE public.crop_master
  SET crop_type = 'open_market'
  WHERE crop_type = 'da_amad_market';

UPDATE public.crop_requests
  SET crop_type = 'open_market'
  WHERE crop_type = 'da_amad_market';

DELETE FROM public.price_records
  WHERE price_type = 'da_amad_market';

-- Narrow the three CHECK constraints to the remaining two values. Using
-- new, explicitly-named constraints rather than guessing the
-- auto-generated original constraint names — if an old 3-value constraint
-- happens to still be present under a different name, it becomes a
-- harmless no-op superset of the new, narrower one below.
ALTER TABLE public.crop_master
  DROP CONSTRAINT IF EXISTS crop_master_crop_type_check;
ALTER TABLE public.crop_master
  ADD CONSTRAINT crop_master_crop_type_check2
  CHECK (crop_type IN ('sp3_cooperative', 'open_market'));

ALTER TABLE public.crop_requests
  DROP CONSTRAINT IF EXISTS crop_requests_crop_type_check;
ALTER TABLE public.crop_requests
  ADD CONSTRAINT crop_requests_crop_type_check2
  CHECK (crop_type IN ('sp3_cooperative', 'open_market'));

ALTER TABLE public.price_records
  DROP CONSTRAINT IF EXISTS price_records_price_type_check;
ALTER TABLE public.price_records
  ADD CONSTRAINT price_records_price_type_check2
  CHECK (price_type IN ('sp3_cooperative', 'open_market'));

-- approve_crop_request(): drop da_amad_market from the inline validation.
-- Full function body re-supplied (CREATE OR REPLACE requires the whole
-- thing) — everything else identical to
-- supabase_schema_crop_master_price_records_refactor.sql's 3-arg version.
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

  IF p_crop_type IS NOT NULL AND p_crop_type NOT IN ('sp3_cooperative', 'open_market') THEN
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

GRANT EXECUTE ON FUNCTION approve_crop_request(UUID, TEXT, TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
