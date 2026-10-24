-- ============================================================
-- SAGANA — Inventory Management: required Source
-- (Manager Dashboard > Management Modules > Inventory Management)
--
-- The Add/Edit Inventory Item form's optional Notes field is replaced by a
-- required Source (where the item came from: supplier, donation, board
-- resolution...). The Loan Item Catalog reads it through its existing
-- cooperative_inventory join, so there is exactly one copy of the value.
--
-- WHAT THIS DOES
--   1. Adds cooperative_inventory.source (nullable text).
--   2. Adds enforce_inventory_source(): a row trigger that, on INSERT and on
--      any UPDATE that sets item_name, category, unit, unit_cost or source,
--      trims Source and refuses an empty value or one over 150 characters.
--      This is the backend rule; the form validation is only the first line.
--
-- WHAT IT DELIBERATELY DOES NOT DO
--   * It does not invent a Source for existing items. They stay NULL and the
--     app shows "Source not recorded" until the Manager edits the item and
--     enters one (the Edit form requires it).
--   * It does not use a CHECK constraint. A constraint, even NOT VALID, is
--     checked on every UPDATE of an old row, so restocking, adjusting stock,
--     issuing a loan or distributing a program benefit on a pre-existing item
--     would start failing. The trigger fires only when the identity columns
--     or source are written, so stock movements (quantity_on_hand,
--     quantity_reserved, reorder_level, is_active, last_restocked_at) are
--     never blocked.
--   * It does not touch the old notes column. Existing notes stay in the
--     database; the app no longer reads or writes them.
--
-- Apply this BEFORE releasing the matching app build: the new Loan Item
-- Catalog queries select cooperative_inventory.source.
--
-- Not applied automatically. Run in the Supabase SQL editor, then run the
-- verification block at the end.
-- ============================================================

BEGIN;

ALTER TABLE public.cooperative_inventory
  ADD COLUMN IF NOT EXISTS source TEXT;

COMMENT ON COLUMN public.cooperative_inventory.source IS
  'Where the item came from (supplier, donation, resolution...). Required for '
  'every new or edited item (enforce_inventory_source). NULL only on items '
  'created before this column existed. Read by the Loan Item Catalog through '
  'its cooperative_inventory join; never copied.';

CREATE OR REPLACE FUNCTION public.enforce_inventory_source()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.source := btrim(coalesce(NEW.source, ''));

  IF NEW.source = '' THEN
    RAISE EXCEPTION 'Source is required for an inventory item.';
  END IF;
  IF char_length(NEW.source) > 150 THEN
    RAISE EXCEPTION 'Source must be 150 characters or fewer.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_inventory_source ON public.cooperative_inventory;
CREATE TRIGGER trg_enforce_inventory_source
  BEFORE INSERT OR UPDATE OF item_name, category, unit, unit_cost, source
  ON public.cooperative_inventory
  FOR EACH ROW EXECUTE FUNCTION public.enforce_inventory_source();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION (read-only unless stated) ──────────────────
-- 1. Column and trigger exist (expect 1 row each):
--    SELECT column_name FROM information_schema.columns
--    WHERE table_schema='public' AND table_name='cooperative_inventory' AND column_name='source';
--    SELECT tgname FROM pg_trigger WHERE tgname='trg_enforce_inventory_source';
--
-- 2. Items still without a Source (these show "Source not recorded"):
--    SELECT id, item_name, category FROM public.cooperative_inventory
--    WHERE source IS NULL OR btrim(source) = '' ORDER BY item_name;
--
-- 3. Backend rule (run inside a transaction and roll back, so nothing is kept).
--    Each statement must fail with the message shown:
--    BEGIN;
--      INSERT INTO public.cooperative_inventory (item_name, category, unit)
--      VALUES ('zz_source_test', 'Fertilizer', 'bag');          -- "Source is required..."
--    ROLLBACK;
--    BEGIN;
--      INSERT INTO public.cooperative_inventory (item_name, category, unit, source)
--      VALUES ('zz_source_test', 'Fertilizer', 'bag', repeat('x', 151)); -- "...150 characters or fewer."
--    ROLLBACK;
--
-- 4. Stock movements on an item with no Source are NOT blocked (expect UPDATE 1):
--    BEGIN;
--      UPDATE public.cooperative_inventory SET quantity_on_hand = quantity_on_hand
--      WHERE id = (SELECT id FROM public.cooperative_inventory WHERE source IS NULL LIMIT 1);
--    ROLLBACK;
-- ============================================================
