-- ============================================================
-- SAGANA — Phase 4: Program Management notification coverage
-- ============================================================
-- Five Program Management workflows had zero notification coverage.
-- This adds:
--   1. distribute_program_benefit  → notify the farmer who received it
--   2. request_program_purchase    → notify all admins
--   3. confirm_program_purchase    → notify the farmer
--   4. cancel_program_purchase     → notify whichever party didn't
--      initiate the cancellation (admin cancels → notify farmer;
--      farmer cancels → notify all admins)
-- enrollFarmer (Dart, program_repository.dart, plain insert/update, no
-- RPC) is handled separately in the same phase — see that file's diff.
--
-- All new notifications use type='program', matching
-- confirm_program_return's existing type for this same module.
-- ============================================================

-- ─── 1. distribute_program_benefit → notify the farmer ─────────────────────

CREATE OR REPLACE FUNCTION public.distribute_program_benefit(p_program_member_id uuid, p_inventory_item_id uuid, p_quantity numeric, p_recorded_by uuid DEFAULT NULL::uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_available NUMERIC;
  v_item_name TEXT;
  v_farmer_id UUID;
BEGIN
  SELECT quantity_on_hand, item_name INTO v_available, v_item_name
    FROM cooperative_inventory
    WHERE id = p_inventory_item_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory item % no longer exists', p_inventory_item_id;
  END IF;

  IF v_available < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock for %: % on hand, % requested',
      v_item_name, v_available, p_quantity;
  END IF;

  UPDATE cooperative_inventory
  SET quantity_on_hand = quantity_on_hand - p_quantity
  WHERE id = p_inventory_item_id;

  INSERT INTO inventory_transactions (
    inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by
  ) VALUES (
    p_inventory_item_id, 'program_distribution', -p_quantity, p_program_member_id, 'program', p_recorded_by
  );

  UPDATE program_members
  SET inventory_item_id = p_inventory_item_id,
      quantity_given = p_quantity,
      distributed_at = NOW(),
      distributed_item_name = v_item_name
  WHERE id = p_program_member_id
  RETURNING farmer_id INTO v_farmer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id, 'program', 'Benefit Distributed',
    'You received ' || p_quantity || ' ' || COALESCE(v_item_name, 'item(s)') || ' from your program.',
    FALSE, NOW()
  );
END;
$$;

-- ─── 2. request_program_purchase → notify all admins ───────────────────────

CREATE OR REPLACE FUNCTION public.request_program_purchase(p_program_id uuid, p_product_id uuid, p_quantity numeric)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_farmer_id   UUID := auth.uid();
  v_product     RECORD;
  v_on_hand     DECIMAL;
  v_reserved    DECIMAL;
  v_item_name   TEXT;
  v_farmer_name TEXT;
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

  INSERT INTO public.program_product_purchases (
    program_id, product_id, farmer_id, quantity, unit_price, total_amount, status
  ) VALUES (
    p_program_id, p_product_id, v_farmer_id, p_quantity, v_product.unit_price,
    (v_product.unit_price * p_quantity), 'pending'
  )
  RETURNING id INTO v_purchase_id;

  SELECT full_name INTO v_farmer_name FROM public.user_information WHERE user_id = v_farmer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT
    ap.user_id,
    'program',
    'New Program Purchase Request',
    COALESCE(v_farmer_name, 'A farmer') || ' requested to purchase ' || p_quantity || ' ' ||
      COALESCE(v_item_name, 'item(s)') || '.',
    FALSE,
    NOW()
  FROM public.admin_profiles ap;

  RETURN v_purchase_id;
END;
$$;

-- ─── 3. confirm_program_purchase → notify the farmer ────────────────────────

CREATE OR REPLACE FUNCTION public.confirm_program_purchase(p_purchase_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_admin_id  UUID := auth.uid();
  v_purchase  RECORD;
  v_on_hand   DECIMAL;
  v_item_name TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = v_admin_id) THEN
    RAISE EXCEPTION 'Only an admin can confirm a purchase.';
  END IF;

  SELECT id, product_id, quantity, status, farmer_id
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
  SELECT ci.quantity_on_hand, ci.item_name
    INTO v_on_hand, v_item_name
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

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_purchase.farmer_id, 'program', 'Purchase Confirmed',
    'Your purchase of ' || v_purchase.quantity || ' ' || COALESCE(v_item_name, 'item(s)') || ' has been confirmed.',
    FALSE, NOW()
  );
END;
$$;

-- ─── 4. cancel_program_purchase → notify whichever party didn't initiate ───

CREATE OR REPLACE FUNCTION public.cancel_program_purchase(p_purchase_id uuid, p_reason text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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

  IF v_is_admin THEN
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
    VALUES (
      v_purchase.farmer_id, 'program', 'Purchase Cancelled',
      'Your program purchase was cancelled by the SP3 Admin.' ||
        CASE WHEN p_reason IS NOT NULL THEN ' Reason: ' || p_reason ELSE '' END,
      FALSE, NOW()
    );
  ELSE
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
    SELECT ap.user_id, 'program', 'Purchase Cancelled',
           'A farmer cancelled their pending program purchase.',
           FALSE, NOW()
    FROM public.admin_profiles ap;
  END IF;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- SELECT proname, prosrc ILIKE '%INSERT INTO notifications%' AS has_notify
-- FROM pg_proc
-- WHERE proname IN (
--   'distribute_program_benefit', 'request_program_purchase',
--   'confirm_program_purchase', 'cancel_program_purchase'
-- );
-- -- expect all 4 TRUE
--
-- In-app: distribute a benefit, request/confirm/cancel a program
-- purchase from both the farmer and admin side, and confirm the right
-- party sees the notification each time.
-- ============================================================
