-- ============================================================
-- SAGANA — Crop Type Classification + Price Records Crop Normalization
--
-- Item 1: crop_master + crop_requests get crop_type as the single source
--         of truth for a crop's business classification.
--         is_cooperative_eligible becomes a generated column derived from
--         it, so existing readers (offer_batch_to_cooperative, the
--         inventory_batches denormalization) never need to change.
--
-- Item 3: price_records gets a real crop_id FK. crop_name stays as a
--         denormalized snapshot for historical accuracy — never rewritten
--         after insert.
-- ============================================================

-- ─── crop_master ────────────────────────────────────────────────────────────

ALTER TABLE public.crop_master
  ADD COLUMN IF NOT EXISTS crop_type TEXT
  CHECK (crop_type IN ('sp3_cooperative', 'da_amad_market', 'open_market'));

-- Backfill from existing data: coop-eligible crops are sp3_cooperative;
-- Ginger is the only DA-AMAD crop today; everything else is open_market.
UPDATE public.crop_master
SET crop_type = CASE
  WHEN is_cooperative_eligible = TRUE THEN 'sp3_cooperative'
  WHEN crop_name = 'Ginger' THEN 'da_amad_market'
  ELSE 'open_market'
END
WHERE crop_type IS NULL;

ALTER TABLE public.crop_master
  ALTER COLUMN crop_type SET NOT NULL,
  ALTER COLUMN crop_type SET DEFAULT 'open_market';

-- is_cooperative_eligible is now derived — drop the plain column and
-- replace it with a generated one so it can never drift from crop_type.
-- IF EXISTS / IF NOT EXISTS make this safe to re-run even if a prior
-- partial run already got this far.
ALTER TABLE public.crop_master
  DROP COLUMN IF EXISTS is_cooperative_eligible;

ALTER TABLE public.crop_master
  ADD COLUMN IF NOT EXISTS is_cooperative_eligible BOOLEAN
  GENERATED ALWAYS AS (crop_type = 'sp3_cooperative') STORED;

-- ─── crop_requests ──────────────────────────────────────────────────────────
-- Mirrors the existing nullable `category` column: farmer suggests it,
-- admin can confirm or override before approval.

ALTER TABLE public.crop_requests
  ADD COLUMN IF NOT EXISTS crop_type TEXT
  CHECK (crop_type IN ('sp3_cooperative', 'da_amad_market', 'open_market'));

-- ─── approve_crop_request(): pass crop_type through to new crop_master rows ──
-- Same structure as before, with one new optional param (p_crop_type) that
-- lets the admin override the farmer's suggested type at approval time,
-- exactly like p_admin_notes already does for notes.
--
-- Adding a parameter changes the function's signature, so Postgres treats
-- CREATE OR REPLACE as a new overload rather than a replacement — the old
-- 2-arg version would stay behind and make any unqualified reference to
-- approve_crop_request (e.g. a plain GRANT) ambiguous. Drop it explicitly
-- first so only the 3-arg version exists afterward.

DROP FUNCTION IF EXISTS public.approve_crop_request(UUID, TEXT);

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

-- ─── price_records ──────────────────────────────────────────────────────────

ALTER TABLE public.price_records
  ADD COLUMN IF NOT EXISTS crop_id UUID REFERENCES public.crop_master(id);

-- Best-effort backfill by name match. Left nullable on purpose — a
-- migration failure can't happen this way, but it means some historical
-- rows may not match. See the check query below.
UPDATE public.price_records pr
SET crop_id = cm.id
FROM public.crop_master cm
WHERE pr.crop_id IS NULL
  AND lower(pr.crop_name) = lower(cm.crop_name);

CREATE INDEX IF NOT EXISTS idx_price_records_crop_id_type_recorded
  ON public.price_records (crop_id, price_type, recorded_at DESC);

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- Post-migration check — run this separately after the above.
-- Anything returned here is a historical price entry whose crop_name
-- didn't match anything currently in crop_master; worth a manual look
-- before relying on crop_id everywhere.
-- ============================================================
-- SELECT id, crop_name, recorded_at FROM public.price_records WHERE crop_id IS NULL;