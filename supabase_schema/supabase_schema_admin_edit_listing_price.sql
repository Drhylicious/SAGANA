-- ============================================================
-- SAGANA — Price Management: admin edits a live Cooperative Market
-- listing's price (Issue 6 / Phase 6b)
--
-- Lets an admin correct the price on a farmer's already-approved listing,
-- but ONLY when that listing's crop is classified sp3_cooperative
-- (Cooperative Market) — Public Market listings remain admin-uneditable,
-- enforced here at the database level, not just withheld in the UI.
--
-- marketplace_listings has no confirmed crop_id FK in this schema history
-- (admin_listing_repository.dart reads one defensively, but no migration
-- file here adds it — it may exist live from an undocumented change).
-- To avoid depending on a column this migration can't verify, the crop
-- lookup joins on lower(crop_name), the same pattern already used by
-- approve_crop_request().
--
-- Column-level restriction is the whole reason this is an RPC rather than
-- a raw client .update() — RLS's existing "admin manages all" FOR ALL
-- policy on marketplace_listings would technically permit editing any
-- column already, but every other write in this codebase goes through a
-- purpose-built RPC (see marketplace_listings_farmer_rls_tighten.sql), and
-- only an RPC can enforce "price only, Cooperative Market only" as a real
-- guarantee rather than a UI convention.
-- ============================================================

CREATE OR REPLACE FUNCTION admin_update_listing_price(
  p_listing_id UUID,
  p_new_price DECIMAL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status    TEXT;
  v_crop_type TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can edit listing prices';
  END IF;

  IF p_new_price IS NULL OR p_new_price <= 0 THEN
    RAISE EXCEPTION 'Price must be greater than zero';
  END IF;

  SELECT ml.status, cm.crop_type INTO v_status, v_crop_type
  FROM marketplace_listings ml
  LEFT JOIN crop_master cm ON lower(cm.crop_name) = lower(ml.crop_name)
  WHERE ml.id = p_listing_id
  FOR UPDATE OF ml;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_status != 'approved' THEN
    RAISE EXCEPTION 'Only live (approved) listings can have their price edited';
  END IF;

  IF v_crop_type IS DISTINCT FROM 'sp3_cooperative' THEN
    RAISE EXCEPTION 'Only Cooperative Market listings can have their price edited by an admin';
  END IF;

  UPDATE marketplace_listings SET price_per_kg = p_new_price WHERE id = p_listing_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_update_listing_price(UUID, DECIMAL) TO authenticated;
