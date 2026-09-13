-- ============================================================
-- SAGANA — M-9 corrective fix (v2). The previous fix
-- (supabase_schema_update_batch_quantity_reservation_guard.sql)
-- bounded p_new_available_kg by quantity_kg - sold_kg, which
-- ignores stock currently held by an active, unsold reservation
-- (listing/cooperative-offer/market-linking). Since
-- _apply_batch_reservation only ever decrements available_kg
-- (reserved_kg is dead schema, never written by any live
-- function), the only accurate ceiling is the batch's own
-- CURRENT available_kg — every legitimate release path
-- (_release_batch_reservation, called from cancel_order,
-- reject_listing, decline_cooperative_offer, withdraw_listing)
-- already restores available_kg automatically, so this RPC
-- never needs to allow a manual increase at all.
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_batch_available_quantity(
  p_batch_id UUID,
  p_new_available_kg DECIMAL
) RETURNS VOID AS $$
DECLARE
  v_quantity_kg DECIMAL;
  v_available_kg DECIMAL;
  v_sold_kg DECIMAL;
  v_new_status TEXT;
BEGIN
  SELECT quantity_kg, available_kg, sold_kg
    INTO v_quantity_kg, v_available_kg, v_sold_kg
    FROM public.inventory_batches
    WHERE id = p_batch_id
    FOR UPDATE;

  IF v_quantity_kg IS NULL THEN
    RAISE EXCEPTION 'Batch not found';
  END IF;

  IF p_new_available_kg < 0 THEN
    RAISE EXCEPTION 'Available quantity cannot be negative';
  END IF;

  IF p_new_available_kg > v_available_kg THEN
    RAISE EXCEPTION 'Available quantity (%) cannot exceed the current available amount of % kg. Increasing available stock isn''t supported here — % kg of this batch is committed to an active listing, cooperative offer, or market linking reservation, and is restored automatically when that reservation ends.',
      p_new_available_kg, v_available_kg, (v_quantity_kg - v_sold_kg - v_available_kg);
  END IF;

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