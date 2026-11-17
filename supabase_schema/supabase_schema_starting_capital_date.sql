-- ============================================================
-- SAGANA — Starting Capital gets its own date (effective_date)
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run.
--
-- WHY
--   Starting Capital (source 'opening_balance') is the capital a member already had
--   BEFORE SAGANA tracked them (for example PHP 2,000 held in 2025). Until now an
--   entry only had created_at, the day it was typed in, so it always landed in the
--   year it was recorded. The Member Patronage Report and the year-end Capital Share
--   need the date the capital was actually held.
--
-- WHAT THIS DOES
--   1. capital_contribution_events gets effective_date (date, nullable).
--      Only a Starting Capital entry carries one. Null = "the day it was recorded"
--      (created_at), so every existing row, every other source and the Add Farmer
--      starting capital keep working and keep their year exactly as before.
--   2. A BEFORE INSERT trigger:
--        * a reversal (cancellation) copies the date of the entry it cancels, so the
--          cancellation lands in the SAME year and the two net to zero there;
--        * a date can only be set on a Starting Capital entry, and not in the future.
--
-- WHAT IT DOES NOT CHANGE
--   Amounts, member_capital_shares and its recompute trigger (the Capital Share is
--   the sum of the ledger, so a dated Starting Capital is counted ONCE, never twice),
--   monthly dues, the immutability rule (no row is edited or deleted), RLS policies.
--   No existing row is touched.
--
-- RUN ORDER: before using the new Starting Capital date in the app (the app sends
-- effective_date and will say so if this script has not been run).
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ─────────────────────────────────────────────────
-- A. The Starting Capital entries that exist today (they keep their recorded day):
--    SELECT farmer_id, amount, created_at::date AS recorded_on, reverses_event_id
--      FROM public.capital_contribution_events WHERE source = 'opening_balance' ORDER BY created_at;
-- B. The column does not exist yet (expected: no rows):
--    SELECT 1 FROM information_schema.columns
--     WHERE table_schema = 'public' AND table_name = 'capital_contribution_events' AND column_name = 'effective_date';
-- ────────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.capital_contribution_events') IS NULL THEN
    RAISE EXCEPTION 'capital_contribution_events is missing.';
  END IF;
END $$;

ALTER TABLE public.capital_contribution_events
  ADD COLUMN IF NOT EXISTS effective_date date;

COMMENT ON COLUMN public.capital_contribution_events.effective_date IS
  'Starting Capital only: the date the member actually held this capital (can be a past year). Null = the day the entry was recorded (created_at).';

CREATE OR REPLACE FUNCTION public.cce_effective_date_rules()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.reverses_event_id IS NOT NULL THEN
    -- A cancellation belongs to the same period as the entry it cancels.
    SELECT effective_date INTO NEW.effective_date
      FROM public.capital_contribution_events
     WHERE id = NEW.reverses_event_id;
    RETURN NEW;
  END IF;

  IF NEW.effective_date IS NOT NULL THEN
    IF NEW.source <> 'opening_balance' THEN
      RAISE EXCEPTION 'Only a Starting Capital entry can carry its own date.';
    END IF;
    IF NEW.effective_date > (now() AT TIME ZONE 'Asia/Manila')::date THEN
      RAISE EXCEPTION 'The Starting Capital date cannot be in the future.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cce_effective_date_rules ON public.capital_contribution_events;
CREATE TRIGGER trg_cce_effective_date_rules
  BEFORE INSERT ON public.capital_contribution_events
  FOR EACH ROW EXECUTE FUNCTION public.cce_effective_date_rules();

COMMIT;

-- ─── POST-CHECK (read-only) ─────────────────────────────────────────────────
-- 1. The column and trigger exist:
--    SELECT column_name FROM information_schema.columns
--     WHERE table_name = 'capital_contribution_events' AND column_name = 'effective_date';
--    SELECT tgname FROM pg_trigger WHERE tgname = 'trg_cce_effective_date_rules';
-- 2. Nothing changed for existing rows (expected: 0):
--    SELECT count(*) FROM public.capital_contribution_events WHERE effective_date IS NOT NULL;
-- 3. Capital Share still equals the ledger (expected: no rows):
--    SELECT s.farmer_id FROM member_capital_shares s
--      JOIN (SELECT farmer_id, SUM(amount) AS t FROM capital_contribution_events GROUP BY 1) e USING (farmer_id)
--     WHERE round(s.total_contribution, 2) <> round(greatest(e.t, 0), 2);
-- ────────────────────────────────────────────────────────────────────────────
