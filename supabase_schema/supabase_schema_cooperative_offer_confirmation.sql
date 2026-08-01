-- ============================================================
-- SAGANA — Cooperative Offer Confirmation Workflow
-- Mirrors approve_crop_request/reject_crop_request's shape:
-- atomic, admin-checked, notifies the farmer either way.
-- ============================================================

ALTER TABLE public.cooperative_purchase_offers
  ADD COLUMN IF NOT EXISTS admin_notes TEXT;

-- ─── Confirm ─────────────────────────────────────────────────────────────────
-- Creates the actual member_sales_transactions row (crop_type derived from
-- the offer's crop name, lowercased — fails loudly if it's ever anything
-- other than palay/peanut, since only those count toward Balik-Tangkilik),
-- links it back onto the offer, and marks the offer confirmed.

CREATE OR REPLACE FUNCTION confirm_cooperative_offer(
  p_offer_id UUID,
  p_confirmed_quantity_kg DECIMAL,
  p_confirmed_amount DECIMAL,
  p_admin_notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer RECORD;
  v_transaction_id UUID;
  v_crop_type TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can confirm cooperative offers';
  END IF;

  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF v_offer IS NULL THEN
    RAISE EXCEPTION 'Cooperative offer not found';
  END IF;
  IF v_offer.status != 'pending' THEN
    RAISE EXCEPTION 'Offer already reviewed (status: %)', v_offer.status;
  END IF;

  IF p_confirmed_quantity_kg <= 0 OR p_confirmed_quantity_kg > v_offer.offered_quantity_kg THEN
    RAISE EXCEPTION 'Confirmed quantity must be between 0 and the offered quantity (%).', v_offer.offered_quantity_kg;
  END IF;

  v_crop_type := lower(v_offer.crop_name);
  IF v_crop_type NOT IN ('palay', 'peanut') THEN
    RAISE EXCEPTION 'Crop % is not eligible for a Balik-Tangkilik sales record.', v_offer.crop_name;
  END IF;

  INSERT INTO member_sales_transactions (
    farmer_id, crop_name, crop_type, quantity_kg, amount, sale_date, recorded_by
  ) VALUES (
    v_offer.farmer_id, v_offer.crop_name, v_crop_type,
    p_confirmed_quantity_kg, p_confirmed_amount, CURRENT_DATE, auth.uid()
  ) RETURNING id INTO v_transaction_id;

  UPDATE cooperative_purchase_offers
  SET status = 'confirmed',
      confirmed_quantity_kg = p_confirmed_quantity_kg,
      confirmed_amount = p_confirmed_amount,
      member_sales_transaction_id = v_transaction_id,
      admin_notes = p_admin_notes,
      confirmed_by = auth.uid(),
      confirmed_at = NOW()
  WHERE id = p_offer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_offer.farmer_id,
    'system',
    'Cooperative Purchase Confirmed',
    'Your offer of ' || p_confirmed_quantity_kg || 'kg ' || v_offer.crop_name ||
      ' was confirmed by SP3 for ₱' || p_confirmed_amount || '.',
    FALSE,
    NOW()
  );

  RETURN v_transaction_id;
END;
$$;

GRANT EXECUTE ON FUNCTION confirm_cooperative_offer TO authenticated;

-- ─── Decline ─────────────────────────────────────────────────────────────────
-- Unlike reject_crop_request, this one has real reserved stock to release —
-- the offer already decremented available_kg via _apply_batch_reservation,
-- so declining must give it back and recompute the batch's status.

CREATE OR REPLACE FUNCTION decline_cooperative_offer(
  p_offer_id UUID,
  p_admin_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer RECORD;
  v_batch RECORD;
  v_new_available DECIMAL;
  v_new_status TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can decline cooperative offers';
  END IF;

  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF v_offer IS NULL THEN
    RAISE EXCEPTION 'Cooperative offer not found';
  END IF;
  IF v_offer.status != 'pending' THEN
    RAISE EXCEPTION 'Offer already reviewed (status: %)', v_offer.status;
  END IF;

  SELECT quantity_kg, available_kg, sold_kg INTO v_batch
    FROM inventory_batches WHERE id = v_offer.inventory_batch_id FOR UPDATE;

  v_new_available := v_batch.available_kg + v_offer.offered_quantity_kg;
  v_new_status := CASE
    WHEN v_new_available <= 0 THEN 'sold_out'
    WHEN v_new_available < v_batch.quantity_kg * 0.15 THEN 'low_stock'
    ELSE 'available'
  END;

  UPDATE inventory_batches
  SET available_kg = v_new_available, status = v_new_status
  WHERE id = v_offer.inventory_batch_id;

  UPDATE cooperative_purchase_offers
  SET status = 'declined', admin_notes = p_admin_notes,
      confirmed_by = auth.uid(), confirmed_at = NOW()
  WHERE id = p_offer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_offer.farmer_id,
    'system',
    'Cooperative Purchase Offer Declined',
    'Your offer of ' || v_offer.offered_quantity_kg || 'kg ' || v_offer.crop_name ||
      ' was not accepted by SP3.' ||
      CASE WHEN p_admin_notes IS NOT NULL THEN ' Reason: ' || p_admin_notes ELSE '' END,
    FALSE,
    NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION decline_cooperative_offer TO authenticated;

NOTIFY pgrst, 'reload schema';