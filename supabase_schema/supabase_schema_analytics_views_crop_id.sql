-- ============================================================
-- SAGANA — Crop Identity Normalization for Analytics Views
--
-- top_harvested_crops and crop_cycle_volumes (the base view
-- crop_planting_forecast is built on top of) both GROUP BY the
-- raw harvest_records.crop_name text directly — meaning a
-- historical "Rice (Palay)" harvest and a "Palay" harvest would
-- appear as two separate rows in both views, even after the
-- crop_id migration and backfill (supabase_schema_crop_id_
-- migration.sql), since that migration only added the crop_id
-- column — it never touched these views' own definitions.
--
-- This redefines both views to LEFT JOIN crop_master via
-- harvest_records.crop_id and GROUP BY the canonical
-- crop_master.crop_name when resolvable, falling back to the
-- raw harvest_records.crop_name for any row whose crop_id is
-- still null (an unmatched historical row the migration's own
-- post-migration check queries would have already surfaced).
--
-- crop_planting_forecast itself needs no changes — it selects
-- crop_name from crop_cycle_volumes, so it inherits the fix
-- automatically once the base view is corrected.
-- ============================================================

CREATE OR REPLACE VIEW public.top_harvested_crops AS
SELECT
  COALESCE(cm.crop_name, hr.crop_name) AS crop_name,
  SUM(hr.quantity_kg) AS total_kg
FROM public.harvest_records hr
LEFT JOIN public.crop_master cm ON cm.id = hr.crop_id
WHERE hr.harvest_date >= NOW() - INTERVAL '90 days'
GROUP BY COALESCE(cm.crop_name, hr.crop_name);

CREATE OR REPLACE VIEW public.crop_cycle_volumes AS
SELECT
  COALESCE(cm.crop_name, hr.crop_name) AS crop_name,
  FLOOR(EXTRACT(EPOCH FROM (NOW() - hr.harvest_date)) / (30 * 86400))::INT AS cycle_index,
  SUM(hr.quantity_kg) AS cycle_volume_kg
FROM public.harvest_records hr
LEFT JOIN public.crop_master cm ON cm.id = hr.crop_id
WHERE hr.harvest_date >= NOW() - INTERVAL '180 days'
GROUP BY COALESCE(cm.crop_name, hr.crop_name), cycle_index;

GRANT SELECT ON public.top_harvested_crops TO authenticated;
GRANT SELECT ON public.crop_cycle_volumes TO authenticated;
GRANT SELECT ON public.crop_planting_forecast TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- Post-migration check — run separately after the above.
-- ============================================================
-- Should now show ONE row for Palay (not split between "Palay"
-- and "Rice (Palay)"), assuming the crop_id migration's backfill
-- already ran successfully.
-- SELECT * FROM public.top_harvested_crops WHERE crop_name ILIKE '%palay%';