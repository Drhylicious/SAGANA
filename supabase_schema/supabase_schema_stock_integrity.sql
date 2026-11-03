-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_stock_integrity.sql
--
-- Marketplace stock: how it is meant to work, how to check that your database
-- really works that way, and the protections that keep it that way.
--
-- THE RULE (what the app and these scripts assume)
--   marketplace_listings.volume_kg     what the Farmer listed. Never changes
--                                      because of an order.
--   marketplace_listings.remaining_kg  what is still free to order.
--     place_order       takes the kg off the moment an order is PLACED
--                       (the listing row is locked, so two Buyers cannot take
--                       the same kg, and an order bigger than what is left is
--                       refused).
--     cancel_my_order   gives the kg back (Buyer / Farmer cancels a pending
--                       order).
--     approve_order     does NOT touch remaining_kg (already reserved).
--     complete_order    does NOT touch remaining_kg (already reserved); it only
--                       adds to the batch's sold_kg.
--   So a listing of 20 kg with a 5 kg order reads 15 kg left from the moment
--   the order is placed, through approval and completion.
--   A listing is "Sold Out" when it is approved and remaining_kg <= 0.
--
-- NOT applied automatically. Run it yourself in the Supabase SQL editor, one
-- STEP at a time. STEP 1 only reads. STEP 2 is the only one that changes data
-- and it keeps a backup first.
-- ─────────────────────────────────────────────────────────────────────────────


-- ═══ STEP 1 · DIAGNOSE (read-only) ═══════════════════════════════════════════

-- 1a. Which functions in YOUR database write stock, and in what way.
--     Many older scripts define the same function, so what matters is what is
--     live. Expected:
--       place_order      writes remaining_kg  (one overload only)
--       cancel_my_order  writes remaining_kg
--       complete_order   writes sold_kg only; if "writes_remaining" is true it
--                        is subtracting stock a SECOND time (the double
--                        deduction): report it and send me its definition.
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS args,
       p.prosrc ~* 'remaining_kg\s*=\s*remaining_kg\s*-'  AS takes_off_remaining,
       p.prosrc ~* 'remaining_kg\s*=\s*remaining_kg\s*\+'  AS gives_back_remaining,
       p.prosrc ~* 'remaining_kg\s*=\s*(0|p_|v_|ml\.)'      AS sets_remaining,
       p.prosrc ~* 'sold_kg\s*=\s*sold_kg\s*\+'             AS adds_sold_kg,
       p.prosrc ~* 'reserved_kg'                            AS touches_reserved_kg
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
WHERE p.prosrc ~* '(remaining_kg|sold_kg)'
  AND p.proname NOT LIKE '%test%'
ORDER BY p.proname;

-- 1b. More than one place_order / complete_order / cancel_my_order means an old
--     overload is still callable. Expect exactly 1 row per name.
SELECT proname, count(*) AS versions
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
WHERE proname IN ('place_order', 'approve_order', 'complete_order', 'cancel_my_order', 'resubmit_listing_with_reservation')
GROUP BY proname ORDER BY proname;

-- 1c. Triggers on the two tables that could move stock behind the RPCs' back.
--     Expect only updated_at / identity / numbering triggers, nothing that
--     writes remaining_kg.
SELECT c.relname AS table_name, t.tgname, pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE NOT t.tgisinternal
  AND c.relname IN ('orders', 'marketplace_listings', 'inventory_batches')
ORDER BY c.relname, t.tgname;

-- 1d. Listings whose remaining_kg does not match their orders.
--     expected_remaining = volume_kg - (pending + approved + completed orders).
--     Expect 0 rows. A row with remaining_kg HIGHER than expected means stock
--     was given back twice; LOWER means it was taken twice (double deduction).
SELECT l.id, l.crop_name, l.status, l.volume_kg, l.remaining_kg,
       l.volume_kg - COALESCE(o.active_kg, 0)  AS expected_remaining,
       l.remaining_kg - (l.volume_kg - COALESCE(o.active_kg, 0)) AS difference,
       COALESCE(o.active_orders, 0) AS active_orders
FROM public.marketplace_listings l
LEFT JOIN (
  SELECT listing_id,
         SUM(quantity_kg) FILTER (WHERE status NOT IN ('cancelled', 'rejected')) AS active_kg,
         count(*)         FILTER (WHERE status NOT IN ('cancelled', 'rejected')) AS active_orders
  FROM public.orders GROUP BY listing_id
) o ON o.listing_id = l.id
WHERE l.status IN ('approved', 'sold')
  AND l.remaining_kg IS DISTINCT FROM l.volume_kg - COALESCE(o.active_kg, 0)
ORDER BY abs(l.remaining_kg - (l.volume_kg - COALESCE(o.active_kg, 0))) DESC;

-- 1e. Impossible quantities. Expect 0 rows.
SELECT id, crop_name, status, volume_kg, remaining_kg
FROM public.marketplace_listings
WHERE remaining_kg < 0 OR remaining_kg > volume_kg;

-- 1f. Status that disagrees with the quantity. Expect 0 rows.
--     "sold" with kg left would show Sold Out although stock exists.
SELECT id, crop_name, status, volume_kg, remaining_kg
FROM public.marketplace_listings
WHERE (status = 'sold' AND remaining_kg > 0)
   OR (status = 'approved' AND remaining_kg <= 0
       AND NOT EXISTS (SELECT 1 FROM public.orders o
                       WHERE o.listing_id = marketplace_listings.id
                         AND o.status NOT IN ('cancelled', 'rejected')));

-- 1g. The same order placed twice by the same Buyer within a minute (a double
--     tap on Place Order). Expect 0 rows; a row is a likely double deduction.
SELECT a.buyer_id, a.listing_id, a.quantity_kg,
       a.order_number AS first_order, b.order_number AS second_order,
       a.created_at AS first_at, b.created_at AS second_at
FROM public.orders a
JOIN public.orders b
  ON b.buyer_id = a.buyer_id AND b.listing_id = a.listing_id
 AND b.quantity_kg = a.quantity_kg AND b.id <> a.id
 AND b.created_at >= a.created_at AND b.created_at < a.created_at + interval '60 seconds'
 AND (b.created_at, b.id) > (a.created_at, a.id)
ORDER BY a.created_at DESC;

-- 1h. Your tomatoes case: every Tomato listing with its orders, so you can see
--     for yourself what each step did. Change the crop name if needed.
SELECT l.id AS listing_id, l.status AS listing_status, l.volume_kg, l.remaining_kg,
       o.order_number, o.status AS order_status, o.quantity_kg,
       o.created_at, o.updated_at
FROM public.marketplace_listings l
LEFT JOIN public.orders o ON o.listing_id = l.id
WHERE l.crop_name ILIKE 'tomato%'
ORDER BY l.created_at DESC, o.created_at;

-- 1i. A superseded resubmit_listing_with_reservation does not reset
--     remaining_kg. Expect true.
SELECT prosrc ~* 'remaining_kg\s*=\s*p_volume_kg' AS resubmit_resets_remaining
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
WHERE proname = 'resubmit_listing_with_reservation';

-- 1j. Live updates: both tables must be in the realtime publication for the
--     app to refresh without a pull-down. Expect two rows.
SELECT tablename FROM pg_publication_tables
WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
  AND tablename IN ('marketplace_listings', 'orders');


-- ═══ STEP 2 · REPAIR (only if 1d / 1e / 1f returned rows) ════════════════════
-- Puts remaining_kg back to volume_kg minus the live orders, for approved and
-- sold listings only. A copy of every row it will change is kept first in
-- public.marketplace_listings_stock_backup. Nothing is deleted.
CREATE TABLE IF NOT EXISTS public.marketplace_listings_stock_backup (
  backed_up_at timestamptz NOT NULL DEFAULT now(),
  listing_id   uuid        NOT NULL,
  status       text,
  volume_kg    numeric,
  remaining_kg numeric
);

BEGIN;
  INSERT INTO public.marketplace_listings_stock_backup (listing_id, status, volume_kg, remaining_kg)
  SELECT l.id, l.status, l.volume_kg, l.remaining_kg
  FROM public.marketplace_listings l
  LEFT JOIN (
    SELECT listing_id, SUM(quantity_kg) AS active_kg
    FROM public.orders WHERE status NOT IN ('cancelled', 'rejected') GROUP BY listing_id
  ) o ON o.listing_id = l.id
  WHERE l.status IN ('approved', 'sold')
    AND l.remaining_kg IS DISTINCT FROM GREATEST(l.volume_kg - COALESCE(o.active_kg, 0), 0);

  UPDATE public.marketplace_listings l
  SET remaining_kg = GREATEST(l.volume_kg - COALESCE(o.active_kg, 0), 0),
      status = CASE
                 WHEN l.status = 'sold' AND l.volume_kg - COALESCE(o.active_kg, 0) > 0 THEN 'approved'
                 ELSE l.status
               END
  FROM (
    SELECT m.id, SUM(x.quantity_kg) FILTER (WHERE x.status NOT IN ('cancelled', 'rejected')) AS active_kg
    FROM public.marketplace_listings m
    LEFT JOIN public.orders x ON x.listing_id = m.id
    GROUP BY m.id
  ) o
  WHERE o.id = l.id
    AND l.status IN ('approved', 'sold')
    AND l.remaining_kg IS DISTINCT FROM GREATEST(l.volume_kg - COALESCE(o.active_kg, 0), 0);
COMMIT;
-- Then run 1d, 1e and 1f again: all three must return 0 rows.
-- To undo: UPDATE public.marketplace_listings l SET remaining_kg = b.remaining_kg, status = b.status
--          FROM public.marketplace_listings_stock_backup b WHERE b.listing_id = l.id;


-- ═══ STEP 3 · PROTECT ════════════════════════════════════════════════════════
-- 3a. A listing can never hold more than was listed. remaining_kg >= 0 already
--     exists (marketplace_listings_remaining_kg_check). NOT VALID checks every
--     new write but does not fail on a row that is already wrong, so this runs
--     even before STEP 2. After STEP 2 you may run:
--       ALTER TABLE public.marketplace_listings VALIDATE CONSTRAINT marketplace_listings_remaining_le_volume;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid = 'public.marketplace_listings'::regclass
                   AND conname = 'marketplace_listings_remaining_le_volume') THEN
    ALTER TABLE public.marketplace_listings
      ADD CONSTRAINT marketplace_listings_remaining_le_volume
      CHECK (remaining_kg <= volume_kg) NOT VALID;
  END IF;
END $$;

-- 3b. Live updates: let the app hear about listing and order changes.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                   WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'marketplace_listings') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.marketplace_listings;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                   WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'orders') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
    END IF;
  END IF;
END $$;

-- 3c. Verify
--   SELECT conname, convalidated FROM pg_constraint
--    WHERE conrelid = 'public.marketplace_listings'::regclass AND contype = 'c';
--   SELECT tablename FROM pg_publication_tables WHERE pubname = 'supabase_realtime'
--      AND tablename IN ('marketplace_listings', 'orders');          -- 2 rows
