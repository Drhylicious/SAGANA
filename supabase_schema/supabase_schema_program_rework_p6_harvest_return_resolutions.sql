-- ============================================================
-- SAGANA — Program Management rework, PROPOSAL 12:
--          HARVEST RETURN + FAILED-OUTCOME RESOLUTIONS
--
-- NOT APPLIED — run it yourself in the Supabase SQL editor, once, AFTER the
-- Phase 5 completion script (…_p5_completion_rules.sql). One transaction.
--
-- WHAT IT ADDS
--   program_returns          one row per SUCCESSFUL outcome in a Harvest Return
--                            program: what is due, what was received, status
--   program_return_receipts  every physical receipt (partial receipts allowed)
--   program_return_events    immutable history: created / adjusted / receipt / closed
--   program_failure_resolutions  append-only log of the resolution chosen for a
--                            FAILED outcome (default: Pending Cooperative Decision)
--   program_settings         configurable policy values (underreporting tolerance,
--                            OFF until the cooperative decides)
--   finalize_program_outcome()   re-issued: also opens the return / the pending
--                            resolution. Nothing else changes in it.
--   adjust_program_return()      change the quantity due; REASON REQUIRED; history
--   record_program_return_receipt()  confirmed quantity received -> Cooperative
--                            Inventory (Harvest Stock) + ledger, never more than due
--   close_program_return()       close with less than due; DOCUMENTED REASON; no penalty
--   record_failed_resolution()   one of four resolutions + a note; NO side effects
--   set_underreport_tolerance()  Manager only; NULL = off
--   program_completion_blockers() re-issued: open returns now block completion
--
-- RULES KEPT
--   * Inventory moves ONLY for quantities actually received and confirmed.
--   * A shortfall is closed with a documented reason: no penalty, no deduction,
--     no loan, no change to patronage.
--   * A resolution never changes another record and never blocks an assistance
--     request (the assistance workflow is the next script).
--   * Nothing is ever deleted: returns, receipts, events and resolutions are kept.
--
-- CODE-prefixed errors the app turns into friendly messages:
--   RETURN_CLOSED  RETURN_OVER_RECEIPT  RETURN_REASON  RESOLUTION_INVALID  NOT_ALLOWED
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.complete_program(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Run the Phase 5 completion script first.';
  END IF;
  IF to_regprocedure('public._coop_inventory_guard()') IS NULL THEN
    RAISE EXCEPTION 'The Cooperative Harvest Phase 2 script must be applied first.';
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- 1. Settings (policy values the cooperative has not decided stay OFF)
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.program_settings (
  key           TEXT PRIMARY KEY,
  numeric_value NUMERIC,
  updated_by    UUID,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO public.program_settings (key, numeric_value)
VALUES ('underreport_tolerance_percent', NULL)   -- NULL = OFF (pending decision)
ON CONFLICT (key) DO NOTHING;

ALTER TABLE public.program_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "program_settings: staff read" ON public.program_settings;
CREATE POLICY "program_settings: staff read" ON public.program_settings
  FOR SELECT TO authenticated USING (public.is_staff());
REVOKE ALL ON public.program_settings FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.program_settings TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 2. Returns, receipts, events
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.program_returns (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  program_id         UUID NOT NULL REFERENCES public.cooperative_programs(id),
  program_member_id  UUID NOT NULL UNIQUE REFERENCES public.program_members(id),
  farmer_id          UUID NOT NULL,
  farmer_name        TEXT,
  outcome_report_id  UUID REFERENCES public.program_outcome_reports(id),
  crop_id            UUID NOT NULL,                 -- crop_master id
  crop_name          TEXT NOT NULL,
  unit               TEXT NOT NULL,
  original_quantity  NUMERIC(12,2) NOT NULL CHECK (original_quantity > 0),
  due_quantity       NUMERIC(12,2) NOT NULL CHECK (due_quantity > 0),
  received_quantity  NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (received_quantity >= 0),
  status             TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'partial', 'received', 'closed_short')),
  -- What the Farmer reported versus what the Officer verified (information only).
  reported_quantity  NUMERIC(12,2),
  verified_quantity  NUMERIC(12,2),
  underreport_flag   BOOLEAN NOT NULL DEFAULT FALSE,
  closed_reason      TEXT,
  closed_by          UUID,
  closed_by_name     TEXT,
  closed_at          TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT program_returns_received_within_due CHECK (received_quantity <= due_quantity),
  CONSTRAINT program_returns_closed_has_reason
    CHECK (status <> 'closed_short' OR (closed_reason IS NOT NULL AND btrim(closed_reason) <> ''))
);
CREATE INDEX IF NOT EXISTS program_returns_program ON public.program_returns (program_id, status);
CREATE INDEX IF NOT EXISTS program_returns_farmer  ON public.program_returns (farmer_id);

CREATE TABLE IF NOT EXISTS public.program_return_receipts (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  return_id                UUID NOT NULL REFERENCES public.program_returns(id),
  quantity                 NUMERIC(12,2) NOT NULL CHECK (quantity > 0),
  note                     TEXT,
  received_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  recorded_by              UUID,
  recorded_by_name         TEXT,
  recorded_by_role         TEXT,
  inventory_id             UUID,
  inventory_transaction_id UUID
);
CREATE INDEX IF NOT EXISTS program_return_receipts_return ON public.program_return_receipts (return_id, received_at);

CREATE TABLE IF NOT EXISTS public.program_return_events (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  return_id       UUID NOT NULL REFERENCES public.program_returns(id),
  event_type      TEXT NOT NULL CHECK (event_type IN ('created', 'adjusted', 'receipt', 'closed')),
  quantity_before NUMERIC(12,2),
  quantity_after  NUMERIC(12,2),
  quantity        NUMERIC(12,2),
  reason          TEXT,
  actor_id        UUID,
  actor_name      TEXT,
  actor_role      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS program_return_events_return ON public.program_return_events (return_id, created_at);

CREATE TABLE IF NOT EXISTS public.program_failure_resolutions (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  program_member_id  UUID NOT NULL REFERENCES public.program_members(id),
  program_id         UUID NOT NULL REFERENCES public.cooperative_programs(id),
  farmer_id          UUID NOT NULL,
  outcome_report_id  UUID REFERENCES public.program_outcome_reports(id),
  resolution         TEXT NOT NULL CHECK (resolution IN (
                       'closed_no_further_obligation',
                       'eligible_for_reassessment',
                       'referred_for_loan_assessment',
                       'pending_cooperative_decision')),
  note               TEXT,
  decided_by         UUID,                -- NULL = the automatic default
  decided_by_name    TEXT,
  decided_by_role    TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS program_failure_resolutions_member
  ON public.program_failure_resolutions (program_member_id, created_at DESC);

-- History is never rewritten or removed.
CREATE OR REPLACE FUNCTION public._program_record_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  RAISE EXCEPTION 'This record is part of the permanent history and cannot be changed or deleted.';
END $$;

DROP TRIGGER IF EXISTS trg_immutable ON public.program_return_receipts;
CREATE TRIGGER trg_immutable BEFORE UPDATE OR DELETE ON public.program_return_receipts
  FOR EACH ROW EXECUTE FUNCTION public._program_record_immutable();
DROP TRIGGER IF EXISTS trg_immutable ON public.program_return_events;
CREATE TRIGGER trg_immutable BEFORE UPDATE OR DELETE ON public.program_return_events
  FOR EACH ROW EXECUTE FUNCTION public._program_record_immutable();
DROP TRIGGER IF EXISTS trg_immutable ON public.program_failure_resolutions;
CREATE TRIGGER trg_immutable BEFORE UPDATE OR DELETE ON public.program_failure_resolutions
  FOR EACH ROW EXECUTE FUNCTION public._program_record_immutable();

CREATE OR REPLACE FUNCTION public._program_return_no_delete()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  RAISE EXCEPTION 'A harvest return record is kept permanently and cannot be deleted.';
END $$;
DROP TRIGGER IF EXISTS trg_no_delete ON public.program_returns;
CREATE TRIGGER trg_no_delete BEFORE DELETE ON public.program_returns
  FOR EACH ROW EXECUTE FUNCTION public._program_return_no_delete();

DROP TRIGGER IF EXISTS trg_updated_at ON public.program_returns;
CREATE TRIGGER trg_updated_at BEFORE UPDATE ON public.program_returns
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Every change lands in the existing accountability trail.
DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.program_returns;
CREATE TRIGGER trg_audit_staff_change
  AFTER INSERT OR UPDATE OR DELETE ON public.program_returns
  FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change('programs', '');
DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.program_failure_resolutions;
CREATE TRIGGER trg_audit_staff_change
  AFTER INSERT OR UPDATE OR DELETE ON public.program_failure_resolutions
  FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change('programs', '');

ALTER TABLE public.program_returns             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_return_receipts     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_return_events       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_failure_resolutions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "program_returns: staff read" ON public.program_returns;
CREATE POLICY "program_returns: staff read" ON public.program_returns
  FOR SELECT TO authenticated USING (public.is_staff());
DROP POLICY IF EXISTS "program_return_receipts: staff read" ON public.program_return_receipts;
CREATE POLICY "program_return_receipts: staff read" ON public.program_return_receipts
  FOR SELECT TO authenticated USING (public.is_staff());
DROP POLICY IF EXISTS "program_return_events: staff read" ON public.program_return_events;
CREATE POLICY "program_return_events: staff read" ON public.program_return_events
  FOR SELECT TO authenticated USING (public.is_staff());
DROP POLICY IF EXISTS "program_failure_resolutions: staff read" ON public.program_failure_resolutions;
CREATE POLICY "program_failure_resolutions: staff read" ON public.program_failure_resolutions
  FOR SELECT TO authenticated USING (public.is_staff());
REVOKE ALL ON public.program_returns, public.program_return_receipts,
              public.program_return_events, public.program_failure_resolutions
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.program_returns, public.program_return_receipts,
                public.program_return_events, public.program_failure_resolutions
  TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 3. Opening a return / a pending resolution (internal helpers)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._program_open_return(p_report_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_r    program_outcome_reports%ROWTYPE;
  v_p    cooperative_programs%ROWTYPE;
  v_crop TEXT;
  v_name TEXT;
  v_tol  NUMERIC;
  v_flag BOOLEAN := FALSE;
  v_id   UUID;
BEGIN
  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id;
  SELECT * INTO v_p FROM cooperative_programs   WHERE id = v_r.program_id;
  IF v_p.benefit_type IS DISTINCT FROM 'revenue_share'
     OR v_p.return_crop_id IS NULL
     OR COALESCE(v_p.return_quantity, 0) <= 0
     OR NULLIF(btrim(COALESCE(v_p.return_unit, '')), '') IS NULL THEN
    RETURN NULL;                       -- not a Harvest Return program
  END IF;
  SELECT id INTO v_id FROM program_returns WHERE program_member_id = v_r.program_member_id;
  IF FOUND THEN RETURN v_id; END IF;

  SELECT crop_name INTO v_crop FROM crop_master WHERE id = v_p.return_crop_id;
  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_r.farmer_id;
  SELECT numeric_value INTO v_tol FROM program_settings WHERE key = 'underreport_tolerance_percent';

  -- Information only: the verified harvest is more than the reported one by
  -- more than the configured tolerance. Off while no tolerance is set.
  IF v_tol IS NOT NULL
     AND v_r.quantity_harvested IS NOT NULL AND v_r.verified_quantity IS NOT NULL
     AND lower(btrim(COALESCE(v_r.quantity_unit, ''))) = lower(btrim(COALESCE(v_r.verified_unit, '')))
     AND v_r.verified_quantity > v_r.quantity_harvested * (1 + v_tol / 100.0) THEN
    v_flag := TRUE;
  END IF;

  INSERT INTO program_returns (
    program_id, program_member_id, farmer_id, farmer_name, outcome_report_id,
    crop_id, crop_name, unit, original_quantity, due_quantity,
    reported_quantity, verified_quantity, underreport_flag
  ) VALUES (
    v_r.program_id, v_r.program_member_id, v_r.farmer_id, v_name, v_r.id,
    v_p.return_crop_id, COALESCE(v_crop, 'Crop'), btrim(v_p.return_unit),
    v_p.return_quantity, v_p.return_quantity,
    v_r.quantity_harvested, v_r.verified_quantity, v_flag
  ) RETURNING id INTO v_id;

  INSERT INTO program_return_events (return_id, event_type, quantity_after, actor_id, actor_name, actor_role)
  SELECT v_id, 'created', v_p.return_quantity, auth.uid(), a_name, a_role FROM public._outcome_actor();

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (v_r.farmer_id, 'program', 'Harvest Return Due',
          'Your outcome for ' || v_p.program_name || ' was successful. The cooperative will record your harvest return of '
            || v_p.return_quantity || ' ' || btrim(v_p.return_unit) || ' ' || COALESCE(v_crop, '') || ' when it is received.',
          FALSE, NOW(), '/farmer/profile/programs/enrolled');
  RETURN v_id;
END;
$function$;
REVOKE ALL ON FUNCTION public._program_open_return(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._program_open_resolution(p_report_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_r program_outcome_reports%ROWTYPE;
BEGIN
  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id;
  IF EXISTS (SELECT 1 FROM program_failure_resolutions WHERE program_member_id = v_r.program_member_id) THEN
    RETURN;
  END IF;
  INSERT INTO program_failure_resolutions
    (program_member_id, program_id, farmer_id, outcome_report_id, resolution)
  VALUES (v_r.program_member_id, v_r.program_id, v_r.farmer_id, v_r.id, 'pending_cooperative_decision');
END;
$function$;
REVOKE ALL ON FUNCTION public._program_open_resolution(UUID) FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 4. finalize_program_outcome(): the Phase 3 function, plus the two openers
--    (only the PERFORM block before the notification is new)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.finalize_program_outcome(
  p_report_id     UUID,
  p_final_outcome TEXT,
  p_note          TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid  UUID := auth.uid();
  v_r    program_outcome_reports%ROWTYPE;
  v_note TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_name TEXT;
  v_role TEXT;
  v_prog TEXT;
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
    RAISE EXCEPTION 'An Officer must complete the field verification first.';
  END IF;
  IF (p_final_outcome <> v_r.reported_outcome OR v_r.verification_finding = 'disputes') AND v_note IS NULL THEN
    RAISE EXCEPTION 'Explain the decision: it differs from the report or the field verification disputed it.';
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

  -- NEW: a Successful Harvest Return outcome opens the return to be received;
  -- a Failed outcome starts at "Pending Cooperative Decision". No loan, no
  -- penalty, no stock movement happens here.
  IF p_final_outcome = 'successful' THEN
    PERFORM public._program_open_return(p_report_id);
  ELSE
    PERFORM public._program_open_resolution(p_report_id);
  END IF;

  SELECT program_name INTO v_prog FROM cooperative_programs WHERE id = v_r.program_id;
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (v_r.farmer_id, 'program',
          CASE p_final_outcome WHEN 'successful' THEN 'Program Outcome: Successful' ELSE 'Program Outcome: Failed' END,
          'Your outcome for ' || COALESCE(v_prog, 'the program') || ' was confirmed as ' || p_final_outcome || '.',
          FALSE, NOW(), '/farmer/profile/programs/enrolled');
END;
$function$;
REVOKE ALL ON FUNCTION public.finalize_program_outcome(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_program_outcome(UUID, TEXT, TEXT) TO authenticated;

-- Outcomes finalized before this script get the same starting records (idempotent).
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT id, final_outcome FROM program_outcome_reports WHERE status = 'finalized' LOOP
    IF r.final_outcome = 'successful' THEN
      PERFORM public._program_open_return(r.id);
    ELSIF r.final_outcome = 'failed' THEN
      PERFORM public._program_open_resolution(r.id);
    END IF;
  END LOOP;
END $$;

-- ════════════════════════════════════════════════════════════
-- 5. Staff actions on a return
-- ════════════════════════════════════════════════════════════
-- Change the quantity due. A reason is required; the original quantity stays on
-- record and the change is written to the history.
CREATE OR REPLACE FUNCTION public.adjust_program_return(
  p_return_id    UUID,
  p_new_quantity NUMERIC,
  p_reason       TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ret    program_returns%ROWTYPE;
  v_reason TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can adjust a harvest return.';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'RETURN_REASON: A reason is required to change the quantity.';
  END IF;
  SELECT * INTO v_ret FROM program_returns WHERE id = p_return_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'RETURN_CLOSED: Harvest return not found.';
  END IF;
  IF v_ret.status IN ('received', 'closed_short') THEN
    RAISE EXCEPTION 'RETURN_CLOSED: This harvest return is already closed.';
  END IF;
  IF p_new_quantity IS NULL OR p_new_quantity <= 0 OR p_new_quantity <> round(p_new_quantity, 2) THEN
    RAISE EXCEPTION 'RETURN_REASON: Enter a quantity greater than zero.';
  END IF;
  IF p_new_quantity < v_ret.received_quantity THEN
    RAISE EXCEPTION 'RETURN_OVER_RECEIPT: The quantity due cannot be lower than what was already received.';
  END IF;
  IF p_new_quantity = v_ret.due_quantity THEN
    RETURN;
  END IF;

  UPDATE program_returns
     SET due_quantity = p_new_quantity,
         status = CASE WHEN received_quantity >= p_new_quantity THEN 'received'
                       WHEN received_quantity > 0 THEN 'partial' ELSE 'pending' END
   WHERE id = p_return_id;

  INSERT INTO program_return_events
    (return_id, event_type, quantity_before, quantity_after, reason, actor_id, actor_name, actor_role)
  SELECT p_return_id, 'adjusted', v_ret.due_quantity, p_new_quantity, v_reason, auth.uid(), a_name, a_role
    FROM public._outcome_actor();
END;
$function$;
REVOKE ALL ON FUNCTION public.adjust_program_return(UUID, NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.adjust_program_return(UUID, NUMERIC, TEXT) TO authenticated;

-- Record a physical receipt (full or partial). The confirmed quantity is added
-- to Cooperative Inventory as Harvest Stock for that Farmer, crop and unit, with
-- the same ledger and batch records a Farmer delivery produces.
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

  SELECT program_name INTO v_prog FROM cooperative_programs WHERE id = v_ret.program_id;
  INSERT INTO inventory_transactions
    (id, inventory_id, transaction_type, quantity, reference_id, reference_type, notes, recorded_by)
  VALUES (v_tx, v_item, 'harvest_received', p_quantity, v_receipt, 'program_return',
          'Harvest return: ' || COALESCE(v_prog, 'program'), auth.uid());

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

-- Close a return that will not be received in full. A documented reason is
-- required. No penalty, deduction, loan or patronage change follows from it.
CREATE OR REPLACE FUNCTION public.close_program_return(
  p_return_id UUID,
  p_reason    TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ret    program_returns%ROWTYPE;
  v_reason TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
  v_name   TEXT;
  v_role   TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can close a harvest return.';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'RETURN_REASON: A reason is required to close a return with less than was due.';
  END IF;
  SELECT * INTO v_ret FROM program_returns WHERE id = p_return_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'RETURN_CLOSED: Harvest return not found.';
  END IF;
  IF v_ret.status IN ('received', 'closed_short') THEN
    RAISE EXCEPTION 'RETURN_CLOSED: This harvest return is already closed.';
  END IF;

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();
  UPDATE program_returns
     SET status = 'closed_short', closed_reason = v_reason,
         closed_by = auth.uid(), closed_by_name = v_name, closed_at = NOW()
   WHERE id = p_return_id;

  INSERT INTO program_return_events
    (return_id, event_type, quantity_before, quantity_after, reason, actor_id, actor_name, actor_role)
  VALUES (p_return_id, 'closed', v_ret.due_quantity, v_ret.received_quantity, v_reason, auth.uid(), v_name, v_role);
END;
$function$;
REVOKE ALL ON FUNCTION public.close_program_return(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.close_program_return(UUID, TEXT) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 6. Failed outcome: record the resolution (no side effects)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.record_failed_resolution(
  p_program_member_id UUID,
  p_resolution        TEXT,
  p_note              TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_m    program_members%ROWTYPE;
  v_note TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_name TEXT;
  v_role TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can record a resolution.';
  END IF;
  IF p_resolution NOT IN ('closed_no_further_obligation', 'eligible_for_reassessment',
                          'referred_for_loan_assessment', 'pending_cooperative_decision') THEN
    RAISE EXCEPTION 'RESOLUTION_INVALID: Choose one of the listed resolutions.';
  END IF;
  IF v_note IS NULL THEN
    RAISE EXCEPTION 'RESOLUTION_INVALID: A note is required.';
  END IF;
  SELECT * INTO v_m FROM program_members WHERE id = p_program_member_id FOR UPDATE;
  IF NOT FOUND OR COALESCE(v_m.distribution_outcome, '') <> 'failed' THEN
    RAISE EXCEPTION 'RESOLUTION_INVALID: Only a Failed outcome has a resolution.';
  END IF;

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();
  -- Appended, never edited: the previous decision stays in the history.
  INSERT INTO program_failure_resolutions
    (program_member_id, program_id, farmer_id, outcome_report_id, resolution, note,
     decided_by, decided_by_name, decided_by_role)
  SELECT v_m.id, v_m.program_id, v_m.farmer_id,
         (SELECT r.id FROM program_outcome_reports r
           WHERE r.program_member_id = v_m.id AND r.status = 'finalized'
           ORDER BY r.finalized_at DESC NULLS LAST LIMIT 1),
         p_resolution, v_note, auth.uid(), v_name, v_role;
END;
$function$;
REVOKE ALL ON FUNCTION public.record_failed_resolution(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_failed_resolution(UUID, TEXT, TEXT) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 7. Policy value (Manager only) and reads
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.set_underreport_tolerance(p_percent NUMERIC)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role = 'admin') THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager can change this setting.';
  END IF;
  IF p_percent IS NOT NULL AND (p_percent < 0 OR p_percent > 100) THEN
    RAISE EXCEPTION 'RESOLUTION_INVALID: Enter a percentage between 0 and 100, or leave it empty to turn it off.';
  END IF;
  UPDATE program_settings
     SET numeric_value = p_percent, updated_by = auth.uid(), updated_at = NOW()
   WHERE key = 'underreport_tolerance_percent';
END;
$function$;
REVOKE ALL ON FUNCTION public.set_underreport_tolerance(NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_underreport_tolerance(NUMERIC) TO authenticated;

-- Staff: returns (one program or all) with receipts and history.
CREATE OR REPLACE FUNCTION public.get_program_returns(p_program_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can read harvest returns.';
  END IF;
  RETURN (
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.created_at DESC), '[]'::jsonb)
    FROM (
      SELECT r.created_at,
             to_jsonb(r) || jsonb_build_object(
               'program_name', cp.program_name,
               'receipts', COALESCE((SELECT jsonb_agg(to_jsonb(rc) ORDER BY rc.received_at)
                                       FROM program_return_receipts rc WHERE rc.return_id = r.id), '[]'::jsonb),
               'events',   COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.created_at)
                                       FROM program_return_events e WHERE e.return_id = r.id), '[]'::jsonb)
             ) AS j
      FROM program_returns r
      JOIN cooperative_programs cp ON cp.id = r.program_id
      WHERE p_program_id IS NULL OR r.program_id = p_program_id
    ) x
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.get_program_returns(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_program_returns(UUID) TO authenticated;

-- Staff: the current resolution of each Failed member (latest row) + history.
CREATE OR REPLACE FUNCTION public.get_failed_resolutions(p_program_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can read resolutions.';
  END IF;
  RETURN (
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.created_at DESC), '[]'::jsonb)
    FROM (
      SELECT DISTINCT ON (f.program_member_id) f.created_at,
             to_jsonb(f) || jsonb_build_object(
               'history_count', (SELECT count(*) FROM program_failure_resolutions h
                                  WHERE h.program_member_id = f.program_member_id)
             ) AS j
      FROM program_failure_resolutions f
      WHERE p_program_id IS NULL OR f.program_id = p_program_id
      ORDER BY f.program_member_id, f.created_at DESC
    ) x
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.get_failed_resolutions(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_failed_resolutions(UUID) TO authenticated;

-- Staff: current policy values.
CREATE OR REPLACE FUNCTION public.get_program_settings()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can read this.';
  END IF;
  RETURN COALESCE((SELECT jsonb_object_agg(key, numeric_value) FROM program_settings), '{}'::jsonb);
END;
$function$;
REVOKE ALL ON FUNCTION public.get_program_settings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_program_settings() TO authenticated;

-- A Farmer's own returns and the PLAIN status of their failed outcomes: no staff
-- names, no internal notes, no reason text (only a status).
CREATE OR REPLACE FUNCTION public.get_my_program_returns()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT jsonb_build_object(
    'returns', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', r.id, 'program_id', r.program_id, 'program_member_id', r.program_member_id,
               'crop_name', r.crop_name, 'unit', r.unit,
               'due_quantity', r.due_quantity, 'received_quantity', r.received_quantity,
               'status', r.status, 'created_at', r.created_at) ORDER BY r.created_at DESC)
      FROM program_returns r WHERE r.farmer_id = auth.uid()), '[]'::jsonb),
    'resolutions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'program_member_id', x.program_member_id, 'program_id', x.program_id,
               'resolution', x.resolution))
      FROM (SELECT DISTINCT ON (f.program_member_id) f.*
              FROM program_failure_resolutions f WHERE f.farmer_id = auth.uid()
             ORDER BY f.program_member_id, f.created_at DESC) x), '[]'::jsonb)
  );
$$;
REVOKE ALL ON FUNCTION public.get_my_program_returns() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_program_returns() TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 8. Completion: an open return now blocks Mark as Completed
--    (the Phase 5 function, plus 'open_returns')
-- ════════════════════════════════════════════════════════════
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
  v_products integer := 0;
  v_pending  integer := 0;
BEGIN
  SELECT * INTO v_p FROM cooperative_programs WHERE id = p_program_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_p.program_purpose = 'distribution' THEN
    SELECT count(*) INTO v_await
      FROM program_members m
     WHERE m.program_id = p_program_id
       AND m.status = 'active'
       AND m.distributed_at IS NOT NULL
       AND COALESCE(m.distribution_outcome, 'pending') NOT IN ('thriving', 'failed');
    SELECT count(*) INTO v_returns
      FROM program_returns r
     WHERE r.program_id = p_program_id AND r.status IN ('pending', 'partial');
  ELSE
    SELECT count(*) INTO v_products FROM program_products WHERE program_id = p_program_id AND is_available;
    SELECT count(*) INTO v_pending  FROM program_product_purchases WHERE program_id = p_program_id AND status = 'pending';
  END IF;

  RETURN jsonb_build_object(
    'awaiting_outcome',  v_await,
    'open_returns',      v_returns,
    'active_products',   v_products,
    'pending_purchases', v_pending
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.program_completion_blockers(uuid) FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 9. Officer permission gate (all of these are Dashboard actions)
-- ════════════════════════════════════════════════════════════
INSERT INTO public.staff_permission_targets (kind, name, module) VALUES
  ('rpc',   'adjust_program_return',         'dashboard'),
  ('rpc',   'record_program_return_receipt', 'dashboard'),
  ('rpc',   'close_program_return',          'dashboard'),
  ('rpc',   'record_failed_resolution',      'dashboard'),
  ('table', 'program_returns',               'dashboard'),
  ('table', 'program_failure_resolutions',   'dashboard')
ON CONFLICT (kind, name) DO NOTHING;
-- set_underreport_tolerance is Manager-only inside the function (like the
-- Balik-Tangkilik actions), so it is deliberately not given to any Officer module.

COMMIT;

-- ════════════════════════════════════════════════════════════
-- VERIFICATION (run after the script; read-only)
-- ════════════════════════════════════════════════════════════
-- V1  The new objects exist.
--   SELECT to_regclass('public.program_returns'), to_regclass('public.program_return_receipts'),
--          to_regclass('public.program_return_events'), to_regclass('public.program_failure_resolutions'),
--          to_regclass('public.program_settings');
-- V2  The tolerance is OFF (numeric_value IS NULL).
--   SELECT * FROM public.program_settings;
-- V3  Gate rows.
--   SELECT kind, name, module FROM staff_permission_targets
--    WHERE name IN ('adjust_program_return','record_program_return_receipt','close_program_return',
--                   'record_failed_resolution','program_returns','program_failure_resolutions') ORDER BY 1,2;
-- V4  Backfill: one return per finalized Successful Harvest Return outcome; one
--     resolution row per finalized Failed outcome.
--   SELECT status, count(*) FROM program_returns GROUP BY 1;
--   SELECT resolution, count(*) FROM program_failure_resolutions GROUP BY 1;
-- V5  Completion now reports open returns.
--   SELECT public.program_completion_blockers(id) FROM cooperative_programs LIMIT 3;
-- V6  Reconciliation: confirmed receipts equal the inventory receipts they created.
--   SELECT r.id, r.received_quantity,
--          (SELECT COALESCE(sum(quantity),0) FROM program_return_receipts WHERE return_id = r.id) AS receipts
--     FROM program_returns r
--    WHERE r.received_quantity <> (SELECT COALESCE(sum(quantity),0) FROM program_return_receipts WHERE return_id = r.id);
--   -- expect 0 rows
