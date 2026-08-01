-- ============================================================
-- SAGANA — Grade Pending State
-- Makes "not yet graded" a real, distinguishable state instead
-- of silently defaulting to 'Grade A' on both harvest_records
-- and inventory_batches. Existing rows are left as-is (their
-- grading history, if any was ever entered manually, is not
-- something we can reconstruct) — this only changes behavior
-- for rows created from now on.
-- ============================================================

ALTER TABLE public.harvest_records
  DROP CONSTRAINT IF EXISTS harvest_records_quality_grade_check;

ALTER TABLE public.harvest_records
  ADD CONSTRAINT harvest_records_quality_grade_check
  CHECK (quality_grade IN ('Grade Pending', 'Grade A', 'Grade B', 'Grade C'));

ALTER TABLE public.harvest_records
  ALTER COLUMN quality_grade SET DEFAULT 'Grade Pending';

ALTER TABLE public.inventory_batches
  ALTER COLUMN quality_grade SET DEFAULT 'Grade Pending';