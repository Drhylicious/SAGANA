-- ============================================================
-- SAGANA — Product Sales Program → Patronage/Balik-Tangkilik
-- Integration (Option B: separate, parallel pool)
--
-- Connects the Product Sales Program direction (farmer BUYS cooperative
-- products, recorded in program_product_purchases — see
-- supabase_schema_program_product_sales.sql) to Member Patronage Report
-- and Balik-Tangkilik Management, as a SECOND, SEPARATE component that
-- never blends into the existing sales-based patronage math (farmer
-- SELLS to the cooperative via Offer to Cooperative, member_sales_
-- transactions). Per the organization's explicit decision (Option B):
-- the two directions stay fully distinguishable end to end — a BOD
-- member should always be able to see which pool a given peso came from.
--
-- Dynamic by construction: program_product_purchases is already a single
-- table shared by every 'sales'-purpose cooperative_programs row, so any
-- future Product Sales program an admin creates is picked up automatically
-- by the aggregation this migration's Dart counterpart adds — no new
-- migration or per-program code is needed when a new sales program is
-- created.
-- ============================================================

-- ─── cooperative_annual_totals: parallel year-level settings ────────────────
-- Mirrors total_coop_sales/distributable_surplus exactly, for the Product
-- Sales side. Admin-entered per year, same "live sum is a suggestion, not
-- an automatic overwrite" pattern as the existing sales-side settings.

ALTER TABLE public.cooperative_annual_totals
  ADD COLUMN IF NOT EXISTS total_program_sales DECIMAL(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS distributable_program_surplus DECIMAL(14,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.cooperative_annual_totals.total_program_sales IS
  'Admin-entered/reconciled total of confirmed Product Sales Program purchases for the year, across every sales-purpose program. Parallel to total_coop_sales, never combined with it.';

COMMENT ON COLUMN public.cooperative_annual_totals.distributable_program_surplus IS
  'The pool Purchase Patronage is drawn from, parallel to distributable_surplus. Independently admin-set — may legitimately be 0 or a different figure than the sales-side pool.';

-- ─── member_contributions: per-farmer Purchase Patronage columns ────────────
-- Mirrors total_sales_amount/estimated_balik_tangkilik/actual_balik_tangkilik's
-- existing estimated/actual separation exactly, for the Product Sales side.

ALTER TABLE public.member_contributions
  ADD COLUMN IF NOT EXISTS program_purchases_amount     DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS estimated_purchase_patronage  DECIMAL(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS actual_purchase_patronage     DECIMAL(12,2);

COMMENT ON COLUMN public.member_contributions.program_purchases_amount IS
  'This farmer''s total confirmed (status=paid) Product Sales Program purchases for the year, across every sales-purpose program. Never a summed physical quantity — different programs sell in different units, so only a peso total is meaningful here, unlike Palay/Peanut kg.';

COMMENT ON COLUMN public.member_contributions.estimated_purchase_patronage IS
  'This farmer''s running-estimate share of distributable_program_surplus, based on their program_purchases_amount relative to total_program_sales. Parallel to estimated_balik_tangkilik, never summed into it directly in storage — the UI combines them for display where a single grand total is wanted.';

COMMENT ON COLUMN public.member_contributions.actual_purchase_patronage IS
  'Finalized Purchase Patronage payout, written only by recordDistribution() alongside actual_balik_tangkilik/actual_interest_on_capital, under the same AFS-finalized, once-per-year gate.';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- Confirm the new columns exist:
--   SELECT column_name FROM information_schema.columns
--   WHERE table_name = 'cooperative_annual_totals'
--     AND column_name IN ('total_program_sales', 'distributable_program_surplus');
--   -- expect 2 rows
--
--   SELECT column_name FROM information_schema.columns
--   WHERE table_name = 'member_contributions'
--     AND column_name IN ('program_purchases_amount', 'estimated_purchase_patronage', 'actual_purchase_patronage');
--   -- expect 3 rows
