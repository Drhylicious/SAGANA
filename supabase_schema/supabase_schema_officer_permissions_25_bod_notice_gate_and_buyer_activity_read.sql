-- ============================================================
-- SAGANA — Officer permissions, script 25:
--   (1) THE MANUAL BOD NOTICE IS GATED   (2) THE MANAGER CAN READ BUYER ACTIVITY
--
-- (1) notify_bod_meeting_near(date)
--   A hand-run placeholder from batch9 (the scheduled monthly reminder is a different function,
--   notify_bod_meeting_upcoming, and is not touched). It tells every active Farmer and all staff
--   that a BOD meeting is coming, and it was not in the Officer gate, so even a View Only Officer
--   could send it by calling the database directly. It is now registered under Loans (the notice
--   opens the Loans screen), so only the Manager and an Officer with Loans = Manage can run it.
--   The app does not call it. NOTE: its text still begins "[PLACEHOLDER]"; if you ever use it by
--   hand, that text goes to every Farmer. Say the word and I will lock it away completely.
--
-- (2) buyer_profile_activity
--   Why the Manager saw 0 rows: the table's own rule lets a Buyer read their own rows, and the
--   only staff rule, "officer reads buyer_profile_activity", tests officer_profiles, so it admits
--   Officers and never the Manager. The app does not read it for staff; this is only for equal
--   data visibility. The Officer-only rule is replaced by one for every staff member
--   (Manager and Officers, read only). Buyers keep their own rule untouched.
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor. Re-runnable.
-- ============================================================

DO $$
BEGIN
  IF to_regclass('public.staff_permission_targets') IS NULL THEN
    RAISE EXCEPTION 'staff_permission_targets is missing. Run officer_permissions_02 first.';
  END IF;
  IF to_regclass('public.buyer_profile_activity') IS NULL THEN
    RAISE EXCEPTION 'buyer_profile_activity is missing.';
  END IF;
  IF to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'is_staff() is missing.';
  END IF;
END $$;

BEGIN;
SELECT set_config('lock_timeout', '5s', true);

INSERT INTO public.staff_permission_targets (kind, name, module)
VALUES ('rpc', 'notify_bod_meeting_near', 'loans')
ON CONFLICT (kind, name) DO NOTHING;

DROP POLICY IF EXISTS "officer reads buyer_profile_activity" ON public.buyer_profile_activity;
DROP POLICY IF EXISTS "staff reads buyer_profile_activity" ON public.buyer_profile_activity;
CREATE POLICY "staff reads buyer_profile_activity"
  ON public.buyer_profile_activity FOR SELECT TO authenticated
  USING (public.is_staff());

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only; run each by itself) ────────────────────────
--   SELECT name, module FROM staff_permission_targets WHERE name = 'notify_bod_meeting_near';   -- loans
--   SELECT policyname, cmd FROM pg_policies WHERE tablename = 'buyer_profile_activity' ORDER BY 1;
--   -- "Buyers manage own profile activity" and "staff reads buyer_profile_activity" (SELECT)
-- Re-run the Officer-vs-Manager row count: buyer_profile_activity no longer differs.
-- ─────────────────────────────────────────────────────────────────────────
