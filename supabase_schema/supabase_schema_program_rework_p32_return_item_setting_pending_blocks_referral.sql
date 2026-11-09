-- ============================================================
-- SAGANA — p32: return item set on the Inventory item, pending decisions block completion, loan referral notice
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after p30 (p31 is optional: this script
-- removes p31's rule if it was run). No data is deleted. Run THIS BEFORE using the new app version.
--
--   1. REVERSES p31. The Farmer does not always return the item given, so the p31 rule that forced the return
--      item to stay empty is removed.
--   2. cooperative_inventory.return_item_id  "When returned, it comes back as": the Inventory item the
--      cooperative receives back when a Farmer returns THIS item in a Harvest Return program
--      (Pechay Seeds -> Pechay produce, Pig -> Pig). Empty = the same item. Only an active, cooperative-owned
--      item can be chosen, never the item itself.
--   3. When an item is handed to a Harvest Return Farmer, their return item is saved from that setting (a
--      snapshot, so a later change to the setting does not rewrite what an earlier Farmer was told). Whatever
--      screen distributes, the database does this.
--   4. _program_open_return(): the return is credited to  the Farmer's saved return item, else the given item's
--      setting, else an older program default, else the item given. Returns already open are not touched.
--   5. program_completion_blockers(): a program cannot be marked Completed while a Failed outcome still has
--      "Pending Cooperative Decision" as its latest decision (new count: pending_decisions). complete_program()
--      already refuses on ANY blocker above zero, so nothing else changes.
--   6. A decision of "Referred for Loan Assessment" notifies the loans staff and the Farmer. It creates NO loan,
--      NO request and NO record in Loan Management: the Farmer requests items on loan the normal way.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.program_failure_resolutions') IS NULL
     OR to_regprocedure('public.set_member_return_arrangement(uuid,uuid,numeric)') IS NULL
     OR to_regprocedure('public.notify_staff(text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Apply p25 (and the notification script) first.';
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- 1. Reverse p31
-- ════════════════════════════════════════════════════════════
DROP TRIGGER IF EXISTS trg_program_member_return_item_is_given ON public.program_members;
DROP FUNCTION IF EXISTS public._program_member_return_item_is_given();

-- ════════════════════════════════════════════════════════════
-- 2. The setting on the Inventory item
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.cooperative_inventory
  ADD COLUMN IF NOT EXISTS return_item_id UUID REFERENCES public.cooperative_inventory(id) ON DELETE SET NULL;

ALTER TABLE public.cooperative_inventory DROP CONSTRAINT IF EXISTS cooperative_inventory_return_item_chk;
ALTER TABLE public.cooperative_inventory
  ADD CONSTRAINT cooperative_inventory_return_item_chk CHECK (return_item_id IS NULL OR return_item_id <> id);

CREATE OR REPLACE FUNCTION public._inventory_return_item_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.return_item_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM cooperative_inventory t
                    WHERE t.id = NEW.return_item_id AND t.is_active
                      AND t.archived_at IS NULL AND t.source_farmer_id IS NULL) THEN
      RAISE EXCEPTION 'RETURN_ITEM: Choose an active cooperative Inventory item for what comes back.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_inventory_return_item_guard ON public.cooperative_inventory;
CREATE TRIGGER trg_inventory_return_item_guard
  BEFORE INSERT OR UPDATE OF return_item_id ON public.cooperative_inventory
  FOR EACH ROW EXECUTE FUNCTION public._inventory_return_item_guard();

-- ════════════════════════════════════════════════════════════
-- 3. Snapshot the return item when the item is handed out
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._program_members_snapshot_return_item()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.return_item_id IS NULL
     AND EXISTS (SELECT 1 FROM cooperative_programs WHERE id = NEW.program_id AND benefit_type = 'revenue_share') THEN
    SELECT ci.return_item_id INTO NEW.return_item_id
      FROM cooperative_inventory ci WHERE ci.id = NEW.inventory_item_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_program_members_snapshot_return_item ON public.program_members;
CREATE TRIGGER trg_program_members_snapshot_return_item
  BEFORE UPDATE OF distributed_at ON public.program_members
  FOR EACH ROW
  WHEN (OLD.distributed_at IS NULL AND NEW.distributed_at IS NOT NULL)
  EXECUTE FUNCTION public._program_members_snapshot_return_item();

-- ════════════════════════════════════════════════════════════
-- 4. The return is credited to the item the Farmer was told (as p25, plus the Inventory setting)
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
  v_item := COALESCE(
              v_m.return_item_id,
              (SELECT g.return_item_id FROM cooperative_inventory g WHERE g.id = v_m.inventory_item_id),
              v_p.return_item_id,
              v_m.inventory_item_id);
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

-- ════════════════════════════════════════════════════════════
-- 5. A pending decision blocks "Mark as Completed" (as p25, plus pending_decisions)
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
  v_pending  integer := 0;
  v_orders   integer := 0;
  v_stock    integer := 0;
BEGIN
  SELECT * INTO v_p FROM cooperative_programs WHERE id = p_program_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_p.program_purpose = 'distribution' THEN
    -- Only a Harvest Return program has outcomes, returns and decisions. A Free Distribution is complete
    -- once the items are handed out.
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
      SELECT count(*) INTO v_pending
        FROM program_members m
       WHERE m.program_id = p_program_id
         AND m.distribution_outcome = 'failed'
         AND (SELECT f.resolution FROM program_failure_resolutions f
               WHERE f.program_member_id = m.id
               ORDER BY f.created_at DESC LIMIT 1) = 'pending_cooperative_decision';
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
    'pending_decisions', v_pending,
    'open_orders',       v_orders,
    'allocated_stock',   v_stock
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.program_completion_blockers(uuid) FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 6. Loan referral: tell the loans staff and the Farmer. Creates nothing in Loan Management.
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._notify_loan_referral()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_name TEXT;
  v_prog TEXT;
BEGIN
  SELECT full_name INTO v_name FROM user_information WHERE user_id = NEW.farmer_id;
  SELECT program_name INTO v_prog FROM cooperative_programs WHERE id = NEW.program_id;
  PERFORM public.notify_staff(
    'program',
    'Loan Assessment Referral',
    COALESCE(v_name, 'A Farmer') || ' was referred for a loan assessment after a failed outcome in ' ||
      COALESCE(v_prog, 'a program') || '. No loan was created: the Farmer can now request items on loan.',
    '/admin/loans/requests');
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (NEW.farmer_id, 'program', 'Loan Assessment Referral',
          'The cooperative referred you for a loan assessment. You may request items on loan from the Loan Item ' ||
            'Catalog. This is not a loan yet: your request will be assessed and approved as usual.',
          FALSE, NOW(), '/farmer/profile/loans/request');
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'loan referral notice failed: %', SQLERRM;   -- a notice must never block the decision
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_loan_referral ON public.program_failure_resolutions;
CREATE TRIGGER trg_notify_loan_referral
  AFTER INSERT ON public.program_failure_resolutions
  FOR EACH ROW
  WHEN (NEW.resolution = 'referred_for_loan_assessment')
  EXECUTE FUNCTION public._notify_loan_referral();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECKS
-- ============================================================
-- V1  New column, guards and triggers exist (expect 3 triggers + the column):
--     SELECT column_name FROM information_schema.columns WHERE table_name = 'cooperative_inventory' AND column_name = 'return_item_id';
--     SELECT tgname FROM pg_trigger WHERE tgname IN ('trg_inventory_return_item_guard','trg_program_members_snapshot_return_item','trg_notify_loan_referral') AND NOT tgisinternal;
-- V2  The p31 rule is gone (expect 0 rows):
--     SELECT tgname FROM pg_trigger WHERE tgname = 'trg_program_member_return_item_is_given' AND NOT tgisinternal;
-- V3  Which items come back as something else (information):
--     SELECT g.item_name AS item, r.item_name AS comes_back_as FROM cooperative_inventory g JOIN cooperative_inventory r ON r.id = g.return_item_id;
-- V4  Programs a pending decision is holding open (information):
--     SELECT cp.program_name, public.program_completion_blockers(cp.id) ->> 'pending_decisions' AS pending
--       FROM cooperative_programs cp WHERE (public.program_completion_blockers(cp.id) ->> 'pending_decisions')::int > 0;
-- V5  Every decision on record, newest first (the history behind each label):
--     SELECT ui.full_name, f.resolution, f.note, f.decided_by_name, f.decided_by_role, f.created_at
--       FROM program_failure_resolutions f LEFT JOIN user_information ui ON ui.user_id = f.farmer_id ORDER BY f.created_at DESC;
