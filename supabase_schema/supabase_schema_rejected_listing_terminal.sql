-- Item A (Decision 1): rejected listings become a terminal, farmer-deletable
-- state, and resubmission is locked to changes_required only.
--
-- 1. delete_listing: guard widened from status = 'withdrawn' to also accept
--    'rejected'. Order-count guard is untouched — a rejected listing with
--    zero orders on record was never buyer-visible in the first place
--    (rejection happens pre-approval), so this can never conflict with
--    buyer order-history preservation.
--
-- 2. resubmit_listing_with_reservation: previously had NO status guard at
--    all — any status could theoretically be resubmitted via a direct RPC
--    call, even though the current UI only ever exposes this action for
--    changes_required listings. This adds the guard at the source of truth
--    rather than relying on the UI never exposing the path.

CREATE OR REPLACE FUNCTION public.delete_listing(p_listing_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_listing    RECORD;
  v_order_count INTEGER;
BEGIN
  SELECT * INTO v_listing FROM marketplace_listings
    WHERE id = p_listing_id AND farmer_id = auth.uid() FOR UPDATE;
  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_listing.status NOT IN ('withdrawn', 'rejected') THEN
    RAISE EXCEPTION 'This listing must be withdrawn or rejected before it can be deleted (status: %)', v_listing.status;
  END IF;

  SELECT COUNT(*) INTO v_order_count
    FROM orders WHERE listing_id = p_listing_id;

  IF v_order_count > 0 THEN
    RAISE EXCEPTION 'This listing has % order(s) on record and cannot be deleted. Order history is preserved for buyers even after a listing is withdrawn.', v_order_count;
  END IF;

  DELETE FROM marketplace_listings WHERE id = p_listing_id;
END;
$$;

CREATE OR REPLACE FUNCTION resubmit_listing_with_reservation(
  p_listing_id UUID,
  p_price_per_kg DECIMAL,
  p_volume_kg DECIMAL,
  p_photo_url TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_listing RECORD;
  v_delta DECIMAL;
BEGIN
  SELECT * INTO v_listing FROM marketplace_listings
    WHERE id = p_listing_id AND farmer_id = auth.uid() FOR UPDATE;
  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_listing.status != 'changes_required' THEN
    RAISE EXCEPTION 'Only listings with status changes_required can be resubmitted (current: %)', v_listing.status;
  END IF;

  v_delta := p_volume_kg - v_listing.volume_kg;

  IF v_listing.inventory_batch_id IS NOT NULL AND v_delta != 0 THEN
    IF v_delta > 0 THEN
      PERFORM _apply_batch_reservation(v_listing.inventory_batch_id, v_delta);
    ELSE
      PERFORM _release_batch_reservation(v_listing.inventory_batch_id, ABS(v_delta));
    END IF;
  END IF;

  UPDATE marketplace_listings
  SET price_per_kg = p_price_per_kg,
      volume_kg = p_volume_kg,
      remaining_kg = p_volume_kg,
      photo_url = p_photo_url,
      status = 'pending_review',
      admin_notes = NULL,
      submitted_at = NOW()
  WHERE id = p_listing_id;

  RETURN p_listing_id;
END;
$$;
