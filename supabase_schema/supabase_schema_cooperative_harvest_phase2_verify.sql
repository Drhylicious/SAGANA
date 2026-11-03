-- READ ONLY. All anomaly queries below should return zero rows, except the one
-- marked INFORMATIONAL.

-- Legacy offers (settled at acceptance, no delivery or receipt) are skipped by
-- Phase 2 and must not have a batch or a receipt transaction.
-- 1. Must return zero rows: a completed offer with receipt activity needs exactly one batch.
SELECT o.id, o.coop_inventory_id, count(b.id) AS batch_count
FROM public.cooperative_purchase_offers o
LEFT JOIN public.cooperative_harvest_batches b ON b.offer_id=o.id
WHERE o.status='completed'
  AND NOT (o.received_by IS NULL AND o.delivered_at IS NULL
    AND NULLIF(btrim(o.delivery_photo_url), '') IS NULL
    AND NOT EXISTS(SELECT 1 FROM public.cooperative_offer_events e WHERE e.offer_id=o.id AND e.action IN ('delivered','received'))
    AND NOT EXISTS(SELECT 1 FROM public.inventory_transactions t WHERE t.reference_id=o.id
      AND t.reference_type='cooperative_offer' AND t.transaction_type='harvest_received'))
GROUP BY o.id HAVING count(b.id) <> 1 OR min(b.inventory_id::text) IS DISTINCT FROM o.coop_inventory_id::text;

-- 1b. INFORMATIONAL: legacy offers skipped on purpose. Their sales stay recorded;
-- none of them has a batch, receipt transaction or cooperative stock.
SELECT o.id, o.crop_name, o.confirmed_quantity_kg, o.confirmed_at,
  o.member_sales_transaction_id, o.coop_inventory_id,
  EXISTS(SELECT 1 FROM public.cooperative_harvest_batches b WHERE b.offer_id=o.id) AS has_batch_should_be_false
FROM public.cooperative_purchase_offers o
WHERE o.status='completed' AND o.received_by IS NULL AND o.delivered_at IS NULL
  AND NULLIF(btrim(o.delivery_photo_url), '') IS NULL
  AND NOT EXISTS(SELECT 1 FROM public.cooperative_offer_events e WHERE e.offer_id=o.id AND e.action IN ('delivered','received'))
ORDER BY o.confirmed_at;

SELECT source_farmer_id, source_crop_id, lower(btrim(unit)), count(*)
FROM public.cooperative_inventory WHERE source_farmer_id IS NOT NULL
GROUP BY 1,2,3 HAVING count(*)>1;

SELECT b.id FROM public.cooperative_harvest_batches b
JOIN public.cooperative_purchase_offers o ON o.id=b.offer_id
JOIN public.inventory_transactions t ON t.id=b.inventory_transaction_id
WHERE b.original_quantity IS DISTINCT FROM o.confirmed_quantity_kg
 OR b.original_quantity IS DISTINCT FROM t.quantity
 OR b.inventory_id <> t.inventory_id OR b.source_farmer_id <> o.farmer_id
 OR b.source_transaction_id IS DISTINCT FROM o.member_sales_transaction_id
 OR b.unit IS DISTINCT FROM lower(btrim(o.unit));

-- For managed Farmer harvest: original receipt/addition batches plus signed
-- corrections/sales/distributions = current quantity. No batch is rewritten.
SELECT i.id, i.source, i.item_name, i.unit, i.quantity_on_hand,
  COALESCE((SELECT sum(t.quantity) FROM public.inventory_transactions t WHERE t.inventory_id=i.id),0) AS ledger_quantity
FROM public.cooperative_inventory i
WHERE i.source_farmer_id IS NOT NULL AND i.quantity_on_hand IS DISTINCT FROM
  COALESCE((SELECT sum(t.quantity) FROM public.inventory_transactions t WHERE t.inventory_id=i.id),0);

SELECT t.id FROM public.inventory_transactions t
LEFT JOIN public.cooperative_inventory_history h ON h.transaction_id=t.id
WHERE h.id IS NULL;
SELECT id FROM public.cooperative_inventory WHERE archived_at IS NOT NULL
 AND (is_active OR quantity_on_hand <> 0 OR quantity_reserved <> 0);

-- Crop/unit overview: the example produces 160 kg across two Farmer rows.
SELECT source_crop_id, min(item_name) AS crop, unit, sum(quantity_on_hand) AS on_hand,
  count(*) AS farmer_items FROM public.cooperative_inventory
WHERE is_active AND source_farmer_id IS NOT NULL GROUP BY source_crop_id,unit;

-- Read-only privileges must be false for each write below.
SELECT has_table_privilege('authenticated','public.cooperative_harvest_batches','INSERT') AS can_insert_batch,
 has_table_privilege('authenticated','public.cooperative_inventory_history','DELETE') AS can_erase_history,
 has_table_privilege('authenticated','public.inventory_transactions','UPDATE') AS can_rewrite_transaction,
 has_function_privilege('authenticated','public._coop_receive_harvest(uuid)','EXECUTE') AS can_call_internal_transfer,
 has_function_privilege('authenticated','public.adjust_inventory_stock(uuid,numeric,text,text,uuid)','EXECUTE') AS can_use_old_adjustment;
