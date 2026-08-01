-- ============================================================
-- SAGANA — Correct create_listing_with_reservation for real
-- Two prior migrations (fix_listing_reservation.sql and
-- marketplace_order_reservation_fix.sql) both touched this
-- function with different parameter lists, so Postgres kept
-- them as separate overloads instead of one replacing the
-- other. The overload the app actually calls (6 params:
-- batch_id/crop_name/variety/quantity_kg/price_per_kg/photo_url)
-- still had the original bug: inserted into a non-existent
-- quantity_kg column with an invalid 'pending' status. This
-- migration fixes that overload in place and drops the
-- unrelated orphaned overload (p_description version, confirmed
-- via pg_proc — never called by any client code).
-- ============================================================

-- Fix the overload the app actually calls — same signature,
-- corrected column name and status value, remaining_kg logic
-- kept intact from the reservation-fix work.
CREATE OR REPLACE FUNCTION public.create_listing_with_reservation(
  p_batch_id UUID,
  p_crop_name TEXT,
  p_variety TEXT,
  p_quantity_kg DECIMAL,
  p_price_per_kg DECIMAL,
  p_photo_url TEXT
) RETURNS UUID AS $$
DECLARE
  v_listing_id UUID;
BEGIN
  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  INSERT INTO public.marketplace_listings (
    farmer_id, inventory_batch_id, crop_name, variety, volume_kg,
    price_per_kg, photo_url, status, remaining_kg
  ) VALUES (
    auth.uid(), p_batch_id, p_crop_name, p_variety, p_quantity_kg,
    p_price_per_kg, p_photo_url, 'pending_review', p_quantity_kg
  ) RETURNING id INTO v_listing_id;

  RETURN v_listing_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop the orphaned overload — confirmed signature from pg_proc,
-- confirmed unused by grepping every Dart repository for this
-- RPC name (only the 6-param p_variety version is ever called).
DROP FUNCTION IF EXISTS public.create_listing_with_reservation(uuid, text, numeric, numeric, text, text);

GRANT EXECUTE ON FUNCTION public.create_listing_with_reservation(uuid, text, text, numeric, numeric, text) TO authenticated;

NOTIFY pgrst, 'reload schema';