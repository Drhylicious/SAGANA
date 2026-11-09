-- ============================================================
-- SAGANA — p25: Programs follow the Item Type; Free Distribution has no outcome; return arrangement
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run AFTER p23 and p24.
--
-- WHAT IT DOES
--  A. WHERE A DISTRIBUTED ITEM IS RECORDED (decided by the item's Item Type, set in Inventory)
--       Seeds & Seedlings  -> the Farmer's Crop Roster gets the crop the moment the item is handed over.
--                             The crop is reused if the Farmer already has it (never a second entry); a pending
--                             request for the same crop is linked. It is a minimal entry (name, category, the
--                             Crop Master link, and the program it came from): NO photo and NO catalog image;
--                             the Farmer completes their own crop details and records their own harvest.
--       Harvested Produce  -> the crop is added the same way AND a Harvest record + batch is created, marked
--                             "Received from program" (source_type = 'program_received'). It is NOT the Farmer's
--                             own production: every production figure counts source_type = 'self' only.
--       Non-Crop Item      -> nothing is added to crops or Harvest; it is listed under My Programs / Received Items.
--     Both program types do this. A crop type needs an active Crop Master crop at distribution (the database
--     refuses otherwise), so a program can only ever distribute crops that exist in Crop Management.
--  B. FREE DISTRIBUTION HAS NO OUTCOME. Once distributed, the item belongs to the Farmer.
--       * a new outcome report can only be filed for a Harvest Return program (trigger);
--       * program completion no longer waits for outcomes or returns on a Free Distribution program;
--       * a new report status 'closed' (+ closed_at, closed_reason): an in-progress Free Distribution report is
--         closed, never deleted; everything the Farmer submitted stays. Finalized outcomes stay as history.
--     No existing distribution row is changed: "distributed" simply counts as completed.
--  C. HARVEST RETURN ARRANGEMENT (the existing workflow is unchanged)
--       cooperative_programs.return_item_id        the DEFAULT item the Farmer returns (Inventory item)
--       program_members.return_item_id / quantity  the agreed return for THIS member's item (set at distribution;
--                                                  falls back to the program default, then to the same item)
--     The return is credited to that Inventory item, in that item's unit, through the unchanged receipt function.
--  D. ONE-TIME DATA (verified against your database checks; every step aborts rather than guess)
--       * Palay Seeds (duplicate) is archived, its 50 kg carried to Rice Seeds, then Rice Seeds becomes the one
--         Palay Seeds item linked to Palay. (Archive = this app's delete: the ledger is kept.)
--       * Peanut Seeds is linked to the Peanut Crop Master id.
--       * Every member who already received a crop-type item gets the crop in their Crop Roster (From program).
--       * In-progress Free Distribution reports are closed (at most 1 expected: Ellen's).
--  E. Production views (Top Harvested Crops, Planting Forecast) count the Farmer's own harvests only.
--
-- SWITCHES for the Palay / Rice step are the two constants at the top of that block.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_name = 'cooperative_inventory' AND column_name = 'item_type') THEN
    RAISE EXCEPTION 'Run p24 first (cooperative_inventory.item_type is missing).';
  END IF;
  IF to_regprocedure('public.finalize_program_outcome(uuid,text,text,numeric,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Program outcome functions are missing.';
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- A1. Where a record came from (crops and harvests)
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.farmer_crops
  ADD COLUMN IF NOT EXISTS source_program_id UUID REFERENCES public.cooperative_programs(id) ON DELETE SET NULL;

ALTER TABLE public.harvest_records
  ADD COLUMN IF NOT EXISTS source_type              TEXT NOT NULL DEFAULT 'self',
  ADD COLUMN IF NOT EXISTS source_program_id        UUID REFERENCES public.cooperative_programs(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS source_program_member_id UUID REFERENCES public.program_members(id)      ON DELETE SET NULL;
ALTER TABLE public.harvest_records DROP CONSTRAINT IF EXISTS harvest_records_source_type_chk;
ALTER TABLE public.harvest_records
  ADD CONSTRAINT harvest_records_source_type_chk CHECK (source_type IN ('self', 'program_received'));

-- One received record per member, ever.
CREATE UNIQUE INDEX IF NOT EXISTS uq_harvest_records_program_member
  ON public.harvest_records (source_program_member_id) WHERE source_program_member_id IS NOT NULL;

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
    IF NEW.source_type <> 'self' OR NEW.source_program_id IS NOT NULL OR NEW.source_program_member_id IS NOT NULL THEN
      RAISE EXCEPTION 'A harvest record can only be marked as received from a program by the program workflow.';
    END IF;
  ELSIF NEW.source_type IS DISTINCT FROM OLD.source_type
     OR NEW.source_program_id IS DISTINCT FROM OLD.source_program_id
     OR NEW.source_program_member_id IS DISTINCT FROM OLD.source_program_member_id THEN
    RAISE EXCEPTION 'Where a harvest record came from cannot be changed.';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_harvest_records_source_guard_ins ON public.harvest_records;
CREATE TRIGGER trg_harvest_records_source_guard_ins
  BEFORE INSERT ON public.harvest_records FOR EACH ROW EXECUTE FUNCTION public._harvest_records_source_guard();
DROP TRIGGER IF EXISTS trg_harvest_records_source_guard_upd ON public.harvest_records;
CREATE TRIGGER trg_harvest_records_source_guard_upd
  BEFORE UPDATE OF source_type, source_program_id, source_program_member_id ON public.harvest_records
  FOR EACH ROW EXECUTE FUNCTION public._harvest_records_source_guard();

-- ════════════════════════════════════════════════════════════
-- A2. The helpers and the distribution trigger
-- ════════════════════════════════════════════════════════════
-- The Farmer's crop for a distributed crop-type item (by member): reused when it exists, created when not.
CREATE OR REPLACE FUNCTION public._program_ensure_crop_for_member(p_member_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_m    program_members%ROWTYPE;
  v_inv  cooperative_inventory%ROWTYPE;
  v_cm   crop_master%ROWTYPE;
  v_crop UUID;
BEGIN
  SELECT * INTO v_m FROM program_members WHERE id = p_member_id;
  IF NOT FOUND OR v_m.inventory_item_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_inv FROM cooperative_inventory WHERE id = v_m.inventory_item_id;
  IF NOT FOUND OR v_inv.item_type = 'non_crop' OR v_inv.crop_master_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_cm FROM crop_master WHERE id = v_inv.crop_master_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  -- 1. The Farmer already has this crop: reuse it. Never a second entry.
  SELECT id INTO v_crop FROM farmer_crops
   WHERE farmer_id = v_m.farmer_id AND crop_master_id = v_cm.id ORDER BY created_at LIMIT 1;
  IF FOUND THEN RETURN v_crop; END IF;

  -- 2. A crop of the same name that is not linked yet (a pending request): the catalog entry settles it.
  SELECT id INTO v_crop FROM farmer_crops
   WHERE farmer_id = v_m.farmer_id AND lower(btrim(crop_name)) = lower(btrim(v_cm.crop_name))
   ORDER BY created_at LIMIT 1;
  IF FOUND THEN
    UPDATE farmer_crops SET crop_master_id = v_cm.id WHERE id = v_crop AND crop_master_id IS NULL;
    RETURN v_crop;
  END IF;

  -- 3. No such crop: a minimal entry. No photo, no catalog image: the Farmer completes their own details.
  INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id, source_program_id)
  VALUES (v_m.farmer_id, v_cm.crop_name, v_cm.category, v_cm.id, v_m.program_id)
  RETURNING id INTO v_crop;
  RETURN v_crop;
END;
$$;
REVOKE ALL ON FUNCTION public._program_ensure_crop_for_member(UUID) FROM PUBLIC, anon, authenticated;

-- Harvested Produce handed to a Farmer: a Harvest record + batch, marked as RECEIVED (not produced).
CREATE OR REPLACE FUNCTION public._program_register_received_produce(p_member_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_m       program_members%ROWTYPE;
  v_p       cooperative_programs%ROWTYPE;
  v_inv     cooperative_inventory%ROWTYPE;
  v_cm      crop_master%ROWTYPE;
  v_crop    farmer_crops%ROWTYPE;
  v_crop_id UUID;
  v_qty     NUMERIC;
  v_unit    TEXT;
  v_date    DATE := (NOW() AT TIME ZONE 'Asia/Manila')::DATE;
  v_h       UUID;
  v_batch   TEXT;
BEGIN
  SELECT * INTO v_m FROM program_members WHERE id = p_member_id;
  IF NOT FOUND OR v_m.inventory_item_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_inv FROM cooperative_inventory WHERE id = v_m.inventory_item_id;
  IF NOT FOUND OR v_inv.item_type <> 'harvested_produce' OR v_inv.crop_master_id IS NULL THEN RETURN NULL; END IF;
  IF EXISTS (SELECT 1 FROM harvest_records WHERE source_program_member_id = v_m.id) THEN RETURN NULL; END IF;

  SELECT * INTO v_p  FROM cooperative_programs WHERE id = v_m.program_id;
  SELECT * INTO v_cm FROM crop_master WHERE id = v_inv.crop_master_id;
  v_crop_id := public._program_ensure_crop_for_member(p_member_id);
  IF v_crop_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_crop FROM farmer_crops WHERE id = v_crop_id;

  v_qty  := round(COALESCE(v_m.quantity_given, 0), 2);
  v_unit := lower(btrim(COALESCE(NULLIF(btrim(v_m.distributed_unit), ''), v_inv.unit)));
  IF v_qty <= 0 OR v_unit IS NULL OR v_unit = '' THEN RETURN NULL; END IF;

  PERFORM set_config('sagana.program_registration', 'on', true);
  INSERT INTO harvest_records (
    farmer_id, crop_id, crop_name, crop_category, quantity_kg, unit, harvest_date,
    batch_number, is_synced, source_type, source_program_id, source_program_member_id
  ) VALUES (
    v_m.farmer_id, v_crop.id, v_crop.crop_name, COALESCE(v_crop.category, 'Other'), v_qty, v_unit,
    COALESCE((v_m.distributed_at AT TIME ZONE 'Asia/Manila')::DATE, v_date),
    'PENDING-' || gen_random_uuid()::TEXT,                 -- replaced by the batch-number trigger
    TRUE, 'program_received', v_m.program_id, v_m.id
  ) RETURNING id, batch_number INTO v_h, v_batch;
  PERFORM set_config('sagana.program_registration', 'off', true);

  INSERT INTO inventory_batches (
    farmer_id, harvest_record_id, crop_id, crop_name, batch_number, unit,
    quantity_kg, available_kg, reserved_kg, sold_kg, status, is_coop_eligible, crop_type
  ) VALUES (
    v_m.farmer_id, v_h, v_crop.id, v_crop.crop_name, v_batch, v_unit,
    v_qty, v_qty, 0, 0, 'available', COALESCE(v_cm.is_cooperative_eligible, FALSE), v_cm.crop_type
  );

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (v_m.farmer_id, 'program', 'Received from Program',
          v_qty || ' ' || v_unit || ' of ' || v_crop.crop_name || ' from ' || COALESCE(v_p.program_name, 'your program') ||
            ' was added to your Harvest tab (' || v_batch || ').',
          FALSE, NOW(), '/farmer/harvest/crops');
  RETURN v_h;
END;
$$;
REVOKE ALL ON FUNCTION public._program_register_received_produce(UUID) FROM PUBLIC, anon, authenticated;

-- A crop type can only be handed out while its crop is available in Crop Management.
CREATE OR REPLACE FUNCTION public._program_members_check_crop_available()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_inv cooperative_inventory%ROWTYPE;
BEGIN
  IF NEW.inventory_item_id IS NOT NULL THEN
    SELECT * INTO v_inv FROM cooperative_inventory WHERE id = NEW.inventory_item_id;
    IF FOUND AND v_inv.item_type <> 'non_crop' THEN
      IF v_inv.crop_master_id IS NULL
         OR NOT EXISTS (SELECT 1 FROM crop_master WHERE id = v_inv.crop_master_id AND is_active) THEN
        RAISE EXCEPTION 'CROP_NOT_AVAILABLE: This item''s crop is not available in Crop Management. Link the item to an active crop in Inventory first.';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_program_members_check_crop_available ON public.program_members;
CREATE TRIGGER trg_program_members_check_crop_available
  BEFORE UPDATE OF distributed_at ON public.program_members
  FOR EACH ROW
  WHEN (OLD.distributed_at IS NULL AND NEW.distributed_at IS NOT NULL)
  EXECUTE FUNCTION public._program_members_check_crop_available();

-- Fires once, when an item is first distributed. A failure here never blocks the distribution
-- (the stock already moved); the one-time block at the end of this script, or a re-run, adds anything missed.
CREATE OR REPLACE FUNCTION public._program_members_route_distribution()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.inventory_item_id IS NULL THEN RETURN NEW; END IF;
  BEGIN
    PERFORM public._program_ensure_crop_for_member(NEW.id);
    PERFORM public._program_register_received_produce(NEW.id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Program distribution routing skipped for member %: %', NEW.id, SQLERRM;
  END;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_program_members_route_distribution ON public.program_members;
CREATE TRIGGER trg_program_members_route_distribution
  AFTER UPDATE OF distributed_at ON public.program_members
  FOR EACH ROW
  WHEN (OLD.distributed_at IS NULL AND NEW.distributed_at IS NOT NULL)
  EXECUTE FUNCTION public._program_members_route_distribution();

-- ════════════════════════════════════════════════════════════
-- B. Free Distribution has no outcome
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.program_outcome_reports
  ADD COLUMN IF NOT EXISTS closed_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS closed_reason TEXT;

DO $$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
     WHERE conrelid = 'public.program_outcome_reports'::regclass AND contype = 'c'
       AND pg_get_constraintdef(oid) ILIKE '%pending_validation%'
       AND pg_get_constraintdef(oid) ILIKE '%finalized%'
  LOOP
    EXECUTE format('ALTER TABLE public.program_outcome_reports DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;
ALTER TABLE public.program_outcome_reports DROP CONSTRAINT IF EXISTS program_outcome_reports_status_chk;
ALTER TABLE public.program_outcome_reports
  ADD CONSTRAINT program_outcome_reports_status_chk
  CHECK (status IN ('pending_validation', 'returned', 'finalized', 'closed'));

CREATE OR REPLACE FUNCTION public._outcome_reports_harvest_return_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cooperative_programs WHERE id = NEW.program_id AND benefit_type = 'revenue_share') THEN
    RAISE EXCEPTION 'A Free Distribution does not need an outcome report: once the item is distributed it belongs to the Farmer.';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_outcome_reports_harvest_return_only ON public.program_outcome_reports;
CREATE TRIGGER trg_outcome_reports_harvest_return_only
  BEFORE INSERT ON public.program_outcome_reports
  FOR EACH ROW EXECUTE FUNCTION public._outcome_reports_harvest_return_only();

-- A program can be completed without waiting for outcomes or returns it never asks for.
CREATE OR REPLACE FUNCTION public.program_completion_blockers(p_program_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_p        cooperative_programs%ROWTYPE;
  v_await    integer := 0;
  v_returns  integer := 0;
  v_orders   integer := 0;
  v_stock    integer := 0;
BEGIN
  SELECT * INTO v_p FROM cooperative_programs WHERE id = p_program_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_p.program_purpose = 'distribution' THEN
    -- Only a Harvest Return program has outcomes and returns. A Free Distribution is complete once
    -- the items are handed out.
    IF v_p.benefit_type = 'revenue_share' THEN
      SELECT count(*) INTO v_await
        FROM program_members m
       WHERE m.program_id = p_program_id
         AND m.status = 'active'
         AND m.distributed_at IS NOT NULL
         AND COALESCE(m.distribution_outcome, 'pending') NOT IN ('thriving', 'failed');
      SELECT count(*) INTO v_returns
        FROM program_returns r
       WHERE r.program_id = p_program_id AND r.status IN ('pending', 'partial');
    END IF;
  ELSE
    SELECT count(*) INTO v_orders
      FROM program_product_purchases p
     WHERE p.program_id = p_program_id
       AND p.status IN ('pending', 'approved', 'ready_for_pickup', 'out_for_delivery', 'delivered');
    SELECT count(*) INTO v_stock
      FROM program_products pp
     WHERE pp.program_id = p_program_id AND pp.stock_allocated > 0;
  END IF;

  RETURN jsonb_build_object(
    'awaiting_outcome',  v_await,
    'open_returns',      v_returns,
    'open_orders',       v_orders,
    'allocated_stock',   v_stock
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.program_completion_blockers(uuid) FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- C. Harvest Return arrangement: the item the Farmer returns, per program (default) and per member
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.cooperative_programs
  ADD COLUMN IF NOT EXISTS return_item_id UUID REFERENCES public.cooperative_inventory(id) ON DELETE SET NULL;
ALTER TABLE public.program_members
  ADD COLUMN IF NOT EXISTS return_item_id  UUID REFERENCES public.cooperative_inventory(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS return_quantity NUMERIC;
ALTER TABLE public.program_members DROP CONSTRAINT IF EXISTS program_members_return_quantity_chk;
ALTER TABLE public.program_members
  ADD CONSTRAINT program_members_return_quantity_chk CHECK (return_quantity IS NULL OR return_quantity > 0);

CREATE OR REPLACE FUNCTION public.set_member_return_arrangement(
  p_member_id      UUID,
  p_return_item_id UUID,
  p_return_quantity NUMERIC
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_m   program_members%ROWTYPE;
  v_p   cooperative_programs%ROWTYPE;
  v_inv cooperative_inventory%ROWTYPE;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can set what the Farmer returns.';
  END IF;
  SELECT * INTO v_m FROM program_members WHERE id = p_member_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Program member not found.'; END IF;
  SELECT * INTO v_p FROM cooperative_programs WHERE id = v_m.program_id;
  IF v_p.benefit_type IS DISTINCT FROM 'revenue_share' THEN
    RAISE EXCEPTION 'RETURN_ITEM: Only a Harvest Return program has something to return.';
  END IF;
  IF EXISTS (SELECT 1 FROM program_returns WHERE program_member_id = p_member_id) THEN
    RAISE EXCEPTION 'RETURN_CLOSED: The return for this member is already open, so it can no longer be changed.';
  END IF;
  IF p_return_item_id IS NOT NULL THEN
    SELECT * INTO v_inv FROM cooperative_inventory WHERE id = p_return_item_id;
    IF NOT FOUND OR NOT v_inv.is_active OR v_inv.archived_at IS NOT NULL THEN
      RAISE EXCEPTION 'RETURN_ITEM: That item is not available in Inventory.';
    END IF;
  END IF;
  IF p_return_quantity IS NOT NULL AND (p_return_quantity <= 0 OR p_return_quantity <> round(p_return_quantity, 2)) THEN
    RAISE EXCEPTION 'RETURN_QUANTITY: Enter a return quantity greater than zero.';
  END IF;
  UPDATE program_members
     SET return_item_id = p_return_item_id, return_quantity = p_return_quantity
   WHERE id = p_member_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.set_member_return_arrangement(UUID, UUID, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_member_return_arrangement(UUID, UUID, NUMERIC) TO authenticated;

DO $$ BEGIN
  IF to_regclass('public.staff_permission_targets') IS NOT NULL THEN
    INSERT INTO public.staff_permission_targets (kind, name, module)
    VALUES ('rpc', 'set_member_return_arrangement', 'dashboard')
    ON CONFLICT (kind, name) DO NOTHING;
  END IF;
END $$;

-- The return is credited to the agreed item (member, else program default, else the item given).
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
  v_item UUID;
BEGIN
  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id;
  SELECT * INTO v_p FROM cooperative_programs   WHERE id = v_r.program_id;
  IF v_p.benefit_type IS DISTINCT FROM 'revenue_share' THEN
    RETURN NULL;                       -- not a Harvest Return program
  END IF;
  SELECT id INTO v_id FROM program_returns WHERE program_member_id = v_r.program_member_id;
  IF FOUND THEN RETURN v_id; END IF;

  SELECT * INTO v_m FROM program_members WHERE id = v_r.program_member_id;
  v_item := COALESCE(v_m.return_item_id, v_p.return_item_id, v_m.inventory_item_id);
  IF v_item IS NULL THEN
    RAISE EXCEPTION 'RETURN_ITEM: There is no item set to return, so there is nothing to credit.';
  END IF;
  SELECT * INTO v_inv FROM cooperative_inventory WHERE id = v_item;
  IF NOT FOUND OR NOT v_inv.is_active OR v_inv.archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'RETURN_ITEM: The item to return is no longer available in Inventory.';
  END IF;
  -- The return is added to that item, so it uses that item's unit.
  IF lower(btrim(p_unit)) IS DISTINCT FROM lower(btrim(v_inv.unit)) THEN
    RAISE EXCEPTION 'RETURN_UNIT: The return must be in the same unit as the item returned (%).', v_inv.unit;
  END IF;
  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_r.farmer_id;

  INSERT INTO program_returns (
    program_id, program_member_id, farmer_id, farmer_name, outcome_report_id,
    crop_id, crop_name, inventory_item_id, unit, original_quantity, due_quantity,
    reported_quantity, verified_quantity, underreport_flag
  ) VALUES (
    v_r.program_id, v_r.program_member_id, v_r.farmer_id, v_name, v_r.id,
    NULL, v_inv.item_name, v_inv.id,
    btrim(v_inv.unit), p_quantity, p_quantity,
    v_r.quantity_harvested, v_r.verified_quantity, FALSE
  ) RETURNING id INTO v_id;

  INSERT INTO program_return_events (return_id, event_type, quantity_after, actor_id, actor_name, actor_role)
  SELECT v_id, 'created', p_quantity, auth.uid(), a_name, a_role FROM public._outcome_actor();

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (v_r.farmer_id, 'program', 'Return Due',
          'Your outcome for ' || v_p.program_name || ' was confirmed as successful after the field verification. '
            || 'You are to return ' || p_quantity || ' ' || btrim(v_inv.unit) || ' ' || v_inv.item_name ||
            ' to the cooperative.',
          FALSE, NOW(), '/farmer/profile/programs/enrolled');
  RETURN v_id;
END;
$function$;
REVOKE ALL ON FUNCTION public._program_open_return(UUID, NUMERIC, TEXT) FROM PUBLIC, anon, authenticated;

-- The staff list: the item to return, its unit and the agreed quantity (to pre-fill the final step).
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
               'return_item_name', (SELECT ci.item_name FROM cooperative_inventory ci
                                     WHERE ci.id = COALESCE(pm.return_item_id, cp.return_item_id, pm.inventory_item_id)),
               'item_unit', (SELECT ci.unit FROM cooperative_inventory ci
                              WHERE ci.id = COALESCE(pm.return_item_id, cp.return_item_id, pm.inventory_item_id)),
               'agreed_return_quantity', COALESCE(pm.return_quantity, cp.return_quantity),
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
-- E. Production views count the Farmer's own harvests only (received produce is not production)
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v    TEXT;
  def  TEXT;
BEGIN
  FOREACH v IN ARRAY ARRAY['top_harvested_crops', 'crop_cycle_volumes'] LOOP
    IF to_regclass('public.' || v) IS NOT NULL THEN
      def := pg_get_viewdef(('public.' || v)::regclass, true);
      IF def ILIKE '%harvest_records%' AND def NOT ILIKE '%source_type%' AND def ~* '\mWHERE\M' THEN
        def := regexp_replace(rtrim(def, E'; \n'), '\mWHERE\M', 'WHERE hr.source_type = ''self'' AND', 'i');
        EXECUTE format('CREATE OR REPLACE VIEW public.%I AS %s', v, def);
      END IF;
    END IF;
  END LOOP;
END $$;

-- ════════════════════════════════════════════════════════════
-- D. One-time data (aborts instead of guessing)
-- ════════════════════════════════════════════════════════════
-- D1. Palay Seeds (duplicate) -> archived; Rice Seeds (the one with the history) becomes the Palay Seeds item.
DO $$
DECLARE
  -- SWITCHES ------------------------------------------------------------------------------------
  c_carry_over_stock CONSTANT BOOLEAN := TRUE;    -- carry the duplicate's stock over to the kept item
  c_rename_kept      CONSTANT BOOLEAN := TRUE;    -- rename the kept item "Palay Seeds"
  -- ---------------------------------------------------------------------------------------------
  v_dup   CONSTANT UUID := 'eee217a9-58ad-41b6-b080-e6e188d40065';   -- Palay Seeds (the duplicate)
  v_keep  CONSTANT UUID := '0b88c44d-cbc5-4595-a9f2-cb287b251380';   -- Rice Seeds (kept)
  v_palay UUID;
  v_dup_row  cooperative_inventory%ROWTYPE;
  v_stock NUMERIC;
  v_by    UUID;
  v_dist  INTEGER;
  v_moves INTEGER;
  v_src_trigger BOOLEAN;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cooperative_inventory WHERE id = v_keep) THEN
    RAISE NOTICE 'Rice Seeds item not found: Palay / Rice step skipped.';
    RETURN;
  END IF;
  SELECT id INTO v_palay FROM crop_master WHERE crop_name = 'Palay' AND is_active;
  IF v_palay IS NULL THEN
    RAISE EXCEPTION 'The crop "Palay" is not an active Crop Master crop. Nothing was changed.';
  END IF;

  -- Older items have no Source recorded, and the "Source is required" rule fires whenever an item's name
  -- changes. It is switched off for these two updates only (so no Source is invented), then back on.
  v_src_trigger := EXISTS (SELECT 1 FROM pg_trigger
                            WHERE tgname = 'trg_enforce_inventory_source'
                              AND tgrelid = 'public.cooperative_inventory'::regclass AND NOT tgisinternal);
  IF v_src_trigger THEN
    ALTER TABLE public.cooperative_inventory DISABLE TRIGGER trg_enforce_inventory_source;
  END IF;

  SELECT * INTO v_dup_row FROM cooperative_inventory WHERE id = v_dup;
  IF FOUND AND v_dup_row.archived_at IS NULL THEN
    -- Archiving keeps all history (the same as the app's own Delete). The loan-catalog entry and the
    -- cooperative product are simply switched off. It stops only if the item was really USED.
    SELECT count(*) INTO v_dist FROM program_members WHERE inventory_item_id = v_dup;
    SELECT count(*) INTO v_moves FROM inventory_transactions
     WHERE inventory_id = v_dup AND transaction_type NOT IN ('restock', 'adjustment');
    IF v_dist > 0 OR v_moves > 0 THEN
      RAISE EXCEPTION 'Palay Seeds has real use: % program distribution(s) and % stock movement(s) other than restock/adjustment. It was NOT archived. Nothing was changed. Run check P0 at the bottom to see them.', v_dist, v_moves;
    END IF;
    v_stock := v_dup_row.quantity_on_hand;
    v_by := v_dup_row.created_by;
    IF v_stock > 0 THEN
      IF c_carry_over_stock THEN
        UPDATE cooperative_inventory SET quantity_on_hand = quantity_on_hand + v_stock, last_restocked_at = NOW()
         WHERE id = v_keep;
        INSERT INTO inventory_transactions (inventory_id, transaction_type, quantity, reference_type, notes, recorded_by)
        VALUES (v_keep, 'adjustment', v_stock, NULL, 'Carried over from the duplicate Palay Seeds item', v_by);
      END IF;
      INSERT INTO inventory_transactions (inventory_id, transaction_type, quantity, reference_type, notes, recorded_by)
      VALUES (v_dup, 'adjustment', -v_stock, NULL,
              CASE WHEN c_carry_over_stock THEN 'Moved to the kept Palay Seeds item (duplicate removed)'
                   ELSE 'Duplicate item removed' END, v_by);
    END IF;
    UPDATE cooperative_inventory
       SET quantity_on_hand = 0, is_active = FALSE, archived_at = NOW(),
           item_name = item_name || ' (duplicate, archived)'
     WHERE id = v_dup;
    UPDATE loan_items_master SET is_loan_eligible = FALSE WHERE inventory_item_id = v_dup AND is_loan_eligible;
    UPDATE program_products  SET is_available = FALSE     WHERE inventory_item_id = v_dup AND is_available;
  END IF;

  UPDATE cooperative_inventory
     SET item_type = 'seeds_seedlings',
         crop_master_id = v_palay,
         item_name = CASE WHEN c_rename_kept THEN 'Palay Seeds' ELSE item_name END
   WHERE id = v_keep;

  IF v_src_trigger THEN
    ALTER TABLE public.cooperative_inventory ENABLE TRIGGER trg_enforce_inventory_source;
  END IF;
END $$;

-- D2. Peanut Seeds is linked to the Peanut Crop Master id.
DO $$
DECLARE
  v_item   CONSTANT UUID := '0df49c4b-96d2-49ff-8b0f-0310169cd3b3';   -- Peanut Seeds
  v_peanut UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cooperative_inventory WHERE id = v_item) THEN
    RAISE NOTICE 'Peanut Seeds item not found: Peanut link skipped.';
    RETURN;
  END IF;
  SELECT id INTO v_peanut FROM crop_master WHERE crop_name = 'Peanut' AND is_active;
  IF v_peanut IS NULL THEN
    RAISE EXCEPTION 'The crop "Peanut" is not an active Crop Master crop. Nothing was changed.';
  END IF;
  UPDATE cooperative_inventory SET item_type = 'seeds_seedlings', crop_master_id = v_peanut
   WHERE id = v_item AND crop_master_id IS DISTINCT FROM v_peanut;
END $$;

-- D3. Close in-progress Free Distribution reports (nothing is deleted; at most one is expected).
DO $$
DECLARE v_n INTEGER;
BEGIN
  UPDATE program_outcome_reports r
     SET status = 'closed', closed_at = NOW(),
         closed_reason = 'No longer required: Free Distribution has no outcome process.'
    FROM cooperative_programs cp
   WHERE cp.id = r.program_id AND cp.benefit_type IS DISTINCT FROM 'revenue_share'
     AND r.status = 'pending_validation';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n > 1 THEN
    RAISE EXCEPTION 'Expected to close at most 1 in-progress Free Distribution report, found %. Nothing was changed.', v_n;
  END IF;
  RAISE NOTICE 'Free Distribution reports closed: %', v_n;
END $$;

-- D4. Everyone who already received a crop-type item gets the crop in their Crop Roster (and received
--     produce its Harvest record). Reuses an existing crop; idempotent.
DO $$
DECLARE
  r RECORD;
  v_crops INTEGER := 0;
BEGIN
  FOR r IN
    SELECT pm.id, ci.item_type
      FROM program_members pm
      JOIN cooperative_inventory ci ON ci.id = pm.inventory_item_id
     WHERE pm.distributed_at IS NOT NULL AND ci.item_type <> 'non_crop' AND ci.crop_master_id IS NOT NULL
  LOOP
    IF public._program_ensure_crop_for_member(r.id) IS NOT NULL THEN v_crops := v_crops + 1; END IF;
    IF r.item_type = 'harvested_produce' THEN
      PERFORM public._program_register_received_produce(r.id);
    END IF;
  END LOOP;
  RAISE NOTICE 'Distributed members checked for the Crop Roster: %', v_crops;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECKS (read-only)
-- ============================================================
-- P0  What references the duplicate Palay Seeds (run this if p25 stops at the Palay step):
--     SELECT 'program distributions' AS what, count(*) FROM program_members WHERE inventory_item_id = 'eee217a9-58ad-41b6-b080-e6e188d40065'
--     UNION ALL SELECT 'loan catalog entries', count(*) FROM loan_items_master WHERE inventory_item_id = 'eee217a9-58ad-41b6-b080-e6e188d40065'
--     UNION ALL SELECT 'cooperative products', count(*) FROM program_products WHERE inventory_item_id = 'eee217a9-58ad-41b6-b080-e6e188d40065'
--     UNION ALL SELECT 'ledger: ' || transaction_type, count(*) FROM inventory_transactions
--                WHERE inventory_id = 'eee217a9-58ad-41b6-b080-e6e188d40065' GROUP BY transaction_type;
-- P1  Palay Seeds is archived, Rice Seeds is the one Palay Seeds item linked to Palay, stock carried over:
--     SELECT item_name, item_type, crop_master_id, quantity_on_hand, is_active, archived_at
--       FROM cooperative_inventory WHERE id IN ('eee217a9-58ad-41b6-b080-e6e188d40065','0b88c44d-cbc5-4595-a9f2-cb287b251380');
-- P2  Peanut Seeds points at the Peanut crop:
--     SELECT ci.item_name, cm.crop_name FROM cooperative_inventory ci JOIN crop_master cm ON cm.id = ci.crop_master_id
--      WHERE ci.id = '0df49c4b-96d2-49ff-8b0f-0310169cd3b3';
-- P3  The Peanut farmers now have Peanut, marked as from the program (expect 4 rows):
--     SELECT ui.full_name, fc.crop_name, fc.source_program_id IS NOT NULL AS from_program
--       FROM farmer_crops fc JOIN user_information ui ON ui.user_id = fc.farmer_id
--      WHERE fc.crop_name = 'Peanut' ORDER BY 1;
-- P4  The in-progress Free Distribution report is closed, the finalized outcomes are untouched:
--     SELECT ui.full_name, r.status, r.closed_reason, r.final_outcome FROM program_outcome_reports r
--       JOIN user_information ui ON ui.user_id = r.farmer_id ORDER BY 1;
-- P5  A Free Distribution program is no longer blocked by outcomes (awaiting_outcome = 0):
--     SELECT cp.program_name, public.program_completion_blockers(cp.id) FROM cooperative_programs cp
--      WHERE cp.benefit_type = 'grant' AND cp.program_purpose = 'distribution';
-- P6  Distribution records are intact (counts unchanged from before):
--     SELECT program_id, count(*) FILTER (WHERE distributed_at IS NOT NULL) AS distributed FROM program_members GROUP BY 1;
-- P7  The ledger lost nothing (only the carry-over pair was added):
--     SELECT transaction_type, count(*) FROM inventory_transactions GROUP BY 1 ORDER BY 1;
-- ============================================================
