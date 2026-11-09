-- ============================================================
-- SAGANA — Program Management p18: the "Remind" button (manual outcome-report reminder)
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run.
-- Run AFTER p17 (and p3, p6 which it builds on).
--
-- WHAT IT DOES
--   A Manager or Officer can remind a Farmer who received a distributed item but has not
--   submitted an outcome report. The database enforces the rules, not only the app:
--
--     * AT MOST ONE reminder per distributed item (program member) per calendar day.
--       The day is the Philippine calendar day (Asia/Manila). Enforced by a UNIQUE
--       constraint on (program_member_id, reminded_on), so even two taps at the same
--       moment, or a direct call, cannot send two.
--     * Only a Manager or an Officer can send one (the Officer permission gate lists it
--       under Dashboard, like the other program actions).
--     * Only while the Farmer is waiting: an active member who received the item, has no
--       outcome recorded and has no outcome report at all.
--     * The Farmer gets a notification that says "the cooperative", never a staff name.
--     * Every reminder is a row in program_report_reminders AND in the Accountability Log
--       (admin_activity_log) with the sender's name and role (Manager or Officer), written
--       by the existing audit trigger. Reminders cannot be edited or deleted.
--
--   No automatic or scheduled reminders: that waits for an official reminder schedule.
--   Nothing existing is changed or removed.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public._outcome_actor()') IS NULL
     OR to_regprocedure('public._program_record_immutable()') IS NULL THEN
    RAISE EXCEPTION 'Apply p3 and p6 first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_name = 'program_members' AND column_name = 'distributed_unit') THEN
    RAISE EXCEPTION 'Apply p17 first.';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.program_report_reminders (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  program_member_id UUID        NOT NULL REFERENCES public.program_members(id),
  program_id        UUID        NOT NULL,
  farmer_id         UUID        NOT NULL,
  -- The Philippine calendar day the reminder was sent on.
  reminded_on       DATE        NOT NULL DEFAULT ((NOW() AT TIME ZONE 'Asia/Manila')::DATE),
  sent_by           UUID,
  sent_by_name      TEXT,
  sent_by_role      TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- One reminder per distributed item per Farmer per calendar day, whoever sends it.
  CONSTRAINT program_report_reminders_one_per_day UNIQUE (program_member_id, reminded_on)
);
CREATE INDEX IF NOT EXISTS program_report_reminders_program
  ON public.program_report_reminders (program_id, created_at DESC);

-- A reminder is part of the permanent history.
DROP TRIGGER IF EXISTS trg_immutable ON public.program_report_reminders;
CREATE TRIGGER trg_immutable BEFORE UPDATE OR DELETE ON public.program_report_reminders
  FOR EACH ROW EXECUTE FUNCTION public._program_record_immutable();

-- Every reminder lands in the Accountability Log with the sender's role.
DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.program_report_reminders;
CREATE TRIGGER trg_audit_staff_change
  AFTER INSERT OR UPDATE OR DELETE ON public.program_report_reminders
  FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change('programs', '');

-- Staff can read them (for "Last reminded"); nobody writes directly, only the function.
ALTER TABLE public.program_report_reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "program_report_reminders: staff read" ON public.program_report_reminders;
CREATE POLICY "program_report_reminders: staff read" ON public.program_report_reminders
  FOR SELECT TO authenticated USING (public.is_staff());
REVOKE ALL ON public.program_report_reminders FROM PUBLIC, anon;
GRANT SELECT ON public.program_report_reminders TO authenticated;

CREATE OR REPLACE FUNCTION public.remind_program_report(p_program_member_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_m      program_members%ROWTYPE;
  v_name   TEXT;
  v_role   TEXT;
  v_rows   INTEGER;
  v_item   TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can send a reminder.';
  END IF;

  SELECT * INTO v_m FROM program_members WHERE id = p_program_member_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'REMINDER_NOT_NEEDED: Program member not found.';
  END IF;

  -- Only while the Farmer is actually waiting to report.
  IF v_m.status <> 'active'
     OR v_m.distributed_at IS NULL
     OR v_m.distribution_outcome IS NOT NULL
     OR EXISTS (SELECT 1 FROM program_outcome_reports r WHERE r.program_member_id = v_m.id) THEN
    RAISE EXCEPTION 'REMINDER_NOT_NEEDED: This Farmer is not waiting to submit an outcome report.';
  END IF;

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();

  -- The one-per-day rule: the UNIQUE constraint decides, so it is race-proof.
  INSERT INTO program_report_reminders
    (program_member_id, program_id, farmer_id, sent_by, sent_by_name, sent_by_role)
  VALUES
    (v_m.id, v_m.program_id, v_m.farmer_id, auth.uid(), v_name, v_role)
  ON CONFLICT (program_member_id, reminded_on) DO NOTHING;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'REMINDER_TODAY: A reminder was already sent today for this item. Try again tomorrow.';
  END IF;

  v_item := COALESCE(NULLIF(btrim(v_m.distributed_item_name), ''), 'item');

  -- The Farmer sees "the cooperative", never who sent it.
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_m.farmer_id, 'program', 'Outcome report pending',
    'The cooperative reminds you to report the outcome of the ' || v_item ||
      ' you received on ' || to_char(v_m.distributed_at AT TIME ZONE 'Asia/Manila', 'Mon DD, YYYY') || '.',
    FALSE, NOW(), '/farmer/profile/programs'
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.remind_program_report(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remind_program_report(UUID) TO authenticated;

-- The Officer permission gate: a Dashboard action, like the other program actions.
INSERT INTO public.staff_permission_targets (kind, name, module) VALUES
  ('rpc',   'remind_program_report',    'dashboard'),
  ('table', 'program_report_reminders', 'dashboard')
ON CONFLICT (kind, name) DO NOTHING;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  The table, its one-per-day rule and the audit trigger exist:
--     SELECT conname FROM pg_constraint WHERE conname = 'program_report_reminders_one_per_day';
--     SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.program_report_reminders'::regclass AND NOT tgisinternal;
-- V2  After a reminder was sent from the app, it is in BOTH places, with the sender's role:
--     SELECT sent_by_name, sent_by_role, reminded_on, created_at FROM program_report_reminders ORDER BY created_at DESC LIMIT 5;
--     SELECT actor_name, actor_role, operation, reference_label, created_at FROM admin_activity_log
--      WHERE table_name = 'program_report_reminders' ORDER BY created_at DESC LIMIT 5;
-- V3  The Farmer's notice never names staff:
--     SELECT title, body FROM notifications WHERE title = 'Outcome report pending' ORDER BY created_at DESC LIMIT 5;
-- V4  Two reminders for the same item on the same day are impossible (should list nothing):
--     SELECT program_member_id, reminded_on, count(*) FROM program_report_reminders GROUP BY 1, 2 HAVING count(*) > 1;
-- V5  The gate lists them:
--     SELECT kind, name, module FROM staff_permission_targets WHERE name IN ('remind_program_report','program_report_reminders');
