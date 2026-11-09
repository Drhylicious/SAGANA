-- ============================================================
-- SAGANA — Harvest Return: the Farmer returns the SAME ITEM they were given
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Needs p6, p9, p11
-- (and p13 for the verification wording).
--
-- WHY
--   A Harvest Return program used to ask for a "Return crop" chosen when the program is
--   created. The item a Farmer receives is now chosen at distribution time, so the
--   program cannot know it. The rule is now: the Farmer returns the same item they were
--   given. That item is already remembered on their distribution record
--   (program_members.inventory_item_id / distributed_item_name).
--
-- WHAT IT CHANGES
--   1. program_returns: crop_id may be empty; new inventory_item_id (the item given).
--   2. program_missing_fields(): a Harvest Return program no longer needs a return crop
--      (it still needs a quantity and a unit).
--   3. _program_open_return(): a Successful outcome opens the return for the item that was
--      given. The unit must be that item's unit (the return is added back to the same item).
--   4. record_program_return_receipt(): the confirmed quantity is ADDED BACK TO THAT SAME
--      ITEM in Cooperative Inventory (ledger type 'restock'), so it can be loaned or
--      distributed again. A return already opened under the old rule is handled as before.
--   5. finalize_program_outcome() and get_program_outcome_reports(): a Harvest Return program
--      no longer needs a return crop; the list also returns the item given and its unit.
--
-- NOTHING IS DELETED. Your check showed there are no returns yet, so no existing return changes.
-- New code-prefixed errors: RETURN_ITEM, RETURN_UNIT
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.program_returns') IS NULL
     OR to_regprocedure('public.finalize_program_outcome(uuid,text,text,numeric,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Apply p6 and p9 first.';
  END IF;
END $$;

ALTER TABLE public.program_returns ALTER COLUMN crop_id DROP NOT NULL;
ALTER TABLE public.program_returns ADD COLUMN IF NOT EXISTS inventory_item_id UUID;

CREATE OR REPLACE FUNCTION public.program_missing_fields(p public.cooperative_programs)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT array_remove(ARRAY[
    CASE WHEN p.program_name IS NULL OR btrim(p.program_name) = ''  THEN 'name' END,
    CASE WHEN p.program_type IS NULL OR btrim(p.program_type) = ''  THEN 'type' END,
    CASE WHEN p.image_url    IS NULL OR btrim(p.image_url)    = ''  THEN 'photo' END,
    CASE WHEN p.description  IS NULL OR btrim(p.description)  = ''  THEN 'description' END,
    CASE WHEN p.budget       IS NULL OR p.budget <= 0               THEN 'budget' END,
    -- Where it distributes from: categories; an older Distribution program with its
    -- single configured item still counts until it is edited.
    CASE WHEN COALESCE(array_length(p.source_categories, 1), 0) = 0
          AND (p.program_purpose = 'sales' OR p.distribution_item_id IS NULL)
                                                                    THEN 'sources' END,
    CASE WHEN p.program_purpose = 'distribution' AND p.benefit_type = 'revenue_share'
          AND (p.return_quantity IS NULL OR p.return_quantity <= 0) THEN 'return_quantity' END,
    CASE WHEN p.program_purpose = 'distribution' AND p.benefit_type = 'revenue_share'
          AND (p.return_unit IS NULL OR btrim(p.return_unit) = '')  THEN 'return_unit' END
  ], NULL);
$$;

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

  -- What the Farmer returns is the SAME ITEM the cooperative gave them, remembered on
  -- their distribution record.
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

CREATE OR REPLACE FUNCTION public.record_program_return_receipt(
  p_return_id UUID,
  p_quantity  NUMERIC,
  p_note      TEXT DEFAULT NULL
) RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ret     program_returns%ROWTYPE;
  v_note    TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_unit    TEXT;
  v_item    UUID;
  v_inv     cooperative_inventory%ROWTYPE;
  v_tx      UUID := gen_random_uuid();
  v_receipt UUID := gen_random_uuid();
  v_name    TEXT;
  v_role    TEXT;
  v_new     NUMERIC;
  v_prog    TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can record a harvest return.';
  END IF;
  SELECT * INTO v_ret FROM program_returns WHERE id = p_return_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'RETURN_CLOSED: Harvest return not found.';
  END IF;
  IF v_ret.status IN ('received', 'closed_short') THEN
    RAISE EXCEPTION 'RETURN_CLOSED: This harvest return is already closed.';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 OR p_quantity <> round(p_quantity, 2)
     OR p_quantity::text IN ('NaN', 'Infinity') THEN
    RAISE EXCEPTION 'RETURN_OVER_RECEIPT: Enter the quantity received (greater than zero).';
  END IF;
  IF v_ret.received_quantity + p_quantity > v_ret.due_quantity THEN
    RAISE EXCEPTION 'RETURN_OVER_RECEIPT: That is more than the quantity still due.';
  END IF;

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();
  v_unit := lower(btrim(v_ret.unit));

  SELECT program_name INTO v_prog FROM cooperative_programs WHERE id = v_ret.program_id;

  IF v_ret.inventory_item_id IS NOT NULL THEN
    -- The Farmer returns the SAME item they were given: the confirmed quantity is added
    -- back to that item in Cooperative Inventory, with a ledger row.
    SELECT * INTO v_inv FROM cooperative_inventory WHERE id = v_ret.inventory_item_id FOR UPDATE;
    IF NOT FOUND OR NOT v_inv.is_active OR v_inv.archived_at IS NOT NULL THEN
      RAISE EXCEPTION 'RETURN_ITEM: The item that was given is no longer available in Inventory.';
    END IF;
    IF lower(btrim(v_inv.unit)) <> v_unit THEN
      RAISE EXCEPTION 'RETURN_UNIT: The return must be in the same unit as the item (%).', v_inv.unit;
    END IF;
    v_item := v_inv.id;
    UPDATE cooperative_inventory
       SET quantity_on_hand = quantity_on_hand + p_quantity, last_restocked_at = NOW()
     WHERE id = v_item;
    INSERT INTO inventory_transactions
      (id, inventory_id, transaction_type, quantity, reference_id, reference_type, notes, recorded_by)
    VALUES (v_tx, v_item, 'restock', p_quantity, v_receipt, 'program_return',
            'Harvest return: ' || COALESCE(v_prog, 'program'), auth.uid());
  ELSE
    -- A return opened before this change (it names a crop, not an item): as before.
      -- Cooperative Inventory: the same item identity a Farmer delivery uses.
    INSERT INTO cooperative_inventory
      (item_name, category, unit, source, source_farmer_id, source_crop_id, created_by)
    VALUES (v_ret.crop_name, 'Harvest Stock', v_unit,
            COALESCE(v_ret.farmer_name, 'Farmer'), v_ret.farmer_id, v_ret.crop_id, auth.uid())
    ON CONFLICT (source_farmer_id, source_crop_id, lower(btrim(unit))) WHERE source_farmer_id IS NOT NULL
    DO UPDATE SET is_active = TRUE, archived_at = NULL
    RETURNING id INTO v_item;

    INSERT INTO cooperative_harvest_batches
      (inventory_id, source_farmer_id, source_farmer_name, source_crop_id,
       inventory_transaction_id, original_quantity, unit, received_at, recorded_by)
    VALUES (v_item, v_ret.farmer_id, v_ret.farmer_name, v_ret.crop_id,
            v_tx, p_quantity, v_unit, NOW(), auth.uid());

    UPDATE cooperative_inventory
       SET quantity_on_hand = quantity_on_hand + p_quantity, last_restocked_at = NOW()
     WHERE id = v_item;

    INSERT INTO inventory_transactions
      (id, inventory_id, transaction_type, quantity, reference_id, reference_type, notes, recorded_by)
    VALUES (v_tx, v_item, 'harvest_received', p_quantity, v_receipt, 'program_return',
            'Harvest return: ' || COALESCE(v_prog, 'program'), auth.uid());

  END IF;

  INSERT INTO program_return_receipts
    (id, return_id, quantity, note, recorded_by, recorded_by_name, recorded_by_role,
     inventory_id, inventory_transaction_id)
  VALUES (v_receipt, p_return_id, p_quantity, v_note, auth.uid(), v_name, v_role, v_item, v_tx);

  v_new := v_ret.received_quantity + p_quantity;
  UPDATE program_returns
     SET received_quantity = v_new,
         status = CASE WHEN v_new >= due_quantity THEN 'received' ELSE 'partial' END
   WHERE id = p_return_id;

  INSERT INTO program_return_events
    (return_id, event_type, quantity, quantity_after, reason, actor_id, actor_name, actor_role)
  VALUES (p_return_id, 'receipt', p_quantity, v_new, v_note, auth.uid(), v_name, v_role);

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (v_ret.farmer_id, 'program', 'Harvest Return Received',
          'The cooperative recorded ' || p_quantity || ' ' || v_ret.unit || ' ' || v_ret.crop_name ||
            ' for ' || COALESCE(v_prog, 'your program') || '.',
          FALSE, NOW(), '/farmer/profile/programs/enrolled');
  RETURN v_new;
END;
$function$;
REVOKE ALL ON FUNCTION public.record_program_return_receipt(UUID, NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_program_return_receipt(UUID, NUMERIC, TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  A Harvest Return program no longer lists return_crop as missing:
--     SELECT program_name, public.program_missing_fields(cp) FROM cooperative_programs cp WHERE benefit_type = 'revenue_share';
-- V2  The new column exists, and crop_id may be empty:
--     SELECT column_name, is_nullable FROM information_schema.columns
--      WHERE table_name = 'program_returns' AND column_name IN ('crop_id', 'inventory_item_id');
-- V3  After a test receipt: the same inventory item went UP by the received quantity:
--     SELECT t.inventory_id, t.transaction_type, t.quantity, t.reference_type
--       FROM inventory_transactions t WHERE t.reference_type = 'program_return' ORDER BY t.created_at DESC LIMIT 5;
