-- ============================================================
-- SAGANA — Capital Share FRESH START (every member back to PHP 0)
--
-- FOR YOUR REVIEW — NOT APPLIED. Run the PRE-FLIGHT first, then the script.
-- This DELETES records. It keeps a copy first, so it can be undone (see UNDO).
--
-- WHY
--   Your check showed the capital ledger and the balances disagree:
--     Marc Louie M. Yañez   ledger PHP 200,000.00 (Phase B migration entry), balance PHP 0.00
--     Ellen Angela Rosal    PHP 2,000.00 (1 share)
--     Jhon Drhy M. Salangsang PHP 1,500.00 (PHP 100 payment + PHP 1,400 old payout)
--   You asked to start fresh for everyone.
--
-- WHAT THIS DOES
--   1. Copies capital_contribution_events and member_capital_shares into two backup
--      tables (capital_contribution_events_bak_20261115, member_capital_shares_bak_20261115).
--   2. Deletes every row of capital_contribution_events. The ledger cannot be changed
--      from the app (a trigger blocks it for signed-in users); the SQL Editor has no
--      signed-in user, so it is allowed here, which is why this is a manual script.
--   3. The ledger's own trigger (trg_cce_recompute) recomputes each balance from the
--      ledger on every delete, so every Capital Share goes to 0 and every share count
--      to 0. A final UPDATE makes sure no row is left over.
--
-- WHAT IT KEEPS (untouched)
--   * member_capital_shares rows themselves (share value PHP 2,000 per member).
--   * member_monthly_contributions (the monthly schedule and any waivers). Because the
--     payments that settled those months are deleted, every month reads UNPAID/OVERDUE
--     again. Waivers are kept.
--   * member_contributions and cooperative_annual_totals (the old Balik-Tangkilik
--     history). Note: the 2026 row still says its payout was "added to capital"
--     (capital_confirmed, PHP 1,400); that history is not rewritten.
--   * Notifications and the staff activity log (they still mention the old entries).
--   * Cooperative Product purchases, offers, loans.
--
-- CONSEQUENCES TO KNOW
--   * Loan eligibility is checked against Capital Share (minimum PHP 2,000). After this
--     nobody meets it until capital is recorded again.
--   * The Member Patronage Report shows PHP 0 Monthly Contributions and no Starting
--     Capital for every member.
--   * New capital entries start from a clean ledger, so Marc's PHP 200,000 can no longer
--     reappear when the next entry is recorded.
-- ============================================================

-- ─── PRE-FLIGHT (read-only; run each by itself) ─────────────────────────────
-- A. What will be deleted (expect 4-6 rows: Ellen's payments, Jhon's 100 + 1400, Marc's 200000):
--    SELECT u.full_name, e.created_at::date, e.source, e.amount, e.note
--      FROM public.capital_contribution_events e JOIN public.user_information u ON u.user_id = e.farmer_id
--     ORDER BY u.full_name, e.created_at;
-- B. The ledger total per member against the stored balance:
--    SELECT u.full_name, COALESCE(l.t, 0) AS ledger_total, c.total_contribution AS stored_balance
--      FROM public.member_capital_shares c
--      JOIN public.user_information u ON u.user_id = c.farmer_id
--      LEFT JOIN (SELECT farmer_id, SUM(amount) AS t FROM public.capital_contribution_events GROUP BY 1) l USING (farmer_id)
--     ORDER BY 2 DESC;
-- ────────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.capital_contribution_events') IS NULL
     OR to_regclass('public.member_capital_shares') IS NULL THEN
    RAISE EXCEPTION 'The capital tables are missing.';
  END IF;
  IF to_regclass('public.capital_contribution_events_bak_20261115') IS NOT NULL THEN
    RAISE EXCEPTION 'The backup tables already exist: this script was already run. Drop them first only if you are sure.';
  END IF;
END $$;

-- 1. The copy that makes this undoable ───────────────────────────────────────
CREATE TABLE public.capital_contribution_events_bak_20261115 AS
  SELECT * FROM public.capital_contribution_events;
CREATE TABLE public.member_capital_shares_bak_20261115 AS
  SELECT * FROM public.member_capital_shares;

-- 2. Clear the ledger (the recompute trigger sets every balance to 0) ────────
DELETE FROM public.capital_contribution_events;

-- 3. Make sure nothing is left over (the trigger also sets total_shares to 0) ─
UPDATE public.member_capital_shares
   SET total_contribution = 0
 WHERE total_contribution <> 0;

COMMIT;

-- ─── POST-CHECK (read-only) ─────────────────────────────────────────────────
-- 1. Expect 0:
--    SELECT count(*) FROM public.capital_contribution_events;
-- 2. Expect 0 / 0:
--    SELECT COALESCE(SUM(total_contribution), 0), COALESCE(SUM(total_shares), 0) FROM public.member_capital_shares;
-- 3. The backup holds what was deleted (expect the rows from PRE-FLIGHT A):
--    SELECT count(*), SUM(amount) FROM public.capital_contribution_events_bak_20261115;
-- ────────────────────────────────────────────────────────────────────────────

-- ─── UNDO (only if you change your mind; run as one block) ──────────────────
-- BEGIN;
--   INSERT INTO public.capital_contribution_events SELECT * FROM public.capital_contribution_events_bak_20261115;
--   -- the insert trigger recomputes every balance from the restored ledger.
-- COMMIT;
-- Drop the two backup tables when you no longer need them:
--   DROP TABLE public.capital_contribution_events_bak_20261115;
--   DROP TABLE public.member_capital_shares_bak_20261115;
-- ────────────────────────────────────────────────────────────────────────────
