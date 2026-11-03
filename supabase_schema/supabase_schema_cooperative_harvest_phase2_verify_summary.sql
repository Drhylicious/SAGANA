-- READ ONLY. Same checks as supabase_schema_cooperative_harvest_phase2_verify.sql,
-- returned as ONE result set (the SQL editor shows only the last result of a
-- script). Every row's "found" must equal its "expected".
SELECT check_name, expected, found, (expected = found) AS ok FROM (
  SELECT 1 AS n, 'modern completed offers without exactly one matching batch' AS check_name, 0 AS expected,
    (SELECT count(*)::int FROM (
      SELECT o.id FROM public.cooperative_purchase_offers o
      LEFT JOIN public.cooperative_harvest_batches b ON b.offer_id=o.id
      WHERE o.status='completed'
        AND NOT (o.received_by IS NULL AND o.delivered_at IS NULL
          AND NULLIF(btrim(o.delivery_photo_url), '') IS NULL
          AND NOT EXISTS(SELECT 1 FROM public.cooperative_offer_events e WHERE e.offer_id=o.id AND e.action IN ('delivered','received'))
          AND NOT EXISTS(SELECT 1 FROM public.inventory_transactions t WHERE t.reference_id=o.id
            AND t.reference_type='cooperative_offer' AND t.transaction_type='harvest_received'))
      GROUP BY o.id HAVING count(b.id) <> 1 OR min(b.inventory_id::text) IS DISTINCT FROM max(o.coop_inventory_id::text)
    ) x) AS found
  UNION ALL SELECT 2, 'legacy offers skipped on purpose (informational: the four old offers)', 4,
    (SELECT count(*)::int FROM public.cooperative_purchase_offers o
      WHERE o.status='completed' AND o.received_by IS NULL AND o.delivered_at IS NULL
        AND NULLIF(btrim(o.delivery_photo_url), '') IS NULL
        AND NOT EXISTS(SELECT 1 FROM public.cooperative_offer_events e WHERE e.offer_id=o.id AND e.action IN ('delivered','received')))
  UNION ALL SELECT 3, 'legacy offers that wrongly have a batch', 0,
    (SELECT count(*)::int FROM public.cooperative_purchase_offers o
      WHERE o.status='completed' AND o.received_by IS NULL AND o.delivered_at IS NULL
        AND NULLIF(btrim(o.delivery_photo_url), '') IS NULL
        AND NOT EXISTS(SELECT 1 FROM public.cooperative_offer_events e WHERE e.offer_id=o.id AND e.action IN ('delivered','received'))
        AND EXISTS(SELECT 1 FROM public.cooperative_harvest_batches b WHERE b.offer_id=o.id))
  UNION ALL SELECT 4, 'duplicate Farmer + Crop + Unit items', 0,
    (SELECT count(*)::int FROM (SELECT 1 FROM public.cooperative_inventory WHERE source_farmer_id IS NOT NULL
      GROUP BY source_farmer_id, source_crop_id, lower(btrim(unit)) HAVING count(*)>1) x)
  UNION ALL SELECT 5, 'batches that disagree with their offer or receipt transaction', 0,
    (SELECT count(*)::int FROM public.cooperative_harvest_batches b
      JOIN public.cooperative_purchase_offers o ON o.id=b.offer_id
      JOIN public.inventory_transactions t ON t.id=b.inventory_transaction_id
      WHERE b.original_quantity IS DISTINCT FROM o.confirmed_quantity_kg
        OR b.original_quantity IS DISTINCT FROM t.quantity
        OR b.inventory_id <> t.inventory_id OR b.source_farmer_id <> o.farmer_id
        OR b.source_transaction_id IS DISTINCT FROM o.member_sales_transaction_id
        OR b.unit IS DISTINCT FROM lower(btrim(o.unit)))
  UNION ALL SELECT 6, 'Farmer items whose on-hand differs from their transaction ledger', 0,
    (SELECT count(*)::int FROM public.cooperative_inventory i
      WHERE i.source_farmer_id IS NOT NULL AND i.quantity_on_hand IS DISTINCT FROM
        COALESCE((SELECT sum(t.quantity) FROM public.inventory_transactions t WHERE t.inventory_id=i.id),0))
  UNION ALL SELECT 7, 'stock transactions with no history entry', 0,
    (SELECT count(*)::int FROM public.inventory_transactions t
      LEFT JOIN public.cooperative_inventory_history h ON h.transaction_id=t.id WHERE h.id IS NULL)
  UNION ALL SELECT 8, 'archived items that are active or still hold stock', 0,
    (SELECT count(*)::int FROM public.cooperative_inventory WHERE archived_at IS NOT NULL
      AND (is_active OR quantity_on_hand <> 0 OR quantity_reserved <> 0))
  UNION ALL SELECT 9, 'client write privileges that should not exist (insert batch, erase history, rewrite transaction, call internal transfer, use old adjustment)', 0,
    (has_table_privilege('authenticated','public.cooperative_harvest_batches','INSERT')::int
     + has_table_privilege('authenticated','public.cooperative_inventory_history','DELETE')::int
     + has_table_privilege('authenticated','public.inventory_transactions','UPDATE')::int
     + has_function_privilege('authenticated','public._coop_receive_harvest(uuid)','EXECUTE')::int
     + has_function_privilege('authenticated','public.adjust_inventory_stock(uuid,numeric,text,text,uuid)','EXECUTE')::int)
) checks ORDER BY n;
