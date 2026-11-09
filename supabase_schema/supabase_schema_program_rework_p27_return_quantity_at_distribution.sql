-- ============================================================
-- SAGANA — p27: the expected return quantity is set when the item is distributed, not on the program
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. No data is changed.
--
--   1. program_missing_fields(): a Harvest Return program no longer needs a "return_quantity" to count as
--      complete (the program form no longer has that field). Everything else in the rule is as in p17.
--   2. A Harvest Return Farmer cannot be marked as given the item unless they have an agreed return quantity
--      (their own, set at distribution through set_member_return_arrangement, else an older program's default).
--      This moves the rule the program form used to enforce into the database.
--
-- Run AFTER p25. Nothing else changes: the return is still opened from the agreed quantity when the
-- outcome is confirmed (_program_open_return), credited to the item that was given.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.set_member_return_arrangement(uuid,uuid,numeric)') IS NULL THEN
    RAISE EXCEPTION 'Apply p25 first.';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.program_missing_fields(p public.cooperative_programs)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT array_remove(ARRAY[
    CASE WHEN p.program_name IS NULL OR btrim(p.program_name) = ''  THEN 'name' END,
    CASE WHEN p.program_type IS NULL OR btrim(p.program_type) = ''  THEN 'type' END,
    CASE WHEN p.image_url    IS NULL OR btrim(p.image_url)    = ''  THEN 'photo' END,
    CASE WHEN p.description  IS NULL OR btrim(p.description)  = ''  THEN 'description' END,
    CASE WHEN p.budget       IS NULL OR p.budget <= 0               THEN 'budget' END,
    CASE WHEN COALESCE(array_length(p.source_categories, 1), 0) = 0
          AND (p.program_purpose = 'sales' OR p.distribution_item_id IS NULL)
                                                                    THEN 'sources' END
  ], NULL);
$$;

CREATE OR REPLACE FUNCTION public._program_members_require_return_quantity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_p cooperative_programs%ROWTYPE;
BEGIN
  SELECT * INTO v_p FROM cooperative_programs WHERE id = NEW.program_id;
  IF FOUND AND v_p.benefit_type = 'revenue_share'
     AND COALESCE(NEW.return_quantity, v_p.return_quantity, 0) <= 0 THEN
    RAISE EXCEPTION 'RETURN_QUANTITY_REQUIRED: Enter the quantity this Farmer is expected to return before distributing.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_program_members_require_return_quantity ON public.program_members;
CREATE TRIGGER trg_program_members_require_return_quantity
  BEFORE UPDATE OF distributed_at ON public.program_members
  FOR EACH ROW
  WHEN (OLD.distributed_at IS NULL AND NEW.distributed_at IS NOT NULL)
  EXECUTE FUNCTION public._program_members_require_return_quantity();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECKS
-- Q1  No Harvest Return program is "incomplete" only because of the return quantity (expect 0 rows with it):
--     SELECT program_name, public.program_missing_fields(cp) FROM cooperative_programs cp
--      WHERE 'return_quantity' = ANY (public.program_missing_fields(cp));
-- Q2  The new guard is installed (expect 1 row):
--     SELECT tgname FROM pg_trigger WHERE tgname = 'trg_program_members_require_return_quantity' AND NOT tgisinternal;
