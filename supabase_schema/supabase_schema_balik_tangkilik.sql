-- ============================================================
-- SAGANA — Balik-Tangkilik Distribution Readiness Flag
-- Adds the AFS-finalized gate discussed for Balik-Tangkilik
-- Management. The cooperative only distributes after the
-- Audited Financial Statement is complete and approved at the
-- Annual General Assembly — this flag models that workflow
-- explicitly rather than inferring readiness from whether a
-- pool amount happens to be non-zero.
-- ============================================================

ALTER TABLE public.cooperative_annual_totals
  ADD COLUMN IF NOT EXISTS afs_finalized BOOLEAN NOT NULL DEFAULT false;