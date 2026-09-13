-- ============================================================
-- SAGANA — M-9 fix: update_batch_available_quantity was validating
-- p_new_available_kg against the batch's original quantity_kg,
-- with no awareness of stock already committed to an active
-- listing/cooperative-offer/market-linking reservation. Since
-- reserved_kg is dead schema (never written by any currently-live
-- function — only by the superseded buyer_orders.sql/
-- order_management.sql), the correct ceiling is quantity_kg -
-- sold_kg: the only quantity the current reservation model
-- actually keeps accurate. v_sold_kg was already being fetched
-- for the status calculation below but was never used in the
-- bounds check — this was the actual defect.
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_batch_available_quantity(
  p_batch_id UUID,
  p_new_available_kg DECIMAL
) RETURNS VOID AS $$
DECLARE
  v_quantity_kg DECIMAL;
  v_sold_kg DECIMAL;
  v_max_available DECIMAL;
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

  v_max_available := v_quantity_kg - v_sold_kg;

  IF p_new_available_kg > v_max_available THEN
    RAISE EXCEPTION 'Available quantity (%) cannot exceed %.2f kg — % kg of this batch is already sold or committed to an active listing, cooperative offer, or market linking reservation.',
      p_new_available_kg, v_max_available, (v_quantity_kg - v_max_available);
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