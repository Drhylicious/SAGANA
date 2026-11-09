-- ============================================================
-- SAGANA — Unified purchasing m01: security, duplicate protection, payment records
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run.
-- Order for the whole set:  m01 -> m02 -> m03 -> m04 -> m05 -> m06
--
-- WHAT IT DOES
--   1. SECURITY: drops the "Buyers create orders" INSERT policy. It let any signed-in
--      user insert an order row for themselves with ANY price or status, skipping
--      place_order(). Every legitimate order is created by place_order(), which is
--      SECURITY DEFINER (it runs as the table owner, so the policy is not needed).
--      The script refuses to run if place_order() is not SECURITY DEFINER.
--   2. DUPLICATE PROTECTION: orders.request_id (+ unique per consumer). A retry of the
--      same checkout line can then return the existing order instead of making another.
--   3. PAYMENT: orders get a separate payment record (status, when, who, amount) and
--      a staff-assisted completion record (reason, photo, who, when). Completed orders
--      from before this change are marked 'not_recorded': no payment is invented for them.
--   4. orders.checkout_group_id is added (the delivery group, see m05).
--
-- Nothing is deleted. No order changes status. Historical totals are untouched.
-- ============================================================

-- PREVIEW (read-only)
SELECT status, count(*) AS orders FROM public.orders GROUP BY 1 ORDER BY 1;

BEGIN;

DO $$
DECLARE v_secdef BOOLEAN;
BEGIN
  IF to_regclass('public.orders') IS NULL THEN
    RAISE EXCEPTION 'public.orders is missing.';
  END IF;
  IF to_regprocedure('public.is_staff()') IS NULL OR to_regprocedure('public.is_manager(uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_staff() / is_manager() are missing (apply the Officer permission scripts first).';
  END IF;
  SELECT bool_and(p.prosecdef) INTO v_secdef
    FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'place_order';
  IF v_secdef IS NOT TRUE THEN
    RAISE EXCEPTION 'place_order() must exist and be SECURITY DEFINER before the INSERT policy is dropped.';
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- 1. Security
-- ════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "Buyers create orders" ON public.orders;

-- ════════════════════════════════════════════════════════════
-- 2. Duplicate protection
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS request_id UUID;
CREATE UNIQUE INDEX IF NOT EXISTS uq_orders_buyer_request
  ON public.orders (buyer_id, request_id) WHERE request_id IS NOT NULL;

-- ════════════════════════════════════════════════════════════
-- 3. Payment and staff-assisted completion records
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_status            TEXT NOT NULL DEFAULT 'unpaid',
  ADD COLUMN IF NOT EXISTS paid_at                   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS payment_recorded_by       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS payment_recorded_by_name  TEXT,
  ADD COLUMN IF NOT EXISTS payment_recorded_by_role  TEXT,
  ADD COLUMN IF NOT EXISTS amount_collected          NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS payment_note              TEXT,
  ADD COLUMN IF NOT EXISTS completion_method         TEXT,
  ADD COLUMN IF NOT EXISTS staff_completion_reason   TEXT,
  ADD COLUMN IF NOT EXISTS staff_completion_photo_url TEXT,
  ADD COLUMN IF NOT EXISTS staff_completed_by        UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS staff_completed_by_name   TEXT,
  ADD COLUMN IF NOT EXISTS staff_completed_by_role   TEXT,
  ADD COLUMN IF NOT EXISTS staff_completed_at        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS checkout_group_id         UUID;

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_payment_status_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_payment_status_check
  CHECK (payment_status IN ('unpaid', 'paid', 'not_recorded'));
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_completion_method_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_completion_method_check
  CHECK (completion_method IS NULL OR completion_method IN ('consumer', 'staff'));

-- A staff-assisted completion always carries its reason, photo and who did it.
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_staff_completion_complete;
ALTER TABLE public.orders ADD CONSTRAINT orders_staff_completion_complete
  CHECK (completion_method IS DISTINCT FROM 'staff'
         OR (staff_completion_reason IS NOT NULL AND staff_completion_photo_url IS NOT NULL
             AND staff_completed_by IS NOT NULL AND staff_completed_at IS NOT NULL)) NOT VALID;

-- Orders already completed before this change: say so, do not invent a payment.
-- (updated_at is left alone: completed-order dates must not move.)
ALTER TABLE public.orders DISABLE TRIGGER orders_updated_at;
UPDATE public.orders
   SET payment_status = 'not_recorded',
       completion_method = COALESCE(completion_method, 'consumer')
 WHERE status = 'completed' AND payment_status = 'unpaid';
ALTER TABLE public.orders ENABLE TRIGGER orders_updated_at;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  The unrestricted INSERT policy is gone (expect no row named "Buyers create orders"):
--     SELECT policyname, cmd FROM pg_policies WHERE tablename = 'orders' ORDER BY 1;
-- V2  Completed orders are marked, nothing else moved (same counts as the preview):
--     SELECT status, payment_status, count(*) FROM orders GROUP BY 1, 2 ORDER BY 1, 2;
-- V3  New columns exist (expect 15 rows):
--     SELECT column_name FROM information_schema.columns WHERE table_name = 'orders'
--      AND column_name IN ('request_id','payment_status','paid_at','payment_recorded_by','payment_recorded_by_name',
--      'payment_recorded_by_role','amount_collected','payment_note','completion_method','staff_completion_reason',
--      'staff_completion_photo_url','staff_completed_by','staff_completed_by_name','staff_completed_by_role',
--      'staff_completed_at','checkout_group_id');
-- V4  The app can still place an order: place an order from a Buyer test account (pickup).
