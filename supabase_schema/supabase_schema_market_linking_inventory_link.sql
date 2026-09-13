-- ============================================================
-- SAGANA — Market Linking optional inventory tie-in
-- Adds an optional batch link and confirmed-sale-quantity column
-- to market_linking_programs. Enrollment, Buyer Found, and
-- Cancelled never touch inventory — only Completed-with-a-batch
-- does, via the RPC below.
-- ============================================================

ALTER TABLE public.market_linking_programs
  ADD COLUMN IF NOT EXISTS inventory_batch_id UUID REFERENCES public.inventory_batches(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS confirmed_volume_kg NUMERIC(10,2);

-- ─── RPC: complete a Market Linking enrollment ─────────────────────────────
-- Two shapes in one function:
--   p_batch_id supplied  -> validates + decrements available_kg, bumps
--                           sold_kg (final sale, not a reservation — see
--                           note below), recomputes status, then completes.
--   p_batch_id omitted   -> plain status flip, exactly like today. No
--                           inventory touched at all.
-- Idempotent: re-calling on an already-completed row is a silent no-op,
-- so a retried/raced call can never double-deduct a batch.
--
-- Note on sold_kg: _apply_batch_reservation (used by every other disposal
-- path) only touches available_kg + status, because it models a
-- provisional hold that might later be released. Market Linking completion
-- is a one-shot, final, non-reversible sale — there's no "release" concept
-- here at all — so this also increments sold_kg, matching what a truly
-- completed sale should do, not just a reservation.

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
  v_quantity_kg DECIMAL;
  v_available_kg DECIMAL;
  v_sold_kg DECIMAL;
  v_new_available DECIMAL;
  v_new_sold DECIMAL;
  v_new_status TEXT;
BEGIN
  SELECT status INTO v_current_status
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

    SELECT quantity_kg, available_kg, sold_kg
      INTO v_quantity_kg, v_available_kg, v_sold_kg
      FROM public.inventory_batches
      WHERE id = p_batch_id
      FOR UPDATE;

    IF v_available_kg IS NULL THEN
      RAISE EXCEPTION 'Batch not found';
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
