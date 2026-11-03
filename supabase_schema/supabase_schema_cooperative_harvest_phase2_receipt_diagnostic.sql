-- READ ONLY: investigate the four legacy offers reported during Phase 2 rollout.
-- This uses only Phase 1 tables and returns ONE result set (four rows), so the
-- SQL editor cannot hide separate diagnostic result sets behind its last tab.
-- Run as the SQL-editor database owner. No updates, backfill, or RPC calls.
--
-- confirmed_by / sales recorded_by identify commercial actions, not necessarily
-- the physical receiver. Do not copy them into received_by without evidence.
-- Phase 1 copied confirmed_at into received_at for old confirmed offers.
-- A non-null received_at alone therefore does not establish physical receipt.
WITH target_ids(id) AS (VALUES
  ('8b3bc79c-e204-43fd-a059-6c226afef03e'::uuid),
  ('f8deda1f-b63f-4ff8-9f3e-37787551d255'::uuid),
  ('22cba6b1-b7ea-4c3d-9a11-7c36f94e0e29'::uuid),
  ('32c23551-cb70-4f88-b8ad-d4c4df5958da'::uuid)
)
SELECT targets.id AS offer_id,
  o.id IS NOT NULL AS offer_found,
  o.crop_name, o.status, o.confirmed_quantity_kg, o.unit,
  jsonb_build_object(
    'farmer_id', o.farmer_id,
    'farmer_name', farmer.full_name,
    'confirmed_at', o.confirmed_at,
    'confirmed_by', o.confirmed_by,
    'confirmed_by_name', confirmer.full_name,
    'delivered_at', o.delivered_at,
    'has_delivery_photo', NULLIF(btrim(o.delivery_photo_url), '') IS NOT NULL,
    'received_at', o.received_at,
    'received_by', o.received_by,
    'receipt_note', o.receipt_note
  ) AS offer_evidence,
  jsonb_build_object(
    'sale_id', o.member_sales_transaction_id,
    'sale_found', sale.id IS NOT NULL,
    'quantity', sale.quantity_kg,
    'sale_date', sale.sale_date,
    'recorded_by', sale.recorded_by,
    'recorded_by_name', recorder.full_name
  ) AS commercial_sale,
  jsonb_build_object(
    'source_batch_id', o.inventory_batch_id,
    'batch_found', batch.id IS NOT NULL,
    'batch_number', batch.batch_number,
    'source_farmer_id', batch.farmer_id,
    'crop_master_id', crop.crop_master_id,
    'harvest_record_id', harvest.id,
    'harvest_date', harvest.harvest_date,
    'storage_location', harvest.storage_location,
    'original_harvest_quantity', batch.quantity_kg,
    'available', batch.available_kg,
    'reserved', batch.reserved_kg,
    'sold', batch.sold_kg
  ) AS source_harvest,
  COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'action', e.action, 'at', e.created_at,
      'actor_id', e.actor_id, 'actor_name', actor.full_name,
      'quantity', e.quantity_kg, 'note', e.note
    ) ORDER BY e.created_at, e.id)
    FROM public.cooperative_offer_events e
    LEFT JOIN public.user_information actor ON actor.user_id=e.actor_id
    WHERE e.offer_id=o.id
  ), '[]'::jsonb) AS offer_history,
  COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'transaction_id', t.id, 'quantity', t.quantity,
      'created_at', t.created_at, 'recorded_by', t.recorded_by,
      'recorded_by_name', receiver.full_name, 'notes', t.notes,
      'inventory_id', t.inventory_id
    ) ORDER BY t.created_at, t.id)
    FROM public.inventory_transactions t
    LEFT JOIN public.user_information receiver ON receiver.user_id=t.recorded_by
    WHERE t.reference_id=o.id AND t.reference_type='cooperative_offer'
      AND t.transaction_type='harvest_received'
  ), '[]'::jsonb) AS receipt_transactions,
  COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'inventory_id', i.id, 'item_name', i.item_name, 'source', i.source,
      'on_hand', i.quantity_on_hand, 'reserved', i.quantity_reserved,
      'unit', i.unit, 'is_active', i.is_active,
      'all_recorded_receipts', (SELECT COALESCE(sum(t.quantity),0)
        FROM public.inventory_transactions t WHERE t.inventory_id=i.id
          AND t.transaction_type='harvest_received' AND t.reference_type='cooperative_offer'),
      'other_movements', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'id',t.id,'action',t.transaction_type,'quantity',t.quantity,'reference_id',t.reference_id)), '[]'::jsonb)
        FROM public.inventory_transactions t WHERE t.inventory_id=i.id
          AND (t.transaction_type='harvest_received' AND t.reference_type='cooperative_offer') IS NOT TRUE),
      'loan_link', EXISTS(SELECT 1 FROM public.loan_items_master WHERE inventory_item_id=i.id),
      'product_link', EXISTS(SELECT 1 FROM public.program_products WHERE inventory_item_id=i.id),
      'distribution_link', EXISTS(SELECT 1 FROM public.program_members WHERE inventory_item_id=i.id)
    ) ORDER BY i.id)
    FROM public.cooperative_inventory i
    WHERE i.id=o.coop_inventory_id OR EXISTS(
      SELECT 1 FROM public.inventory_transactions t WHERE t.inventory_id=i.id
        AND t.reference_id=o.id AND t.reference_type='cooperative_offer'
        AND t.transaction_type='harvest_received'
    )
  ), '[]'::jsonb) AS existing_cooperative_stock
FROM target_ids targets
LEFT JOIN public.cooperative_purchase_offers o ON o.id=targets.id
LEFT JOIN public.user_information farmer ON farmer.user_id=o.farmer_id
LEFT JOIN public.user_information confirmer ON confirmer.user_id=o.confirmed_by
LEFT JOIN public.member_sales_transactions sale ON sale.id=o.member_sales_transaction_id
LEFT JOIN public.user_information recorder ON recorder.user_id=sale.recorded_by
LEFT JOIN public.inventory_batches batch ON batch.id=o.inventory_batch_id
LEFT JOIN public.harvest_records harvest ON harvest.id=batch.harvest_record_id
LEFT JOIN public.farmer_crops crop ON crop.id=batch.crop_id
ORDER BY o.confirmed_at, targets.id;
