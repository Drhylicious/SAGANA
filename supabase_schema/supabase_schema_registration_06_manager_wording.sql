-- ============================================================
-- SAGANA — Registration refactor, step 6: "Admin" → "Manager" in notification
-- text written by the database
--
-- WHY A TRIGGER. Dozens of database functions across more than a hundred
-- migration files write notification titles and bodies that say "admin" (for
-- example "Your listing is awaiting admin review"). Rewriting every one of
-- those function bodies would be a large, risky change to live business logic.
-- Instead, a BEFORE INSERT trigger on notifications swaps the word in the text
-- as it is stored, so every present and future notification — from any
-- function, trigger or app insert — reads "Manager". Nothing else is touched:
-- the stored role value 'admin', routes, policies and function names stay.
--
-- Whole words only (so "administration" is left alone):
--   Administrators → Managers   Administrator → Manager
--   Admins         → Managers   Admin         → Manager     (any letter case)
--
-- NOT COVERED: text inside RAISE EXCEPTION messages (errors shown when an
-- action is refused) in older functions. The app shows few of those to a user;
-- they are listed by the query below if you want to review them.
--
-- Not applied automatically.
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ──────────────────────────────────────────────
-- A. Existing notifications that still say admin (informational):
--    SELECT count(*) FROM public.notifications
--    WHERE title ~* '\m(admins?|administrators?)\M' OR body ~* '\m(admins?|administrators?)\M';
-- B. Functions whose error messages mention admin (informational, not changed):
--    SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--      AND prosrc ~* 'RAISE EXCEPTION[^;]*\m(admins?|administrators?)\M' ORDER BY proname;
-- ────────────────────────────────────────────────────────────────────────

BEGIN;

CREATE OR REPLACE FUNCTION public.to_manager_wording(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN p_text IS NULL THEN NULL ELSE
    regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(p_text, '\mAdministrators\M', 'Managers', 'gi'),
          '\mAdministrator\M', 'Manager', 'gi'),
        '\mAdmins\M', 'Managers', 'gi'),
      '\mAdmin\M', 'Manager', 'gi')
  END;
$$;

CREATE OR REPLACE FUNCTION public.notifications_manager_wording()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.title := public.to_manager_wording(NEW.title);
  NEW.body  := public.to_manager_wording(NEW.body);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notifications_manager_wording ON public.notifications;
CREATE TRIGGER trg_notifications_manager_wording
  BEFORE INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.notifications_manager_wording();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── OPTIONAL — NOT RUN BY THIS FILE ─────────────────────────────────────
-- Re-word notifications that were already sent (changes stored text only; no
-- row is deleted). Review PRE-FLIGHT query A first.
--   UPDATE public.notifications
--   SET title = public.to_manager_wording(title), body = public.to_manager_wording(body)
--   WHERE title ~* '\m(admins?|administrators?)\M' OR body ~* '\m(admins?|administrators?)\M';
-- ────────────────────────────────────────────────────────────────────────

-- ─── POST-DEPLOY VERIFICATION ────────────────────────────────────────────
-- 1. (expect "Your listing is awaiting Manager review by the Managers")
--    SELECT public.to_manager_wording('Your listing is awaiting admin review by the Administrators');
-- 2. Whole words only (expect unchanged): SELECT public.to_manager_wording('administration office');
-- 3. Trigger exists (expect 1 row):
--    SELECT tgname FROM pg_trigger WHERE tgname='trg_notifications_manager_wording';
-- ============================================================
