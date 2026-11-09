-- ============================================================
-- SAGANA — Program Management p19: a Completed program's products are read-only
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run.
-- Run AFTER p18 (it needs nothing from it; the order is only for tidiness).
--
-- WHY
--   A Completed program no longer accepts members, distributions or purchases. Its
--   products should be just as frozen: no new product, no price change and no On sale
--   switch. The Manage Products screen already shows them read-only; this makes the
--   database refuse it too, so the rule holds for every caller and not only the screen.
--
-- WHAT IT DOES
--   A trigger on program_products refuses any INSERT or UPDATE once the program's
--   status is 'completed' (PROGRAM_COMPLETED). Direct SQL with no signed-in user is not
--   blocked, like the program status and Benefit Type locks.
--
-- Nothing is deleted or rewritten; existing products, prices and purchases are untouched.
-- Products are still never deleted (that guard already exists).
-- ============================================================

-- PREVIEW (read-only): products that belong to a completed program (they become read-only)
SELECT cp.program_name, count(pp.id) AS products
  FROM cooperative_programs cp
  LEFT JOIN program_products pp ON pp.program_id = cp.id
 WHERE cp.status = 'completed'
 GROUP BY cp.program_name
 ORDER BY cp.program_name;

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.program_products') IS NULL THEN
    RAISE EXCEPTION 'Apply the Product Sales scripts first.';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.guard_completed_program_products()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND EXISTS (SELECT 1 FROM cooperative_programs cp WHERE cp.id = NEW.program_id AND cp.status = 'completed') THEN
    RAISE EXCEPTION 'PROGRAM_COMPLETED: This program is completed. Its products can no longer be changed.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_completed_program_products ON public.program_products;
CREATE TRIGGER trg_guard_completed_program_products
  BEFORE INSERT OR UPDATE ON public.program_products
  FOR EACH ROW EXECUTE FUNCTION public.guard_completed_program_products();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  The trigger exists:
--     SELECT tgname FROM pg_trigger WHERE tgname = 'trg_guard_completed_program_products';
-- V2  From the app, on a Completed program: the Manage Products switch, Edit price and
--     + button are gone / disabled, and a direct change is refused with PROGRAM_COMPLETED.
-- V3  An active program's products still change normally (toggle, edit price, add).
-- V4  Nothing was lost (same counts as before):
--     SELECT count(*) FROM program_products;
