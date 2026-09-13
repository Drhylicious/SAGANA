-- ============================================================
-- SAGANA — complete_market_linking authorization guard
-- Closes the one gap where this SECURITY DEFINER function had
-- no internal admin check (every sibling RPC — reject_listing,
-- approve_listing, cancel_order, complete_order,
-- confirm_cooperative_offer, decline_cooperative_offer,
-- adjust_inventory_stock — already has one) and no check that
-- the batch being attached actually belongs to the farmer on
-- the market_linking_programs record being completed.
-- ============================================================

CREATE OR REPLACE FUNCTION public.complete_market_linking(
  p_id UUID,
  p_batch_id UUID DEFAULT NULL,
  p_confirmed_volume_kg NUMERIC DEFAULT NULL,
  p_buyer_name TEXT DEFAULT NULL,
  p_buyer_contact TEXT DEFAULT NULL,
  p_price_per_kg NUMERIC DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
  v_current_status TEXT;
  v_farmer_id UUID;
  v_batch_farmer_id UUID;
  v_quantity_kg DECIMAL;
  v_available_kg DECIMAL;
  v_sold_kg DECIMAL;
  v_new_available DECIMAL;
  v_new_sold DECIMAL;
  v_new_status TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can complete market linking records';
  END IF;

  SELECT status, farmer_id INTO v_current_status, v_farmer_id
    FROM public.market_linking_programs
    WHERE id = p_id
    FOR UPDATE;

  IF v_current_status IS NULL THEN
    RAISE EXCEPTION 'Market linking record not found';
  END IF;

  IF v_current_status = 'completed' THEN
    RETURN; -- already completed — no-op, avoids double-deducting on a retry/race
  END IF;

  IF p_batch_id IS NOT NULL THEN
    IF p_confirmed_volume_kg IS NULL OR p_confirmed_volume_kg <= 0 THEN
      RAISE EXCEPTION 'confirmed_volume_kg is required when a batch is attached';
    END IF;

    SELECT quantity_kg, available_kg, sold_kg, farmer_id
      INTO v_quantity_kg, v_available_kg, v_sold_kg, v_batch_farmer_id
      FROM public.inventory_batches
      WHERE id = p_batch_id
      FOR UPDATE;

    IF v_available_kg IS NULL THEN
      RAISE EXCEPTION 'Batch not found';
    END IF;

    IF v_batch_farmer_id != v_farmer_id THEN
      RAISE EXCEPTION 'Batch does not belong to the farmer on this market linking record';
    END IF;

    IF p_confirmed_volume_kg > v_available_kg THEN
      RAISE EXCEPTION 'Confirmed volume (%) exceeds available batch stock (%)', p_confirmed_volume_kg, v_available_kg;
    END IF;

    v_new_available := v_available_kg - p_confirmed_volume_kg;
    v_new_sold := v_sold_kg + p_confirmed_volume_kg;

    -- Same thresholds as _apply_batch_reservation, for consistency.
    IF v_new_available <= 0 THEN
      v_new_status := 'sold_out';
    ELSIF v_new_available < v_quantity_kg * 0.15 THEN
      v_new_status := 'low_stock';
    ELSE
      v_new_status := 'available';
    END IF;

    UPDATE public.inventory_batches
      SET available_kg = v_new_available, sold_kg = v_new_sold, status = v_new_status
      WHERE id = p_batch_id;
  END IF;

  UPDATE public.market_linking_programs
    SET status = 'completed',
        completed_at = NOW(),
        inventory_batch_id = COALESCE(p_batch_id, inventory_batch_id),
        confirmed_volume_kg = COALESCE(p_confirmed_volume_kg, confirmed_volume_kg),
        buyer_name = COALESCE(p_buyer_name, buyer_name),
        buyer_contact = COALESCE(p_buyer_contact, buyer_contact),
        price_per_kg = COALESCE(p_price_per_kg, price_per_kg),
        notes = COALESCE(p_notes, notes)
    WHERE id = p_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.complete_market_linking(UUID, UUID, NUMERIC, TEXT, TEXT, NUMERIC, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';