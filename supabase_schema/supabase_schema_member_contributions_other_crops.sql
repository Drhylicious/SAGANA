-- ============================================================
-- SAGANA — member_contributions: Other Crops columns
-- Covers: Farmer Details "Volume to SP3" stat, farmer's own
-- "My Total Sales to SP3" card (My Contribution screen)
--
-- WHY: member_contributions has tracked palay_sales_kg/amount and
-- peanut_sales_kg/amount since its original schema, from before
-- Offer to Cooperative accepted any crop (Phase 9's widening of
-- member_sales_transactions / MemberSalesTotals). total_sales_amount
-- has always correctly included every crop (it's written from
-- MemberSalesTotals.totalAmount), but the two per-crop display
-- columns never got the same widening — so a farmer who sold e.g.
-- corn via Offer to Cooperative would see a correct Total but an
-- incomplete Palay/Peanut breakdown underneath it, with nowhere for
-- that corn revenue to show. This mirrors the exact same gap Phase 11
-- already fixed in Member Contribution Report's MemberContributionRow
-- (admin_reports_model.dart) / MemberSalesTotals
-- (member_sales_aggregation.dart) — this migration extends the same
-- fix to member_contributions, the table Balik-Tangkilik actually
-- writes to and Farmer Details / My Contribution read from.
-- ============================================================

ALTER TABLE public.member_contributions
  ADD COLUMN IF NOT EXISTS other_crops_qty_kg  DECIMAL(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS other_crops_amount  DECIMAL(12,2) NOT NULL DEFAULT 0;
