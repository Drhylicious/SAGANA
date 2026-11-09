-- ============================================================
-- SAGANA — Supply Chain Management: read-only tracking model
--
-- FOR YOUR REVIEW — NOT APPLIED. Safe to re-run (CREATE OR REPLACE only).
--
-- WHAT IT DOES
--   Adds two READ-ONLY functions. Nothing is created, changed or deleted in any
--   table, and no existing function, trigger, policy or RPC is touched.
--
--   get_supply_chain_records(p_from, p_to)
--     One row per supply movement that really happened (or, for orders, is
--     still being fulfilled), read from the records the other modules already
--     keep. Nothing is copied or stored a second time:
--       stage 'source'   Inventory Management: a restock from a supplier / source
--                        (inventory_transactions 'restock', manual)
--       stage 'program'  Program Management: a benefit distributed to a member
--                        (program_members.distributed_at) and a harvest return
--                        received (program_return_receipts) — the receipt names
--                        the Cooperative Inventory item that received it
--       stage 'offer'    Offer to Cooperative: a completed purchase received into
--                        Cooperative Inventory (cooperative_harvest_batches)
--       stage 'consumer' Order Management: Cooperative Product orders
--                        (program_product_purchases) and Farmer Marketplace
--                        orders (orders), pickup or delivery
--       stage 'other'    Loans: inventory items issued on a loan (the loan_issued
--                        ledger row) — a real outgoing movement of cooperative stock
--     Cancelled / rejected orders are not supply movements and are left out.
--     is_confirmed = the supply has actually moved (an order counts once it is
--     completed); an order still being fulfilled is returned with FALSE.
--
--   get_supply_chain_totals(p_year)
--     Counts confirmed movements for a calendar year (Asia/Manila), incoming and
--     outgoing, plus the orders still in progress. Feeds the Dashboard
--     "Total Supplies" card. Defaults to the current year, so it starts again
--     every January.
--
--   Both return nothing / zeros unless the caller is a Manager or Officer
--   (is_staff()). Both are SECURITY DEFINER only so that one staff query can
--   read the cooperative ledgers whatever the table's own policy says.
--
-- DOES NOT CHANGE: inventory, programs, offers, orders, loans, stock or any
-- business rule. The old farm-location map used no database object of its own
-- (it read farmer_profiles / farmer_crops, which other modules still use), so
-- there is nothing to drop on the backend.
--
-- Requires (already part of the app): Cooperative harvest phase 2, program
-- rework p15 + p17, unify m04 (Cooperative orders) and the order fulfillment
-- workflow. The check below stops with a clear message if one is missing.
-- ============================================================

BEGIN;

DO $$
DECLARE
  need text[][] := ARRAY[
    ['cooperative_inventory',          'source_farmer_id'],
    ['cooperative_harvest_batches',    'offer_id'],
    ['cooperative_harvest_batches',    'source_batch_number'],
    ['inventory_transactions',         'reference_type'],
    ['program_members',                'distributed_at'],
    ['program_members',                'distributed_unit'],
    ['program_returns',                'inventory_item_id'],
    ['program_return_receipts',        'inventory_transaction_id'],
    ['program_product_purchases',      'order_number'],
    ['program_product_purchases',      'fulfillment_method'],
    ['program_product_purchases',      'completed_at'],
    ['orders',                         'received_at'],
    ['orders',                         'fulfillment_method'],
    ['farmer_loans',                   'reference_no'],
    ['marketplace_listings',           'inventory_batch_id'],
    ['inventory_batches',              'batch_number']
  ];
  i int;
BEGIN
  FOR i IN 1 .. array_length(need, 1) LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = need[i][1] AND column_name = need[i][2]
    ) THEN
      RAISE EXCEPTION 'Supply Chain read model needs %.% — apply the earlier script that adds it first.',
        need[i][1], need[i][2];
    END IF;
  END LOOP;
  IF to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'is_staff() is missing (role-based staff access script).';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.get_supply_chain_records(
  p_from timestamptz DEFAULT NULL,
  p_to   timestamptz DEFAULT NULL
)
RETURNS TABLE (
  record_key         text,
  stage              text,
  record_type        text,
  direction          text,
  occurred_at        timestamptz,
  is_confirmed       boolean,
  item_name          text,
  category           text,
  quantity           numeric,
  unit               text,
  inventory_id       uuid,
  item_source        text,
  from_name          text,
  from_role          text,
  to_name            text,
  to_role            text,
  farmer_name        text,
  program_name       text,
  reference_label    text,
  batch_number       text,
  fulfillment_method text,
  fulfillment_status text,
  ref_type           text,
  ref_id             uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
WITH
nm AS (
  SELECT user_id, full_name FROM user_information
),
rl AS (
  SELECT DISTINCT ON (user_id) user_id, role FROM user_roles ORDER BY user_id, role
),
-- Where an inventory item came from: the Farmer its stock belongs to, else the
-- Source typed on the item (supplier, donation, resolution ...).
io AS (
  SELECT ci.id, ci.item_name, ci.category, ci.unit,
         COALESCE(f.full_name, NULLIF(btrim(ci.source), '')) AS origin,
         (ci.source_farmer_id IS NOT NULL)                   AS from_farmer
    FROM cooperative_inventory ci
    LEFT JOIN nm f ON f.user_id = ci.source_farmer_id
),
rec AS (
  -- 1. SUPPLIER / INVENTORY SOURCE: stock restocked from a supplier or source.
  SELECT 'tx:' || t.id::text, 'source', 'inventory_restock', 'incoming',
         t.created_at, TRUE,
         io.item_name, io.category, abs(t.quantity)::numeric, io.unit, io.id, io.origin,
         io.origin,
         CASE WHEN io.from_farmer THEN 'farmer' ELSE 'supplier' END,
         NULL::text, 'cooperative',
         CASE WHEN io.from_farmer THEN io.origin END,
         NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
         'inventory_transaction', t.id
    FROM inventory_transactions t
    JOIN io ON io.id = t.inventory_id
   WHERE t.transaction_type = 'restock'
     AND t.quantity > 0
     AND COALESCE(t.reference_type, 'manual') NOT IN ('program_return', 'cooperative_offer')

  UNION ALL
  -- 2a. PROGRAM: a benefit distributed to a member (stock leaves the cooperative).
  SELECT 'dist:' || pm.id::text, 'program', 'program_distribution', 'outgoing',
         pm.distributed_at, TRUE,
         COALESCE(pm.distributed_item_name, io.item_name), io.category,
         pm.quantity_given::numeric, COALESCE(pm.distributed_unit, io.unit),
         pm.inventory_item_id, io.origin,
         NULL::text, 'cooperative',
         f.full_name, 'farmer',
         CASE WHEN io.from_farmer THEN io.origin END,
         cp.program_name,
         NULL::text, NULL::text, NULL::text, NULL::text,
         'program_member', pm.id
    FROM program_members pm
    JOIN cooperative_programs cp ON cp.id = pm.program_id
    LEFT JOIN io ON io.id = pm.inventory_item_id
    LEFT JOIN nm f ON f.user_id = pm.farmer_id
   WHERE pm.distributed_at IS NOT NULL
     AND COALESCE(pm.quantity_given, 0) > 0

  UNION ALL
  -- 2b. PROGRAM: a harvest return received into Cooperative Inventory.
  SELECT 'return:' || rr.id::text, 'program', 'harvest_return', 'incoming',
         rr.received_at, TRUE,
         COALESCE(io.item_name, pr.crop_name), io.category,
         rr.quantity::numeric, pr.unit, rr.inventory_id, io.origin,
         COALESCE(pr.farmer_name, f.full_name), 'farmer',
         NULL::text, 'cooperative',
         COALESCE(pr.farmer_name, f.full_name),
         cp.program_name,
         NULL::text, b.source_batch_number, NULL::text, NULL::text,
         'program_return', rr.id
    FROM program_return_receipts rr
    JOIN program_returns pr ON pr.id = rr.return_id
    JOIN cooperative_programs cp ON cp.id = pr.program_id
    LEFT JOIN io ON io.id = rr.inventory_id
    LEFT JOIN cooperative_harvest_batches b ON b.inventory_transaction_id = rr.inventory_transaction_id
    LEFT JOIN nm f ON f.user_id = pr.farmer_id

  UNION ALL
  -- 3. SUCCESSFUL COOPERATIVE PURCHASE: an Offer to Cooperative that was delivered,
  --    confirmed and received into Cooperative Inventory (the receipt batch).
  SELECT 'offer:' || o.id::text, 'offer', 'cooperative_purchase', 'incoming',
         b.received_at, TRUE,
         io.item_name, io.category, b.original_quantity::numeric, b.unit,
         b.inventory_id, io.origin,
         COALESCE(b.source_farmer_name, f.full_name), 'farmer',
         NULL::text, 'cooperative',
         COALESCE(b.source_farmer_name, f.full_name),
         NULL::text,
         'OFFER-' || upper(left(replace(o.id::text, '-', ''), 8)),
         b.source_batch_number, NULL::text, o.status,
         'cooperative_offer', o.id
    FROM cooperative_harvest_batches b
    JOIN cooperative_purchase_offers o ON o.id = b.offer_id
    JOIN io ON io.id = b.inventory_id
    LEFT JOIN nm f ON f.user_id = o.farmer_id

  UNION ALL
  -- 4a. FINAL CONSUMER: a Cooperative Product order (a member buys cooperative stock).
  SELECT 'coop-order:' || p.id::text, 'consumer', 'cooperative_sale', 'outgoing',
         COALESCE(p.completed_at, p.requested_at), (p.status = 'completed'),
         COALESCE(p.item_name, io.item_name), io.category,
         p.quantity::numeric, COALESCE(p.unit, io.unit),
         pp.inventory_item_id, io.origin,
         NULL::text, 'cooperative',
         f.full_name, 'farmer',
         CASE WHEN io.from_farmer THEN io.origin END,
         COALESCE(p.program_name, cp.program_name),
         p.order_number, NULL::text,
         p.fulfillment_method, p.status,
         'program_purchase', p.id
    FROM program_product_purchases p
    JOIN program_products pp ON pp.id = p.product_id
    LEFT JOIN io ON io.id = pp.inventory_item_id
    LEFT JOIN cooperative_programs cp ON cp.id = p.program_id
    LEFT JOIN nm f ON f.user_id = p.farmer_id
   WHERE p.status <> 'cancelled'

  UNION ALL
  -- 4b. FINAL CONSUMER: a Farmer Marketplace order (a Farmer's listed harvest to a buyer).
  SELECT 'order:' || o.id::text, 'consumer', 'marketplace_sale', 'outgoing',
         COALESCE(o.received_at, o.created_at), (o.status = 'completed'),
         l.crop_name,
         (SELECT cm.category FROM crop_master cm WHERE lower(cm.crop_name) = lower(l.crop_name) LIMIT 1),
         o.quantity_kg::numeric, COALESCE(NULLIF(o.unit, ''), 'kg'),
         NULL::uuid, sf.full_name,
         sf.full_name, 'farmer',
         bf.full_name, COALESCE(rl.role::text, 'buyer'),
         sf.full_name,
         NULL::text,
         o.order_number, ib.batch_number,
         COALESCE(o.fulfillment_method, 'pickup'), o.status,
         'order', o.id
    FROM orders o
    JOIN marketplace_listings l ON l.id = o.listing_id
    LEFT JOIN inventory_batches ib ON ib.id = l.inventory_batch_id
    LEFT JOIN nm sf ON sf.user_id = l.farmer_id
    LEFT JOIN nm bf ON bf.user_id = o.buyer_id
    LEFT JOIN rl ON rl.user_id = o.buyer_id
   WHERE o.status NOT IN ('cancelled', 'rejected')

  UNION ALL
  -- 5. OTHER (a real transaction type): inventory items issued to a Farmer on a loan.
  SELECT 'tx:' || t.id::text, 'other', 'loan_issue', 'outgoing',
         t.created_at, TRUE,
         io.item_name, io.category, abs(t.quantity)::numeric, io.unit, io.id, io.origin,
         NULL::text, 'cooperative',
         f.full_name, 'farmer',
         CASE WHEN io.from_farmer THEN io.origin END,
         NULL::text,
         fl.reference_no, NULL::text, NULL::text, NULL::text,
         'loan', fl.id
    FROM inventory_transactions t
    JOIN farmer_loans fl ON fl.id = t.reference_id
    JOIN io ON io.id = t.inventory_id
    LEFT JOIN nm f ON f.user_id = fl.farmer_id
   WHERE t.transaction_type = 'loan_issued'
     AND t.reference_type = 'loan'
)
SELECT r.*
  FROM rec AS r(record_key, stage, record_type, direction, occurred_at, is_confirmed,
                item_name, category, quantity, unit, inventory_id, item_source,
                from_name, from_role, to_name, to_role, farmer_name, program_name,
                reference_label, batch_number, fulfillment_method, fulfillment_status,
                ref_type, ref_id)
 WHERE public.is_staff()
   AND (p_from IS NULL OR r.occurred_at >= p_from)
   AND (p_to   IS NULL OR r.occurred_at <  p_to)
 ORDER BY r.occurred_at DESC, r.record_key;
$$;

REVOKE ALL ON FUNCTION public.get_supply_chain_records(timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_supply_chain_records(timestamptz, timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_supply_chain_totals(p_year integer DEFAULT NULL)
RETURNS TABLE (incoming bigint, outgoing bigint, in_progress bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH y AS (
    SELECT COALESCE(p_year, EXTRACT(YEAR FROM (now() AT TIME ZONE 'Asia/Manila'))::integer) AS yr
  )
  SELECT
    count(*) FILTER (WHERE r.direction = 'incoming' AND r.is_confirmed),
    count(*) FILTER (WHERE r.direction = 'outgoing' AND r.is_confirmed),
    count(*) FILTER (WHERE NOT r.is_confirmed)
  FROM y
  CROSS JOIN LATERAL public.get_supply_chain_records(
    make_timestamptz(y.yr,     1, 1, 0, 0, 0, 'Asia/Manila'),
    make_timestamptz(y.yr + 1, 1, 1, 0, 0, 0, 'Asia/Manila')
  ) r;
$$;

REVOKE ALL ON FUNCTION public.get_supply_chain_totals(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_supply_chain_totals(integer) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only; run as a Manager or Officer session, or in the
-- SQL editor after setting the JWT claims — as postgres is_staff() is false
-- and the functions return nothing by design)
-- ============================================================
-- V1  Functions exist and are not callable by anon (expect 2 rows, anon = false):
--     SELECT p.proname, has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_run
--       FROM pg_proc p WHERE p.proname IN ('get_supply_chain_records', 'get_supply_chain_totals');
--
-- V2  Rows per stage this year (signed in as staff):
--     SELECT stage, record_type, direction, count(*), count(*) FILTER (WHERE is_confirmed) AS confirmed
--       FROM public.get_supply_chain_records(date_trunc('year', now()), NULL)
--      GROUP BY 1, 2, 3 ORDER BY 1, 2;
--
-- V3  The dashboard figure (signed in as staff):
--     SELECT * FROM public.get_supply_chain_totals();
--
-- V4  No double counting — every record_key is unique (expect 0 rows):
--     SELECT record_key, count(*) FROM public.get_supply_chain_records() GROUP BY 1 HAVING count(*) > 1;
--
-- V5  Every received offer / return / distribution reaches an inventory item (expect 0 rows):
--     SELECT record_key, record_type FROM public.get_supply_chain_records()
--      WHERE record_type IN ('cooperative_purchase', 'harvest_return', 'program_distribution')
--        AND inventory_id IS NULL;
-- ============================================================
