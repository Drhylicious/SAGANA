-- ============================================================
-- SAGANA — Program Management rework, PHASE 5: COMPLETION AND PROTECTION RULES
--
-- Requires: the Phase 5A, 1, 3 and 4 scripts (already run). NOT APPLIED — run it
-- yourself once, then the verification block. One transaction: all or nothing.
--
-- WHAT IT DOES
--   1. Product Sales programs now have required fields too (name, type, photo,
--      description, budget). An existing Sales program that lacks them is shown
--      as Incomplete but keeps operating (nothing here blocks sales).
--   2. A program is closed by ONE action: complete_program(). The status can no
--      longer be edited directly, and a Completed program cannot be reopened
--      from the app.
--        Distribution:  every enrolled farmer who RECEIVED an item has a final
--                       outcome (Successful or Failed; earlier recorded outcomes
--                       count as final). Farmers who never received anything do
--                       not block completion.
--        Product Sales: every product is switched OFF and no purchase is pending.
--      Completing also declines any pending enrollment requests, each with a
--      recorded reason and a notice to the Farmer. Nobody is removed and no
--      history is touched.
--   3. Programs are NEVER deleted (not even an empty one).
--   4. Staff cannot withdraw an enrolled member (enrollment history is kept).
--   5. Staff cannot delete a product; switching it OFF is how it stops selling.
--   6. Manager AND Officer may complete a program; an Officer needs Manage
--      access on the Dashboard group (the Officer permission gate), a View Only
--      Officer is refused at the database.
--
-- Messages start with a CODE: the app turns each code into a plain, translated
-- sentence and keeps the technical text out of sight.
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. Required fields: Distribution (as before) and Product Sales (new)
-- ════════════════════════════════════════════════════════════
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
    CASE WHEN p.program_purpose = 'distribution' AND p.distribution_item_id IS NULL
                                                                    THEN 'item' END,
    CASE WHEN p.program_purpose = 'distribution' AND p.benefit_type = 'revenue_share'
          AND p.return_crop_id IS NULL                              THEN 'return_crop' END,
    CASE WHEN p.program_purpose = 'distribution' AND p.benefit_type = 'revenue_share'
          AND (p.return_quantity IS NULL OR p.return_quantity <= 0) THEN 'return_quantity' END,
    CASE WHEN p.program_purpose = 'distribution' AND p.benefit_type = 'revenue_share'
          AND (p.return_unit IS NULL OR btrim(p.return_unit) = '')  THEN 'return_unit' END
  ], NULL);
$$;

-- ════════════════════════════════════════════════════════════
-- 2. Completion
-- ════════════════════════════════════════════════════════════
-- What still stands in the way of completing a program (all zero = ready).
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
  v_products integer := 0;
  v_pending  integer := 0;
BEGIN
  SELECT * INTO v_p FROM cooperative_programs WHERE id = p_program_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_p.program_purpose = 'distribution' THEN
    -- Received an item but no FINAL outcome yet (an outcome recorded before the
    -- evidence workflow, 'thriving' or 'failed', is final).
    SELECT count(*) INTO v_await
      FROM program_members m
     WHERE m.program_id = p_program_id
       AND m.status = 'active'
       AND m.distributed_at IS NOT NULL
       AND COALESCE(m.distribution_outcome, 'pending') NOT IN ('thriving', 'failed');
  ELSE
    SELECT count(*) INTO v_products FROM program_products WHERE program_id = p_program_id AND is_available;
    SELECT count(*) INTO v_pending  FROM program_product_purchases WHERE program_id = p_program_id AND status = 'pending';
  END IF;

  RETURN jsonb_build_object(
    'awaiting_outcome', v_await,
    'active_products',  v_products,
    'pending_purchases', v_pending
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.program_completion_blockers(uuid) FROM PUBLIC, anon, authenticated;

-- For the screen: every active program with what is outstanding, in one call.
CREATE OR REPLACE FUNCTION public.get_programs_completion_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can see this.';
  END IF;
  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'program_id', cp.id,
             'blockers',   b.j,
             'ready',      NOT EXISTS (SELECT 1 FROM jsonb_each_text(b.j) e WHERE e.value::int > 0)
           )), '[]'::jsonb)
    FROM cooperative_programs cp
    CROSS JOIN LATERAL (SELECT public.program_completion_blockers(cp.id) AS j) b
    WHERE cp.status = 'active'
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.get_programs_completion_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_programs_completion_status() TO authenticated;

-- The ONE way a program becomes Completed.
CREATE OR REPLACE FUNCTION public.complete_program(p_program_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_p        cooperative_programs%ROWTYPE;
  v_b        jsonb;
  v_declined integer := 0;
  r          RECORD;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can complete a program.';
  END IF;

  SELECT * INTO v_p FROM cooperative_programs WHERE id = p_program_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROGRAM_NOT_FOUND: Program not found.';
  END IF;
  IF v_p.status = 'completed' THEN
    RAISE EXCEPTION 'PROGRAM_COMPLETED: This program is already completed.';
  END IF;

  v_b := public.program_completion_blockers(p_program_id);
  IF EXISTS (SELECT 1 FROM jsonb_each_text(v_b) e WHERE e.value::int > 0) THEN
    RAISE EXCEPTION 'PROGRAM_NOT_READY: This program still has unfinished work: %', v_b::text;
  END IF;

  -- Pending enrollment requests are declined with a recorded reason and a notice.
  FOR r IN
    SELECT id, farmer_id FROM program_enrollment_requests
     WHERE program_id = p_program_id AND status = 'pending'
     FOR UPDATE
  LOOP
    UPDATE program_enrollment_requests
       SET status = 'rejected', reviewed_by = auth.uid(), reviewed_at = NOW(),
           admin_notes = 'This program was completed and is no longer accepting members.'
     WHERE id = r.id;
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
    VALUES (r.farmer_id, 'program', 'Program Enrollment Declined',
            'Your enrollment request for ' || v_p.program_name ||
              ' was declined because the program was completed. You may join other open programs.',
            FALSE, NOW());
    v_declined := v_declined + 1;
  END LOOP;

  PERFORM set_config('sagana.completing_program', 'on', TRUE);
  UPDATE cooperative_programs SET status = 'completed' WHERE id = p_program_id;
  PERFORM set_config('sagana.completing_program', '', TRUE);

  RETURN v_declined;
END;
$function$;
REVOKE ALL ON FUNCTION public.complete_program(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_program(uuid) TO authenticated;

-- No other way to change the status: not from the app, not by a direct update,
-- and a Completed program is never reopened by a signed-in user.
CREATE OR REPLACE FUNCTION public.enforce_program_status_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND auth.uid() IS NOT NULL THEN
    IF COALESCE(current_setting('sagana.completing_program', TRUE), '') <> 'on'
       OR OLD.status <> 'active' OR NEW.status <> 'completed' THEN
      RAISE EXCEPTION 'PROGRAM_STATUS_LOCKED: A program is closed with Mark as Completed, and a completed program cannot be reopened.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_program_status_change ON public.cooperative_programs;
CREATE TRIGGER trg_enforce_program_status_change
  BEFORE UPDATE ON public.cooperative_programs
  FOR EACH ROW EXECUTE FUNCTION public.enforce_program_status_change();

-- ════════════════════════════════════════════════════════════
-- 3. Programs are never deleted
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.protect_program_from_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  RAISE EXCEPTION 'PROGRAM_NO_DELETE: Programs are never deleted. Mark the program as Completed instead.';
END;
$$;

-- ════════════════════════════════════════════════════════════
-- 4. Staff cannot withdraw an enrolled member
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.protect_member_enrollment()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.status = 'withdrawn' AND OLD.status <> 'withdrawn'
     AND auth.uid() IS NOT NULL AND public.is_staff() THEN
    RAISE EXCEPTION 'NO_WITHDRAW: Staff cannot remove an enrolled member. Enrollment records are kept.';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_member_enrollment ON public.program_members;
CREATE TRIGGER trg_protect_member_enrollment
  BEFORE UPDATE OF status ON public.program_members
  FOR EACH ROW EXECUTE FUNCTION public.protect_member_enrollment();

-- ════════════════════════════════════════════════════════════
-- 5. Staff cannot delete a product (switch it OFF instead)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.protect_program_product_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF auth.uid() IS NULL OR pg_trigger_depth() > 1 THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'NO_PRODUCT_DELETE: A product cannot be deleted. Turn it off to stop selling it.';
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_program_product_delete ON public.program_products;
CREATE TRIGGER trg_protect_program_product_delete
  BEFORE DELETE ON public.program_products
  FOR EACH ROW EXECUTE FUNCTION public.protect_program_product_delete();

-- ════════════════════════════════════════════════════════════
-- 6. Officer permission gate: completing is a Dashboard write
-- ════════════════════════════════════════════════════════════
INSERT INTO public.staff_permission_targets (kind, name, module) VALUES
  ('rpc', 'complete_program', 'dashboard')
ON CONFLICT (kind, name) DO NOTHING;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only; run each by itself AFTER applying)
-- ============================================================
-- V1. Objects exist (expect 4 rows, then 4 rows, then 1 row):
--     SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
--       ('complete_program','get_programs_completion_status','program_completion_blockers','enforce_program_status_change');
--     SELECT tgname FROM pg_trigger WHERE tgname IN ('trg_enforce_program_status_change','trg_protect_member_enrollment',
--       'trg_protect_program_product_delete','trg_protect_program_from_delete');
--     SELECT kind, name, module FROM staff_permission_targets WHERE name = 'complete_program';
-- V2. What blocks completion today (expect: Peanut Seed Distribution awaiting_outcome = 2; Peanut Cookies active_products = 1):
--     SELECT cp.program_name, public.program_completion_blockers(cp.id) FROM cooperative_programs cp ORDER BY cp.created_at;
-- V3. Programs that are now Incomplete (Peanut Cookies should list photo/description/budget):
--     SELECT program_name, program_purpose, public.program_missing_fields(cp) FROM cooperative_programs cp ORDER BY created_at;
-- V4. Nothing changed in the data (expect 6 programs, 5 distributed members, 1 paid purchase of 500.00):
--     SELECT count(*) FROM cooperative_programs;
--     SELECT count(*) FROM program_members WHERE distributed_at IS NOT NULL;
--     SELECT count(*), sum(total_amount) FROM program_product_purchases WHERE status='paid';
-- ============================================================
