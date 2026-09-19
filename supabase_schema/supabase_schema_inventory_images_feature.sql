-- ============================================================
-- SAGANA — Inventory Item Images & Cross-Module Integration
-- Phase 0: Database & storage foundation only. No client code in
-- this migration — see new_feature.md for the full feature and
-- the approved phase-by-phase plan.
--
-- Decisions this migration encodes (agreed before implementation):
--   1. cooperative_inventory.image_url / cooperative_programs.image_url
--      are new, nullable columns — Inventory Management and Program
--      Management remain the sole source of truth for their own image;
--      every other module reuses it via the existing joins on
--      cooperative_inventory, never a separate copy.
--   2. Delete Item is a real hard delete, but only when it's actually
--      safe: program_product_purchases.product_id -> program_products.id
--      is RESTRICT with no item-name snapshot of its own, so an item
--      that was ever sold through Product Sales can never be hard-deleted
--      without destroying real purchase/payment records — delete_inventory_item()
--      below blocks that case outright rather than attempting it.
--   3. program_members gets a distributed_item_name snapshot, written at
--      distribution time, so a farmer's distribution history stays
--      meaningful even after the source inventory item is later deleted
--      (inventory_item_id itself is ON DELETE SET NULL there already).
-- ============================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Image columns
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.cooperative_inventory
  ADD COLUMN IF NOT EXISTS image_url TEXT;

COMMENT ON COLUMN public.cooperative_inventory.image_url IS
  'Public Storage URL of the item''s photo (cooperative_inventory_images '
  'bucket). NULL falls back to the generic category icon everywhere this '
  'item is displayed. This is the single source of truth — Loan Item '
  'Catalog, Loan Management, Distribution, Product Sales, and Cooperative '
  'Stock Report all read it via their existing cooperative_inventory '
  'join rather than storing their own copy.';

ALTER TABLE public.cooperative_programs
  ADD COLUMN IF NOT EXISTS image_url TEXT;

COMMENT ON COLUMN public.cooperative_programs.image_url IS
  'Public Storage URL of the program''s photo (cooperative_inventory_images '
  'bucket, program_images/ prefix). Upload-only, no camera capture — a '
  'program is not a physical item. NULL falls back to the existing '
  'generic program presentation.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. program_members.distributed_item_name — snapshot, not a new FK
-- v_item_name was already being looked up inside distribute_program_benefit()
-- (see supabase_schema_program_atomic_distribution.sql) for its error
-- message only; this just also persists it. Mirrors the same snapshot
-- idiom already used by farmer_loan_items (item_name/quantity/unit/
-- unit_price/line_total stored as plain values, no FK back to the
-- catalog) so distribution history survives the source item being deleted.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.program_members
  ADD COLUMN IF NOT EXISTS distributed_item_name TEXT;

COMMENT ON COLUMN public.program_members.distributed_item_name IS
  'Item name captured at the moment distribute_program_benefit() ran — '
  'independent of inventory_item_id (ON DELETE SET NULL), so this stays '
  'meaningful even if the source cooperative_inventory row is later '
  'deleted via delete_inventory_item().';

CREATE OR REPLACE FUNCTION distribute_program_benefit(
  p_program_member_id UUID,
  p_inventory_item_id UUID,
  p_quantity NUMERIC,
  p_recorded_by UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_available NUMERIC;
  v_item_name TEXT;
BEGIN
  SELECT quantity_on_hand, item_name INTO v_available, v_item_name
    FROM cooperative_inventory
    WHERE id = p_inventory_item_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory item % no longer exists', p_inventory_item_id;
  END IF;

  IF v_available < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock for %: % on hand, % requested',
      v_item_name, v_available, p_quantity;
  END IF;

  UPDATE cooperative_inventory
  SET quantity_on_hand = quantity_on_hand - p_quantity
  WHERE id = p_inventory_item_id;

  INSERT INTO inventory_transactions (
    inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by
  ) VALUES (
    p_inventory_item_id, 'program_distribution', -p_quantity, p_program_member_id, 'program', p_recorded_by
  );

  UPDATE program_members
  SET inventory_item_id = p_inventory_item_id,
      quantity_given = p_quantity,
      distributed_at = NOW(),
      distributed_item_name = v_item_name
  WHERE id = p_program_member_id;
END;
$$;

GRANT EXECUTE ON FUNCTION distribute_program_benefit TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. delete_inventory_item() — the only safe path to a hard delete
--
-- FK chain confirmed live before writing this:
--   loan_items_master.inventory_item_id      -> RESTRICT, nothing else
--     references loan_items_master.id, and farmer_loan_items already
--     fully snapshots item_name/quantity/unit/unit_price/line_total —
--     un-publishing here is risk-free.
--   program_products.inventory_item_id       -> RESTRICT
--   program_product_purchases.product_id     -> RESTRICT (program_products.id),
--     with NO item-name snapshot of its own — so a program_products row
--     that has ANY purchase (pending, paid, or cancelled) can never be
--     deleted without destroying that purchase record, which transitively
--     means the cooperative_inventory row can't be deleted either.
--   program_members.inventory_item_id        -> SET NULL (distributed_item_name
--     above keeps the record meaningful regardless).
--   inventory_transactions.inventory_id       -> CASCADE (the item's full
--     restock/adjustment audit trail is permanently removed — by design,
--     per the approved Delete Item confirmation-dialog wording).
--
-- Raises a distinct, matchable message when blocked so the Dart layer can
-- show "deactivate instead" rather than a raw Postgres FK error.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION delete_inventory_item(p_inventory_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_purchase_count INTEGER;
BEGIN
  SELECT count(*) INTO v_purchase_count
    FROM program_product_purchases ppp
    JOIN program_products pp ON pp.id = ppp.product_id
    WHERE pp.inventory_item_id = p_inventory_id;

  IF v_purchase_count > 0 THEN
    RAISE EXCEPTION 'CANNOT_DELETE_HAS_PURCHASE_HISTORY';
  END IF;

  -- No purchase history exists for any Product Sales listing of this item,
  -- so removing the listing(s) below cannot destroy real transaction data.
  DELETE FROM program_products WHERE inventory_item_id = p_inventory_id;

  -- Un-publish from the Loan Item Catalog — see FK-chain note above.
  DELETE FROM loan_items_master WHERE inventory_item_id = p_inventory_id;

  -- CASCADE: inventory_transactions. SET NULL: program_members.inventory_item_id
  -- (distributed_item_name already preserves the historical record).
  DELETE FROM cooperative_inventory WHERE id = p_inventory_id;
END;
$$;

GRANT EXECUTE ON FUNCTION delete_inventory_item TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Storage bucket + RLS policies
-- Mirrors profile_photos / crop_images / listing_photos exactly
-- (supabase_schema_fixes.sql) — public read, owner-folder (uploader's own
-- auth.uid()) write. Program images use the same bucket under a
-- program_images/ path prefix rather than a second bucket, since the
-- policies are identical and a prefix is enough to keep the two image
-- kinds from colliding.
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO storage.buckets (id, name, public)
VALUES ('cooperative_inventory_images', 'cooperative_inventory_images', true)
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS "Inventory images public read"   ON storage.objects;
DROP POLICY IF EXISTS "Inventory images owner upload"  ON storage.objects;
DROP POLICY IF EXISTS "Inventory images owner update"  ON storage.objects;
DROP POLICY IF EXISTS "Inventory images owner delete"  ON storage.objects;

CREATE POLICY "Inventory images public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'cooperative_inventory_images');

CREATE POLICY "Inventory images owner upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'cooperative_inventory_images'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Inventory images owner update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'cooperative_inventory_images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Inventory images owner delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'cooperative_inventory_images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
