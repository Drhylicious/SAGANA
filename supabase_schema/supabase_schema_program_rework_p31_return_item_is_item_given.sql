-- ============================================================
-- SAGANA — p31: ONE rule: what the Farmer returns is exactly the item that was given
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after p30.
--
-- Undoes the seed-to-produce idea (p28) and the older "return item" choices, and makes the rule impossible to
-- break from any screen:
--   1. program_members.return_item_id is cleared where the return is not open yet. The agreed return QUANTITY
--      is kept. Returns that are ALREADY open are left exactly as they are (their records stand).
--   2. cooperative_programs.return_item_id (an older program-level default) is cleared. It was never set by
--      the new program form.
--   3. A trigger keeps program_members.return_item_id empty from now on, so the return always falls back to the
--      item given (_program_open_return uses COALESCE(return item, program default, item given)).
-- Nothing is deleted. Quantities, receipts, history and inventory are untouched.
-- ============================================================

BEGIN;

DO $$
DECLARE v_m INTEGER; v_p INTEGER;
BEGIN
  UPDATE program_members pm
     SET return_item_id = NULL
   WHERE pm.return_item_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM program_returns r WHERE r.program_member_id = pm.id);
  GET DIAGNOSTICS v_m = ROW_COUNT;

  UPDATE cooperative_programs SET return_item_id = NULL WHERE return_item_id IS NOT NULL;
  GET DIAGNOSTICS v_p = ROW_COUNT;

  RAISE NOTICE 'Member return items cleared: %; program defaults cleared: %', v_m, v_p;
END $$;

CREATE OR REPLACE FUNCTION public._program_member_return_item_is_given()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  NEW.return_item_id := NULL;      -- the item returned is always the item given
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_program_member_return_item_is_given ON public.program_members;
CREATE TRIGGER trg_program_member_return_item_is_given
  BEFORE INSERT OR UPDATE OF return_item_id ON public.program_members
  FOR EACH ROW EXECUTE FUNCTION public._program_member_return_item_is_given();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECKS
-- S1  No member has a separate return item (expect 0 rows):
--     SELECT id FROM program_members WHERE return_item_id IS NOT NULL;
-- S2  Any return that was ALREADY open against a different item than was given (information only):
--     SELECT r.id, r.crop_name AS returns, g.item_name AS given
--       FROM program_returns r
--       JOIN program_members pm ON pm.id = r.program_member_id
--       JOIN cooperative_inventory g ON g.id = pm.inventory_item_id
--      WHERE r.inventory_item_id IS DISTINCT FROM pm.inventory_item_id;
