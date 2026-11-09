-- ============================================================
-- SAGANA — Program Management p20: crop-linked items, "Farmer returns" setting,
--          automatic Crop Roster + Harvest records on a Successful outcome
--
-- FOR YOUR REVIEW — NOT APPLIED. Run once in the Supabase SQL editor (after p15 and p17),
-- then the CHECKS at the bottom. One transaction, safe to re-run.
--
-- WHAT THIS ADDS (nothing is deleted; existing rows keep their values)
--   1. cooperative_inventory.crop_master_id + item_form
--        Which crop an item is, and whether it is PLANTING MATERIAL (seeds, seedlings: it grows
--        the crop) or HARVESTED STOCK (already harvested produce). Both empty = not a crop item
--        (tools, feeds, animals...). Farmer-delivered "Harvest Stock" items are filled in by
--        themselves (backfill + trigger) from the crop they came from.
--   2. cooperative_programs.return_basis ('harvested_produce' | 'same_item')
--        What a Harvest Return Farmer gives back. Chosen at creation, then locked (like Benefit
--        Type). Existing programs become 'same_item', which is exactly how they work today.
--        A 'harvested_produce' program can only distribute planting material (checked at
--        distribution, by a trigger, so distribute_program_benefit() itself is not rewritten).
--   3. Successful outcome -> the Farmer's records (finalize_program_outcome):
--        a. Crop Roster: the Farmer's crop for the item's crop is reused (never duplicated), or
--           created from the cooperative's own crop catalog entry when missing (no Crop Request:
--           the Manager already approved that crop).
--        b. Harvest record + inventory batch (Harvest ID issued by the existing trigger) for what the
--           Farmer KEEPS: planting material -> verified harvest minus the produce returned;
--           harvested stock -> quantity given minus any same-item return. It is marked with its
--           source (program_harvest / program_stock), the program and the member.
--        c. Duplicate safeguards: one program record per member (unique index); a possible
--           duplicate of a harvest the Farmer entered themselves is flagged, never silently
--           dropped; source fields cannot be set or changed by a Farmer.
--   4. Harvest Return, produce basis: the return is opened for the crop (unit = the verified
--      harvest unit, quantity <= the verified quantity) and each receipt is credited to Harvest Stock
--      by the existing record_program_return_receipt(), unchanged.
--   5. Non-crop items: a Successful report needs only the explanation and photos (no planting date,
--      harvest date or harvested quantity), and the field verification needs no measured quantity.
--   6. The three old money / loan-convert / thriving functions are no longer callable by the app
--      (they conflict with the locked rules: produce return, no automatic loan).
--
-- NOT CHANGED: distribute_program_benefit (stock still deducts once, atomically), record_program_return_receipt,
-- the review / verification stages, Failed outcomes, order and Marketplace tables.
-- Needs: p3, p6, p9, p13, p15, p17, crop_master, farmer_crops, harvest_records, units.
-- New error codes: RETURN_BASIS (and the existing RETURN_ITEM / RETURN_UNIT / RETURN_QUANTITY).
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.program_returns') IS NULL
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_name = 'program_returns' AND column_name = 'inventory_item_id') THEN
    RAISE EXCEPTION 'Apply p15 first (program_returns.inventory_item_id is missing).';
  END IF;
  IF to_regprocedure('public.finalize_program_outcome(uuid,text,text,numeric,text,text,text)') IS NULL
     OR to_regprocedure('public.verify_program_outcome(uuid,text,numeric,text,date,text,text[])') IS NULL
     OR to_regprocedure('public.submit_program_outcome_report(uuid,text,text,date,date,numeric,text,numeric,text,text,date,text[])') IS NULL THEN
    RAISE EXCEPTION 'Apply p9 / p13 / p15 first.';
  END IF;
  IF to_regclass('public.crop_master') IS NULL OR to_regclass('public.farmer_crops') IS NULL
     OR to_regclass('public.harvest_records') IS NULL OR to_regclass('public.inventory_batches') IS NULL THEN
    RAISE EXCEPTION 'The crop / harvest tables are missing.';
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- 1. Inventory items know their crop
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.cooperative_inventory
  ADD COLUMN IF NOT EXISTS crop_master_id UUID REFERENCES public.crop_master(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS item_form      TEXT;

ALTER TABLE public.cooperative_inventory DROP CONSTRAINT IF EXISTS cooperative_inventory_item_form_chk;
ALTER TABLE public.cooperative_inventory
  ADD CONSTRAINT cooperative_inventory_item_form_chk
  CHECK (item_form IS NULL OR item_form IN ('planting_material', 'harvested_stock'));

-- Backfill BEFORE the pairing rule: Farmer-delivered Harvest Stock is harvested stock of its crop.
UPDATE public.cooperative_inventory ci
   SET crop_master_id = fc.crop_master_id,
       item_form      = 'harvested_stock'
  FROM public.farmer_crops fc
 WHERE ci.source_crop_id = fc.id
   AND fc.crop_master_id IS NOT NULL
   AND ci.crop_master_id IS NULL
   AND ci.item_form IS NULL;

ALTER TABLE public.cooperative_inventory DROP CONSTRAINT IF EXISTS cooperative_inventory_crop_form_chk;
ALTER TABLE public.cooperative_inventory
  ADD CONSTRAINT cooperative_inventory_crop_form_chk
  CHECK ((crop_master_id IS NULL) = (item_form IS NULL));

-- A Farmer's delivery creates the Harvest Stock item itself: link it to the crop on the way in.
CREATE OR REPLACE FUNCTION public._inventory_link_harvest_stock_crop()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.crop_master_id IS NULL AND NEW.source_crop_id IS NOT NULL THEN
    SELECT fc.crop_master_id INTO NEW.crop_master_id FROM farmer_crops fc WHERE fc.id = NEW.source_crop_id;
    NEW.item_form := CASE WHEN NEW.crop_master_id IS NULL THEN NULL ELSE 'harvested_stock' END;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_inventory_link_harvest_stock_crop ON public.cooperative_inventory;
CREATE TRIGGER trg_inventory_link_harvest_stock_crop
  BEFORE INSERT ON public.cooperative_inventory
  FOR EACH ROW EXECUTE FUNCTION public._inventory_link_harvest_stock_crop();

-- ════════════════════════════════════════════════════════════
-- 2. "The Farmer returns": harvested produce or the same item
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.cooperative_programs
  ADD COLUMN IF NOT EXISTS return_basis TEXT NOT NULL DEFAULT 'same_item';
ALTER TABLE public.cooperative_programs DROP CONSTRAINT IF EXISTS cooperative_programs_return_basis_chk;
ALTER TABLE public.cooperative_programs
  ADD CONSTRAINT cooperative_programs_return_basis_chk
  CHECK (return_basis IN ('harvested_produce', 'same_item'));

CREATE OR REPLACE FUNCTION public.lock_program_return_basis()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.return_basis IS DISTINCT FROM OLD.return_basis AND auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'BENEFIT_TYPE_LOCKED: What the Farmer returns cannot be changed after the program is created. Members, outcomes and returns depend on it.';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_lock_program_return_basis ON public.cooperative_programs;
CREATE TRIGGER trg_lock_program_return_basis
  BEFORE UPDATE OF return_basis ON public.cooperative_programs
  FOR EACH ROW EXECUTE FUNCTION public.lock_program_return_basis();

-- A produce-return program gives out planting material only. Checked at the moment of distribution.
CREATE OR REPLACE FUNCTION public._program_members_check_return_basis()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_p   cooperative_programs%ROWTYPE;
  v_inv cooperative_inventory%ROWTYPE;
BEGIN
  IF NEW.distributed_at IS NOT NULL AND OLD.distributed_at IS NULL AND NEW.inventory_item_id IS NOT NULL THEN
    SELECT * INTO v_p FROM cooperative_programs WHERE id = NEW.program_id;
    IF v_p.benefit_type = 'revenue_share' AND v_p.return_basis = 'harvested_produce' THEN
      SELECT * INTO v_inv FROM cooperative_inventory WHERE id = NEW.inventory_item_id;
      IF v_inv.item_form IS DISTINCT FROM 'planting_material' THEN
        RAISE EXCEPTION 'RETURN_BASIS: This program asks the Farmer to return harvested produce, so only seeds or seedlings linked to a crop can be given. Link the item to a crop in Inventory, or choose another item.';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_program_members_check_return_basis ON public.program_members;
CREATE TRIGGER trg_program_members_check_return_basis
  BEFORE UPDATE OF distributed_at, inventory_item_id ON public.program_members
  FOR EACH ROW EXECUTE FUNCTION public._program_members_check_return_basis();

-- ════════════════════════════════════════════════════════════
-- 3. Where a record came from (traceability) + duplicate safeguards
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.harvest_records
  ADD COLUMN IF NOT EXISTS source_type              TEXT NOT NULL DEFAULT 'self',
  ADD COLUMN IF NOT EXISTS source_program_id        UUID REFERENCES public.cooperative_programs(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS source_program_member_id UUID REFERENCES public.program_members(id)      ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS possible_duplicate_of    UUID REFERENCES public.harvest_records(id)      ON DELETE SET NULL;
ALTER TABLE public.harvest_records DROP CONSTRAINT IF EXISTS harvest_records_source_type_chk;
ALTER TABLE public.harvest_records
  ADD CONSTRAINT harvest_records_source_type_chk
  CHECK (source_type IN ('self', 'program_harvest', 'program_stock'));

-- One program record per member, ever: a second finalize / replay cannot add another.
CREATE UNIQUE INDEX IF NOT EXISTS uq_harvest_records_program_member
  ON public.harvest_records (source_program_member_id)
  WHERE source_program_member_id IS NOT NULL;

ALTER TABLE public.farmer_crops
  ADD COLUMN IF NOT EXISTS source_program_id UUID REFERENCES public.cooperative_programs(id) ON DELETE SET NULL;

-- Only the program workflow may write the source fields (a Farmer cannot claim or change them).
CREATE OR REPLACE FUNCTION public._harvest_records_source_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF COALESCE(current_setting('sagana.program_registration', true), '') = 'on' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.source_type <> 'self' OR NEW.source_program_id IS NOT NULL
       OR NEW.source_program_member_id IS NOT NULL OR NEW.possible_duplicate_of IS NOT NULL THEN
      RAISE EXCEPTION 'A harvest record can only be marked as coming from a program by the program workflow.';
    END IF;
  ELSE
    IF NEW.source_type IS DISTINCT FROM OLD.source_type
       OR NEW.source_program_id IS DISTINCT FROM OLD.source_program_id
       OR NEW.source_program_member_id IS DISTINCT FROM OLD.source_program_member_id
       OR NEW.possible_duplicate_of IS DISTINCT FROM OLD.possible_duplicate_of THEN
      RAISE EXCEPTION 'Where a harvest record came from cannot be changed.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_harvest_records_source_guard_ins ON public.harvest_records;
CREATE TRIGGER trg_harvest_records_source_guard_ins
  BEFORE INSERT ON public.harvest_records
  FOR EACH ROW EXECUTE FUNCTION public._harvest_records_source_guard();
DROP TRIGGER IF EXISTS trg_harvest_records_source_guard_upd ON public.harvest_records;
CREATE TRIGGER trg_harvest_records_source_guard_upd
  BEFORE UPDATE OF source_type, source_program_id, source_program_member_id, possible_duplicate_of ON public.harvest_records
  FOR EACH ROW EXECUTE FUNCTION public._harvest_records_source_guard();

-- ════════════════════════════════════════════════════════════
-- 4. Helpers
-- ════════════════════════════════════════════════════════════
-- Does the item this member received grow a crop (planting material)? An old distribution with
-- no item on record keeps the old behaviour (it asked for harvest data).
CREATE OR REPLACE FUNCTION public._program_item_grows_crop(p_member_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE WHEN pm.inventory_item_id IS NULL THEN TRUE
              ELSE COALESCE(ci.item_form = 'planting_material', FALSE) END
    FROM program_members pm
    LEFT JOIN cooperative_inventory ci ON ci.id = pm.inventory_item_id
   WHERE pm.id = p_member_id;
$$;
REVOKE ALL ON FUNCTION public._program_item_grows_crop(UUID) FROM PUBLIC, anon, authenticated;

-- The Farmer's crop for the item's crop: reused when it exists, created when it does not.
-- Returns NULL when the item is not linked to a crop.
CREATE OR REPLACE FUNCTION public._program_ensure_farmer_crop(p_report_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_r    program_outcome_reports%ROWTYPE;
  v_inv  cooperative_inventory%ROWTYPE;
  v_cm   crop_master%ROWTYPE;
  v_crop UUID;
BEGIN
  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id;
  SELECT ci.* INTO v_inv
    FROM program_members pm JOIN cooperative_inventory ci ON ci.id = pm.inventory_item_id
   WHERE pm.id = v_r.program_member_id;
  IF NOT FOUND OR v_inv.crop_master_id IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v_cm FROM crop_master WHERE id = v_inv.crop_master_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  -- 1. The Farmer already has this crop (same catalog crop): reuse it, never add another.
  SELECT id INTO v_crop FROM farmer_crops
   WHERE farmer_id = v_r.farmer_id AND crop_master_id = v_cm.id
   ORDER BY created_at LIMIT 1;
  IF FOUND THEN RETURN v_crop; END IF;

  -- 2. The Farmer has a crop of the same name that is not linked to the catalog yet (a pending
  --    request): the cooperative's own catalog entry settles it, so link it instead of adding one.
  SELECT id INTO v_crop FROM farmer_crops
   WHERE farmer_id = v_r.farmer_id AND lower(btrim(crop_name)) = lower(btrim(v_cm.crop_name))
   ORDER BY created_at LIMIT 1;
  IF FOUND THEN
    UPDATE farmer_crops SET crop_master_id = v_cm.id WHERE id = v_crop AND crop_master_id IS NULL;
    RETURN v_crop;
  END IF;

  -- 3. No such crop: create it from the catalog entry (already approved by the Manager).
  INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id, source_program_id)
  VALUES (v_r.farmer_id, v_cm.crop_name, v_cm.category, v_cm.id, v_r.program_id)
  RETURNING id INTO v_crop;
  RETURN v_crop;
END;
$$;
REVOKE ALL ON FUNCTION public._program_ensure_farmer_crop(UUID) FROM PUBLIC, anon, authenticated;

-- The Harvest record + inventory batch for what the Farmer keeps. Returns the harvest id (or NULL).
CREATE OR REPLACE FUNCTION public._program_register_harvest(p_report_id UUID, p_return_qty NUMERIC)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_r     program_outcome_reports%ROWTYPE;
  v_m     program_members%ROWTYPE;
  v_p     cooperative_programs%ROWTYPE;
  v_inv   cooperative_inventory%ROWTYPE;
  v_cm    crop_master%ROWTYPE;
  v_crop  farmer_crops%ROWTYPE;
  v_crop_id UUID;
  v_total NUMERIC;
  v_ret   NUMERIC := 0;
  v_keep  NUMERIC;
  v_unit  TEXT;
  v_date  DATE;
  v_type  TEXT;
  v_dup   UUID;
  v_h     UUID;
  v_batch TEXT;
  v_extra TEXT := '';
BEGIN
  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id;
  SELECT * INTO v_m FROM program_members          WHERE id = v_r.program_member_id;
  SELECT * INTO v_p FROM cooperative_programs     WHERE id = v_r.program_id;
  SELECT * INTO v_inv FROM cooperative_inventory  WHERE id = v_m.inventory_item_id;
  IF NOT FOUND OR v_inv.crop_master_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_cm FROM crop_master WHERE id = v_inv.crop_master_id;

  -- Already registered for this member: nothing more (idempotent).
  IF EXISTS (SELECT 1 FROM harvest_records WHERE source_program_member_id = v_m.id) THEN
    RETURN NULL;
  END IF;

  v_crop_id := public._program_ensure_farmer_crop(p_report_id);
  IF v_crop_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_crop FROM farmer_crops WHERE id = v_crop_id;

  IF v_inv.item_form = 'planting_material' THEN
    -- Seeds / seedlings: what was harvested (the verified measurement wins), less the produce returned.
    v_total := COALESCE(v_r.verified_quantity, v_r.quantity_harvested);
    v_unit  := lower(btrim(COALESCE(NULLIF(btrim(v_r.verified_unit), ''), v_r.quantity_unit)));
    v_date  := COALESCE(v_r.harvest_date, (NOW() AT TIME ZONE 'Asia/Manila')::DATE);
    v_type  := 'program_harvest';
    IF v_p.benefit_type = 'revenue_share' AND v_p.return_basis = 'harvested_produce' THEN
      v_ret := COALESCE(p_return_qty, 0);
    END IF;
  ELSE
    -- Already-harvested stock given to the Farmer: it is theirs, less anything returned as the same item.
    v_total := v_m.quantity_given;
    v_unit  := lower(btrim(v_inv.unit));
    v_date  := (COALESCE(v_m.distributed_at, NOW()) AT TIME ZONE 'Asia/Manila')::DATE;
    v_type  := 'program_stock';
    IF v_p.benefit_type = 'revenue_share' AND v_p.return_basis = 'same_item' THEN
      v_ret := COALESCE(p_return_qty, 0);
    END IF;
  END IF;

  v_keep := round(COALESCE(v_total, 0) - v_ret, 2);
  IF v_keep <= 0 OR v_unit IS NULL OR v_unit = '' THEN
    RETURN NULL;
  END IF;

  -- Possible duplicate of a harvest the Farmer entered themselves: same crop and unit, within 3 days.
  SELECT id INTO v_dup FROM harvest_records
   WHERE farmer_id = v_r.farmer_id AND crop_id = v_crop.id AND source_type = 'self'
     AND lower(btrim(unit)) = v_unit
     AND harvest_date BETWEEN v_date - 3 AND v_date + 3
   ORDER BY created_at DESC LIMIT 1;

  PERFORM set_config('sagana.program_registration', 'on', true);
  INSERT INTO harvest_records (
    farmer_id, crop_id, crop_name, crop_category, quantity_kg, unit, harvest_date,
    batch_number, is_synced, source_type, source_program_id, source_program_member_id, possible_duplicate_of
  ) VALUES (
    v_r.farmer_id, v_crop.id, v_crop.crop_name, COALESCE(v_crop.category, 'Other'), v_keep, v_unit, v_date,
    'PENDING-' || gen_random_uuid()::TEXT,          -- replaced by the batch-number trigger
    TRUE, v_type, v_r.program_id, v_m.id, v_dup
  ) RETURNING id, batch_number INTO v_h, v_batch;
  PERFORM set_config('sagana.program_registration', 'off', true);

  -- The batch the Farmer can then list, offer to the cooperative or sell (number and unit come from the harvest).
  INSERT INTO inventory_batches (
    farmer_id, harvest_record_id, crop_id, crop_name, batch_number, unit,
    quantity_kg, available_kg, reserved_kg, sold_kg, status, is_coop_eligible, crop_type
  ) VALUES (
    v_r.farmer_id, v_h, v_crop.id, v_crop.crop_name, v_batch, v_unit,
    v_keep, v_keep, 0, 0, 'available', COALESCE(v_cm.is_cooperative_eligible, FALSE), v_cm.crop_type
  );

  IF v_dup IS NOT NULL THEN
    v_extra := ' It looks similar to a harvest you entered yourself, so please check that you did not record it twice.';
  END IF;
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (v_r.farmer_id, 'program', 'Harvest Added to Your Records',
          v_keep || ' ' || v_unit || ' of ' || v_crop.crop_name || ' from ' || COALESCE(v_p.program_name, 'your program') ||
            ' was added to your Harvest records (' || v_batch || ').' || v_extra,
          FALSE, NOW(), '/farmer/harvest/crops');
  RETURN v_h;
END;
$$;
REVOKE ALL ON FUNCTION public._program_register_harvest(UUID, NUMERIC) FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 5. Return: produce basis credits Harvest Stock; same-item keeps p15
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._program_open_return(
  p_report_id UUID,
  p_quantity  NUMERIC,
  p_unit      TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_r    program_outcome_reports%ROWTYPE;
  v_p    cooperative_programs%ROWTYPE;
  v_m    program_members%ROWTYPE;
  v_inv  cooperative_inventory%ROWTYPE;
  v_name TEXT;
  v_id   UUID;
  v_crop farmer_crops%ROWTYPE;
  v_crop_id UUID;
  v_cap  NUMERIC;
  v_vu   TEXT;
BEGIN
  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id;
  SELECT * INTO v_p FROM cooperative_programs   WHERE id = v_r.program_id;
  IF v_p.benefit_type IS DISTINCT FROM 'revenue_share' THEN
    RETURN NULL;                       -- not a Harvest Return program
  END IF;
  SELECT id INTO v_id FROM program_returns WHERE program_member_id = v_r.program_member_id;
  IF FOUND THEN RETURN v_id; END IF;

  SELECT * INTO v_m FROM program_members WHERE id = v_r.program_member_id;
  IF v_m.inventory_item_id IS NULL THEN
    RAISE EXCEPTION 'RETURN_ITEM: This member has no distributed item on record, so there is nothing to return.';
  END IF;
  SELECT * INTO v_inv FROM cooperative_inventory WHERE id = v_m.inventory_item_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'RETURN_ITEM: The item that was given is no longer in Inventory.';
  END IF;
  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_r.farmer_id;

  IF v_p.return_basis = 'harvested_produce' THEN
    -- The Farmer returns part of what they HARVESTED, in the unit it was measured in. It is
    -- credited to Harvest Stock for the crop when received (record_program_return_receipt).
    IF v_inv.crop_master_id IS NULL THEN
      RAISE EXCEPTION 'RETURN_ITEM: The item that was given is not linked to a crop, so harvested produce cannot be returned.';
    END IF;
    v_cap := COALESCE(v_r.verified_quantity, v_r.quantity_harvested);
    v_vu  := lower(btrim(COALESCE(NULLIF(btrim(v_r.verified_unit), ''), v_r.quantity_unit)));
    IF v_cap IS NULL OR v_vu IS NULL OR v_vu = '' THEN
      RAISE EXCEPTION 'RETURN_QUANTITY: There is no verified harvest quantity to return from.';
    END IF;
    IF lower(btrim(p_unit)) IS DISTINCT FROM v_vu THEN
      RAISE EXCEPTION 'RETURN_UNIT: The return must be in the same unit as the verified harvest (%).', v_vu;
    END IF;
    IF p_quantity > v_cap THEN
      RAISE EXCEPTION 'RETURN_QUANTITY: The return cannot be more than the verified harvest (% %).', v_cap, v_vu;
    END IF;
    v_crop_id := public._program_ensure_farmer_crop(p_report_id);
    IF v_crop_id IS NULL THEN
      RAISE EXCEPTION 'RETURN_ITEM: The Farmer''s crop could not be found.';
    END IF;
    SELECT * INTO v_crop FROM farmer_crops WHERE id = v_crop_id;

    INSERT INTO program_returns (
      program_id, program_member_id, farmer_id, farmer_name, outcome_report_id,
      crop_id, crop_name, inventory_item_id, unit, original_quantity, due_quantity,
      reported_quantity, verified_quantity, underreport_flag
    ) VALUES (
      v_r.program_id, v_r.program_member_id, v_r.farmer_id, v_name, v_r.id,
      v_crop.id, v_crop.crop_name, NULL, v_vu, p_quantity, p_quantity,
      v_r.quantity_harvested, v_r.verified_quantity, FALSE
    ) RETURNING id INTO v_id;

    INSERT INTO program_return_events (return_id, event_type, quantity_after, actor_id, actor_name, actor_role)
    SELECT v_id, 'created', p_quantity, auth.uid(), a_name, a_role FROM public._outcome_actor();

    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (v_r.farmer_id, 'program', 'Harvest Return Due',
            'Your outcome for ' || v_p.program_name || ' was confirmed as successful after the field verification. '
              || 'You are to return ' || p_quantity || ' ' || v_vu || ' of your harvested ' || v_crop.crop_name ||
              ' to the cooperative. The rest of your harvest stays with you.',
            FALSE, NOW(), '/farmer/profile/programs/enrolled');
    RETURN v_id;
  END IF;

  -- Same item back (as p15): the return is added back to that same item, in its unit.
  IF lower(btrim(p_unit)) IS DISTINCT FROM lower(btrim(v_inv.unit)) THEN
    RAISE EXCEPTION 'RETURN_UNIT: The return must be in the same unit as the item given (%).', v_inv.unit;
  END IF;
  INSERT INTO program_returns (
    program_id, program_member_id, farmer_id, farmer_name, outcome_report_id,
    crop_id, crop_name, inventory_item_id, unit, original_quantity, due_quantity,
    reported_quantity, verified_quantity, underreport_flag
  ) VALUES (
    v_r.program_id, v_r.program_member_id, v_r.farmer_id, v_name, v_r.id,
    NULL, COALESCE(NULLIF(btrim(v_m.distributed_item_name), ''), v_inv.item_name), v_inv.id,
    btrim(v_inv.unit), p_quantity, p_quantity,
    v_r.quantity_harvested, v_r.verified_quantity, FALSE
  ) RETURNING id INTO v_id;

  INSERT INTO program_return_events (return_id, event_type, quantity_after, actor_id, actor_name, actor_role)
  SELECT v_id, 'created', p_quantity, auth.uid(), a_name, a_role FROM public._outcome_actor();

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (v_r.farmer_id, 'program', 'Harvest Return Due',
          'Your outcome for ' || v_p.program_name || ' was confirmed as successful after the field verification. '
            || 'You are to return ' || p_quantity || ' ' || btrim(v_inv.unit) || ' ' || v_inv.item_name ||
            ' to the cooperative.',
          FALSE, NOW(), '/farmer/profile/programs/enrolled');
  RETURN v_id;
END;
$function$;
REVOKE ALL ON FUNCTION public._program_open_return(UUID, NUMERIC, TEXT) FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 6. Finalize: same as p15, plus the Farmer's crop and harvest records
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.finalize_program_outcome(
  p_report_id       UUID,
  p_final_outcome   TEXT,
  p_note            TEXT DEFAULT NULL,
  p_return_quantity NUMERIC DEFAULT NULL,   -- Successful, Harvest Return programs: required
  p_return_unit     TEXT DEFAULT NULL,
  p_resolution      TEXT DEFAULT NULL,      -- Failed: one of the four decisions
  p_resolution_note TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid  UUID := auth.uid();
  v_r    program_outcome_reports%ROWTYPE;
  v_p    cooperative_programs%ROWTYPE;
  v_note TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_rnote TEXT := NULLIF(btrim(COALESCE(p_resolution_note, '')), '');
  v_name TEXT;
  v_role TEXT;
  v_prog TEXT;
  v_returns BOOLEAN;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only a Manager or Officer can finalize an outcome.';
  END IF;
  IF p_final_outcome NOT IN ('successful', 'failed') THEN
    RAISE EXCEPTION 'The final outcome must be successful or failed.';
  END IF;

  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Outcome report not found.';
  END IF;
  IF v_r.status = 'finalized' THEN
    RAISE EXCEPTION 'This outcome was already finalized.';
  END IF;
  IF v_r.status <> 'pending_validation' THEN
    RAISE EXCEPTION 'This report cannot be finalized (status: %).', v_r.status;
  END IF;
  IF v_r.review_decision IS DISTINCT FROM 'validated' THEN
    RAISE EXCEPTION 'The evidence must be reviewed and validated first.';
  END IF;
  IF v_r.verified_by IS NULL THEN
    RAISE EXCEPTION 'The field verification must be completed first.';
  END IF;
  IF (p_final_outcome <> v_r.reported_outcome OR v_r.verification_finding = 'disputes') AND v_note IS NULL THEN
    RAISE EXCEPTION 'Explain the decision: it differs from the report or the field verification disputed it.';
  END IF;

  SELECT * INTO v_p FROM cooperative_programs WHERE id = v_r.program_id;
  v_returns := (v_p.benefit_type = 'revenue_share');

  IF p_final_outcome = 'successful' AND v_returns THEN
    IF p_return_quantity IS NULL OR p_return_quantity <= 0 OR p_return_quantity <> round(p_return_quantity, 2)
       OR NULLIF(btrim(COALESCE(p_return_unit, '')), '') IS NULL THEN
      RAISE EXCEPTION 'RETURN_QUANTITY: Enter the quantity and unit the Farmer must return.';
    END IF;
  END IF;
  IF p_final_outcome = 'failed' THEN
    IF p_resolution IS NULL OR p_resolution NOT IN ('closed_no_further_obligation', 'eligible_for_reassessment',
                                                    'referred_for_loan_assessment', 'pending_cooperative_decision') THEN
      RAISE EXCEPTION 'RESOLUTION_INVALID: Choose one of the four decisions.';
    END IF;
    IF p_resolution <> 'pending_cooperative_decision' AND v_rnote IS NULL THEN
      RAISE EXCEPTION 'RESOLUTION_INVALID: A note is required for this decision.';
    END IF;
  END IF;

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();

  UPDATE program_outcome_reports
     SET status            = 'finalized',
         final_outcome     = p_final_outcome,
         finalized_by      = v_uid,
         finalized_by_name = v_name,
         finalized_by_role = v_role,
         finalized_at      = NOW(),
         final_note        = v_note
   WHERE id = p_report_id;

  UPDATE program_members
     SET distribution_outcome = CASE p_final_outcome WHEN 'successful' THEN 'thriving' ELSE 'failed' END,
         outcome_recorded_at  = NOW()
   WHERE id = v_r.program_member_id;

  IF p_final_outcome = 'successful' THEN
    IF v_returns THEN
      PERFORM public._program_open_return(p_report_id, p_return_quantity, p_return_unit);
    END IF;
    -- The distributed item joins the Farmer's own records: their crop (reused or created) and the
    -- harvest they keep, linked to this program. Items not linked to a crop are skipped.
    PERFORM public._program_ensure_farmer_crop(p_report_id);
    PERFORM public._program_register_harvest(p_report_id, p_return_quantity);
  ELSE
    PERFORM public._program_open_resolution(p_report_id, p_resolution, v_rnote);
  END IF;

  v_prog := v_p.program_name;
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (v_r.farmer_id, 'program',
          CASE p_final_outcome WHEN 'successful' THEN 'Program Outcome: Successful' ELSE 'Program Outcome: Failed' END,
          'Your outcome for ' || COALESCE(v_prog, 'the program') || ' was confirmed as ' || p_final_outcome || '.',
          FALSE, NOW(), '/farmer/profile/programs/enrolled');
END;
$function$;
REVOKE ALL ON FUNCTION public.finalize_program_outcome(UUID, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_program_outcome(UUID, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 7. Farmer report + field verification: crop items ask for harvest data, other items do not
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.submit_program_outcome_report(
  p_program_member_id UUID,
  p_outcome           TEXT,
  p_explanation       TEXT,
  p_planted_date      DATE,
  p_harvest_date      DATE,
  p_quantity          NUMERIC,
  p_unit              TEXT,
  p_area              NUMERIC,
  p_area_unit         TEXT,
  p_failure_cause     TEXT,
  p_failure_date      DATE,
  p_photo_paths       TEXT[]
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid     UUID := auth.uid();
  v_member  program_members%ROWTYPE;
  v_program cooperative_programs%ROWTYPE;
  v_id      UUID;
  v_path    TEXT;
  v_farmer  TEXT;
  v_grows   BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'You must be signed in.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = v_uid AND role = 'farmer' AND status = 'active') THEN
    RAISE EXCEPTION 'Only an active cooperative member can report an outcome.';
  END IF;

  SELECT * INTO v_member FROM program_members WHERE id = p_program_member_id FOR UPDATE;
  IF NOT FOUND OR v_member.farmer_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'Program enrollment not found.';
  END IF;
  IF v_member.status <> 'active' THEN
    RAISE EXCEPTION 'Only an active member can report an outcome.';
  END IF;
  IF v_member.distributed_at IS NULL THEN
    RAISE EXCEPTION 'You can report an outcome after you have received the program item.';
  END IF;

  SELECT * INTO v_program FROM cooperative_programs WHERE id = v_member.program_id;
  IF v_program.program_purpose <> 'distribution' THEN
    RAISE EXCEPTION 'Outcomes are reported for distribution programs only.';
  END IF;

  IF EXISTS (SELECT 1 FROM program_outcome_reports
              WHERE program_member_id = p_program_member_id AND status <> 'returned') THEN
    RAISE EXCEPTION 'An outcome report for this program is already in progress or finished.';
  END IF;
  IF v_member.distribution_outcome IN ('thriving', 'failed') THEN
    RAISE EXCEPTION 'An outcome was already recorded for this program.';
  END IF;

  IF p_outcome NOT IN ('successful', 'failed') THEN
    RAISE EXCEPTION 'Choose Successful or Failed.';
  END IF;
  IF p_explanation IS NULL OR btrim(p_explanation) = '' THEN
    RAISE EXCEPTION 'Write your explanation.';
  END IF;

  -- Planting material grows a crop: harvest facts are required. Any other item (tools, feeds,
  -- animals...): the explanation and the photos are the evidence.
  v_grows := public._program_item_grows_crop(p_program_member_id);

  IF p_outcome = 'successful' AND v_grows
     AND (p_quantity IS NULL OR p_quantity <= 0 OR p_unit IS NULL OR btrim(p_unit) = '') THEN
    RAISE EXCEPTION 'Enter the quantity harvested and its unit.';
  END IF;
  IF p_outcome = 'failed' AND (p_failure_cause IS NULL OR btrim(p_failure_cause) = '') THEN
    RAISE EXCEPTION 'Describe what caused the failure.';
  END IF;
  IF v_grows AND p_planted_date IS NULL THEN
    RAISE EXCEPTION 'Enter the date planted.';
  END IF;
  IF p_outcome = 'successful' AND v_grows AND p_harvest_date IS NULL THEN
    RAISE EXCEPTION 'Enter the harvest date.';
  END IF;
  IF p_outcome = 'failed' AND p_failure_date IS NULL THEN
    RAISE EXCEPTION 'Enter the date it failed.';
  END IF;
  IF p_planted_date IS NOT NULL AND p_harvest_date IS NOT NULL AND p_harvest_date < p_planted_date THEN
    RAISE EXCEPTION 'The harvest date cannot be before the planting date.';
  END IF;

  PERFORM public._outcome_check_paths(p_photo_paths, 1, 5);

  INSERT INTO program_outcome_reports (
    program_member_id, program_id, farmer_id, reported_outcome, explanation,
    planted_date, harvest_date, quantity_harvested, quantity_unit, area_planted, area_unit,
    failure_cause, failure_date
  ) VALUES (
    p_program_member_id, v_member.program_id, v_uid, p_outcome, btrim(p_explanation),
    CASE WHEN v_grows THEN p_planted_date END,
    CASE WHEN v_grows THEN p_harvest_date END,
    CASE WHEN p_outcome = 'successful' AND v_grows THEN p_quantity END,
    CASE WHEN p_outcome = 'successful' AND v_grows THEN btrim(p_unit) END,
    p_area, CASE WHEN p_area IS NOT NULL THEN p_area_unit END,
    CASE WHEN p_outcome = 'failed' THEN btrim(p_failure_cause) END,
    CASE WHEN p_outcome = 'failed' THEN p_failure_date END
  ) RETURNING id INTO v_id;

  FOREACH v_path IN ARRAY p_photo_paths LOOP
    INSERT INTO program_outcome_photos (report_id, uploaded_by, uploader_role, storage_path)
    VALUES (v_id, v_uid, 'farmer', v_path);
  END LOOP;

  SELECT full_name INTO v_farmer FROM user_information WHERE user_id = v_uid;
  PERFORM public.notify_staff(
    'program',
    'Program Outcome Report',
    COALESCE(v_farmer, 'A farmer') || ' reported a ' || p_outcome || ' outcome for ' ||
      COALESCE(v_program.program_name, 'a program') || '. It is waiting for review and field verification.',
    '/admin/programs/outcomes'
  );

  RETURN v_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.submit_program_outcome_report(UUID, TEXT, TEXT, DATE, DATE, NUMERIC, TEXT, NUMERIC, TEXT, TEXT, DATE, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_program_outcome_report(UUID, TEXT, TEXT, DATE, DATE, NUMERIC, TEXT, NUMERIC, TEXT, TEXT, DATE, TEXT[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.verify_program_outcome(
  p_report_id        UUID,
  p_finding          TEXT,
  p_verified_quantity NUMERIC,
  p_verified_unit    TEXT,
  p_field_visit_date DATE,
  p_note             TEXT,
  p_photo_paths      TEXT[]
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   UUID := auth.uid();
  v_r     program_outcome_reports%ROWTYPE;
  v_name  TEXT;
  v_role  TEXT;
  v_path  TEXT;
  v_grows BOOLEAN;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only a Manager or Officer can record the field verification.';
  END IF;
  IF p_finding NOT IN ('confirms', 'disputes') THEN
    RAISE EXCEPTION 'The finding must be confirms or disputes.';
  END IF;
  IF p_note IS NULL OR btrim(p_note) = '' THEN
    RAISE EXCEPTION 'Write what you found during the field verification.';
  END IF;
  IF p_field_visit_date IS NULL THEN
    RAISE EXCEPTION 'Enter the date of the field visit.';
  END IF;
  IF p_field_visit_date > (NOW() AT TIME ZONE 'Asia/Manila')::DATE THEN
    RAISE EXCEPTION 'The field visit date cannot be in the future.';
  END IF;

  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Outcome report not found.';
  END IF;
  IF v_r.status <> 'pending_validation' THEN
    RAISE EXCEPTION 'This report is no longer waiting for verification (status: %).', v_r.status;
  END IF;
  IF v_r.verified_by IS NOT NULL THEN
    RAISE EXCEPTION 'The field verification for this report was already recorded.';
  END IF;

  -- A crop item's successful report is checked against what was measured; other items have no quantity.
  v_grows := public._program_item_grows_crop(v_r.program_member_id);
  IF v_r.reported_outcome = 'successful' AND v_grows
     AND (p_verified_quantity IS NULL OR p_verified_quantity <= 0
          OR p_verified_unit IS NULL OR btrim(p_verified_unit) = '') THEN
    RAISE EXCEPTION 'Enter the quantity you measured in the field and its unit.';
  END IF;

  PERFORM public._outcome_check_paths(p_photo_paths, 0, 5);

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();

  UPDATE program_outcome_reports
     SET verification_finding = p_finding,
         verified_by          = v_uid,
         verified_by_name     = v_name,
         verified_by_role     = v_role,
         verified_at          = NOW(),
         field_visit_date     = p_field_visit_date,
         verified_quantity    = CASE WHEN v_r.reported_outcome = 'successful' AND v_grows THEN p_verified_quantity END,
         verified_unit        = CASE WHEN v_r.reported_outcome = 'successful' AND v_grows THEN btrim(p_verified_unit) END,
         verification_note    = btrim(p_note)
   WHERE id = p_report_id;

  FOREACH v_path IN ARRAY COALESCE(p_photo_paths, ARRAY[]::TEXT[]) LOOP
    INSERT INTO program_outcome_photos (report_id, uploaded_by, uploader_role, storage_path)
    VALUES (p_report_id, v_uid, 'staff', v_path);
  END LOOP;
END;
$function$;
REVOKE ALL ON FUNCTION public.verify_program_outcome(UUID, TEXT, NUMERIC, TEXT, DATE, TEXT, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_program_outcome(UUID, TEXT, NUMERIC, TEXT, DATE, TEXT, TEXT[]) TO authenticated;

-- Staff list (p15) + what kind of item it was and what the Farmer returns
CREATE OR REPLACE FUNCTION public.get_program_outcome_reports(p_program_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only a Manager or Officer can read outcome reports.';
  END IF;
  RETURN (
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.submitted_at DESC), '[]'::jsonb)
    FROM (
      SELECT r.submitted_at,
             to_jsonb(r) || jsonb_build_object(
               'program_name', cp.program_name,
               'is_harvest_return', (cp.benefit_type = 'revenue_share'),
               'return_basis', cp.return_basis,
               'grows_crop', public._program_item_grows_crop(r.program_member_id),
               'return_item_name', COALESCE(NULLIF(btrim(pm.distributed_item_name), ''),
                                            (SELECT ci.item_name FROM cooperative_inventory ci WHERE ci.id = pm.inventory_item_id)),
               'item_unit', (SELECT ci.unit FROM cooperative_inventory ci WHERE ci.id = pm.inventory_item_id),
               'farmer_name', ui.full_name,
               'item_name', pm.distributed_item_name,
               'quantity_given', pm.quantity_given,
               'distributed_at', pm.distributed_at,
               'photos', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                     'id', ph.id, 'path', ph.storage_path, 'by', ph.uploader_role)
                                   ORDER BY ph.created_at)
                                   FROM program_outcome_photos ph WHERE ph.report_id = r.id), '[]'::jsonb)
             ) AS j
      FROM program_outcome_reports r
      JOIN cooperative_programs cp ON cp.id = r.program_id
      LEFT JOIN program_members pm ON pm.id = r.program_member_id
      LEFT JOIN user_information ui ON ui.user_id = r.farmer_id
      WHERE p_program_id IS NULL OR r.program_id = p_program_id
    ) x
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.get_program_outcome_reports(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_program_outcome_reports(UUID) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 8. The old money / loan-convert / thriving functions are closed to the app
--    (nothing in the app calls them; they conflict with the locked rules). Every overload.
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND p.proname IN ('confirm_program_return', 'convert_program_distribution_to_loan', 'record_program_thriving_outcome')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
  END LOOP;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECKS (read-only; run after the script)
-- ============================================================
-- C1  New columns exist (expect 4 rows):
--     SELECT table_name, column_name FROM information_schema.columns
--      WHERE (table_name = 'cooperative_inventory' AND column_name IN ('crop_master_id','item_form'))
--         OR (table_name = 'cooperative_programs'  AND column_name = 'return_basis')
--         OR (table_name = 'harvest_records'       AND column_name = 'source_type');
-- C2  Existing programs keep today's behaviour (expect every row same_item):
--     SELECT program_name, benefit_type, return_basis FROM cooperative_programs;
-- C3  Items still NOT linked to a crop. Seeds / seedlings / planting material listed here must be
--     linked in Inventory (Edit item -> Crop) before their Farmers report an outcome, otherwise they
--     are treated as non-crop items:
--     SELECT item_name, category, unit, quantity_on_hand FROM cooperative_inventory
--      WHERE crop_master_id IS NULL AND is_active ORDER BY category, item_name;
-- C4  Farmer-delivered Harvest Stock is linked by itself (expect 0 rows):
--     SELECT item_name FROM cooperative_inventory
--      WHERE source_crop_id IS NOT NULL AND crop_master_id IS NULL
--        AND EXISTS (SELECT 1 FROM farmer_crops fc WHERE fc.id = source_crop_id AND fc.crop_master_id IS NOT NULL);
-- C5  The old functions are closed (expect callable = false for every row):
--     SELECT p.proname, has_function_privilege('authenticated', p.oid, 'EXECUTE') AS callable
--       FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
--        AND p.proname IN ('confirm_program_return','convert_program_distribution_to_loan','record_program_thriving_outcome');
-- C6  After a Successful outcome is finalized: the record is traceable (one row per member):
--     SELECT h.batch_number, h.crop_name, h.quantity_kg, h.unit, h.source_type, cp.program_name, h.possible_duplicate_of
--       FROM harvest_records h LEFT JOIN cooperative_programs cp ON cp.id = h.source_program_id
--      WHERE h.source_type <> 'self' ORDER BY h.created_at DESC;
-- C7  No member has two program harvest records, and no crop is duplicated for a Farmer (expect 0 rows each):
--     SELECT source_program_member_id FROM harvest_records WHERE source_program_member_id IS NOT NULL
--      GROUP BY 1 HAVING count(*) > 1;
--     SELECT farmer_id, crop_master_id FROM farmer_crops WHERE crop_master_id IS NOT NULL
--      GROUP BY 1, 2 HAVING count(*) > 1;
-- C8  Each program batch agrees with its harvest (expect 0 rows):
--     SELECT h.id FROM harvest_records h JOIN inventory_batches b ON b.harvest_record_id = h.id
--      WHERE h.source_type <> 'self' AND (b.batch_number <> h.batch_number OR b.unit <> h.unit OR b.quantity_kg <> h.quantity_kg);
-- ============================================================
