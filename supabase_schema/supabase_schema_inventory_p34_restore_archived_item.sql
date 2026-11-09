-- ============================================================
-- SAGANA — p34: restore an archived Inventory item
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Adds ONE function; no table or data changes.
--
-- Archiving (delete_inventory_item) keeps every record and only switches the item off. This is its undo:
--   * Only a Manager or Officer can restore.
--   * The item becomes active again, with the stock it had (archiving needs zero stock, so that is 0).
--   * It is refused if an ACTIVE item already exists with the same identity, so two live items can never be
--     the same thing: the same crop + Item Type + unit for a crop item, or the same name + Item Type for any
--     other cooperative item. The message tells staff to archive or rename the other one first.
--   * It does NOT switch anything else back on: a loan catalog entry or cooperative product that archiving
--     turned off stays off until staff turn it on again, deliberately.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.restore_inventory_item(p_inventory_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE i cooperative_inventory;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can restore inventory.';
  END IF;
  SELECT * INTO i FROM cooperative_inventory WHERE id = p_inventory_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'RESTORE_CONFLICT: Inventory item not found.';
  END IF;
  IF i.archived_at IS NULL AND i.is_active THEN
    RETURN;                                   -- already active
  END IF;

  IF i.source_farmer_id IS NULL THEN
    IF i.crop_master_id IS NOT NULL AND EXISTS (
         SELECT 1 FROM cooperative_inventory o
          WHERE o.id <> i.id AND o.archived_at IS NULL AND o.source_farmer_id IS NULL
            AND o.item_type = i.item_type AND o.crop_master_id = i.crop_master_id
            AND lower(btrim(o.unit)) = lower(btrim(i.unit))) THEN
      RAISE EXCEPTION 'RESTORE_CONFLICT: An active item for the same crop, type and unit already exists.';
    END IF;
    IF EXISTS (
         SELECT 1 FROM cooperative_inventory o
          WHERE o.id <> i.id AND o.archived_at IS NULL AND o.source_farmer_id IS NULL
            AND o.item_type = i.item_type AND lower(btrim(o.item_name)) = lower(btrim(i.item_name))) THEN
      RAISE EXCEPTION 'RESTORE_CONFLICT: An active item with the same name and type already exists.';
    END IF;
  END IF;

  UPDATE cooperative_inventory SET is_active = true, archived_at = NULL WHERE id = i.id;
END $$;
REVOKE ALL ON FUNCTION public.restore_inventory_item(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.restore_inventory_item(uuid) TO authenticated;

DO $$ BEGIN
  IF to_regclass('public.staff_permission_targets') IS NOT NULL THEN
    INSERT INTO public.staff_permission_targets (kind, name, module)
    VALUES ('rpc', 'restore_inventory_item', 'dashboard')
    ON CONFLICT (kind, name) DO NOTHING;
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECKS
-- X1  The function exists (expect 1 row):
--     SELECT proname FROM pg_proc WHERE proname = 'restore_inventory_item';
-- X2  After a real restore: the item is live again and the change was logged with who and when:
--     SELECT item_name, is_active, archived_at FROM cooperative_inventory WHERE item_name = 'Pig';
--     SELECT created_at, actor_name, description FROM admin_activity_log WHERE table_name = 'cooperative_inventory' ORDER BY created_at DESC LIMIT 5;
