-- ============================================================
-- SAGANA — Revert farmer self-recorded Monthly Membership Renewal
--
-- On review, letting a farmer directly record their own capital
-- contribution broke this app's one consistent financial-integrity rule:
-- every other money-adjacent write (loan payments, capital
-- contributions, Product Sales Program purchases) requires admin (or a
-- server-verified event) to confirm real money actually changed hands
-- before it counts. record_membership_renewal() was the one exception —
-- a farmer could assert "I paid this" and have it immediately count
-- toward their real capital total and loan eligibility, with no
-- verification at all. The once-per-month guard slowed abuse but didn't
-- prevent it, especially once the amount also became farmer-editable.
--
-- Membership renewal is being reverted to the Loan Management pattern
-- instead: admin records the payment after actually receiving it, via
-- the existing Record Contribution flow (member_payment source) — no
-- new function needed for that, it already exists. This migration only
-- removes the farmer-callable RPC so the capability is fully gone at
-- the database level, not just hidden from the UI (a farmer could
-- otherwise still call it directly against the API even without an
-- app button for it).
--
-- The loan_policy_settings farmer-read policy from
-- supabase_schema_farmer_membership_renewal.sql is KEPT — the farmer's
-- own capital contribution / loan-eligibility PROGRESS display still
-- needs to read the real policy thresholds, and that's read-only,
-- non-sensitive data with no integrity risk.
-- ============================================================

BEGIN;

DROP FUNCTION IF EXISTS public.record_membership_renewal(NUMERIC, TEXT);
DROP FUNCTION IF EXISTS public.record_membership_renewal(TEXT);

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- Confirm the function no longer exists (should return zero rows):
--   SELECT proname FROM pg_proc WHERE proname = 'record_membership_renewal';
-- Confirm a farmer can still read the policy thresholds (unaffected by
-- this migration — should still return a row):
--   SELECT monthly_dues_amount, minimum_capital_contribution FROM loan_policy_settings WHERE id = 1;
