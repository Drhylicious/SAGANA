-- ============================================================
-- SAGANA — Atomic manual quantity update for inventory_batches
-- Brings the farmer's manual "Update Quantity" correction in
-- Manage Inventory in line with the row-locked pattern already
-- used by _apply_batch_reservation (create_listing_with_reservation,
-- offer_batch_to_cooperative, record_informal_sale). Previously this
-- was a client-side read-then-write with no lock and no bounds check.
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_batch_available_quantity(
  p_batch_id UUID,
  p_new_available_kg DECIMAL
) RETURNS VOID AS $$
DECLARE
  v_quantity_kg DECIMAL;
  v_sold_kg DECIMAL;
  v_new_status TEXT;
BEGIN
  SELECT quantity_kg, sold_kg
    INTO v_quantity_kg, v_sold_kg
    FROM public.inventory_batches
    WHERE id = p_batch_id
    FOR UPDATE; -- lock the row for the duration of this transaction

  IF v_quantity_kg IS NULL THEN
    RAISE EXCEPTION 'Batch not found';
  END IF;

  IF p_new_available_kg < 0 THEN
    RAISE EXCEPTION 'Available quantity cannot be negative';
  END IF;

  IF p_new_available_kg > v_quantity_kg THEN
    RAISE EXCEPTION 'Available quantity (%) cannot exceed the batch''s original quantity (%).',
      p_new_available_kg, v_quantity_kg;
  END IF;

  -- Same thresholds as _apply_batch_reservation, for consistency.
  IF p_new_available_kg <= 0 THEN
    v_new_status := CASE WHEN v_sold_kg >= v_quantity_kg THEN 'sold_out' ELSE 'reserved' END;
  ELSIF p_new_available_kg < v_quantity_kg * 0.15 THEN
    v_new_status := 'low_stock';
  ELSE
    v_new_status := 'available';
  END IF;

  UPDATE public.inventory_batches
    SET available_kg = p_new_available_kg, status = v_new_status
    WHERE id = p_batch_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.update_batch_available_quantity(UUID, DECIMAL) TO authenticated;

NOTIFY pgrst, 'reload schema';
