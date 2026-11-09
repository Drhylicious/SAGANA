-- ============================================================
-- SAGANA — Program Management rework, PHASE 4: PRODUCT SALES MEMBER PRICING
--
-- Every active, approved Farmer can see and buy the products of an ACTIVE
-- Product Sales program. Enrollment no longer decides whether a product is
-- available; it decides the PRICE: an enrolled Farmer pays the regular price
-- less the program's member discount (Balik-Tangkilik at the point of sale);
-- a Farmer who is not enrolled pays the regular price.
--
-- Written from the LIVE definitions (Database_checks.md Q3 / Q4) and the Phase 1
-- version of request_program_purchase. NOT APPLIED — run it yourself once, then
-- the verification block. One transaction: all or nothing.
--
-- WHAT IT DOES
--   1. cooperative_programs.member_discount_percent — the discount, SET PER
--      PROGRAM by the Manager / authorized staff. Default 0 (no discount). The
--      10% mentioned in discussion is NOT stored or assumed anywhere.
--   2. program_product_purchases records what each purchase actually was:
--        regular_unit_price   the price list price per unit
--        discount_percent     the discount applied (0 for a non-member)
--        discount_amount      regular total minus what was charged
--        is_member_price      whether the buyer was enrolled when they requested
--      unit_price and total_amount keep meaning "what was charged" (the NET
--      amount), so everything that already reads them — Balik-Tangkilik,
--      Member Patronage Report, My Contribution — keeps reading real money paid.
--      Existing purchases are back-filled truthfully: regular price = the price
--      they paid, no discount, member = true (until now ONLY enrolled farmers
--      could buy).
--   3. Visibility: the program-product and inventory read policies no longer
--      require enrollment; they require an active farmer and an ACTIVE sales
--      program. (A Completed program's products are no longer offered.)
--   4. request_program_purchase() decides the price on the SERVER from the
--      buyer's enrollment, never from the app, and snapshots it. Stock checks,
--      the staff notice and the pending -> paid flow are unchanged.
--
-- NOT CHANGED (by your decision, pending your review): Purchase Patronage,
-- Balik-Tangkilik, the Member Patronage Report and My Contribution calculations.
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. The member discount, set per program
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.cooperative_programs
  ADD COLUMN IF NOT EXISTS member_discount_percent NUMERIC(5,2) NOT NULL DEFAULT 0;

ALTER TABLE public.cooperative_programs
  DROP CONSTRAINT IF EXISTS cooperative_programs_member_discount_check;
ALTER TABLE public.cooperative_programs
  ADD CONSTRAINT cooperative_programs_member_discount_check
  CHECK (member_discount_percent >= 0 AND member_discount_percent <= 100);

COMMENT ON COLUMN public.cooperative_programs.member_discount_percent IS
  'Product Sales programs: the discount (percent off the regular price) an ENROLLED '
  'member pays at purchase (Balik-Tangkilik at the point of sale). Set per program by '
  'the Manager or authorized staff; 0 = no discount. Never a hardcoded rate.';

-- ════════════════════════════════════════════════════════════
-- 2. What each purchase actually was
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.program_product_purchases
  ADD COLUMN IF NOT EXISTS regular_unit_price NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS discount_percent   NUMERIC(5,2)  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS discount_amount    NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_member_price    BOOLEAN       NOT NULL DEFAULT FALSE;

-- Back-fill: every purchase made so far was by an enrolled member (the old
-- function required it) at the single price list price, with no discount.
UPDATE public.program_product_purchases
   SET regular_unit_price = unit_price,
       discount_percent   = 0,
       discount_amount    = 0,
       is_member_price    = TRUE
 WHERE regular_unit_price IS NULL;

ALTER TABLE public.program_product_purchases
  DROP CONSTRAINT IF EXISTS program_product_purchases_price_check;
ALTER TABLE public.program_product_purchases
  ADD CONSTRAINT program_product_purchases_price_check
  CHECK (regular_unit_price IS NULL OR unit_price <= regular_unit_price);

ALTER TABLE public.program_product_purchases
  DROP CONSTRAINT IF EXISTS program_product_purchases_discount_check;
ALTER TABLE public.program_product_purchases
  ADD CONSTRAINT program_product_purchases_discount_check
  CHECK (discount_percent >= 0 AND discount_percent <= 100 AND discount_amount >= 0);

COMMENT ON COLUMN public.program_product_purchases.unit_price IS
  'The price actually charged per unit (net of any member discount).';
COMMENT ON COLUMN public.program_product_purchases.total_amount IS
  'The NET amount charged: quantity x unit_price. The figure reports and patronage read.';

-- ════════════════════════════════════════════════════════════
-- 3. Visibility: every active farmer, active sales programs only
-- ════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "program_products: enrolled active farmers read available" ON public.program_products;
DROP POLICY IF EXISTS "program_products: farmers read available" ON public.program_products;
CREATE POLICY "program_products: farmers read available"
  ON public.program_products FOR SELECT
  USING (
    is_available = TRUE
    AND EXISTS (SELECT 1 FROM public.user_roles ur
                WHERE ur.user_id = auth.uid() AND ur.role = 'farmer' AND ur.status = 'active')
    AND EXISTS (SELECT 1 FROM public.cooperative_programs cp
                WHERE cp.id = program_products.program_id
                  AND cp.status = 'active' AND cp.program_purpose = 'sales')
  );

-- The catalog also reads the item's name, unit, stock and photo.
DROP POLICY IF EXISTS "cooperative_inventory: enrolled farmers read sales program items" ON public.cooperative_inventory;
DROP POLICY IF EXISTS "cooperative_inventory: farmers read sales program items" ON public.cooperative_inventory;
CREATE POLICY "cooperative_inventory: farmers read sales program items"
  ON public.cooperative_inventory FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.user_roles ur
            WHERE ur.user_id = auth.uid() AND ur.role = 'farmer' AND ur.status = 'active')
    AND EXISTS (
      SELECT 1
      FROM public.program_products pp
      JOIN public.cooperative_programs cp ON cp.id = pp.program_id
      WHERE pp.inventory_item_id = cooperative_inventory.id
        AND pp.is_available = TRUE
        AND cp.status = 'active' AND cp.program_purpose = 'sales'
    )
  );

-- ════════════════════════════════════════════════════════════
-- 4. request_program_purchase(): the server decides the price
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.request_program_purchase(p_program_id uuid, p_product_id uuid, p_quantity numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_farmer_id   UUID := auth.uid();
  v_program     cooperative_programs%ROWTYPE;
  v_product     RECORD;
  v_on_hand     DECIMAL;
  v_reserved    DECIMAL;
  v_item_name   TEXT;
  v_farmer_name TEXT;
  v_purchase_id UUID;
  v_is_member   BOOLEAN;
  v_pct         NUMERIC;
  v_regular     NUMERIC;
  v_unit        NUMERIC;
  v_total       NUMERIC;
  v_discount    NUMERIC;
BEGIN
  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'You must be signed in.';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero.';
  END IF;

  -- Any active cooperative member may buy; enrollment only decides the price.
  IF NOT EXISTS (SELECT 1 FROM public.user_roles
                  WHERE user_id = v_farmer_id AND role = 'farmer' AND status = 'active') THEN
    RAISE EXCEPTION 'Only an active cooperative member can buy these products.';
  END IF;

  SELECT * INTO v_program FROM public.cooperative_programs WHERE id = p_program_id;
  IF NOT FOUND OR v_program.program_purpose <> 'sales' THEN
    RAISE EXCEPTION 'Product Sales program not found.';
  END IF;
  IF v_program.status <> 'active' THEN
    RAISE EXCEPTION 'This program is Completed and no longer accepts purchases.';
  END IF;

  v_is_member := EXISTS (
    SELECT 1 FROM public.program_members
     WHERE program_id = p_program_id AND farmer_id = v_farmer_id AND status = 'active');

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

  SELECT quantity_on_hand, quantity_reserved, item_name
    INTO v_on_hand, v_reserved, v_item_name
    FROM public.cooperative_inventory
    WHERE id = v_product.inventory_item_id
    FOR SHARE;

  IF v_on_hand IS NULL THEN
    RAISE EXCEPTION 'Linked inventory item no longer exists.';
  END IF;
  IF (v_on_hand - v_reserved) < p_quantity THEN
    RAISE EXCEPTION 'Not enough stock available for this quantity.';
  END IF;

  -- The price: regular for everyone; less the program's member discount for an
  -- enrolled member. Rounded to centavos, then snapshotted on the purchase.
  v_regular  := v_product.unit_price;
  v_pct      := CASE WHEN v_is_member THEN COALESCE(v_program.member_discount_percent, 0) ELSE 0 END;
  v_unit     := round(v_regular * (1 - v_pct / 100.0), 2);
  v_total    := round(v_unit * p_quantity, 2);
  v_discount := round(v_regular * p_quantity, 2) - v_total;

  INSERT INTO public.program_product_purchases (
    program_id, product_id, farmer_id, quantity, unit_price, total_amount, status,
    regular_unit_price, discount_percent, discount_amount, is_member_price
  ) VALUES (
    p_program_id, p_product_id, v_farmer_id, p_quantity, v_unit, v_total, 'pending',
    v_regular, v_pct, v_discount, v_is_member
  )
  RETURNING id INTO v_purchase_id;

  SELECT full_name INTO v_farmer_name FROM public.user_information WHERE user_id = v_farmer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT
    ap.user_id,
    'program',
    'New Program Purchase Request',
    COALESCE(v_farmer_name, 'A farmer') || ' requested to purchase ' || p_quantity || ' ' ||
      COALESCE(v_item_name, 'item(s)') ||
      CASE WHEN v_pct > 0 THEN ' at the member price (' || v_pct || '% off).' ELSE '.' END,
    FALSE,
    NOW()
  FROM public.admin_profiles ap;

  RETURN v_purchase_id;
END;
$function$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only; run each by itself AFTER applying)
-- ============================================================
-- V1. New columns exist (expect 1 row, then 4 rows):
--     SELECT column_name FROM information_schema.columns WHERE table_name='cooperative_programs' AND column_name='member_discount_percent';
--     SELECT column_name FROM information_schema.columns WHERE table_name='program_product_purchases'
--       AND column_name IN ('regular_unit_price','discount_percent','discount_amount','is_member_price');
-- V2. The existing purchase was back-filled truthfully (expect 1 row: 500.00 paid, regular = unit price, no discount, member = true):
--     SELECT status, total_amount, unit_price, regular_unit_price, discount_percent, discount_amount, is_member_price
--     FROM program_product_purchases;
-- V3. No program has a discount until you set one (expect every row 0.00):
--     SELECT program_name, program_purpose, member_discount_percent FROM cooperative_programs ORDER BY created_at;
-- V4. The old enrollment-only policies are gone and the new ones exist (expect 0 rows, then 2 rows):
--     SELECT policyname FROM pg_policies WHERE policyname IN
--       ('program_products: enrolled active farmers read available','cooperative_inventory: enrolled farmers read sales program items');
--     SELECT policyname FROM pg_policies WHERE policyname IN
--       ('program_products: farmers read available','cooperative_inventory: farmers read sales program items');
-- V5. The purchase function now prices by enrollment (expect true, true):
--     SELECT pg_get_functiondef('public.request_program_purchase(uuid,uuid,numeric)'::regprocedure) ILIKE '%member_discount_percent%' AS prices_by_program,
--            pg_get_functiondef('public.request_program_purchase(uuid,uuid,numeric)'::regprocedure) ILIKE '%Completed%' AS blocks_completed;
-- V6. Reconciliation: for every purchase, regular total - discount = net charged (expect 0 rows):
--     SELECT id FROM program_product_purchases
--     WHERE round(COALESCE(regular_unit_price, unit_price) * quantity - discount_amount, 2) <> total_amount;
-- V7. Patronage inputs unchanged (expect the same figures as before: 500.00 / 400.00):
--     SELECT sum(total_amount) FROM program_product_purchases WHERE status = 'paid';
--     SELECT total_program_sales, distributable_program_surplus FROM cooperative_annual_totals WHERE year = 2026;
-- ============================================================
