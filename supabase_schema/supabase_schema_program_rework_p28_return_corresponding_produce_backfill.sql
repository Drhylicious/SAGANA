-- ============================================================
-- SAGANA — p28: Harvest Return gives back the CORRESPONDING PRODUCE (one-time data backfill)
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. No table, function or trigger changes.
--
-- The app now sets, when seeds are distributed in a Harvest Return program, the member's return item to the
-- cooperative's Harvested Produce item of the SAME crop. This script does the same for members who were given
-- seeds BEFORE that: where the member has no return item yet, the return is not open yet, and Inventory has
-- exactly ONE cooperative-owned Harvested Produce item for that crop. Anything else is left as it is (the
-- return then falls back to the item given). Run after p27. Nothing is overwritten, nothing is deleted.
-- ============================================================

BEGIN;

DO $$
DECLARE v_n INTEGER;
BEGIN
  WITH cand AS (
    SELECT pm.id AS member_id,
           (array_agg(prod.id))[1] AS produce_id,
           count(prod.id)           AS produce_count
      FROM program_members pm
      JOIN cooperative_programs cp ON cp.id = pm.program_id AND cp.benefit_type = 'revenue_share'
      JOIN cooperative_inventory seed ON seed.id = pm.inventory_item_id
                                     AND seed.item_type = 'seeds_seedlings' AND seed.crop_master_id IS NOT NULL
      JOIN cooperative_inventory prod ON prod.crop_master_id = seed.crop_master_id
                                     AND prod.item_type = 'harvested_produce'
                                     AND prod.source_farmer_id IS NULL
                                     AND prod.is_active AND prod.archived_at IS NULL
     WHERE pm.distributed_at IS NOT NULL
       AND pm.return_item_id IS NULL
       AND cp.return_item_id IS NULL
       AND NOT EXISTS (SELECT 1 FROM program_returns r WHERE r.program_member_id = pm.id)
     GROUP BY pm.id
  )
  UPDATE program_members pm
     SET return_item_id = c.produce_id
    FROM cand c
   WHERE pm.id = c.member_id AND c.produce_count = 1;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE 'Members now returning the corresponding produce: %', v_n;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECK (who returns what; expect the produce item for seed programs):
--   SELECT ui.full_name, cp.program_name, g.item_name AS given, r.item_name AS returns, pm.return_quantity
--     FROM program_members pm
--     JOIN cooperative_programs cp ON cp.id = pm.program_id AND cp.benefit_type = 'revenue_share'
--     LEFT JOIN user_information ui ON ui.user_id = pm.farmer_id
--     LEFT JOIN cooperative_inventory g ON g.id = pm.inventory_item_id
--     LEFT JOIN cooperative_inventory r ON r.id = pm.return_item_id
--    WHERE pm.distributed_at IS NOT NULL;
