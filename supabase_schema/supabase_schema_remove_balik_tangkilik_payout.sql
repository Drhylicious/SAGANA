-- ============================================================
-- SAGANA — Remove Balik-Tangkilik Management + Payout Decision (backend)
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run.
-- Run the PRE-FLIGHT first (read-only), then this script.
--
-- WHY
--   The Manager/Officer "Balik-Tangkilik Management" screen and the Farmer
--   "Balik-Tangkilik" screen are removed from the app, together with the
--   Payout Decision (Cash or Add to Capital). The Farmer now has a read-only
--   Benefits Tracking screen. Nothing in the app calls the functions below
--   any more, so they are dropped rather than left reachable.
--
-- WHAT IT DROPS (functions and triggers only — no table, column, row or policy)
--   RPCs
--     request_payout_decision(int, text, numeric)   Farmer picked Cash / Capital
--     confirm_payout_decision(uuid, int)            Manager confirmed it
--     reject_payout_decision(uuid, int)             Manager rejected it
--     reinvest_patronage_capital(int, numeric, text) old direct reinvest (already revoked)
--     get_my_activity_share(int)                    Farmer's share % of the year totals
--   Notice triggers on member_contributions
--     trg_notify_balik_distributed  -> fn_notify_balik_distributed()
--     trg_notify_staff_payout_requested -> fn_notify_staff_payout_requested()
--
-- WHAT IT KEEPS ON PURPOSE (historical records and calculations)
--   * member_contributions and cooperative_annual_totals — every row stays.
--     The paid rows are the only record of past payouts. member_sales_
--     transactions.contribution_id still points at member_contributions.
--   * capital_contribution_events — including the 'patronage_capital' entry
--     (PHP 1,400.00, 1 row in your check). It is part of that member's Capital
--     Share. The source value stays in the CHECK constraint, and a ledger
--     entry cannot be edited or deleted (trg_cce_immutable), so it is untouched.
--   * member_capital_shares and its recompute trigger (Capital Share is
--     unchanged), monthly dues, Cooperative Product purchases and Offers.
--   * The audit triggers on member_contributions / cooperative_annual_totals
--     and their RLS policies: they are harmless on tables nothing writes to,
--     and they keep the staff accountability history of past edits readable.
--   * Notifications already sent ("Payout Decision Confirmed", ...) stay as history.
--
-- HOW TO UNDO
--   Re-run the old scripts: supabase_schema_payout_decision_workflow.sql,
--   supabase_schema_phase4_balik_notice.sql, supabase_schema_phase2_notification_
--   completeness.sql, supabase_schema_officer_permissions_16_farmer_own_share_
--   function.sql. Nothing is lost by this script, so there is nothing to restore.
--
-- RUN ORDER: any time. Safe before or after the app update, because the new app
-- never calls these functions. An OLD app build would fail on them, so update first.
-- ============================================================

-- ─── PRE-FLIGHT (read-only — run each by itself) ────────────────────────────
-- A. Your baseline (nothing here is changed by this script):
--    SELECT status, payout_decision, COUNT(*) FROM member_contributions GROUP BY 1, 2;
--      expected: paid / capital_confirmed = 1, paid / NULL = 3
--    SELECT COUNT(*), COALESCE(SUM(amount), 0) FROM capital_contribution_events WHERE source = 'patronage_capital';
--      expected: 1 / 1400.00
--    SELECT year, total_coop_sales, afs_finalized FROM cooperative_annual_totals ORDER BY year;
--      expected: 2026 / 1100.00 / true
--
-- B. No payout request is waiting (a pending one would be lost to the Farmer):
--    SELECT farmer_id, year, payout_decision, payout_decision_amount
--      FROM member_contributions WHERE payout_decision IN ('pending_cash', 'pending_capital');
--      expected: no rows. If any, settle them in the old app first.
--
-- C. What else points at the functions about to be dropped (expected: only the
--    two notice triggers below):
--    SELECT tgname, tgrelid::regclass FROM pg_trigger
--     WHERE NOT tgisinternal AND tgfoid::regprocedure::text ILIKE ANY
--       (ARRAY['%fn_notify_balik_distributed%', '%fn_notify_staff_payout_requested%']);
-- ────────────────────────────────────────────────────────────────────────────

BEGIN;

-- Stop if a payout request is still waiting: dropping the functions now would
-- leave the Farmer's request with nobody able to confirm it.
DO $$
BEGIN
  IF to_regclass('public.member_contributions') IS NOT NULL
     AND EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'member_contributions'
                    AND column_name = 'payout_decision')
     AND EXISTS (SELECT 1 FROM public.member_contributions
                  WHERE payout_decision IN ('pending_cash', 'pending_capital')) THEN
    RAISE EXCEPTION 'A Cash / Add to Capital request is still pending. Confirm or reject it in the old app first (PRE-FLIGHT B).';
  END IF;
END $$;

-- 1. Notice triggers ─────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_notify_balik_distributed ON public.member_contributions;
DROP TRIGGER IF EXISTS trg_notify_staff_payout_requested ON public.member_contributions;
DROP FUNCTION IF EXISTS public.fn_notify_balik_distributed();
DROP FUNCTION IF EXISTS public.fn_notify_staff_payout_requested();

-- 2. Payout Decision RPCs ────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.request_payout_decision(integer, text, numeric);
DROP FUNCTION IF EXISTS public.confirm_payout_decision(uuid, integer);
DROP FUNCTION IF EXISTS public.reject_payout_decision(uuid, integer);
DROP FUNCTION IF EXISTS public.reinvest_patronage_capital(integer, numeric, text);

-- 3. The Farmer's share-of-year RPC (read only the Balik screen used it) ─────
DROP FUNCTION IF EXISTS public.get_my_activity_share(integer);

COMMIT;

-- ─── POST-CHECK (read-only) ─────────────────────────────────────────────────
-- 1. The functions are gone (expected: no rows):
--    SELECT proname FROM pg_proc
--     WHERE pronamespace = 'public'::regnamespace
--       AND proname IN ('request_payout_decision', 'confirm_payout_decision', 'reject_payout_decision',
--                       'reinvest_patronage_capital', 'get_my_activity_share',
--                       'fn_notify_balik_distributed', 'fn_notify_staff_payout_requested');
-- 2. The history is untouched (same numbers as PRE-FLIGHT A):
--    SELECT status, payout_decision, COUNT(*) FROM member_contributions GROUP BY 1, 2;
--    SELECT COUNT(*), COALESCE(SUM(amount), 0) FROM capital_contribution_events WHERE source = 'patronage_capital';
--    SELECT year, total_coop_sales, afs_finalized FROM cooperative_annual_totals ORDER BY year;
-- 3. Capital Share still adds up (expected: no rows):
--    SELECT s.farmer_id FROM member_capital_shares s
--      JOIN (SELECT farmer_id, SUM(amount) AS t FROM capital_contribution_events GROUP BY 1) e USING (farmer_id)
--     WHERE round(s.total_contribution, 2) <> round(greatest(e.t, 0), 2);
-- ────────────────────────────────────────────────────────────────────────────
