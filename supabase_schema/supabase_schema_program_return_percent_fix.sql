-- ============================================================
-- SAGANA — Program Return Percent: cooperative-wide policy,
-- not per-farmer. Moved from program_members to cooperative_programs.
-- ============================================================

ALTER TABLE public.cooperative_programs
  ADD COLUMN IF NOT EXISTS expected_return_percent DECIMAL(5,2);

ALTER TABLE public.program_members
  DROP COLUMN IF EXISTS expected_return_percent;

NOTIFY pgrst, 'reload schema';
