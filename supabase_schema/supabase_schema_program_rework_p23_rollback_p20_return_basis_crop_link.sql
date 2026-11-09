-- ============================================================
-- SAGANA — Program Management p23: ROLL BACK p20 (return basis, crop link, auto harvest)
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run BEFORE p24 (Item Type).
--
-- WHY: the "What the Farmer returns" field (Part of the harvest / The item received) and the
-- per-item crop link are removed from the product. This puts the database back to how p15 / p13 / p9
-- left it, so no unused logic or columns remain.
--
-- WHAT IT REVERSES (everything p20 introduced; p21 / p22 too, if they were ever run)
--   FUNCTIONS RESTORED to their previous definitions:
--     _program_open_return        (p15)      finalize_program_outcome   (p15)
--     get_program_outcome_reports (p15)      submit_program_outcome_report (p9)
--     verify_program_outcome      (p13)
--   FUNCTIONS DROPPED:  _program_item_grows_crop, _program_ensure_farmer_crop,
--     _program_register_harvest, _inventory_link_harvest_stock_crop, lock_program_return_basis,
--     _program_members_check_return_basis, _harvest_records_source_guard
--     (+ p21: _program_ensure_crop_for_member, _program_register_stock_at_distribution,
--      _program_members_route_distribution; p22: _inventory_form_from_category,
--      _programs_check_source_categories)
--   TRIGGERS DROPPED with them.
--   COLUMNS DROPPED:  cooperative_inventory.crop_master_id, item_form;
--     cooperative_programs.return_basis; harvest_records.source_type, source_program_id,
--     source_program_member_id, possible_duplicate_of (+ its unique index);
--     farmer_crops.source_program_id; inventory_categories.item_form (p22, if run).
--
-- DATA IS PRESERVED. Any Harvest record, batch or crop that a program created while p20 was live
-- stays as an ordinary record (only its "came from a program" markers go). Nothing is deleted from
-- harvest_records, inventory_batches, farmer_crops, program_members, program_returns or inventory.
--
-- KEPT ON PURPOSE: the three old money / loan-convert / thriving functions stay closed to the app
-- (they conflict with the locked rules: produce return, no automatic loan). That is not part of the
-- "What the Farmer returns" feature.
--
-- The Farmer's outcome report and the staff verification ask for the harvest facts again, for every
-- item, exactly as before p20. (Item Type, p24, does not change the outcome forms.)
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.program_returns') IS NULL
     OR to_regprocedure('public._outcome_actor()') IS NULL THEN
    RAISE EXCEPTION 'Program Management tables / helpers are missing; nothing to roll back.';
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- 1. Restore the functions p20 replaced (BEFORE the helpers they call are dropped)
-- ════════════════════════════════════════════════════════════

-- _program_open_return — p15: the Farmer returns the SAME ITEM they were given
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
  -- The returned quantity is added back to that same item, so it uses the item's unit.
  IF lower(btrim(p_unit)) IS DISTINCT FROM lower(btrim(v_inv.unit)) THEN
    RAISE EXCEPTION 'RETURN_UNIT: The return must be in the same unit as the item given (%).', v_inv.unit;
  END IF;
  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_r.farmer_id;

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

-- finalize_program_outcome — p15
CREATE OR REPLACE FUNCTION public.finalize_program_outcome(
  p_report_id       UUID,
  p_final_outcome   TEXT,
  p_note            TEXT DEFAULT NULL,
  p_return_quantity NUMERIC DEFAULT NULL,
  p_return_unit     TEXT DEFAULT NULL,
  p_resolution      TEXT DEFAULT NULL,
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
  -- Nothing is confirmed just because the Farmer submitted it: the evidence must
  -- be reviewed AND the field verification done first.
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

-- get_program_outcome_reports — p15
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

-- submit_program_outcome_report — p9: every detail required
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
  -- Earlier recorded (legacy) outcome with no report: not reported again.
  IF v_member.distribution_outcome IN ('thriving', 'failed') THEN
    RAISE EXCEPTION 'An outcome was already recorded for this program.';
  END IF;

  IF p_outcome NOT IN ('successful', 'failed') THEN
    RAISE EXCEPTION 'Choose Successful or Failed.';
  END IF;
  IF p_explanation IS NULL OR btrim(p_explanation) = '' THEN
    RAISE EXCEPTION 'Write your explanation.';
  END IF;
  IF p_outcome = 'successful' AND (p_quantity IS NULL OR p_quantity <= 0 OR p_unit IS NULL OR btrim(p_unit) = '') THEN
    RAISE EXCEPTION 'Enter the quantity harvested and its unit.';
  END IF;
  IF p_outcome = 'failed' AND (p_failure_cause IS NULL OR btrim(p_failure_cause) = '') THEN
    RAISE EXCEPTION 'Describe what caused the failure.';
  END IF;
  -- Every detail is required (the area planted is no longer asked for).
  IF p_planted_date IS NULL THEN
    RAISE EXCEPTION 'Enter the date planted.';
  END IF;
  IF p_outcome = 'successful' AND p_harvest_date IS NULL THEN
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
    p_planted_date, p_harvest_date,
    CASE WHEN p_outcome = 'successful' THEN p_quantity END,
    CASE WHEN p_outcome = 'successful' THEN btrim(p_unit) END,
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

-- verify_program_outcome — p13: a successful report is checked against what was measured
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
BEGIN
  -- The Manager or an Officer conducts the field verification. Who did it is recorded.
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
  -- A successful report is checked against what was actually measured.
  IF v_r.reported_outcome = 'successful'
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
         verified_quantity    = CASE WHEN v_r.reported_outcome = 'successful' THEN p_verified_quantity END,
         verified_unit        = CASE WHEN v_r.reported_outcome = 'successful' THEN btrim(p_verified_unit) END,
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

-- ════════════════════════════════════════════════════════════
-- 2. Drop the triggers, then the functions only p20 / p21 / p22 used
-- ════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS trg_inventory_link_harvest_stock_crop   ON public.cooperative_inventory;
DROP TRIGGER IF EXISTS trg_inventory_zz_form_from_category     ON public.cooperative_inventory;
DROP TRIGGER IF EXISTS trg_lock_program_return_basis           ON public.cooperative_programs;
DROP TRIGGER IF EXISTS trg_programs_check_source_categories    ON public.cooperative_programs;
DROP TRIGGER IF EXISTS trg_program_members_check_return_basis  ON public.program_members;
DROP TRIGGER IF EXISTS trg_program_members_route_distribution  ON public.program_members;
DROP TRIGGER IF EXISTS trg_harvest_records_source_guard_ins    ON public.harvest_records;
DROP TRIGGER IF EXISTS trg_harvest_records_source_guard_upd    ON public.harvest_records;

DROP FUNCTION IF EXISTS public._inventory_link_harvest_stock_crop();
DROP FUNCTION IF EXISTS public._inventory_form_from_category();
DROP FUNCTION IF EXISTS public.lock_program_return_basis();
DROP FUNCTION IF EXISTS public._programs_check_source_categories();
DROP FUNCTION IF EXISTS public._program_members_check_return_basis();
DROP FUNCTION IF EXISTS public._program_members_route_distribution();
DROP FUNCTION IF EXISTS public._harvest_records_source_guard();
DROP FUNCTION IF EXISTS public._program_register_stock_at_distribution(uuid);
DROP FUNCTION IF EXISTS public._program_register_harvest(uuid, numeric);
DROP FUNCTION IF EXISTS public._program_ensure_farmer_crop(uuid);
DROP FUNCTION IF EXISTS public._program_ensure_crop_for_member(uuid);
DROP FUNCTION IF EXISTS public._program_item_grows_crop(uuid);

-- ════════════════════════════════════════════════════════════
-- 3. Drop the columns (their rows' data is kept; only the markers go)
-- ════════════════════════════════════════════════════════════
DROP INDEX IF EXISTS public.uq_harvest_records_program_member;

ALTER TABLE public.harvest_records DROP CONSTRAINT IF EXISTS harvest_records_source_type_chk;
ALTER TABLE public.harvest_records
  DROP COLUMN IF EXISTS possible_duplicate_of,
  DROP COLUMN IF EXISTS source_program_member_id,
  DROP COLUMN IF EXISTS source_program_id,
  DROP COLUMN IF EXISTS source_type;

ALTER TABLE public.farmer_crops DROP COLUMN IF EXISTS source_program_id;

ALTER TABLE public.cooperative_programs DROP CONSTRAINT IF EXISTS cooperative_programs_return_basis_chk;
ALTER TABLE public.cooperative_programs DROP COLUMN IF EXISTS return_basis;

ALTER TABLE public.cooperative_inventory DROP CONSTRAINT IF EXISTS cooperative_inventory_crop_form_chk;
ALTER TABLE public.cooperative_inventory DROP CONSTRAINT IF EXISTS cooperative_inventory_item_form_chk;
ALTER TABLE public.cooperative_inventory
  DROP COLUMN IF EXISTS item_form,
  DROP COLUMN IF EXISTS crop_master_id;

ALTER TABLE public.inventory_categories DROP CONSTRAINT IF EXISTS inventory_categories_item_form_chk;
ALTER TABLE public.inventory_categories DROP COLUMN IF EXISTS item_form;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECKS (read-only; run after the script)
-- ============================================================
-- R1  None of the p20 columns remain (expect 0 rows):
--     SELECT table_name, column_name FROM information_schema.columns
--      WHERE table_schema = 'public' AND (
--            (table_name = 'cooperative_inventory' AND column_name IN ('crop_master_id', 'item_form'))
--         OR (table_name = 'cooperative_programs'  AND column_name = 'return_basis')
--         OR (table_name = 'harvest_records'       AND column_name IN ('source_type','source_program_id','source_program_member_id','possible_duplicate_of'))
--         OR (table_name = 'farmer_crops'          AND column_name = 'source_program_id')
--         OR (table_name = 'inventory_categories'  AND column_name = 'item_form'));
-- R2  None of the p20 / p21 / p22 helpers remain (expect 0 rows):
--     SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname IN (
--       '_program_item_grows_crop','_program_ensure_farmer_crop','_program_register_harvest',
--       '_program_ensure_crop_for_member','_program_register_stock_at_distribution',
--       '_program_members_route_distribution','_inventory_link_harvest_stock_crop',
--       'lock_program_return_basis','_program_members_check_return_basis','_harvest_records_source_guard',
--       '_inventory_form_from_category','_programs_check_source_categories');
-- R3  The restored outcome functions no longer mention the removed concepts (expect 0 rows):
--     SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace
--        AND proname IN ('finalize_program_outcome','_program_open_return','submit_program_outcome_report','verify_program_outcome')
--        AND (pg_get_functiondef(oid) ILIKE '%return_basis%' OR pg_get_functiondef(oid) ILIKE '%grows_crop%'
--             OR pg_get_functiondef(oid) ILIKE '%register_harvest%');
-- R4  Nothing was lost (compare with the numbers you had before; no rows are deleted by this script):
--     SELECT (SELECT count(*) FROM harvest_records) AS harvests, (SELECT count(*) FROM inventory_batches) AS batches,
--            (SELECT count(*) FROM farmer_crops) AS farmer_crops, (SELECT count(*) FROM cooperative_inventory) AS inventory_items,
--            (SELECT count(*) FROM program_returns) AS returns;
-- ============================================================
