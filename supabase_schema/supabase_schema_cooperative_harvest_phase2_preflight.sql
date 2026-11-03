-- READ ONLY. Run before Phase 2. Inspect each result; do not rerun old migrations.
-- 1. Current receipt/RPC definitions and authorization. Save these with a backup.
SELECT p.oid::regprocedure, pg_get_functiondef(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN
 ('confirm_cooperative_offer_receipt','_coop_receive_harvest','adjust_inventory_stock',
  'delete_inventory_item','is_staff','_coop_offer_status_flow');
SELECT tablename, policyname, cmd, qual, with_check FROM pg_policies
WHERE schemaname='public' AND tablename IN
 ('cooperative_inventory','inventory_transactions','cooperative_purchase_offers','inventory_batches');
SELECT event_object_table, trigger_name, action_statement FROM information_schema.triggers
WHERE event_object_schema='public' AND event_object_table IN
 ('cooperative_inventory','inventory_transactions','cooperative_purchase_offers');

-- 2a. INFORMATIONAL: legacy completed offers that Phase 2 will SKIP. Phase 1
-- converted old confirmed offers to completed and copied confirmed_at into
-- received_at; with no delivery, receipt event, receiver or receipt transaction
-- there is no physical receipt. Their sales are kept; no receiver/date is invented.
SELECT o.id, o.farmer_id, o.crop_name, o.confirmed_quantity_kg, o.confirmed_at, o.received_at,
  o.member_sales_transaction_id
FROM public.cooperative_purchase_offers o
WHERE o.status='completed' AND o.received_by IS NULL AND o.delivered_at IS NULL
  AND NULLIF(btrim(o.delivery_photo_url), '') IS NULL
  AND NOT EXISTS(SELECT 1 FROM public.cooperative_offer_events e WHERE e.offer_id=o.id AND e.action IN ('delivered','received'))
  AND NOT EXISTS(SELECT 1 FROM public.inventory_transactions t WHERE t.reference_id=o.id
    AND t.reference_type='cooperative_offer' AND t.transaction_type='harvest_received')
ORDER BY o.confirmed_at;

-- 2b. Must return zero rows. A completed offer that is NOT legacy but lacks a
-- receiver, receipt date or sale is inconsistent data; the migration aborts on it.
SELECT o.id, o.farmer_id, o.crop_name, o.status, o.confirmed_at, o.received_at, o.received_by,
  o.delivered_at, o.member_sales_transaction_id
FROM public.cooperative_purchase_offers o
WHERE o.status='completed'
  AND (o.received_at IS NULL OR o.received_by IS NULL OR o.member_sales_transaction_id IS NULL)
  AND NOT (o.received_by IS NULL AND o.delivered_at IS NULL
    AND NULLIF(btrim(o.delivery_photo_url), '') IS NULL
    AND NOT EXISTS(SELECT 1 FROM public.cooperative_offer_events e WHERE e.offer_id=o.id AND e.action IN ('delivered','received'))
    AND NOT EXISTS(SELECT 1 FROM public.inventory_transactions t WHERE t.reference_id=o.id
      AND t.reference_type='cooperative_offer' AND t.transaction_type='harvest_received'));

-- 3. Must return zero rows. Resolve missing identities / source records first.
SELECT o.id, o.farmer_id, o.crop_name, b.id AS batch_id, fc.crop_master_id,
  h.harvest_date, u.full_name
FROM public.cooperative_purchase_offers o
LEFT JOIN public.inventory_batches b ON b.id=o.inventory_batch_id
LEFT JOIN public.farmer_crops fc ON fc.id=b.crop_id
LEFT JOIN public.harvest_records h ON h.id=b.harvest_record_id
LEFT JOIN public.user_information u ON u.user_id=o.farmer_id
WHERE o.status='completed'
  AND NOT (o.received_by IS NULL AND o.delivered_at IS NULL
    AND NULLIF(btrim(o.delivery_photo_url), '') IS NULL
    AND NOT EXISTS(SELECT 1 FROM public.cooperative_offer_events e WHERE e.offer_id=o.id AND e.action IN ('delivered','received'))
    AND NOT EXISTS(SELECT 1 FROM public.inventory_transactions t WHERE t.reference_id=o.id
      AND t.reference_type='cooperative_offer' AND t.transaction_type='harvest_received'))
  AND (fc.crop_master_id IS NULL OR h.id IS NULL
  OR b.farmer_id IS DISTINCT FROM o.farmer_id OR NULLIF(btrim(u.full_name),'') IS NULL
  OR o.confirmed_quantity_kg IS NULL OR o.confirmed_quantity_kg <= 0);

-- 4. Pools that cannot be split automatically. Any row needs reconciliation.
-- Do NOT reset a consumed pool to its original receipt total to make this pass.
WITH receipts AS (
 SELECT inventory_id, sum(quantity) total FROM public.inventory_transactions
 WHERE transaction_type='harvest_received' AND reference_type='cooperative_offer'
 GROUP BY inventory_id
)
SELECT i.id, i.item_name, i.quantity_on_hand, r.total AS original_receipts, i.quantity_reserved,
  EXISTS(SELECT 1 FROM public.loan_items_master WHERE inventory_item_id=i.id) AS loan_link,
  EXISTS(SELECT 1 FROM public.program_products WHERE inventory_item_id=i.id) AS product_link,
  EXISTS(SELECT 1 FROM public.program_members WHERE inventory_item_id=i.id) AS distribution_link,
  (SELECT jsonb_agg(to_jsonb(t)) FROM public.inventory_transactions t
   WHERE t.inventory_id=i.id AND NOT(t.transaction_type='harvest_received' AND t.reference_type='cooperative_offer')) AS other_movements
FROM public.cooperative_inventory i JOIN receipts r ON r.inventory_id=i.id
WHERE i.quantity_on_hand <> r.total OR i.quantity_reserved <> 0
 OR EXISTS(SELECT 1 FROM public.inventory_transactions t WHERE t.inventory_id=i.id
   AND NOT(t.transaction_type='harvest_received' AND t.reference_type='cooperative_offer'))
 OR EXISTS(SELECT 1 FROM public.loan_items_master WHERE inventory_item_id=i.id)
 OR EXISTS(SELECT 1 FROM public.program_products WHERE inventory_item_id=i.id)
 OR EXISTS(SELECT 1 FROM public.program_members WHERE inventory_item_id=i.id);

-- 5. Must return zero rows: receipt ledger/source mismatch or duplicate.
SELECT t.id, t.reference_id, t.quantity, o.confirmed_quantity_kg, o.status
FROM public.inventory_transactions t LEFT JOIN public.cooperative_purchase_offers o ON o.id=t.reference_id
WHERE t.transaction_type='harvest_received' AND t.reference_type='cooperative_offer'
 AND (o.id IS NULL OR o.status <> 'completed' OR t.quantity IS DISTINCT FROM o.confirmed_quantity_kg);
SELECT reference_id, count(*) FROM public.inventory_transactions
WHERE transaction_type='harvest_received' AND reference_type='cooperative_offer'
GROUP BY reference_id HAVING count(*)>1;

-- 6. Existing manual duplicate names: review; Phase 2 refuses NEW duplicates
-- without deleting or merging these existing records.
SELECT lower(btrim(item_name)), count(*) FROM public.cooperative_inventory
WHERE category <> 'Harvest Stock' GROUP BY 1 HAVING count(*)>1;
