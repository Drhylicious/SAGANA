-- ============================================================
-- SAGANA — script 26: ONE BOD MEETING REMINDER PER MEETING (scheduled job + manual "send now")
--
-- THE REQUIREMENT: the BOD meets on the FIRST SATURDAY of every month, every Farmer and every
-- staff member is reminded, the daily 08:00 job keeps working, and nobody is told twice.
--
-- WHAT I FOUND
--   * notify_bod_meeting_upcoming(date) (batch10, plus the log line from script 22): run daily at
--     08:00 Manila; sends exactly 3 days before the next first Saturday. Correct, and unchanged in
--     what it sends.
--   * notify_bod_meeting_near(date) (batch9): a hand-run PLACEHOLDER. It accepted ANY date (not only
--     a first Saturday), sent "[PLACEHOLDER] ..." text, and had no memory of what was already sent,
--     so running it, or running it next to the job, told everybody twice.
--   * The three date rules agree (SQL bod_first_saturday / bod_next_meeting, SQL
--     next_bod_saturday_after, Dart BodSchedule): first Saturday of the month.
--   * Staff can also send the "BOD Meeting This Saturday" template from Broadcast. That is a
--     deliberate manual broadcast and is not tracked here.
--
-- WHAT THIS DOES
--   1. A small table, bod_meeting_notices: one row per meeting date, saying who/what sent the
--      reminder (the daily job, or a staff member). Its primary key is what prevents duplicates.
--   2. One internal helper, _bod_send_notice(), used by BOTH functions: it claims the meeting date
--      first (so a second sender gets nothing), then sends the same notices as before (Farmers:
--      type loan; staff: type system) with the same wording:
--          3 days before -> title "BOD Meeting in 3 Days", body "The BOD meeting is on
--          March 07, 2026 (in 3 days)."  (identical to what the job sent before)
--          other days    -> "BOD Meeting in N Days" / "Tomorrow" / "Today".
--   3. notify_bod_meeting_upcoming(date): same schedule and same daily job. If the reminder for that
--      meeting was already sent (for example by hand), it sends nothing.
--   4. notify_bod_meeting_near(date DEFAULT NULL): becomes the manual "send the reminder now".
--      With no date it uses the next first Saturday. It REFUSES any date that is not a first
--      Saturday, a meeting that has passed, and a meeting whose reminder was already sent. No more
--      "[PLACEHOLDER]" text. Only the Manager and an Officer with Loans = Manage can run it (Loans gate).
--      The job then skips that meeting, so Farmers get one reminder, not two.
--   5. A manual send is recorded in Staff Accountability (who sent it). The scheduled run keeps its
--      "System" line.
--
-- NOT CHANGED: the cron job (bod-meeting-upcoming, 00:00 UTC = 08:00 Manila), bod_first_saturday,
-- bod_next_meeting, the Broadcast template.
-- LIMIT: a reminder sent BEFORE this script is not in the new table, so running either function by
-- hand for a meeting already reminded earlier would send again. The next daily run only matters on the
-- day exactly 3 days before a meeting.
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor. Re-runnable.
-- ============================================================

DO $$
BEGIN
  IF to_regprocedure('public.bod_first_saturday(date)') IS NULL OR to_regprocedure('public.bod_next_meeting(date)') IS NULL THEN
    RAISE EXCEPTION 'bod_first_saturday(date) / bod_next_meeting(date) are missing (batch10_01).';
  END IF;
  IF to_regclass('public.notifications') IS NULL OR to_regclass('public.admin_activity_log') IS NULL THEN
    RAISE EXCEPTION 'notifications or admin_activity_log is missing.';
  END IF;
  IF to_regprocedure('public.is_staff()') IS NULL OR to_regprocedure('public.audit_staff_change()') IS NULL THEN
    RAISE EXCEPTION 'is_staff() / audit_staff_change() are missing.';
  END IF;
  IF to_regprocedure('public.notify_bod_meeting_upcoming(date)') IS NULL THEN
    RAISE EXCEPTION 'notify_bod_meeting_upcoming(date) is missing.';
  END IF;
  -- Replace the job function only if it is the version this work knows (batch10 + the script 22 log line,
  -- or this script's own version on a re-run).
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = 'public.notify_bod_meeting_upcoming(date)'::regprocedure
                 AND (prosrc LIKE '%bod_system_log%' OR prosrc LIKE '%_bod_send_notice%')) THEN
    RAISE EXCEPTION 'notify_bod_meeting_upcoming() is not the expected version (run script 22 first, or send me its definition).';
  END IF;
END $$;

BEGIN;
SELECT set_config('lock_timeout', '5s', true);

-- ════════════════════════════════════════════════════════════
-- 1. One row per meeting
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.bod_meeting_notices (
  meeting_date     date        PRIMARY KEY,
  sent_at          timestamptz NOT NULL DEFAULT now(),
  sent_by          uuid        REFERENCES auth.users (id) ON DELETE SET NULL,   -- NULL = the daily job
  source           text        NOT NULL CHECK (source IN ('scheduled', 'manual')),
  farmers_notified integer     NOT NULL DEFAULT 0,
  staff_notified   integer     NOT NULL DEFAULT 0
);
COMMENT ON TABLE public.bod_meeting_notices IS
  'One row per BOD meeting whose reminder has been sent. The primary key stops a second reminder.';

ALTER TABLE public.bod_meeting_notices ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "bod_meeting_notices: staff read" ON public.bod_meeting_notices;
CREATE POLICY "bod_meeting_notices: staff read"
  ON public.bod_meeting_notices FOR SELECT TO authenticated USING (public.is_staff());
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.bod_meeting_notices FROM anon, authenticated;

DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.bod_meeting_notices;
CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.bod_meeting_notices
  FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change('loans', '');

-- ════════════════════════════════════════════════════════════
-- 2. The one place the notices are sent
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._bod_send_notice(p_meeting date, p_source text, p_by uuid, p_today date)
RETURNS integer              -- Farmers notified; -1 = the reminder for this meeting was already sent
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days    integer := p_meeting - p_today;
  v_title   text;
  v_body    text;
  v_farmers integer := 0;
  v_staff   integer := 0;
  v_new     integer;
BEGIN
  -- Claim the meeting first: whoever is second finds the row and sends nothing.
  INSERT INTO bod_meeting_notices (meeting_date, source, sent_by)
  VALUES (p_meeting, p_source, p_by)
  ON CONFLICT (meeting_date) DO NOTHING;
  GET DIAGNOSTICS v_new = ROW_COUNT;
  IF v_new = 0 THEN
    RETURN -1;
  END IF;

  v_title := CASE v_days WHEN 0 THEN 'BOD Meeting Today' WHEN 1 THEN 'BOD Meeting Tomorrow'
                         ELSE 'BOD Meeting in ' || v_days || ' Days' END;
  v_body  := 'The BOD meeting is on ' || to_char(p_meeting, 'FMMonth DD, YYYY')
             || CASE v_days WHEN 0 THEN ' (today).' WHEN 1 THEN ' (tomorrow).'
                            ELSE ' (in ' || v_days || ' days).' END;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ur.user_id, 'loan', v_title, v_body, FALSE, NOW(), '/farmer/profile/loans'
  FROM user_roles ur
  WHERE ur.role = 'farmer' AND ur.status = 'active';
  GET DIAGNOSTICS v_farmers = ROW_COUNT;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ur.user_id, 'system', v_title, v_body, FALSE, NOW(), '/admin/loans'
  FROM user_roles ur
  WHERE ur.role IN ('admin', 'officer');
  GET DIAGNOSTICS v_staff = ROW_COUNT;

  UPDATE bod_meeting_notices SET farmers_notified = v_farmers, staff_notified = v_staff
  WHERE meeting_date = p_meeting;

  -- The daily job has no person behind it: it leaves one "System" line (a staff send is already
  -- recorded by the audit trigger on bod_meeting_notices, with the person's name).
  IF p_source = 'scheduled' THEN
    BEGIN
      INSERT INTO admin_activity_log (
        admin_id, module, action_type, description, actor_role, actor_name,
        table_name, operation, reference_label, new_values, source
      ) VALUES (
        NULL, 'system', 'bod_reminder',
        'BOD meeting reminder sent for ' || to_char(p_meeting, 'FMMonth DD, YYYY')
          || ' to ' || v_farmers || ' Farmers and ' || v_staff || ' staff',
        'system', 'System', 'notifications', 'created', to_char(p_meeting, 'YYYY-MM-DD'),
        jsonb_build_object('meeting_date', p_meeting, 'farmers', v_farmers, 'staff', v_staff), 'db'
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'BOD reminder log failed: %', SQLERRM;
    END;
  END IF;

  RETURN v_farmers;
END;
$$;
REVOKE ALL ON FUNCTION public._bod_send_notice(date, text, uuid, date) FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 3. The daily job: same schedule, never a duplicate
-- ════════════════════════════════════════════════════════════
-- bod_system_log: marker kept so older checks still recognise the version.
CREATE OR REPLACE FUNCTION public.notify_bod_meeting_upcoming(p_today date DEFAULT CURRENT_DATE)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_meeting date := public.bod_next_meeting(p_today);
  v_sent    integer;
BEGIN
  IF v_meeting - p_today <> 3 THEN
    RETURN 0;                                   -- only exactly 3 days before the first Saturday
  END IF;
  v_sent := public._bod_send_notice(v_meeting, 'scheduled', NULL, p_today);
  RETURN GREATEST(v_sent, 0);                   -- -1 (already sent by hand) -> nothing more to send
END;
$$;

-- ════════════════════════════════════════════════════════════
-- 4. The manual "send the reminder now"
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.notify_bod_meeting_near(p_meeting_date date DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today   date := (now() AT TIME ZONE 'Asia/Manila')::date;
  v_meeting date;
  v_sent    integer;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only the Manager or an Officer can send this notice';
  END IF;

  v_meeting := COALESCE(p_meeting_date, public.bod_next_meeting(v_today));
  IF v_meeting <> public.bod_first_saturday(v_meeting) THEN
    RAISE EXCEPTION 'BOD meetings are held on the first Saturday of the month (%). Choose that date.',
      to_char(public.bod_first_saturday(v_meeting), 'FMMonth DD, YYYY');
  END IF;
  IF v_meeting < v_today THEN
    RAISE EXCEPTION 'That BOD meeting has already passed.';
  END IF;

  v_sent := public._bod_send_notice(v_meeting, 'manual', auth.uid(), v_today);
  IF v_sent = -1 THEN
    RAISE EXCEPTION 'The reminder for the BOD meeting on % was already sent.', to_char(v_meeting, 'FMMonth DD, YYYY');
  END IF;
  RETURN v_sent;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_bod_meeting_near(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notify_bod_meeting_near(date) TO authenticated;

-- Only the Manager and an Officer with Loans = Manage (same as script 25; harmless to repeat).
INSERT INTO public.staff_permission_targets (kind, name, module)
VALUES ('rpc', 'notify_bod_meeting_near', 'loans')
ON CONFLICT (kind, name) DO NOTHING;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only; run each by itself) ────────────────────────
--   SELECT jobname, schedule FROM cron.job WHERE jobname = 'bod-meeting-upcoming';   -- 0 0 * * *  (08:00 Manila)
--   SELECT public.bod_next_meeting(CURRENT_DATE);                                    -- a first Saturday
--   SELECT prosrc LIKE '%_bod_send_notice%' FROM pg_proc WHERE proname = 'notify_bod_meeting_upcoming';  -- true
--   SELECT meeting_date, source, farmers_notified, staff_notified FROM bod_meeting_notices ORDER BY 1 DESC;
-- The SQL editor has no signed-in user, so a call there answers "Unauthorized". The rules (not a first Saturday,
-- already passed, already sent) are answered to a signed-in Manager or Officer calling it from the app or API.
-- Do NOT call notify_bod_meeting_near() with no date unless you really want the reminder sent now.
-- ─────────────────────────────────────────────────────────────────────────
