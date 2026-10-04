-- ============================================================
-- SAGANA — Crop Identity Normalization for Analytics Views (fix)
--
-- Supersedes supabase_schema_analytics_views_crop_id.sql, whose
-- `LEFT JOIN public.crop_master cm ON cm.id = hr.crop_id` compared two
-- unrelated UUID columns: harvest_records.crop_id is a FK to
-- farmer_crops(id), not crop_master(id) — see
-- supabase_schema_crops.sql (farmer_crops) and
-- supabase_schema_harvest.sql (harvest_records.crop_id definition).
--
-- Confirmed live, 2026-09-23:
--   SELECT count(*) FROM harvest_records hr
--   WHERE EXISTS (SELECT 1 FROM crop_master cm WHERE cm.id = hr.crop_id);
-- returned 0 — the old join never matched a single row, so
-- COALESCE(cm.crop_name, hr.crop_name) silently fell back to the raw,
-- uncanonicalized crop_name on every row in both views below.
--
-- This redefines the same two views with the correct two-hop path:
--   harvest_records.crop_id -> farmer_crops.id
--     -> farmer_crops.crop_master_id -> crop_master.id
-- matching the pattern already used elsewhere in this codebase for the
-- identical harvest_records.crop_id collision (crop_lookup.dart's
-- fetchFarmerCropToCropMasterMap + fetchCropNameMap in Dart;
-- supabase_schema_harvest_market_type_persistence.sql and
-- supabase_schema_da_amad_enrollment.sql's
-- `JOIN crop_master cm ON cm.id = fc.crop_master_id` in SQL).
--
-- Scope note: this migration only covers harvest_records-derived data
-- (Top Harvested Crops, Planting Forecast — both cooperative-wide,
-- shared by Farmer Analytics and Admin's Analytics Dashboard). It does
-- NOT touch member_sales_transactions, informal_sales, or
-- marketplace_listings — none of those tables have a crop_id column
-- today, so their own crop_name fragmentation risk (if any) is a
-- separate, not-yet-scoped follow-up, not part of this fix.
-- ============================================================

CREATE OR REPLACE VIEW public.top_harvested_crops AS
SELECT
  COALESCE(cm.crop_name, hr.crop_name) AS crop_name,
  SUM(hr.quantity_kg) AS total_kg
FROM public.harvest_records hr
LEFT JOIN public.farmer_crops fc ON fc.id = hr.crop_id
LEFT JOIN public.crop_master cm ON cm.id = fc.crop_master_id
WHERE hr.harvest_date >= NOW() - INTERVAL '90 days'
GROUP BY COALESCE(cm.crop_name, hr.crop_name);

CREATE OR REPLACE VIEW public.crop_cycle_volumes AS
SELECT
  COALESCE(cm.crop_name, hr.crop_name) AS crop_name,
  FLOOR(EXTRACT(EPOCH FROM (NOW() - hr.harvest_date)) / (30 * 86400))::INT AS cycle_index,
  SUM(hr.quantity_kg) AS cycle_volume_kg
FROM public.harvest_records hr
LEFT JOIN public.farmer_crops fc ON fc.id = hr.crop_id
LEFT JOIN public.crop_master cm ON cm.id = fc.crop_master_id
WHERE hr.harvest_date >= NOW() - INTERVAL '180 days'
GROUP BY COALESCE(cm.crop_name, hr.crop_name), cycle_index;

-- crop_planting_forecast itself needs no changes — it selects crop_name
-- from crop_cycle_volumes, so it inherits the fix automatically once
-- the base view above is corrected.

GRANT SELECT ON public.top_harvested_crops TO authenticated;
GRANT SELECT ON public.crop_cycle_volumes TO authenticated;
GRANT SELECT ON public.crop_planting_forecast TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- Post-migration check — run separately after the above.
-- ============================================================
-- Should now return a non-zero, near-total count (most/all
-- harvest_records rows resolving through farmer_crops to a
-- crop_master entry) — contrast with the old join's confirmed 0:
--
-- SELECT count(*) FROM harvest_records hr
-- WHERE EXISTS (
--   SELECT 1 FROM crop_master cm
--   JOIN farmer_crops fc ON fc.crop_master_id = cm.id
--   WHERE fc.id = hr.crop_id
-- );
--
-- Should show ONE row for any crop with a historical catalog split
-- (not divided across two differently-spelled crop_name values):
-- SELECT * FROM public.top_harvested_crops ORDER BY total_kg DESC;
