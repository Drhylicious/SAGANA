-- ============================================================
-- SAGANA — Cooperative Product Sales Program (Phase A: schema only)
-- (Admin Dashboard investigation, dashboard.md sections 6-9 / 14)
--
-- Introduces a second, distinct kind of Program: one where the
-- cooperative SELLS its own inventory-owned products (e.g. peanut
-- cookies) to enrolled farmer-members, instead of DISTRIBUTING a
-- benefit the farmer may owe back on (the only kind of Program that
-- existed before this). Deliberately does not touch Member Patronage /
-- Balik-Tangkilik in any way — that stays a separate, later decision.
--
-- Design decisions this migration encodes (agreed before implementation):
--   1. Patronage is untouched — no reference to member_sales_transactions
--      or the BT calculation anywhere here.
--   2. Real payment lifecycle — a purchase starts 'pending' and only
--      becomes 'paid' via an explicit admin confirmation RPC. Stock is
--      never deducted until that confirmation.
--   3. Enrollment stays admin-only, via the existing program_members
--      mechanism — enforced here at the RLS level (a farmer can only see
--      products, and the purchase RPC only succeeds, for a program they
--      have an ACTIVE program_members row in).
--   4. Cross-catalog separation (an item shouldn't quietly be usable
--      through both the Loan Item Catalog and a Sales Program) is left to
--      the application layer (each picker excludes items already claimed
--      by the other catalog), not a DB constraint — so the business rule
--      can change later without a migration.
-- ============================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. cooperative_programs.program_purpose
-- Orthogonal to benefit_type ('grant'/'revenue_share'), which answers "how
-- does the member owe the coop back" — a question that doesn't apply to a
-- sale at all. 'distribution' is the default so every existing program
-- (built before this column existed) keeps behaving exactly as before.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.cooperative_programs
  ADD COLUMN IF NOT EXISTS program_purpose TEXT NOT NULL DEFAULT 'distribution'
  CHECK (program_purpose IN ('distribution', 'sales'));

COMMENT ON COLUMN public.cooperative_programs.program_purpose IS
  '''distribution'' = the existing benefit/loan-ROI workflow (grant or '
  'revenue_share). ''sales'' = the cooperative sells its own inventory '
  'products to enrolled members via program_products / '
  'program_product_purchases — distribution/outcome/loan-conversion '
  'actions do not apply to this kind of program.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. program_products
-- Which cooperative_inventory items a 'sales' program currently offers,
-- and at what price. Mirrors loan_items_master's own shape (a thin join
-- table onto cooperative_inventory, not a duplicate item record) —
-- already the established pattern in this schema for "this inventory item
-- is also available through a second catalog."
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.program_products (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  program_id        UUID          NOT NULL REFERENCES public.cooperative_programs(id) ON DELETE CASCADE,
  inventory_item_id UUID          NOT NULL REFERENCES public.cooperative_inventory(id) ON DELETE RESTRICT,
  unit_price        DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
  is_available      BOOLEAN       NOT NULL DEFAULT TRUE,
  created_by        UUID          REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (program_id, inventory_item_id)
);

CREATE TRIGGER trg_program_products_updated_at
  BEFORE UPDATE ON public.program_products
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

CREATE INDEX IF NOT EXISTS idx_program_products_program
  ON public.program_products (program_id, is_available);

ALTER TABLE public.program_products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "program_products: admin manages all"
  ON public.program_products FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

-- A farmer sees a product only if it's available AND they have an ACTIVE
-- enrollment in that specific program — this is decision 3's admin-only
-- enrollment gate, enforced in the database rather than only in the app.
CREATE POLICY "program_products: enrolled active farmers read available"
  ON public.program_products FOR SELECT
  USING (
    is_available = TRUE
    AND EXISTS (
      SELECT 1 FROM public.program_members pm
      WHERE pm.program_id = program_products.program_id
        AND pm.farmer_id = auth.uid()
        AND pm.status = 'active'
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. program_product_purchases
-- One row per purchase request. status starts 'pending' and is never
-- auto-advanced — only confirm_program_purchase()/cancel_program_purchase()
-- (both below) ever change it. unit_price/total_amount are snapshotted at
-- request time so a later price change on program_products never rewrites
-- a farmer's already-placed order.
--
-- No farmer INSERT/UPDATE policy is defined here deliberately — every
-- write goes through the SECURITY DEFINER RPCs below, which validate
-- enrollment, availability, and stock server-side before touching this
-- table. Same precedent as issue_loan()/confirm_cooperative_offer(): a
-- real-money operation is never a raw client insert in this schema.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.program_product_purchases (
  id            UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  program_id    UUID          NOT NULL REFERENCES public.cooperative_programs(id) ON DELETE CASCADE,
  product_id    UUID          NOT NULL REFERENCES public.program_products(id) ON DELETE RESTRICT,
  farmer_id     UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  quantity      DECIMAL(12,2) NOT NULL CHECK (quantity > 0),
  unit_price    DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
  total_amount  DECIMAL(12,2) NOT NULL CHECK (total_amount >= 0),
  status        TEXT          NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'paid', 'cancelled')),
  requested_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  confirmed_at  TIMESTAMPTZ,
  confirmed_by  UUID          REFERENCES auth.users(id) ON DELETE SET NULL,
  cancelled_at  TIMESTAMPTZ,
  cancel_reason TEXT,
  notes         TEXT
);

CREATE INDEX IF NOT EXISTS idx_program_product_purchases_farmer
  ON public.program_product_purchases (farmer_id, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_program_product_purchases_status
  ON public.program_product_purchases (status);

ALTER TABLE public.program_product_purchases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "program_product_purchases: admin manages all"
  ON public.program_product_purchases FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

CREATE POLICY "program_product_purchases: farmer reads own"
  ON public.program_product_purchases FOR SELECT
  USING (auth.uid() = farmer_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. request_program_purchase()
-- Farmer-facing entry point. Re-validates enrollment and availability
-- server-side (never trusts the client), checks stock is sufficient, and
-- inserts a 'pending' row with a server-computed total_amount — nothing in
-- cooperative_inventory is touched here (decision 2: no auto-deduction).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.request_program_purchase(
  p_program_id UUID,
  p_product_id UUID,
  p_quantity   DECIMAL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer_id  UUID := auth.uid();
  v_product    RECORD;
  v_on_hand    DECIMAL;
  v_reserved   DECIMAL;
  v_purchase_id UUID;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.program_members
    WHERE program_id = p_program_id
      AND farmer_id = v_farmer_id
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'You are not an active member of this program.';
  END IF;

  SELECT pp.id, pp.unit_price, pp.is_available, pp.inventory_item_id
    INTO v_product
    FROM public.program_products pp
    WHERE pp.id = p_product_id
      AND pp.program_id = p_program_id
    FOR SHARE;

  IF v_product IS NULL THEN
    RAISE EXCEPTION 'Product not found for this program.';
  END IF;
  IF NOT v_product.is_available THEN
    RAISE EXCEPTION 'This product is not currently available for purchase.';
  END IF;

  SELECT quantity_on_hand, quantity_reserved
    INTO v_on_hand, v_reserved
    FROM public.cooperative_inventory
    WHERE id = v_product.inventory_item_id
    FOR SHARE;

  IF v_on_hand IS NULL THEN
    RAISE EXCEPTION 'Linked inventory item no longer exists.';
  END IF;
  IF (v_on_hand - v_reserved) < p_quantity THEN
    RAISE EXCEPTION 'Not enough stock available for this quantity.';
  END IF;

  INSERT INTO public.program_product_purchases (
    program_id, product_id, farmer_id, quantity, unit_price, total_amount, status
  ) VALUES (
    p_program_id, p_product_id, v_farmer_id, p_quantity, v_product.unit_price,
    (v_product.unit_price * p_quantity), 'pending'
  )
  RETURNING id INTO v_purchase_id;

  RETURN v_purchase_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. confirm_program_purchase()
-- Admin-only. Moves a pending purchase to 'paid' and — only at this
-- point — deducts stock, atomically and row-locked, same as every other
-- stock-moving RPC in this schema. Also writes an inventory_transactions
-- row so the movement shows up in existing stock history/reporting.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.confirm_program_purchase(
  p_purchase_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_purchase RECORD;
  v_on_hand  DECIMAL;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = v_admin_id) THEN
    RAISE EXCEPTION 'Only an admin can confirm a purchase.';
  END IF;

  SELECT id, product_id, quantity, status
    INTO v_purchase
    FROM public.program_product_purchases
    WHERE id = p_purchase_id
    FOR UPDATE;

  IF v_purchase IS NULL THEN
    RAISE EXCEPTION 'Purchase not found.';
  END IF;
  IF v_purchase.status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending purchase can be confirmed.';
  END IF;

  -- Row-lock the linked inventory item through program_products, re-check
  -- stock at confirmation time (it may have moved since the request).
  SELECT ci.quantity_on_hand
    INTO v_on_hand
    FROM public.cooperative_inventory ci
    JOIN public.program_products pp ON pp.inventory_item_id = ci.id
    WHERE pp.id = v_purchase.product_id
    FOR UPDATE OF ci;

  IF v_on_hand IS NULL OR v_on_hand < v_purchase.quantity THEN
    RAISE EXCEPTION 'Not enough stock remaining to confirm this purchase.';
  END IF;

  UPDATE public.cooperative_inventory ci
    SET quantity_on_hand = ci.quantity_on_hand - v_purchase.quantity
    FROM public.program_products pp
    WHERE pp.id = v_purchase.product_id
      AND ci.id = pp.inventory_item_id;

  INSERT INTO public.inventory_transactions (
    inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by, notes
  )
  SELECT pp.inventory_item_id, 'sold', -v_purchase.quantity, v_purchase.id, 'program_purchase', v_admin_id,
         'Program product sale'
  FROM public.program_products pp
  WHERE pp.id = v_purchase.product_id;

  UPDATE public.program_product_purchases
    SET status = 'paid',
        confirmed_at = NOW(),
        confirmed_by = v_admin_id
    WHERE id = p_purchase_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. cancel_program_purchase()
-- Only a still-pending purchase can be cancelled (a paid one has already
-- moved real stock and would need a separate return/refund flow, out of
-- scope here). Callable by the farmer who placed it, or any admin.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cancel_program_purchase(
  p_purchase_id UUID,
  p_reason      TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_purchase  RECORD;
  v_is_admin  BOOLEAN;
BEGIN
  SELECT EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = v_caller_id)
    INTO v_is_admin;

  SELECT id, farmer_id, status
    INTO v_purchase
    FROM public.program_product_purchases
    WHERE id = p_purchase_id
    FOR UPDATE;

  IF v_purchase IS NULL THEN
    RAISE EXCEPTION 'Purchase not found.';
  END IF;
  IF NOT v_is_admin AND v_purchase.farmer_id <> v_caller_id THEN
    RAISE EXCEPTION 'You can only cancel your own purchase.';
  END IF;
  IF v_purchase.status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending purchase can be cancelled.';
  END IF;

  UPDATE public.program_product_purchases
    SET status = 'cancelled',
        cancelled_at = NOW(),
        cancel_reason = p_reason
    WHERE id = p_purchase_id;
END;
$$;

NOTIFY pgrst, 'reload schema';
