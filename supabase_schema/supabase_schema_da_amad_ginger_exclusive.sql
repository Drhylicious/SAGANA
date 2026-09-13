-- ============================================================
-- SAGANA — Reintroduce DA-AMAD Market, Exclusive to Ginger
-- (Admin Marketplace review, Crop Management phase)
--
-- supabase_schema_remove_da_amad.sql previously reclassified Ginger
-- (and every other da_amad_market row, though Ginger was the only one)
-- to open_market and narrowed crop_type/price_type to two values. That
-- removal overlooked that Ginger specifically needs to stay in its own
-- exclusive classification — it can only ever be sold through Market
-- Linking, never the general Marketplace, Offer to Cooperative, or an
-- informal sale. This migration reintroduces the third value, assigns
-- it to Ginger only, and is the one crop_type value the app now
-- restricts to a single crop (see crop_management_screen.dart).
--
-- Does NOT touch market_linking_programs or any Market Linking table —
-- that workflow never depended on crop_master.crop_type; it identified
-- Ginger growers via a crop_name substring match. This migration makes
-- that classification available so a future pass (see
-- market_linking_repository.dart) can use it instead, but does not
-- require it to.
-- ============================================================

BEGIN;

-- ─── Widen crop_type / price_type back to three values ─────────────────────
-- Same constraint-replacement pattern remove_da_amad.sql used — new,
-- explicitly-named constraints rather than guessing auto-generated names.

ALTER TABLE public.crop_master
  DROP CONSTRAINT IF EXISTS crop_master_crop_type_check2;
ALTER TABLE public.crop_master
  ADD CONSTRAINT crop_master_crop_type_check3
  CHECK (crop_type IN ('sp3_cooperative', 'da_amad_market', 'open_market'));

ALTER TABLE public.crop_requests
  DROP CONSTRAINT IF EXISTS crop_requests_crop_type_check2;
ALTER TABLE public.crop_requests
  ADD CONSTRAINT crop_requests_crop_type_check3
  CHECK (crop_type IN ('sp3_cooperative', 'da_amad_market', 'open_market'));

ALTER TABLE public.price_records
  DROP CONSTRAINT IF EXISTS price_records_price_type_check2;
ALTER TABLE public.price_records
  ADD CONSTRAINT price_records_price_type_check3
  CHECK (price_type IN ('sp3_cooperative', 'da_amad_market', 'open_market'));

-- ─── Ginger becomes DA-AMAD-exclusive ───────────────────────────────────────

UPDATE public.crop_master
  SET crop_type = 'da_amad_market'
  WHERE crop_name = 'Ginger';

-- ─── is_cooperative_eligible: redefine the generated expression ────────────
-- Previously `crop_type = 'sp3_cooperative'` — meaning only Cooperative
-- Market crops could be offered to the cooperative. Per the Admin
-- Marketplace review's decision, Offer to Cooperative should accept any
-- crop's market type EXCEPT Ginger's DA-AMAD-exclusive one. Since
-- crop_type only ever has these three values, "not da_amad_market" is
-- exactly that rule — Cooperative Market and Public Market crops both
-- become eligible, only Ginger is excluded. Being a GENERATED STORED
-- column, every existing row recomputes automatically; no manual UPDATE
-- needed on crop_master itself (inventory_batches.is_coop_eligible is a
-- separate, denormalized snapshot — backfilled in a companion migration).
-- IF EXISTS on the drop (matching the safety convention the original
-- crop_master_price_records_refactor.sql migration used) so this stays
-- safe to re-run if a prior attempt partially applied.
ALTER TABLE public.crop_master
  DROP COLUMN IF EXISTS is_cooperative_eligible;
ALTER TABLE public.crop_master
  ADD COLUMN IF NOT EXISTS is_cooperative_eligible BOOLEAN
  GENERATED ALWAYS AS (crop_type <> 'da_amad_market') STORED;

-- ─── approve_crop_request(): allow da_amad_market again ────────────────────
-- Full function body re-supplied (CREATE OR REPLACE requires the whole
-- thing) — identical to supabase_schema_remove_da_amad.sql's version
-- except the validation IN-list is widened back to three values. In
-- practice no new crop is expected to request this classification
-- (Ginger already exists) — this is restored purely for schema
-- consistency with the widened CHECK constraint above.
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

-- ─── Backfill inventory_batches.is_coop_eligible for existing batches ──────
-- This denormalized snapshot (set once per batch at harvest time, in
-- harvest_entry_repository.dart) is frozen at whatever crop_master said
-- when the batch was created. Existing non-Ginger batches harvested
-- before this migration were likely stamped `false` under the old
-- sp3_cooperative-only rule — sync them to the now-current, correct
-- value via the same farmer_crops -> crop_master resolution path the
-- Dart code uses. Ginger batches correctly stay/become `false`.
UPDATE public.inventory_batches ib
SET is_coop_eligible = cm.is_cooperative_eligible
FROM public.farmer_crops fc
JOIN public.crop_master cm ON cm.id = fc.crop_master_id
WHERE ib.crop_id = fc.id
  AND ib.is_coop_eligible IS DISTINCT FROM cm.is_cooperative_eligible;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) Ginger reclassified:
--    SELECT crop_name, crop_type, is_cooperative_eligible FROM crop_master
--    WHERE crop_name ILIKE '%ginger%';
--    -- expect crop_type = 'da_amad_market', is_cooperative_eligible = false
--
-- 2) Everything else eligible:
--    SELECT crop_name, crop_type, is_cooperative_eligible FROM crop_master
--    WHERE crop_name NOT ILIKE '%ginger%' AND is_active = true;
--    -- expect is_cooperative_eligible = true for all rows
--
-- 3) Existing batches backfilled:
--    SELECT crop_name, is_coop_eligible FROM inventory_batches
--    WHERE crop_name NOT ILIKE '%ginger%';
--    -- expect is_coop_eligible = true for all rows
