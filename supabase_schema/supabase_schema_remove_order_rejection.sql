-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_remove_order_rejection.sql
--
-- Removes the Manager's "Disapprove (reject) order" path from the database.
--
-- Business rule after this script:
--   * A Buyer or Farmer cancels their OWN order, only while it is pending
--     (cancel_my_order, unchanged).
--   * The Manager / Officer approves a pending order and completes an
--     approved one (approve_order / complete_order, unchanged).
--   * An order is never "disapproved". Its status is one of
--     pending | approved | completed | cancelled.
--
-- Nothing is deleted. Disapproved ('rejected') orders are converted to
-- 'cancelled', keeping their reason (notes), order number, dates and a full
-- copy of the original rows in public.orders_rejection_backup.
-- The stock of a rejected order was already returned to its listing when it
-- was rejected (cancel_order added remaining_kg back), so converting it does
-- not touch any listing quantity.
--
-- NOT applied automatically. Run it yourself in the Supabase SQL editor,
-- one STEP at a time, and read the result of each STEP before the next.
-- Safe to re-run. The app already reads a stored 'rejected' as 'cancelled',
-- so it works the same before and after you run this.
-- ─────────────────────────────────────────────────────────────────────────────


-- ═══ STEP 1 · IDENTIFY (read-only) ═══════════════════════════════════════════
-- 1a. How many orders exist per status.
SELECT status, count(*) AS orders FROM public.orders GROUP BY status ORDER BY status;

-- 1b. Every Disapproved (rejected) order, newest first.
SELECT o.id, o.order_number, o.status, o.notes AS reason, o.quantity_kg,
       o.listing_id, o.buyer_id, o.created_at, o.updated_at
FROM public.orders o
WHERE o.status = 'rejected'
ORDER BY o.updated_at DESC;

-- 1c. Rejected orders whose stock may NOT have been returned. Expect 0 rows.
--     (A rejected order always returned its kg to remaining_kg. If a listing's
--     remaining_kg + its live orders' kg exceeds volume_kg, something else is
--     wrong, see supabase_schema_stock_integrity.sql.)
SELECT l.id AS listing_id, l.crop_name, l.volume_kg, l.remaining_kg,
       COALESCE(SUM(o.quantity_kg) FILTER (WHERE o.status IN ('pending','approved','completed')), 0) AS live_order_kg
FROM public.marketplace_listings l
JOIN public.orders o ON o.listing_id = l.id AND o.status = 'rejected'
GROUP BY l.id, l.crop_name, l.volume_kg, l.remaining_kg
HAVING l.remaining_kg + COALESCE(SUM(o.quantity_kg) FILTER (WHERE o.status IN ('pending','approved','completed')), 0) > l.volume_kg;

-- 1d. Notifications that still talk about a disapproved order (kept, not edited).
SELECT id, user_id, title, left(body, 80) AS body, created_at
FROM public.notifications
WHERE type = 'order'
  AND (title IN ('Order Rejected', 'Order Disapproved') OR body ~* 'was (rejected|disapproved)')
ORDER BY created_at DESC;


-- ═══ STEP 2 · BACKUP (creates a copy, changes nothing else) ══════════════════
CREATE TABLE IF NOT EXISTS public.orders_rejection_backup AS
SELECT now() AS backed_up_at, o.*
FROM public.orders o
WHERE false;

INSERT INTO public.orders_rejection_backup
SELECT now(), o.*
FROM public.orders o
WHERE o.status = 'rejected'
  AND NOT EXISTS (SELECT 1 FROM public.orders_rejection_backup b WHERE b.id = o.id);

SELECT count(*) AS backed_up_rejected_orders FROM public.orders_rejection_backup;


-- ═══ STEP 3 · CONVERT rejected → cancelled (no deletes) ══════════════════════
-- The orders_updated_at trigger is switched off for this one statement so each
-- order keeps the date it was disapproved on ("Cancelled on <that date>").
BEGIN;
  ALTER TABLE public.orders DISABLE TRIGGER orders_updated_at;

  UPDATE public.orders
  SET status = 'cancelled'
  WHERE status = 'rejected';

  ALTER TABLE public.orders ENABLE TRIGGER orders_updated_at;
COMMIT;

-- Expect 0.
SELECT count(*) AS still_rejected FROM public.orders WHERE status = 'rejected';


-- ═══ STEP 4 · CLOSE THE DOOR ═════════════════════════════════════════════════
-- 4a. The Manager's disapprove action no longer exists, so remove the RPC.
--     (Buyers/Farmers use cancel_my_order, which stays.)
DROP FUNCTION IF EXISTS public.cancel_order(uuid, text);

-- 4b. orders.status can only be one of the four real statuses again. Every
--     check constraint on orders that mentions status is replaced, because the
--     name of the old one is not guaranteed. Run only after STEP 3 reports 0.
DO $$
DECLARE
  v_name TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM public.orders WHERE status = 'rejected') THEN
    RAISE EXCEPTION 'Rejected orders still exist, run STEP 3 first';
  END IF;

  FOR v_name IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.orders'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.orders DROP CONSTRAINT %I', v_name);
  END LOOP;

  ALTER TABLE public.orders
    ADD CONSTRAINT orders_status_check
    CHECK (status IN ('pending', 'approved', 'completed', 'cancelled'));
END $$;


-- ═══ STEP 5 · VERIFY ═════════════════════════════════════════════════════════
--   SELECT status, count(*) FROM public.orders GROUP BY status;      -- no 'rejected'
--   SELECT proname FROM pg_proc WHERE proname = 'cancel_order';       -- 0 rows
--   SELECT proname FROM pg_proc WHERE proname = 'cancel_my_order';    -- 1 row
--   SELECT pg_get_constraintdef(oid) FROM pg_constraint
--    WHERE conname = 'orders_status_check';                           -- 4 statuses
--
-- ROLLBACK (only if you must undo STEP 3; the backup holds the original rows):
--   UPDATE public.orders o SET status = 'rejected'
--   FROM public.orders_rejection_backup b WHERE b.id = o.id;
--   (re-add 'rejected' to orders_status_check first)
