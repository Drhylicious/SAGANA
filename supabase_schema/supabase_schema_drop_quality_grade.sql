-- Removes the quality_grade concept entirely, per decision: hard drop.
-- Harvest Entry has never had a grading UI; the column was only ever
-- populated by a database DEFAULT ('Grade Pending' post-migration,
-- 'Grade A' before it) that no application code path ever overrides or
-- reads meaningfully. Confirmed via full system trace: Admin's "Grade A
-- Share" KPI is structurally near-zero for all current data (nothing
-- ever assigns 'Grade A' anymore), and the buyer-facing badge displayed
-- "Grade Pending" in a green, positive-looking pill with no special-case
-- handling — actively misleading. Any real Grade A/B/C values manually
-- entered before this became fully automatic are lost with this drop;
-- accepted per explicit decision given this is what's actually driving
-- confusing behavior across three separate screens.

ALTER TABLE public.harvest_records DROP COLUMN IF EXISTS quality_grade;
ALTER TABLE public.inventory_batches DROP COLUMN IF EXISTS quality_grade;
