-- ============================================================
-- SAGANA — Unified purchasing m04: the Cooperative order engine
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after m01, m02, m03.
--
-- WHAT IT DOES
--   Cooperative Products (Product Sales programs) are now ordered like any Marketplace order:
--   one cart, one checkout, one "My Orders" for the Farmer, one Order Management for staff.
--   They are still stored in program_product_purchases (NOT in orders), so Marketplace
--   listings, batches and Farmer sales stay exactly as they are.
--
--   1. Status vocabulary: pending, approved, ready_for_pickup, out_for_delivery, delivered,
--      completed, cancelled. (Old "paid" becomes "completed".) "delivered" is kept internally and
--      shown to people under Out for Delivery as "Handed over, awaiting confirmation".
--        Pickup  : pending -> approved -> ready_for_pickup -> completed
--        Delivery: pending -> approved -> out_for_delivery -> (delivered) -> completed
--   2. Order reference PSO-YYYYMMDD-A001 (its own yearly counter, same A001 pattern as ORD-).
--   3. PAYMENT is cash collected: at the counter for Pickup, cash on delivery for Delivery.
--      It is recorded by staff, separately from the fulfillment status. A Farmer can confirm
--      receipt only AFTER payment is recorded. Staff can complete an order on the Farmer's
--      behalf with a reason, a photo, their identity and the time (and only after cash was collected).
--   4. DUPLICATE PROTECTION: request_id, unique per Farmer. A retry returns the same order.
--   5. STOCK: each Cooperative Product gets "stock for this program" (stock_allocated).
--        - Allocated stock is protected: no loan, distribution, other program or stock
--          adjustment can take cooperative stock below what is allocated.
--        - Allocations can never add up to more than the stock on hand.
--        - An order RESERVES its quantity when it is placed (stock_reserved) and gives it back
--          when cancelled, so two Farmers cannot buy the same last item.
--        - Physical stock is deducted once, when the order is completed.
--   6. Staff actions follow the Marketplace permission module: an Officer with View Only can
--      read orders but cannot approve, record payment, cancel or complete them.
--   7. The two old purchases (the paid P500 and the pending P50) are migrated and written to
--      purchase_migration_log. No stock is deducted twice.
--   8. Direct writes to the purchases table are closed; everything goes through the functions.
--
-- Does NOT change: Marketplace orders, Buyer ordering, Farmer sales, patronage totals
-- (the completed P500 purchase counts exactly as before).
-- ============================================================

-- PREVIEW (read-only): what will be migrated
SELECT p.id, p.status, p.total_amount, p.quantity, p.requested_at, p.confirmed_at
  FROM public.program_product_purchases p
 ORDER BY p.requested_at;

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.checkout_groups') IS NULL THEN RAISE EXCEPTION 'Run m03 first.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'request_id') THEN
    RAISE EXCEPTION 'Run m01 first.';
  END IF;
  IF to_regprocedure('public.format_order_sequence(integer)') IS NULL THEN
    RAISE EXCEPTION 'format_order_sequence() is missing (order number script).';
  END IF;
  IF to_regprocedure('public.staff_can_manage(text, uuid)') IS NULL THEN
    RAISE EXCEPTION 'staff_can_manage() is missing (Officer permission scripts).';
  END IF;
  IF EXISTS (SELECT 1 FROM public.program_product_purchases
              WHERE status NOT IN ('pending', 'paid', 'cancelled', 'approved', 'ready_for_pickup', 'out_for_delivery', 'delivered', 'completed')) THEN
    RAISE EXCEPTION 'Unexpected purchase status found; stop and check the data first.';
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- 1. New columns on program_products (the allocation) and the purchases (the order)
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.program_products
  ADD COLUMN IF NOT EXISTS stock_allocated NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS stock_reserved  NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE public.program_products DROP CONSTRAINT IF EXISTS program_products_allocation_check;
ALTER TABLE public.program_products ADD CONSTRAINT program_products_allocation_check
  CHECK (stock_allocated >= 0 AND stock_reserved >= 0 AND stock_reserved <= stock_allocated);

ALTER TABLE public.program_product_purchases
  ADD COLUMN IF NOT EXISTS order_number            TEXT,
  ADD COLUMN IF NOT EXISTS request_id              UUID,
  ADD COLUMN IF NOT EXISTS fulfillment_method      TEXT NOT NULL DEFAULT 'pickup',
  ADD COLUMN IF NOT EXISTS checkout_group_id       UUID REFERENCES public.checkout_groups(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS delivery_address        TEXT,
  ADD COLUMN IF NOT EXISTS delivery_latitude       DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS delivery_longitude      DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS delivery_contact        TEXT,
  ADD COLUMN IF NOT EXISTS delivery_recipient      TEXT,
  ADD COLUMN IF NOT EXISTS delivery_label          TEXT,
  ADD COLUMN IF NOT EXISTS delivery_notes          TEXT,
  ADD COLUMN IF NOT EXISTS delivery_fee_collected  NUMERIC(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS item_name               TEXT,
  ADD COLUMN IF NOT EXISTS unit                    TEXT,
  ADD COLUMN IF NOT EXISTS program_name            TEXT,
  ADD COLUMN IF NOT EXISTS approved_at             TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS approved_by             UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS ready_at                TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS out_for_delivery_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivered_at            TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS handover_photo_url      TEXT,
  ADD COLUMN IF NOT EXISTS handover_note           TEXT,
  ADD COLUMN IF NOT EXISTS fulfilled_by            UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS received_at             TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS completed_at            TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS payment_status          TEXT NOT NULL DEFAULT 'unpaid',
  ADD COLUMN IF NOT EXISTS paid_at                 TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS payment_recorded_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS payment_recorded_by_name TEXT,
  ADD COLUMN IF NOT EXISTS payment_recorded_by_role TEXT,
  ADD COLUMN IF NOT EXISTS amount_collected        NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS payment_note            TEXT,
  ADD COLUMN IF NOT EXISTS completion_method       TEXT,
  ADD COLUMN IF NOT EXISTS staff_completion_reason TEXT,
  ADD COLUMN IF NOT EXISTS staff_completion_photo_url TEXT,
  ADD COLUMN IF NOT EXISTS staff_completed_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS staff_completed_by_name TEXT,
  ADD COLUMN IF NOT EXISTS staff_completed_by_role TEXT,
  ADD COLUMN IF NOT EXISTS staff_completed_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancelled_by            UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cancelled_by_role       TEXT,
  ADD COLUMN IF NOT EXISTS stock_deducted_at       TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS legacy_migrated         BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.program_product_purchases DROP CONSTRAINT IF EXISTS program_product_purchases_status_check;
ALTER TABLE public.program_product_purchases DROP CONSTRAINT IF EXISTS program_product_purchases_fulfillment_check;
ALTER TABLE public.program_product_purchases ADD CONSTRAINT program_product_purchases_fulfillment_check
  CHECK (fulfillment_method IN ('pickup', 'delivery'));
ALTER TABLE public.program_product_purchases DROP CONSTRAINT IF EXISTS program_product_purchases_payment_check;
ALTER TABLE public.program_product_purchases ADD CONSTRAINT program_product_purchases_payment_check
  CHECK (payment_status IN ('unpaid', 'paid', 'not_recorded'));
ALTER TABLE public.program_product_purchases DROP CONSTRAINT IF EXISTS program_product_purchases_completion_method_check;
ALTER TABLE public.program_product_purchases ADD CONSTRAINT program_product_purchases_completion_method_check
  CHECK (completion_method IS NULL OR completion_method IN ('consumer', 'staff'));
ALTER TABLE public.program_product_purchases DROP CONSTRAINT IF EXISTS program_product_purchases_staff_completion_complete;
ALTER TABLE public.program_product_purchases ADD CONSTRAINT program_product_purchases_staff_completion_complete
  CHECK (completion_method IS DISTINCT FROM 'staff'
         OR (staff_completion_reason IS NOT NULL AND staff_completion_photo_url IS NOT NULL
             AND staff_completed_by IS NOT NULL AND staff_completed_at IS NOT NULL));

-- ════════════════════════════════════════════════════════════
-- 2. Migrate the existing rows (documented; nothing is lost; no stock is deducted twice)
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.purchase_migration_log (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_id UUID NOT NULL,
  action      TEXT NOT NULL,
  note        TEXT NOT NULL,
  before_row  JSONB NOT NULL,
  after_row   JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.purchase_migration_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "purchase_migration_log: staff read" ON public.purchase_migration_log;
CREATE POLICY "purchase_migration_log: staff read" ON public.purchase_migration_log FOR SELECT TO authenticated USING (public.is_staff());
REVOKE ALL ON public.purchase_migration_log FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.purchase_migration_log FROM authenticated;
GRANT SELECT ON public.purchase_migration_log TO authenticated;

-- The yearly counter for PSO numbers (the same idea as the ORD- counter).
CREATE TABLE IF NOT EXISTS public.program_order_counters (
  year     INTEGER PRIMARY KEY CHECK (year BETWEEN 2000 AND 9999),
  last_seq INTEGER NOT NULL CHECK (last_seq >= 0)
);
ALTER TABLE public.program_order_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.program_order_counters FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.next_program_order_number(p_at TIMESTAMPTZ DEFAULT NOW())
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_local TIMESTAMP := p_at AT TIME ZONE 'Asia/Manila';
  v_year  INTEGER   := EXTRACT(YEAR FROM (p_at AT TIME ZONE 'Asia/Manila'))::INTEGER;
  v_seq   INTEGER;
BEGIN
  INSERT INTO program_order_counters (year, last_seq) VALUES (v_year, 1)
  ON CONFLICT (year) DO UPDATE SET last_seq = program_order_counters.last_seq + 1
  RETURNING last_seq INTO v_seq;
  RETURN 'PSO-' || to_char(v_local, 'YYYYMMDD') || '-' || public.format_order_sequence(v_seq);
END $$;
REVOKE ALL ON FUNCTION public.next_program_order_number(TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;

-- Snapshots for every existing row (so a later rename never rewrites an old order).
UPDATE public.program_product_purchases p
   SET item_name    = COALESCE(p.item_name, ci.item_name),
       unit         = COALESCE(p.unit, ci.unit),
       program_name = COALESCE(p.program_name, cp.program_name)
  FROM public.program_products pp
  JOIN public.cooperative_inventory ci ON ci.id = pp.inventory_item_id
  JOIN public.cooperative_programs cp  ON cp.id = pp.program_id
 WHERE pp.id = p.product_id
   AND (p.item_name IS NULL OR p.unit IS NULL OR p.program_name IS NULL);

-- Number the old rows, oldest first, dated by when they were requested.
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT id, requested_at FROM public.program_product_purchases WHERE order_number IS NULL ORDER BY requested_at, id LOOP
    UPDATE public.program_product_purchases SET order_number = public.next_program_order_number(r.requested_at) WHERE id = r.id;
  END LOOP;
END $$;

-- Document, then migrate: paid -> completed (cash was received, stock was deducted at confirmation).
INSERT INTO public.purchase_migration_log (purchase_id, action, note, before_row)
SELECT p.id,
       CASE p.status WHEN 'paid' THEN 'paid_to_completed' WHEN 'pending' THEN 'pending_kept' ELSE 'cancelled_kept' END,
       CASE p.status
         WHEN 'paid' THEN 'Old confirmed purchase. Marked Completed with payment recorded at the old confirmation time. Stock had already been deducted at that time, so none is deducted again.'
         WHEN 'pending' THEN 'Old pending purchase. Stays Pending (Pickup). Its quantity is reserved from the program allocation. Staff approve or cancel it in Order Management.'
         ELSE 'Old cancelled purchase. Kept as Cancelled.' END,
       to_jsonb(p)
  FROM public.program_product_purchases p
 WHERE NOT p.legacy_migrated
   AND NOT EXISTS (SELECT 1 FROM public.purchase_migration_log l WHERE l.purchase_id = p.id);

UPDATE public.program_product_purchases
   SET status = 'completed',
       payment_status = 'paid',
       paid_at = COALESCE(confirmed_at, requested_at),
       amount_collected = total_amount,
       payment_recorded_by = confirmed_by,
       completed_at = COALESCE(confirmed_at, requested_at),
       stock_deducted_at = COALESCE(confirmed_at, requested_at),
       legacy_migrated = TRUE
 WHERE status = 'paid';
UPDATE public.program_product_purchases SET legacy_migrated = TRUE WHERE status IN ('pending', 'cancelled') AND NOT legacy_migrated;

UPDATE public.purchase_migration_log l
   SET after_row = to_jsonb(p)
  FROM public.program_product_purchases p
 WHERE p.id = l.purchase_id AND l.after_row IS NULL;

ALTER TABLE public.program_product_purchases ADD CONSTRAINT program_product_purchases_status_check
  CHECK (status IN ('pending', 'approved', 'ready_for_pickup', 'out_for_delivery', 'delivered', 'completed', 'cancelled'));
ALTER TABLE public.program_product_purchases ALTER COLUMN order_number SET NOT NULL;
ALTER TABLE public.program_product_purchases DROP CONSTRAINT IF EXISTS program_product_purchases_order_number_format;
ALTER TABLE public.program_product_purchases ADD CONSTRAINT program_product_purchases_order_number_format
  CHECK (order_number ~ '^PSO-[0-9]{8}-[A-Z]+[0-9]{3}$');
CREATE UNIQUE INDEX IF NOT EXISTS uq_program_purchases_order_number ON public.program_product_purchases (order_number);
CREATE UNIQUE INDEX IF NOT EXISTS uq_program_purchases_farmer_request
  ON public.program_product_purchases (farmer_id, request_id) WHERE request_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS program_purchases_group ON public.program_product_purchases (checkout_group_id) WHERE checkout_group_id IS NOT NULL;

-- ════════════════════════════════════════════════════════════
-- 3. Stock allocation (migration, then the protection)
-- ════════════════════════════════════════════════════════════
-- Allocate what is on hand to the one active Product Sales product of each item (the oldest
-- product row if, unusually, two programs offer the same item); reserve the pending quantity.
-- This runs once only (a marker row records it), so a re-run never re-allocates sold-out stock.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.purchase_migration_log WHERE action = 'allocation_initial') THEN
    RETURN;
  END IF;
  WITH ranked AS (
    SELECT pp.id, pp.inventory_item_id,
           row_number() OVER (PARTITION BY pp.inventory_item_id ORDER BY pp.created_at, pp.id) AS rn
      FROM public.program_products pp
      JOIN public.cooperative_programs cp ON cp.id = pp.program_id
     WHERE cp.program_purpose = 'sales' AND cp.status = 'active' AND pp.is_available
  )
  UPDATE public.program_products pp
     SET stock_allocated = ci.quantity_on_hand
    FROM ranked r, public.cooperative_inventory ci
   WHERE r.id = pp.id AND r.rn = 1 AND ci.id = pp.inventory_item_id;

  UPDATE public.program_products pp
     SET stock_reserved = LEAST(pp.stock_allocated, COALESCE((
           SELECT sum(p.quantity) FROM public.program_product_purchases p
            WHERE p.product_id = pp.id AND p.status IN ('pending', 'approved', 'ready_for_pickup', 'out_for_delivery', 'delivered')), 0));

  INSERT INTO public.purchase_migration_log (purchase_id, action, note, before_row)
  VALUES ('00000000-0000-0000-0000-000000000000', 'allocation_initial',
          'Initial stock allocation: the stock on hand was set aside for the one active Product Sales product of each item.', '{}'::jsonb);
END $$;

-- An old pending purchase that no longer fits inside the allocation is a data problem: say so.
DO $$
DECLARE v_bad INTEGER;
BEGIN
  SELECT count(*) INTO v_bad FROM public.program_products pp
   WHERE COALESCE((SELECT sum(p.quantity) FROM public.program_product_purchases p
                    WHERE p.product_id = pp.id AND p.status IN ('pending','approved','ready_for_pickup','out_for_delivery','delivered')), 0) > pp.stock_reserved;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'An open purchase is larger than the stock on hand for its product (% product(s)). Cancel or adjust it first.', v_bad;
  END IF;
END $$;

-- Helper: how much of an item is already set aside (all programs).
CREATE OR REPLACE FUNCTION public._item_allocated_total(p_item_id uuid, p_except_product uuid DEFAULT NULL)
RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT COALESCE(sum(stock_allocated), 0) FROM program_products
   WHERE inventory_item_id = p_item_id AND (p_except_product IS NULL OR id <> p_except_product);
$$;
REVOKE ALL ON FUNCTION public._item_allocated_total(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Allocations can never add up to more than the stock that is free.
CREATE OR REPLACE FUNCTION public._assert_allocation_fits(p_product_id uuid, p_item_id uuid, p_new numeric)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_on_hand numeric; v_res numeric; v_other numeric; v_name text;
BEGIN
  SELECT quantity_on_hand, quantity_reserved, item_name INTO v_on_hand, v_res, v_name
    FROM cooperative_inventory WHERE id = p_item_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'The inventory item no longer exists.'; END IF;
  v_other := public._item_allocated_total(p_item_id, p_product_id);
  IF v_other + p_new > v_on_hand - v_res THEN
    RAISE EXCEPTION 'OVER_ALLOCATED: Only % of % is free to set aside (% on hand, % already set aside for programs).',
      GREATEST(v_on_hand - v_res - v_other, 0), v_name, v_on_hand, v_other;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public._assert_allocation_fits(uuid, uuid, numeric) FROM PUBLIC, anon, authenticated;

-- Invoker trigger: a client can never write the two stock columns directly; only the functions below can.
CREATE OR REPLACE FUNCTION public._program_products_stock_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon') THEN
    IF (TG_OP = 'INSERT' AND (NEW.stock_allocated <> 0 OR NEW.stock_reserved <> 0))
       OR (TG_OP = 'UPDATE' AND (NEW.stock_allocated, NEW.stock_reserved) IS DISTINCT FROM (OLD.stock_allocated, OLD.stock_reserved)) THEN
      RAISE EXCEPTION 'Use the stock allocation function to change the stock for a program.';
    END IF;
  END IF;
  IF TG_OP = 'INSERT' OR NEW.stock_allocated IS DISTINCT FROM OLD.stock_allocated THEN
    IF NEW.stock_allocated > 0 THEN
      PERFORM public._assert_allocation_fits(NEW.id, NEW.inventory_item_id, NEW.stock_allocated);
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_program_products_stock_guard ON public.program_products;
CREATE TRIGGER trg_program_products_stock_guard BEFORE INSERT OR UPDATE ON public.program_products
  FOR EACH ROW EXECUTE FUNCTION public._program_products_stock_guard();

-- THE PROTECTION: nothing (loan, distribution, another program, a stock adjustment, a
-- write-off) can take cooperative stock below what is set aside for programs.
CREATE OR REPLACE FUNCTION public._inventory_allocation_protect()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_alloc numeric;
BEGIN
  IF NEW.quantity_on_hand < OLD.quantity_on_hand THEN
    v_alloc := public._item_allocated_total(NEW.id);
    IF NEW.quantity_on_hand < v_alloc THEN
      RAISE EXCEPTION 'STOCK_ALLOCATED: % of % is set aside for a Product Sales program and cannot be used for anything else (% would be left on hand). Release the allocation first.',
        v_alloc, NEW.item_name, NEW.quantity_on_hand;
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_inventory_allocation_protect ON public.cooperative_inventory;
CREATE TRIGGER trg_inventory_allocation_protect BEFORE UPDATE OF quantity_on_hand ON public.cooperative_inventory
  FOR EACH ROW EXECUTE FUNCTION public._inventory_allocation_protect();

-- ════════════════════════════════════════════════════════════
-- 4. Access: read through policies, write only through the functions
-- ════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "program_product_purchases: admin manages all" ON public.program_product_purchases;
DROP POLICY IF EXISTS "program_product_purchases: staff read" ON public.program_product_purchases;
CREATE POLICY "program_product_purchases: staff read" ON public.program_product_purchases FOR SELECT TO authenticated USING (public.is_staff());
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.program_product_purchases FROM authenticated, anon;

-- State machine: the only legal moves, financial snapshots frozen, completion only through a function.
CREATE OR REPLACE FUNCTION public._program_orders_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF (NEW.farmer_id, NEW.program_id, NEW.product_id, NEW.quantity, NEW.unit_price, NEW.total_amount,
      NEW.regular_unit_price, NEW.discount_percent, NEW.discount_amount, NEW.is_member_price,
      NEW.order_number, NEW.fulfillment_method)
     IS DISTINCT FROM
     (OLD.farmer_id, OLD.program_id, OLD.product_id, OLD.quantity, OLD.unit_price, OLD.total_amount,
      OLD.regular_unit_price, OLD.discount_percent, OLD.discount_amount, OLD.is_member_price,
      OLD.order_number, OLD.fulfillment_method) THEN
    RAISE EXCEPTION 'The price, quantity and method of an order cannot be changed.';
  END IF;
  IF OLD.payment_status = 'paid' AND (NEW.payment_status, NEW.paid_at, NEW.amount_collected)
       IS DISTINCT FROM (OLD.payment_status, OLD.paid_at, OLD.amount_collected) THEN
    RAISE EXCEPTION 'A recorded payment cannot be changed.';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT (
         (OLD.status = 'pending'          AND NEW.status IN ('approved', 'cancelled'))
      OR (OLD.status = 'approved'         AND ((NEW.status = 'ready_for_pickup' AND OLD.fulfillment_method = 'pickup')
                                            OR (NEW.status = 'out_for_delivery' AND OLD.fulfillment_method = 'delivery')
                                            OR NEW.status = 'cancelled'))
      OR (OLD.status = 'ready_for_pickup' AND NEW.status IN ('completed', 'cancelled'))
      OR (OLD.status = 'out_for_delivery' AND NEW.status IN ('delivered', 'cancelled'))
      OR (OLD.status = 'delivered'        AND NEW.status = 'completed')
    ) THEN
      RAISE EXCEPTION 'An order cannot move from % to %.', OLD.status, NEW.status;
    END IF;
    IF NEW.status = 'completed' THEN
      IF NEW.payment_status IS DISTINCT FROM 'paid' THEN
        RAISE EXCEPTION 'An order is completed only after the payment is recorded.';
      END IF;
      IF current_setting('sagana.program_order_rpc', true) IS DISTINCT FROM NEW.id::text THEN
        RAISE EXCEPTION 'An order is completed by the Farmer confirming receipt, or by staff with a reason and a photo.';
      END IF;
    END IF;
    IF NEW.status IN ('delivered') AND NEW.payment_status IS DISTINCT FROM 'paid' THEN
      RAISE EXCEPTION 'A delivery is handed over together with the cash payment.';
    END IF;
    IF NEW.status = 'cancelled' AND OLD.payment_status = 'paid' THEN
      RAISE EXCEPTION 'An order that was paid cannot be cancelled.';
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_program_orders_guard ON public.program_product_purchases;
CREATE TRIGGER trg_program_orders_guard BEFORE UPDATE ON public.program_product_purchases
  FOR EACH ROW EXECUTE FUNCTION public._program_orders_guard();

-- Staff actions on these orders are governed by the Marketplace module and logged under it.
DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.program_product_purchases;
CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.program_product_purchases
  FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change('marketplace', '');

-- ════════════════════════════════════════════════════════════
-- 5. Internal helpers
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._pp_staff_guard()
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_role text;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can do this.';
  END IF;
  IF NOT public.staff_can_manage('marketplace') THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Your Officer account has view-only access to the Marketplace module. Ask the Manager to give you Manage access.'
      USING ERRCODE = '42501';
  END IF;
  SELECT role INTO v_role FROM user_roles WHERE user_id = auth.uid();
  RETURN v_role;
END $$;
REVOKE ALL ON FUNCTION public._pp_staff_guard() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._pp_notify(p_user uuid, p_title text, p_body text, p_route text)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (p_user, 'order', p_title, p_body, FALSE, NOW(), p_route);
$$;
REVOKE ALL ON FUNCTION public._pp_notify(uuid, text, text, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._pp_notify_staff(p_title text, p_body text)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ur.user_id, 'order', p_title, p_body, FALSE, NOW(), '/admin/marketplace/orders'
    FROM user_roles ur WHERE ur.role IN ('admin', 'officer');
$$;
REVOKE ALL ON FUNCTION public._pp_notify_staff(text, text) FROM PUBLIC, anon, authenticated;

-- Take the stock out for real, once, when an order is completed.
CREATE OR REPLACE FUNCTION public._pp_finalize(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE o program_product_purchases%ROWTYPE; pp program_products%ROWTYPE; v_on_hand numeric;
BEGIN
  SELECT * INTO o FROM program_product_purchases WHERE id = p_order_id FOR UPDATE;
  IF o.stock_deducted_at IS NOT NULL THEN RETURN; END IF;        -- never twice
  SELECT * INTO pp FROM program_products WHERE id = o.product_id FOR UPDATE;
  SELECT quantity_on_hand INTO v_on_hand FROM cooperative_inventory WHERE id = pp.inventory_item_id FOR UPDATE;
  IF v_on_hand IS NULL OR v_on_hand < o.quantity THEN
    RAISE EXCEPTION 'Not enough stock on hand to complete this order.';
  END IF;
  -- The allocation goes down first, so the protection trigger sees a consistent picture.
  UPDATE program_products
     SET stock_allocated = stock_allocated - o.quantity, stock_reserved = stock_reserved - o.quantity
   WHERE id = pp.id;
  UPDATE cooperative_inventory SET quantity_on_hand = quantity_on_hand - o.quantity WHERE id = pp.inventory_item_id;
  INSERT INTO inventory_transactions (inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by, notes)
  VALUES (pp.inventory_item_id, 'sold', -o.quantity, o.id, 'program_purchase', auth.uid(), 'Cooperative product sale ' || o.order_number);
  UPDATE program_product_purchases SET stock_deducted_at = NOW() WHERE id = o.id;
END $$;
REVOKE ALL ON FUNCTION public._pp_finalize(uuid) FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 6. Placing an order (Farmers only; Buyers can never order Cooperative Products)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.place_program_order(
  p_program_id         uuid,
  p_product_id         uuid,
  p_quantity           numeric,
  p_fulfillment_method text,
  p_group_id           uuid,
  p_request_id         uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_farmer   uuid := auth.uid();
  v_program  cooperative_programs%ROWTYPE;
  v_product  program_products%ROWTYPE;
  v_item     cooperative_inventory%ROWTYPE;
  g          checkout_groups%ROWTYPE;
  o          program_product_purchases%ROWTYPE;
  v_member   boolean; v_pct numeric; v_regular numeric; v_unit numeric; v_total numeric; v_discount numeric;
  v_name     text;
BEGIN
  IF v_farmer IS NULL THEN RAISE EXCEPTION 'You must be signed in.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = v_farmer AND role = 'farmer' AND status = 'active') THEN
    RAISE EXCEPTION 'COOPERATIVE_FARMERS_ONLY: Cooperative Products can be bought by active cooperative members only.';
  END IF;
  IF p_request_id IS NULL THEN RAISE EXCEPTION 'A request id is required.'; END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 OR p_quantity <> round(p_quantity, 2) THEN
    RAISE EXCEPTION 'Quantity must be greater than zero (two decimals at most).';
  END IF;
  IF p_fulfillment_method IS NULL OR p_fulfillment_method NOT IN ('pickup', 'delivery') THEN
    RAISE EXCEPTION 'Choose Pickup or Delivery.';
  END IF;

  -- A retry of the same request returns the same order and changes nothing.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_farmer::text || p_request_id::text, 41));
  SELECT * INTO o FROM program_product_purchases WHERE farmer_id = v_farmer AND request_id = p_request_id;
  IF FOUND THEN
    RETURN jsonb_build_object('order_id', o.id, 'order_number', o.order_number, 'total_amount', o.total_amount, 'existing', TRUE);
  END IF;

  SELECT * INTO v_program FROM cooperative_programs WHERE id = p_program_id;
  IF NOT FOUND OR v_program.program_purpose <> 'sales' THEN RAISE EXCEPTION 'Product Sales program not found.'; END IF;
  IF v_program.status <> 'active' THEN RAISE EXCEPTION 'This program is Completed and no longer accepts orders.'; END IF;

  SELECT * INTO v_product FROM program_products WHERE id = p_product_id AND program_id = p_program_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product not found for this program.'; END IF;
  IF NOT v_product.is_available THEN RAISE EXCEPTION 'This product is not currently available.'; END IF;
  SELECT * INTO v_item FROM cooperative_inventory WHERE id = v_product.inventory_item_id;
  IF NOT FOUND OR NOT v_item.is_active THEN RAISE EXCEPTION 'This product is no longer in stock.'; END IF;

  -- Overselling is impossible: the product row is locked and the free stock is checked.
  IF v_product.stock_allocated - v_product.stock_reserved < p_quantity THEN
    RAISE EXCEPTION 'OUT_OF_STOCK: Only % % left for this product.',
      GREATEST(v_product.stock_allocated - v_product.stock_reserved, 0), COALESCE(v_item.unit, '');
  END IF;

  IF p_fulfillment_method = 'delivery' THEN
    IF p_group_id IS NULL THEN RAISE EXCEPTION 'GROUP_REQUIRED: Choose a delivery address first.'; END IF;
    SELECT * INTO g FROM checkout_groups WHERE id = p_group_id AND buyer_id = v_farmer;
    IF NOT FOUND THEN RAISE EXCEPTION 'GROUP_REQUIRED: The delivery address was not found. Choose it again.'; END IF;
  ELSIF p_group_id IS NOT NULL THEN
    RAISE EXCEPTION 'A Pickup order has no delivery group.';
  END IF;

  v_member := EXISTS (SELECT 1 FROM program_members WHERE program_id = p_program_id AND farmer_id = v_farmer AND status = 'active');
  v_regular  := v_product.unit_price;
  v_pct      := CASE WHEN v_member THEN COALESCE(v_program.member_discount_percent, 0) ELSE 0 END;
  v_unit     := round(v_regular * (1 - v_pct / 100.0), 2);
  v_total    := round(v_unit * p_quantity, 2);
  v_discount := round(v_regular * p_quantity, 2) - v_total;

  INSERT INTO program_product_purchases (
    program_id, product_id, farmer_id, quantity, unit_price, total_amount, status,
    regular_unit_price, discount_percent, discount_amount, is_member_price,
    order_number, request_id, fulfillment_method, checkout_group_id,
    delivery_address, delivery_latitude, delivery_longitude, delivery_contact, delivery_recipient, delivery_label, delivery_notes,
    item_name, unit, program_name)
  VALUES (
    p_program_id, p_product_id, v_farmer, p_quantity, v_unit, v_total, 'pending',
    v_regular, v_pct, v_discount, v_member,
    public.next_program_order_number(), p_request_id, p_fulfillment_method, g.id,
    g.address_line, g.latitude, g.longitude, g.contact_number, g.recipient_name, g.address_label, g.delivery_notes,
    v_item.item_name, v_item.unit, v_program.program_name)
  RETURNING * INTO o;

  UPDATE program_products SET stock_reserved = stock_reserved + p_quantity WHERE id = v_product.id;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_farmer;
  PERFORM public._pp_notify_staff('New Cooperative Order',
    COALESCE(v_name, 'A Farmer') || ' ordered ' || p_quantity || ' ' || COALESCE(v_item.unit, '') || ' ' || v_item.item_name ||
    ' (' || o.order_number || ', ' || CASE p_fulfillment_method WHEN 'delivery' THEN 'Delivery' ELSE 'Pickup' END || ').');

  RETURN jsonb_build_object('order_id', o.id, 'order_number', o.order_number, 'total_amount', o.total_amount, 'existing', FALSE);
END $$;
REVOKE ALL ON FUNCTION public.place_program_order(uuid, uuid, numeric, text, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_program_order(uuid, uuid, numeric, text, uuid, uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 7. Staff steps (Manager, or an Officer with Marketplace = Manage)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.approve_program_order(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE o program_product_purchases%ROWTYPE;
BEGIN
  PERFORM public._pp_staff_guard();
  SELECT * INTO o FROM program_product_purchases WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF o.status <> 'pending' THEN RAISE EXCEPTION 'Only a pending order can be approved (current status: %).', o.status; END IF;
  UPDATE program_product_purchases SET status = 'approved', approved_at = NOW(), approved_by = auth.uid() WHERE id = o.id;
  PERFORM public._pp_notify(o.farmer_id, 'Order Approved',
    'Your order ' || o.order_number || ' (' || COALESCE(o.item_name, 'item') || ') was approved.', '/farmer/profile/orders');
END $$;

CREATE OR REPLACE FUNCTION public.mark_program_order_ready(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE o program_product_purchases%ROWTYPE;
BEGIN
  PERFORM public._pp_staff_guard();
  SELECT * INTO o FROM program_product_purchases WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF o.fulfillment_method <> 'pickup' THEN RAISE EXCEPTION 'This is a delivery order. Use Out for Delivery instead.'; END IF;
  IF o.status <> 'approved' THEN RAISE EXCEPTION 'Only an approved order can be marked Ready for Pickup (current status: %).', o.status; END IF;
  UPDATE program_product_purchases SET status = 'ready_for_pickup', ready_at = NOW(), fulfilled_by = auth.uid() WHERE id = o.id;
  PERFORM public._pp_notify(o.farmer_id, 'Order Ready for Pickup',
    'Your order ' || o.order_number || ' is ready. Collect it at the cooperative and pay the cashier, then confirm receipt in the app.', '/farmer/profile/orders');
END $$;

CREATE OR REPLACE FUNCTION public.mark_program_order_out_for_delivery(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE o program_product_purchases%ROWTYPE;
BEGIN
  PERFORM public._pp_staff_guard();
  SELECT * INTO o FROM program_product_purchases WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF o.fulfillment_method <> 'delivery' THEN RAISE EXCEPTION 'This is a pickup order. Use Ready for Pickup instead.'; END IF;
  IF o.status <> 'approved' THEN RAISE EXCEPTION 'Only an approved order can be marked Out for Delivery (current status: %).', o.status; END IF;
  UPDATE program_product_purchases SET status = 'out_for_delivery', out_for_delivery_at = NOW(), fulfilled_by = auth.uid() WHERE id = o.id;
  PERFORM public._pp_notify(o.farmer_id, 'Order Out for Delivery',
    'Your order ' || o.order_number || ' is on its way. Please have the payment ready (cash on delivery).', '/farmer/profile/orders');
END $$;

-- Cash collected and the item handed over. Pickup: at the counter. Delivery: at the door, with a photo.
-- p_amount must equal what is due: the product total, plus the delivery fee when this is the
-- first handover of the group (the fee is collected once per group).
CREATE OR REPLACE FUNCTION public.record_program_order_handover(
  p_order_id  uuid,
  p_amount    numeric,
  p_photo_url text DEFAULT NULL,
  p_note      text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  o program_product_purchases%ROWTYPE;
  v_role text; v_name text; v_fee numeric := 0; v_expected numeric;
BEGIN
  v_role := public._pp_staff_guard();
  SELECT * INTO o FROM program_product_purchases WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF o.payment_status = 'paid' THEN RAISE EXCEPTION 'The payment of this order is already recorded.'; END IF;
  IF o.fulfillment_method = 'pickup' AND o.status <> 'ready_for_pickup' THEN
    RAISE EXCEPTION 'Record the payment once the order is Ready for Pickup (current status: %).', o.status;
  END IF;
  IF o.fulfillment_method = 'delivery' AND o.status <> 'out_for_delivery' THEN
    RAISE EXCEPTION 'Record the handover once the order is Out for Delivery (current status: %).', o.status;
  END IF;
  IF o.fulfillment_method = 'delivery'
     AND (p_photo_url IS NULL OR btrim(p_photo_url) = '' OR btrim(p_photo_url) NOT ILIKE 'http%') THEN
    RAISE EXCEPTION 'Upload a photo of the delivery first.';
  END IF;
  IF p_amount IS NULL OR p_amount <> round(p_amount, 2) THEN RAISE EXCEPTION 'Enter the amount collected.'; END IF;

  IF o.fulfillment_method = 'delivery' THEN
    v_fee := public._collect_group_fee(o.checkout_group_id, o.id, 'cooperative');
  END IF;
  v_expected := o.total_amount + v_fee;
  IF round(p_amount, 2) <> v_expected THEN
    RAISE EXCEPTION 'AMOUNT_MISMATCH: The amount to collect is %. Check the cash received.', v_expected;
  END IF;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = auth.uid();
  UPDATE program_product_purchases
     SET payment_status = 'paid', paid_at = NOW(), amount_collected = round(p_amount, 2),
         delivery_fee_collected = v_fee,
         payment_recorded_by = auth.uid(), payment_recorded_by_name = v_name, payment_recorded_by_role = v_role,
         payment_note = NULLIF(btrim(COALESCE(p_note, '')), ''),
         confirmed_at = NOW(), confirmed_by = auth.uid(),
         status = CASE WHEN o.fulfillment_method = 'delivery' THEN 'delivered' ELSE status END,
         delivered_at = CASE WHEN o.fulfillment_method = 'delivery' THEN NOW() ELSE delivered_at END,
         handover_photo_url = CASE WHEN o.fulfillment_method = 'delivery' THEN btrim(p_photo_url) ELSE handover_photo_url END,
         handover_note = CASE WHEN o.fulfillment_method = 'delivery' THEN NULLIF(btrim(COALESCE(p_note, '')), '') ELSE handover_note END,
         fulfilled_by = auth.uid()
   WHERE id = o.id;

  PERFORM public._pp_notify(o.farmer_id,
    CASE o.fulfillment_method WHEN 'delivery' THEN 'Order Handed Over' ELSE 'Payment Recorded' END,
    CASE o.fulfillment_method WHEN 'delivery' THEN 'Your order ' || o.order_number || ' was handed over and the payment recorded. Check it, then confirm receipt.'
         ELSE 'The payment for ' || o.order_number || ' was recorded. Confirm receipt once you have your items.' END,
    '/farmer/profile/orders');
  RETURN jsonb_build_object('amount_collected', round(p_amount, 2), 'delivery_fee', v_fee);
END $$;

-- ════════════════════════════════════════════════════════════
-- 8. Completing: the Farmer confirms, or staff complete with a reason and a photo
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.confirm_program_order_received(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE o program_product_purchases%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO o FROM program_product_purchases WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR o.farmer_id <> auth.uid() THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF o.status = 'completed' THEN RAISE EXCEPTION 'You already confirmed receiving this order.'; END IF;
  IF o.payment_status <> 'paid' THEN
    RAISE EXCEPTION 'PAYMENT_NOT_RECORDED: You can confirm receipt after the cooperative records your payment.';
  END IF;
  IF NOT ((o.fulfillment_method = 'pickup' AND o.status = 'ready_for_pickup')
       OR (o.fulfillment_method = 'delivery' AND o.status = 'delivered')) THEN
    RAISE EXCEPTION 'This order cannot be confirmed yet (current status: %).', o.status;
  END IF;
  PERFORM set_config('sagana.program_order_rpc', o.id::text, TRUE);
  UPDATE program_product_purchases
     SET status = 'completed', received_at = NOW(), completed_at = NOW(), completion_method = 'consumer'
   WHERE id = o.id;
  PERFORM set_config('sagana.program_order_rpc', '', TRUE);
  PERFORM public._pp_finalize(o.id);
  PERFORM public._pp_notify_staff('Order Completed', o.order_number || ' was confirmed received by the Farmer.');
END $$;

CREATE OR REPLACE FUNCTION public.staff_complete_program_order(p_order_id uuid, p_reason text, p_photo_url text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE o program_product_purchases%ROWTYPE; v_role text; v_name text;
BEGIN
  v_role := public._pp_staff_guard();
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN RAISE EXCEPTION 'Write the reason (at least a few words).'; END IF;
  IF p_photo_url IS NULL OR btrim(p_photo_url) = '' OR btrim(p_photo_url) NOT ILIKE 'http%' THEN
    RAISE EXCEPTION 'Upload a photo as proof first.';
  END IF;
  SELECT * INTO o FROM program_product_purchases WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF o.status = 'completed' THEN RAISE EXCEPTION 'This order is already completed.'; END IF;
  IF o.payment_status <> 'paid' THEN
    RAISE EXCEPTION 'PAYMENT_NOT_RECORDED: Record the cash payment and the handover first.';
  END IF;
  IF NOT ((o.fulfillment_method = 'pickup' AND o.status = 'ready_for_pickup')
       OR (o.fulfillment_method = 'delivery' AND o.status = 'delivered')) THEN
    RAISE EXCEPTION 'This order cannot be completed yet (current status: %).', o.status;
  END IF;
  SELECT full_name INTO v_name FROM user_information WHERE user_id = auth.uid();
  PERFORM set_config('sagana.program_order_rpc', o.id::text, TRUE);
  UPDATE program_product_purchases
     SET status = 'completed', completed_at = NOW(), completion_method = 'staff',
         staff_completion_reason = btrim(p_reason), staff_completion_photo_url = btrim(p_photo_url),
         staff_completed_by = auth.uid(), staff_completed_by_name = v_name, staff_completed_by_role = v_role,
         staff_completed_at = NOW()
   WHERE id = o.id;
  PERFORM set_config('sagana.program_order_rpc', '', TRUE);
  PERFORM public._pp_finalize(o.id);
  PERFORM public._pp_notify(o.farmer_id, 'Order Completed',
    'Your order ' || o.order_number || ' was marked completed by the cooperative staff.', '/farmer/profile/orders');
END $$;

-- ════════════════════════════════════════════════════════════
-- 9. Cancelling (same name as before). The Farmer: own, only while Pending.
--    Staff (Manage): Pending, Approved or on the way, but never after the cash was taken.
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.cancel_program_purchase(p_purchase_id uuid, p_reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  o program_product_purchases%ROWTYPE;
  v_staff boolean := public.is_staff();
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO o FROM program_product_purchases WHERE id = p_purchase_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  IF v_staff THEN
    v_role := public._pp_staff_guard();
    IF p_reason IS NULL OR length(btrim(p_reason)) < 3 THEN RAISE EXCEPTION 'Write the reason for cancelling.'; END IF;
  ELSE
    IF o.farmer_id <> auth.uid() THEN RAISE EXCEPTION 'You can only cancel your own order.'; END IF;
    IF o.status <> 'pending' THEN RAISE EXCEPTION 'You can cancel an order only while it is Pending.'; END IF;
    v_role := 'farmer';
  END IF;
  IF o.status IN ('completed', 'cancelled', 'delivered') OR o.payment_status = 'paid' THEN
    RAISE EXCEPTION 'This order can no longer be cancelled (current status: %).', o.status;
  END IF;

  UPDATE program_product_purchases
     SET status = 'cancelled', cancelled_at = NOW(), cancel_reason = NULLIF(btrim(COALESCE(p_reason, '')), ''),
         cancelled_by = auth.uid(), cancelled_by_role = v_role
   WHERE id = o.id;
  -- The reserved stock goes back.
  UPDATE program_products SET stock_reserved = GREATEST(stock_reserved - o.quantity, 0) WHERE id = o.product_id;

  IF v_staff THEN
    PERFORM public._pp_notify(o.farmer_id, 'Order Cancelled',
      'Your order ' || o.order_number || ' was cancelled by the cooperative.' ||
      CASE WHEN NULLIF(btrim(COALESCE(p_reason, '')), '') IS NOT NULL THEN ' Reason: ' || btrim(p_reason) ELSE '' END,
      '/farmer/profile/orders');
  ELSE
    PERFORM public._pp_notify_staff('Order Cancelled', 'A Farmer cancelled the pending order ' || o.order_number || '.');
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.cancel_program_purchase(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_program_purchase(uuid, text) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 10. Stock for a program (Manager, or Officer with Dashboard = Manage)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.set_program_product_allocation(p_product_id uuid, p_allocated numeric)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE pp program_products%ROWTYPE; v_program cooperative_programs%ROWTYPE;
BEGIN
  IF NOT public.is_staff() THEN RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can set aside stock for a program.'; END IF;
  IF NOT public.staff_can_manage('dashboard') THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Your Officer account has view-only access to the Dashboard module.' USING ERRCODE = '42501';
  END IF;
  IF p_allocated IS NULL OR p_allocated < 0 OR p_allocated <> round(p_allocated, 2) THEN
    RAISE EXCEPTION 'Enter a stock amount of zero or more (two decimals at most).';
  END IF;
  SELECT * INTO pp FROM program_products WHERE id = p_product_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product not found.'; END IF;
  SELECT * INTO v_program FROM cooperative_programs WHERE id = pp.program_id;
  IF v_program.status <> 'active' THEN RAISE EXCEPTION 'This program is Completed. Its stock can no longer be changed.'; END IF;
  IF p_allocated < pp.stock_reserved THEN
    RAISE EXCEPTION 'BELOW_RESERVED: % is already reserved by open orders. Finish or cancel those orders first.', pp.stock_reserved;
  END IF;
  UPDATE program_products SET stock_allocated = round(p_allocated, 2) WHERE id = pp.id;   -- the guard checks it fits
  RETURN round(p_allocated, 2);
END $$;
REVOKE ALL ON FUNCTION public.set_program_product_allocation(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_program_product_allocation(uuid, numeric) TO authenticated;

-- Give the unsold, un-reserved part back to the cooperative's general stock.
CREATE OR REPLACE FUNCTION public.release_program_product_allocation(p_product_id uuid)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE pp program_products%ROWTYPE; v_released numeric;
BEGIN
  IF NOT public.is_staff() THEN RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can release program stock.'; END IF;
  IF NOT public.staff_can_manage('dashboard') THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Your Officer account has view-only access to the Dashboard module.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO pp FROM program_products WHERE id = p_product_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Product not found.'; END IF;
  v_released := pp.stock_allocated - pp.stock_reserved;
  UPDATE program_products SET stock_allocated = stock_reserved WHERE id = pp.id;
  RETURN v_released;
END $$;
REVOKE ALL ON FUNCTION public.release_program_product_allocation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.release_program_product_allocation(uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 11. The old single-step functions are retired (nothing can bypass the new flow)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.request_program_purchase(p_program_id uuid, p_product_id uuid, p_quantity numeric)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  RAISE EXCEPTION 'UPDATE_REQUIRED: Cooperative Products are now ordered from the Marketplace. Please update the app.';
END $$;
CREATE OR REPLACE FUNCTION public.confirm_program_purchase(p_purchase_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  RAISE EXCEPTION 'UPDATE_REQUIRED: Payment is now recorded from Order Management when the order is handed over. Please update the app.';
END $$;

-- Staff permission registry: these orders belong to the Marketplace module now.
DELETE FROM public.staff_permission_targets
 WHERE (kind = 'table' AND name = 'program_product_purchases')
    OR (kind = 'rpc'   AND name IN ('confirm_program_purchase', 'cancel_program_purchase'));
INSERT INTO public.staff_permission_targets (kind, name, module) VALUES
  ('table', 'program_product_purchases',          'marketplace'),
  ('rpc',   'approve_program_order',              'marketplace'),
  ('rpc',   'mark_program_order_ready',           'marketplace'),
  ('rpc',   'mark_program_order_out_for_delivery','marketplace'),
  ('rpc',   'record_program_order_handover',      'marketplace'),
  ('rpc',   'staff_complete_program_order',       'marketplace'),
  ('rpc',   'cancel_program_purchase',            'marketplace'),
  ('rpc',   'set_program_product_allocation',     'dashboard'),
  ('rpc',   'release_program_product_allocation', 'dashboard')
ON CONFLICT (kind, name) DO UPDATE SET module = EXCLUDED.module;

-- The product sales figure now counts completed orders.
CREATE OR REPLACE FUNCTION public.get_program_product_stats(p_program_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'You must be signed in.'; END IF;
  IF NOT (public.is_staff()
          OR EXISTS (SELECT 1 FROM user_roles ur WHERE ur.user_id = auth.uid() AND ur.role = 'farmer' AND ur.status = 'active')) THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Farmer or the cooperative can see this.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cooperative_programs WHERE id = p_program_id AND program_purpose = 'sales') THEN
    RETURN '[]'::jsonb;
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('product_id', pp.id, 'buyers', COALESCE(s.buyers, 0), 'quantity_sold', COALESCE(s.sold, 0)))
      FROM program_products pp
      LEFT JOIN (SELECT p.product_id, count(DISTINCT p.farmer_id) AS buyers, sum(p.quantity) AS sold
                   FROM program_product_purchases p
                  WHERE p.program_id = p_program_id AND p.status = 'completed'
                  GROUP BY p.product_id) s ON s.product_id = pp.id
     WHERE pp.program_id = p_program_id), '[]'::jsonb);
END;
$function$;
REVOKE ALL ON FUNCTION public.get_program_product_stats(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_program_product_stats(UUID) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  The two old purchases and what happened to them (expect the P500 completed + paid, the P50 pending):
--     SELECT order_number, status, payment_status, total_amount, stock_deducted_at, legacy_migrated
--       FROM program_product_purchases ORDER BY requested_at;
-- V2  The migration record:
--     SELECT purchase_id, action, note FROM purchase_migration_log ORDER BY created_at;
-- V3  Stock set aside per product (Peanut Cookies should show everything on hand, the pending P50 reserved):
--     SELECT ci.item_name, ci.quantity_on_hand, pp.stock_allocated, pp.stock_reserved
--       FROM program_products pp JOIN cooperative_inventory ci ON ci.id = pp.inventory_item_id;
-- V4  Nothing can take stock below the allocation (this must FAIL with STOCK_ALLOCATED; it changes nothing):
--     DO $t$ BEGIN
--       UPDATE cooperative_inventory SET quantity_on_hand = 0
--        WHERE id = (SELECT inventory_item_id FROM program_products WHERE stock_allocated > 0 LIMIT 1);
--     END $t$;
-- V5  Clients cannot write purchases directly (expect no INSERT/UPDATE/DELETE privilege for authenticated):
--     SELECT privilege_type FROM information_schema.role_table_grants
--      WHERE table_name = 'program_product_purchases' AND grantee = 'authenticated';
-- V6  The sales figure is intact (the completed P500 is still counted):
--     SELECT sum(total_amount) FROM program_product_purchases WHERE status = 'completed';
