-- ============================================================
-- SAGANA — Block Ginger from the Open Marketplace
-- (Admin Marketplace review, Crop Management phase)
--
-- Ginger can only ever be sold through Market Linking (DA-AMAD) — never
-- listed on the open Marketplace, offered to the cooperative, or sold
-- informally. The farmer-side UI already stops offering those options
-- for a Ginger batch (see disposal_action_sheet.dart), but nothing
-- previously stopped this RPC itself if called directly. This adds the
-- same crop-name check already used consistently elsewhere for Ginger
-- (market_linking_repository.dart's ILIKE '%ginger%' match), as a
-- server-side backstop — defense in depth, not the primary enforcement.
--
-- Every existing line is preserved exactly (see
-- supabase_schema_farmer_notification_gaps.sql, the current canonical
-- version — adds the admin fan-out notification on submission) — only
-- the new guard is added, right after the parameters are available and
-- before anything else happens.
-- ============================================================

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
  IF p_crop_name ILIKE '%ginger%' THEN
    RAISE EXCEPTION 'Ginger cannot be listed on the open Marketplace — it can only be sold through Market Linking.';
  END IF;

  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  INSERT INTO public.marketplace_listings (
    farmer_id, inventory_batch_id, crop_name, variety, volume_kg,
    price_per_kg, photo_url, status, remaining_kg
  ) VALUES (
    auth.uid(), p_batch_id, p_crop_name, p_variety, p_quantity_kg,
    p_price_per_kg, p_photo_url, 'pending_review', p_quantity_kg
  ) RETURNING id INTO v_listing_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT
    ap.user_id,
    'listing_submitted',
    'New Listing Submitted',
    p_crop_name || ' (' || p_quantity_kg || 'kg) was submitted for review.',
    FALSE,
    NOW()
  FROM admin_profiles ap;

  RETURN v_listing_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.create_listing_with_reservation(uuid, text, text, numeric, numeric, text) TO authenticated;
