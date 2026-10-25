-- ============================================================
-- SAGANA — Copra is a processed product, not a crop: take it out of the crop
-- catalog (non-destructive)
--
-- Preflight showed one Copra catalog row (active, Public Market), one price
-- record that points at it, no farmer crops, no listings, and two old price
-- notifications. Nothing is deleted:
--
--   1. The Copra row in crop_master is ARCHIVED (is_active = false). Every crop
--      picker in the app lists only active crops, so Copra is no longer
--      selectable anywhere (Add Price Entry, Request / Add Crop, Add Member,
--      listing creation, the Buyer category lookup). Crop Management shows it
--      only under Archived, where it can be restored if this was a mistake.
--   2. Reference prices of an archived crop are hidden from Farmers and Buyers
--      by the database (the existing price_records read rule gains "the crop
--      is still active"), so Market Rates, Home, Analytics and Buyer Prices
--      stop showing a Copra price. Staff still read every row, and the price
--      record itself, the old notifications and all history stay in place.
--      This applies to ANY archived crop, which is what archiving means.
--
-- Safe to re-run. Run supabase_schema_copra_preflight.sql first.
-- ============================================================

BEGIN;

-- 1. Archive Copra.
UPDATE public.crop_master
SET is_active = FALSE
WHERE lower(btrim(crop_name)) = 'copra'
  AND is_active = TRUE;

-- 2. Hide archived crops' prices from non-staff. SECURITY DEFINER so the check
--    does not depend on what crop_master rows the caller may read.
CREATE OR REPLACE FUNCTION public.crop_is_listed(p_crop_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_crop_id IS NULL
      OR EXISTS (SELECT 1 FROM public.crop_master m
                 WHERE m.id = p_crop_id AND m.is_active);
$$;

REVOKE ALL ON FUNCTION public.crop_is_listed(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.crop_is_listed(UUID) TO authenticated;

DROP POLICY IF EXISTS "price_records: restricted markets hidden from buyers"
  ON public.price_records;
CREATE POLICY "price_records: restricted markets hidden from buyers"
  ON public.price_records
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (
    public.can_view_market_type(price_type)
    AND (public.is_staff() OR public.crop_is_listed(crop_id))
  );

COMMIT;

-- ── Verify (read-only) ──────────────────────────────────────────────────────
-- SELECT id, crop_name, is_active FROM public.crop_master WHERE crop_name ILIKE '%copra%';
--   (expect is_active = false)
-- SELECT COUNT(*) FROM public.crop_master WHERE crop_name ILIKE '%copra%' AND is_active;
--   (expect 0)
-- SELECT COUNT(*) FROM public.price_records WHERE crop_name ILIKE '%copra%';
--   (expect 1: the record is kept; staff still see it, Farmers and Buyers do not)
-- SELECT policyname, permissive FROM pg_policies
--   WHERE tablename = 'price_records' AND policyname LIKE '%restricted markets%';
--   (expect permissive = RESTRICTIVE)
