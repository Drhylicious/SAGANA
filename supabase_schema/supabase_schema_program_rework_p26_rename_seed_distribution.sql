-- ============================================================
-- SAGANA — p26: rename "Peanut Seed Distribution" to "Seed Distribution"
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Changes ONE row's name; the program's
-- id, members, distributions, reports and returns are untouched (they point at the program by id).
-- Stops, changing nothing, if another program already uses the name "Seed Distribution".
-- ============================================================

BEGIN;

DO $$
DECLARE v_n INTEGER;
BEGIN
  IF EXISTS (SELECT 1 FROM public.cooperative_programs WHERE lower(btrim(program_name)) = 'seed distribution') THEN
    RAISE NOTICE 'A program named "Seed Distribution" already exists: nothing renamed.';
    RETURN;
  END IF;
  UPDATE public.cooperative_programs
     SET program_name = 'Seed Distribution'
   WHERE program_name = 'Peanut Seed Distribution';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n > 1 THEN
    RAISE EXCEPTION 'Expected to rename exactly one program, found %. Nothing was changed.', v_n;
  END IF;
  RAISE NOTICE 'Programs renamed: %', v_n;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECK  (expect 1 row, same id as before):
--   SELECT id, program_name FROM cooperative_programs WHERE program_name = 'Seed Distribution';
